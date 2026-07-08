#include <Poseidon/Foundation/Common/PlatformPaths.hpp>

#include <cstdlib>
#include <string>
#include <sys/stat.h>

namespace
{
void ensureDirectory(const std::string& path)
{
    if (path.empty())
        return;
    for (size_t i = 1; i < path.size(); ++i)
    {
        if (path[i] == '/')
        {
            std::string partial = path.substr(0, i);
            mkdir(partial.c_str(), 0755);
        }
    }
    mkdir(path.c_str(), 0755);
}

std::string homeDir()
{
    const char* home = getenv("HOME");
    if (home && home[0] != '\0')
        return home;
    return "/tmp";
}

std::string appSupportDir(const char* appName)
{
    std::string dir = homeDir() + "/Library/Application Support/" + (appName ? appName : "Poseidon");
    ensureDirectory(dir);
    return dir;
}

std::string cacheDir(const char* appName)
{
    std::string dir = homeDir() + "/Library/Caches/" + (appName ? appName : "Poseidon");
    ensureDirectory(dir);
    return dir;
}
} // namespace

namespace Poseidon::Foundation
{
std::string getUserConfigDir(const char* appName)
{
    return appSupportDir(appName);
}

std::string getUserDataDir(const char* appName)
{
    return appSupportDir(appName);
}

std::string getUserCacheDir(const char* appName)
{
    return cacheDir(appName);
}

std::string getUserDocumentsDir(const char* appName)
{
    return appSupportDir(appName);
}
} // namespace Poseidon::Foundation
