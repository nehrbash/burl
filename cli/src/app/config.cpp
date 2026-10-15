#include "config.hpp"

#include "util.hpp"

namespace burl {

UserConfig loadUserConfig(const Paths& paths) {
    UserConfig config;
    try {
        const auto json = parseJson(readFile(paths.userConfig).toStdString());
        if (const auto* theme = json.find("theme"); theme && theme->isObject()) {
            config.theme = *theme;
        }
        const auto* section = json.find("wallpaper");
        const auto* hook = section && section->isObject() ? section->find("postHook") : nullptr;
        if (hook && hook->isString()) {
            config.postHook = QString::fromStdString(hook->asString());
        }
    } catch (const FileNotFound&) {
    } catch (const JsonError&) {
    }
    return config;
}

} // namespace burl
