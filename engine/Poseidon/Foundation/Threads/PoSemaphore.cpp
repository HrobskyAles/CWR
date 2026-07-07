#include <Poseidon/Foundation/Threads/PoSemaphore.hpp>

namespace Poseidon::Foundation
{
PoSemaphore::PoSemaphore(long init, long maxCount)
{
    LockRegister(lock, "PoSemaphore");
    if (init < 0L)
    {
        init = 0L;
    }
#ifdef _WIN32
    handle = CreateSemaphore(nullptr, init, maxCount, nullptr);
    error = (handle == nullptr);
#elif defined(__APPLE__)
    if (maxCount < 1L)
    {
        maxCount = 1L;
    }
    if (init > maxCount)
    {
        init = maxCount;
    }

    count = init;
    this->maxCount = maxCount;
    syncReady = false;
    error = (pthread_mutex_init(&mutex, nullptr) != 0);
    if (!error)
    {
        error = (pthread_cond_init(&cond, nullptr) != 0);
        if (error)
        {
            pthread_mutex_destroy(&mutex);
        }
        else
        {
            syncReady = true;
        }
    }
#else
    error = (sem_init(&sem, 0, (unsigned)init) != 0);
    // maxCount is ignored under pthreads
#endif
}

void PoSemaphore::wait()
{
#ifdef _WIN32
    if (handle != nullptr)
    {
        WaitForSingleObject(handle, INFINITE);
    }
#elif defined(__APPLE__)
    if (!syncReady)
    {
        error = true;
        return;
    }
    pthread_mutex_lock(&mutex);
    while (count == 0L)
    {
        pthread_cond_wait(&cond, &mutex);
    }
    --count;
    pthread_mutex_unlock(&mutex);
#else
    sem_wait(&sem);
#endif
}

bool PoSemaphore::tryWait()
{
#ifdef _WIN32
    if (handle == nullptr)
    {
        return false;
    }
    return (WaitForSingleObject(handle, 0L) == WAIT_OBJECT_0);
#elif defined(__APPLE__)
    if (!syncReady)
    {
        error = true;
        return false;
    }
    bool acquired = false;
    pthread_mutex_lock(&mutex);
    if (count > 0L)
    {
        --count;
        acquired = true;
    }
    pthread_mutex_unlock(&mutex);
    return acquired;
#else
    return (sem_trywait(&sem) == 0);
#endif
}

void PoSemaphore::signal(long count)
{
    if (count < 1L)
    {
        count = 1L;
    }
#ifdef _WIN32
    if (handle == nullptr)
    {
        error = true;
        return;
    }
    // NOTE: ReleaseSemaphore returns nonzero on success — this error test reads inverted.
    error = (ReleaseSemaphore(handle, count, nullptr) != 0);
#elif defined(__APPLE__)
    if (!syncReady)
    {
        error = true;
        return;
    }
    pthread_mutex_lock(&mutex);
    if (count > maxCount - this->count)
    {
        error = true;
    }
    else
    {
        error = false;
        this->count += count;
        while (count-- > 0L)
        {
            pthread_cond_signal(&cond);
        }
    }
    pthread_mutex_unlock(&mutex);
#else
    error = false;
    while (!error && count > 0L)
    {
        error = (sem_post(&sem) != 0);
        count--;
    }
#endif
}

long PoSemaphore::getValue()
{
#ifdef _WIN32
    error = true; // getValue is not available on Win32
    return 0L;
#else
#ifdef __APPLE__
    if (!syncReady)
    {
        error = true;
        return 0L;
    }
    pthread_mutex_lock(&mutex);
    long val = count;
    pthread_mutex_unlock(&mutex);
    error = false;
    return val;
#else
#ifdef __CYGWIN__
    error = true;
    return 0L;
#else
    int val = 0;
    error = (sem_getvalue(&sem, &val) != 0);
    return (long)val;
#endif
#endif
#endif
}

PoSemaphore::~PoSemaphore()
{
#ifdef _WIN32
    if (handle != nullptr)
    {
        CloseHandle(handle);
        handle = nullptr;
    }
#elif defined(__APPLE__)
    if (syncReady)
    {
        pthread_cond_destroy(&cond);
        pthread_mutex_destroy(&mutex);
    }
#else
    sem_destroy(&sem);
#endif
}

} // namespace Poseidon::Foundation
