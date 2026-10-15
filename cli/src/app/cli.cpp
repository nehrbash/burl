#include "cli.hpp"

#include "paths.hpp"
#include "scheme.hpp"
#include "theme.hpp"
#include "util.hpp"
#include "wallpaper.hpp"

#include <algorithm>
#include <cstdio>
#include <map>
#include <optional>

using Qt::StringLiterals::operator""_s;

namespace burl {

namespace {

constexpr int exitUsage = 2;

struct UsageError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

struct HelpRequested {};

enum class Kind { Flag, Value, Optional };

struct Option {
    QString shortFlag;
    QString longFlag;
    QString dest;
    Kind kind = Kind::Flag;
    QStringList choices;
    QString constValue;

    Option(QString shortName, QString longName, QString destination, Kind optionKind = Kind::Flag,
           QStringList allowed = {}, QString fallback = {})
        : shortFlag(std::move(shortName))
        , longFlag(std::move(longName))
        , dest(std::move(destination))
        , kind(optionKind)
        , choices(std::move(allowed))
        , constValue(std::move(fallback)) {}

    [[nodiscard]] QString display() const {
        return shortFlag.isEmpty() ? longFlag : shortFlag + u"/" + longFlag;
    }
};

struct Parsed {
    std::map<QString, QString> values;
    QStringList unknown;

    [[nodiscard]] bool flag(const QString& dest) const { return values.count(dest) > 0; }
    [[nodiscard]] QString value(const QString& dest) const {
        const auto found = values.find(dest);
        return found == values.end() ? QString() : found->second;
    }
};

bool looksLikeOption(const QString& argument) {
    if (argument.size() < 2 || argument[0] != u'-') {
        return false;
    }
    bool number = false;
    argument.toDouble(&number);
    return !number;
}

const Option& findLong(const QList<Option>& options, const QString& name) {
    const Option* match = nullptr;
    QStringList candidates;
    for (const auto& option : options) {
        if (option.longFlag == name) {
            return option;
        }
        if (option.longFlag.startsWith(name)) {
            candidates.append(option.longFlag);
            match = &option;
        }
    }
    if (candidates.size() > 1) {
        throw UsageError(u"ambiguous option: %1 could match %2"_s.arg(name, candidates.join(u", ")).toStdString());
    }
    if (!match) {
        throw UsageError(("unrecognized arguments: " + name).toStdString());
    }
    return *match;
}

void store(Parsed& parsed, const Option& option, const QString& value) {
    if (!option.choices.isEmpty() && !option.choices.contains(value)) {
        QStringList quoted;
        for (const auto& choice : option.choices) {
            quoted.append(u"'" + choice + u"'");
        }
        throw UsageError(u"argument %1: invalid choice: '%2' (choose from %3)"_s
                             .arg(option.display(), value, quoted.join(u", "))
                             .toStdString());
    }
    parsed.values[option.dest] = value;
}

// argparse-compatible enough for burl's flags: --long=value, unique long
// prefixes, clustered short flags, -fVALUE, optional values.
Parsed parseOptions(const QStringList& arguments, const QList<Option>& options) {
    Parsed parsed;
    const auto next = [&](qsizetype index) -> std::optional<QString> {
        if (index + 1 < arguments.size() && !looksLikeOption(arguments[index + 1])) {
            return arguments[index + 1];
        }
        return std::nullopt;
    };

    for (qsizetype i = 0; i < arguments.size(); i++) {
        const auto& argument = arguments[i];

        if (argument == u"-h" || argument == u"--help") {
            throw HelpRequested();
        }

        if (argument == u"--") {
            parsed.unknown.append(arguments.mid(i + 1));
            break;
        }

        if (argument.startsWith(u"--")) {
            const auto equals = argument.indexOf(u'=');
            const auto name = equals < 0 ? argument : argument.left(equals);
            if (name == u"--help") {
                throw HelpRequested();
            }
            const auto& option = findLong(options, name);
            if (option.kind == Kind::Flag) {
                if (equals >= 0) {
                    throw UsageError(("argument " + option.display() + ": ignored explicit argument '"
                                      + argument.mid(equals + 1) + "'").toStdString());
                }
                parsed.values[option.dest] = u"1"_s;
            } else if (equals >= 0) {
                store(parsed, option, argument.mid(equals + 1));
            } else if (const auto value = next(i)) {
                store(parsed, option, *value);
                i++;
            } else if (option.kind == Kind::Optional) {
                store(parsed, option, option.constValue);
            } else {
                throw UsageError(("argument " + option.display() + ": expected one argument").toStdString());
            }
        } else if (looksLikeOption(argument)) {
            for (qsizetype c = 1; c < argument.size(); c++) {
                const auto flag = u"-" + argument.mid(c, 1);
                const auto found = std::find_if(options.begin(), options.end(),
                                                [&](const Option& option) { return option.shortFlag == flag; });
                if (found == options.end()) {
                    throw UsageError(("unrecognized arguments: " + argument).toStdString());
                }
                if (found->kind == Kind::Flag) {
                    parsed.values[found->dest] = u"1"_s;
                    continue;
                }
                const auto rest = argument.mid(c + 1);
                if (!rest.isEmpty()) {
                    store(parsed, *found, rest.startsWith(u'=') ? rest.mid(1) : rest);
                } else if (const auto value = next(i)) {
                    store(parsed, *found, *value);
                    i++;
                } else if (found->kind == Kind::Optional) {
                    store(parsed, *found, found->constValue);
                } else {
                    throw UsageError(("argument " + found->display() + ": expected one argument").toStdString());
                }
                break;
            }
        } else {
            parsed.unknown.append(argument);
        }
    }

    if (!parsed.unknown.isEmpty()) {
        throw UsageError(("unrecognized arguments: " + parsed.unknown.join(u" ")).toStdString());
    }
    return parsed;
}

void printHelp(const QString& text) {
    std::fputs(text.toUtf8().constData(), stdout);
}

const QString topHelp = uR"(usage: burl [-h] [-v] COMMAND ...

burl theme/wallpaper utilities

options:
  -h, --help     show this help message and exit
  -v, --version  print the current version

subcommands:
  COMMAND        the subcommand to run
    scheme       manage the colour scheme
    wallpaper    manage the wallpaper
)"_s;

const QString schemeHelp = uR"(usage: burl scheme [-h] {list,get,set} ...

subcommands:
  list           list available schemes
  get            get scheme properties
  set            set the current scheme
)"_s;

const QString listHelp = uR"(usage: burl scheme list [-h] [-n] [-f] [-m] [-v]

options:
  -n, --names     list scheme names
  -f, --flavours  list scheme flavours
  -m, --modes     list scheme modes
  -v, --variants  list scheme variants
)"_s;

const QString getHelp = uR"(usage: burl scheme get [-h] [-n] [-f] [-m] [-v]

options:
  -n, --name     print the current scheme name
  -f, --flavour  print the current scheme flavour
  -m, --mode     print the current scheme mode
  -v, --variant  print the current scheme variant
)"_s;

const QString setHelp = uR"(usage: burl scheme set [-h] [--notify] [-r] [-n NAME] [-f FLAVOUR] [-m {dark,light}] [-v VARIANT]

options:
  --notify               send a notification on error
  -r, --random           switch to a random scheme
  -n, --name NAME        the name of the scheme to switch to
  -f, --flavour FLAVOUR  the flavour to switch to
  -m, --mode {dark,light}
                         the mode to switch to
  -v, --variant VARIANT  the variant to switch to
)"_s;

const QString wallpaperHelp = uR"(usage: burl wallpaper [-h] [-p [PATH]] [-r [DIR]] [-f FILE] [-n] [-t THRESHOLD] [-N]

options:
  -p, --print [PATH]        print the scheme for a wallpaper
  -r, --random [DIR]        switch to a random wallpaper
  -f, --file FILE           the path to the wallpaper to switch to
  -n, --no-filter           do not filter by size
  -t, --threshold THRESHOLD the minimum percentage of the largest monitor size the image must be greater than to be selected
  -N, --no-smart            do not automatically change the scheme mode based on wallpaper colour
)"_s;

void printNames(const QString& label, const QStringList& values, bool multiple) {
    if (multiple) {
        printLine(label + u" " + values.join(u" "));
    } else {
        printLine(values.join(u"\n"));
    }
}

int schemeList(const Paths& paths, const QStringList& arguments) {
    const auto parsed = parseOptions(arguments,
                                     {{u"-n"_s, u"--names"_s, u"names"_s},
                                      {u"-f"_s, u"--flavours"_s, u"flavours"_s},
                                      {u"-m"_s, u"--modes"_s, u"modes"_s},
                                      {u"-v"_s, u"--variants"_s, u"variants"_s}});
    const auto names = parsed.flag(u"names"_s);
    const auto flavours = parsed.flag(u"flavours"_s);
    const auto modes = parsed.flag(u"modes"_s);
    const auto variants = parsed.flag(u"variants"_s);
    const auto multiple = int(names) + int(flavours) + int(modes) + int(variants) > 1;

    if (names || flavours || modes || variants) {
        if (names) {
            printNames(u"Names:"_s, schemeNames(paths), multiple);
        }
        if (flavours) {
            printNames(u"Flavours:"_s, schemeFlavours(paths, Scheme::load(paths).name()), multiple);
        }
        if (modes) {
            const auto current = Scheme::load(paths);
            printNames(u"Modes:"_s, schemeModes(paths, current.name(), current.flavour()), multiple);
        }
        if (variants) {
            printNames(u"Variants:"_s, schemeVariants, multiple);
        }
        return 0;
    }

    const auto current = Scheme::load(paths);
    auto schemes = JsonValue::object();
    for (const auto& name : schemeNames(paths)) {
        auto byFlavour = JsonValue::object();
        for (const auto& flavour : schemeFlavours(paths, name)) {
            auto mode = current.mode();
            const auto available = schemeModes(paths, name, flavour);
            if (available.isEmpty()) {
                throw Error(u"No modes found for %1 %2"_s.arg(name, flavour));
            }
            if (!available.contains(mode)) {
                mode = available.first();
            }
            Scheme scheme(paths, name, flavour, mode, current.variant(), current.colours());
            try {
                scheme.refreshColours();
                byFlavour.set(flavour.toStdString(), coloursToJson(scheme.colours()));
            } catch (const Error&) {
            } catch (const std::domain_error&) {
            }
        }
        schemes.set(name.toStdString(), std::move(byFlavour));
    }
    printLine(dumpJson(schemes));
    return 0;
}

int schemeGet(const Paths& paths, const QStringList& arguments) {
    const auto parsed = parseOptions(arguments,
                                     {{u"-n"_s, u"--name"_s, u"name"_s},
                                      {u"-f"_s, u"--flavour"_s, u"flavour"_s},
                                      {u"-m"_s, u"--mode"_s, u"mode"_s},
                                      {u"-v"_s, u"--variant"_s, u"variant"_s}});
    const auto scheme = Scheme::load(paths);

    if (parsed.values.empty()) {
        printLine(scheme.summary());
        return 0;
    }
    if (parsed.flag(u"name"_s)) {
        printLine(scheme.name());
    }
    if (parsed.flag(u"flavour"_s)) {
        printLine(scheme.flavour());
    }
    if (parsed.flag(u"mode"_s)) {
        printLine(scheme.mode());
    }
    if (parsed.flag(u"variant"_s)) {
        printLine(scheme.variant());
    }
    return 0;
}

int schemeSet(const Paths& paths, const QStringList& arguments) {
    const auto parsed = parseOptions(
        arguments,
        {{{}, u"--notify"_s, u"notify"_s},
         {u"-r"_s, u"--random"_s, u"random"_s},
         {u"-n"_s, u"--name"_s, u"name"_s, Kind::Value, schemeNames(paths)},
         {u"-f"_s, u"--flavour"_s, u"flavour"_s, Kind::Value},
         {u"-m"_s, u"--mode"_s, u"mode"_s, Kind::Value, {u"dark"_s, u"light"_s}},
         {u"-v"_s, u"--variant"_s, u"variant"_s, Kind::Value, schemeVariants}});

    const auto config = loadUserConfig(paths);
    const ThemeLock lock(paths.themeLock);
    auto scheme = Scheme::load(paths);
    scheme.setNotify(parsed.flag(u"notify"_s));

    if (parsed.flag(u"random"_s)) {
        scheme.setRandom();
    } else if (parsed.flag(u"name"_s) || parsed.flag(u"flavour"_s) || parsed.flag(u"mode"_s)
               || parsed.flag(u"variant"_s)) {
        scheme.select(parsed.value(u"name"_s), parsed.value(u"flavour"_s), parsed.value(u"mode"_s),
                      parsed.value(u"variant"_s));
    } else {
        printLine(u"No args given. Use --name, --flavour, --mode, --variant or --random to set a scheme"_s);
        return 0;
    }

    applyColours(lock, paths, config, scheme.colours(), scheme.mode());
    return 0;
}

int wallpaperCommand(const Paths& paths, const QStringList& arguments) {
    const auto current = currentWallpaper(paths);
    const auto parsed = parseOptions(
        arguments,
        {{u"-p"_s, u"--print"_s, u"print"_s, Kind::Optional, {}, current.value_or(QString())},
         {u"-r"_s, u"--random"_s, u"random"_s, Kind::Optional, {}, paths.wallpapersDir},
         {u"-f"_s, u"--file"_s, u"file"_s, Kind::Value},
         {u"-n"_s, u"--no-filter"_s, u"no-filter"_s},
         {u"-t"_s, u"--threshold"_s, u"threshold"_s, Kind::Value},
         {u"-N"_s, u"--no-smart"_s, u"no-smart"_s}});

    const auto noSmart = parsed.flag(u"no-smart"_s);

    if (!parsed.value(u"print"_s).isEmpty()) {
        const auto palette = coloursForWallpaper(paths, parsed.value(u"print"_s), noSmart);
        auto json = JsonValue::object();
        json.set("name", JsonValue::string(palette.name.toStdString()));
        json.set("flavour", JsonValue::string(palette.flavour.toStdString()));
        json.set("mode", JsonValue::string(palette.mode.toStdString()));
        json.set("variant", JsonValue::string(palette.variant.toStdString()));
        json.set("colours", coloursToJson(palette.colours));
        printLine(dumpJson(json));
    } else if (!parsed.value(u"file"_s).isEmpty()) {
        setWallpaper(paths, parsed.value(u"file"_s), noSmart);
    } else if (!parsed.value(u"random"_s).isEmpty()) {
        RandomOptions options;
        options.directory = parsed.value(u"random"_s);
        options.noFilter = parsed.flag(u"no-filter"_s);
        options.noSmart = noSmart;
        if (parsed.flag(u"threshold"_s)) {
            bool ok = false;
            options.threshold = parsed.value(u"threshold"_s).toDouble(&ok);
            if (!ok) {
                throw UsageError(("argument -t/--threshold: invalid float value: '" + parsed.value(u"threshold"_s) + "'")
                                     .toStdString());
            }
        }
        setRandomWallpaper(paths, options);
    } else {
        printLine(current && !current->isEmpty() ? *current : u"No wallpaper set"_s);
    }
    return 0;
}

int dispatch(const QStringList& arguments) {
    // Top-level options precede the command word.
    qsizetype commandIndex = 0;
    bool version = false;
    for (; commandIndex < arguments.size() && looksLikeOption(arguments[commandIndex]); commandIndex++) {
        const auto& argument = arguments[commandIndex];
        if (argument == u"-h" || argument == u"--help") {
            throw HelpRequested();
        }
        if (argument == u"-v" || (argument.size() > 2 && QStringView(u"--version").startsWith(argument))) {
            version = true;
        } else {
            throw UsageError(("unrecognized arguments: " + argument).toStdString());
        }
    }

    if (version) {
        printLine(u"burl " + QStringLiteral(BURL_VERSION) + u" (" + QStringLiteral(BURL_GIT_REVISION) + u")");
        return 0;
    }
    if (commandIndex >= arguments.size()) {
        printHelp(topHelp);
        return 0;
    }

    const auto command = arguments[commandIndex];
    const auto rest = arguments.mid(commandIndex + 1);

    if (command == u"wallpaper") {
        if (rest.contains(u"-h") || rest.contains(u"--help")) {
            printHelp(wallpaperHelp);
            return 0;
        }
        return wallpaperCommand(Paths::fromEnvironment(), rest);
    }

    if (command != u"scheme") {
        throw UsageError(("argument COMMAND: invalid choice: '" + command + "' (choose from 'scheme', 'wallpaper')")
                             .toStdString());
    }

    if (rest.isEmpty()) {
        printHelp(topHelp);
        return 0;
    }
    const auto sub = rest.first();
    const auto subArguments = rest.mid(1);
    const auto wantsHelp = subArguments.contains(u"-h") || subArguments.contains(u"--help");

    if (sub == u"-h" || sub == u"--help") {
        printHelp(schemeHelp);
        return 0;
    }
    if (sub == u"list") {
        if (wantsHelp) {
            printHelp(listHelp);
            return 0;
        }
        return schemeList(Paths::fromEnvironment(), subArguments);
    }
    if (sub == u"get") {
        if (wantsHelp) {
            printHelp(getHelp);
            return 0;
        }
        return schemeGet(Paths::fromEnvironment(), subArguments);
    }
    if (sub == u"set") {
        if (wantsHelp) {
            printHelp(setHelp);
            return 0;
        }
        return schemeSet(Paths::fromEnvironment(), subArguments);
    }
    throw UsageError(("argument {list,get,set}: invalid choice: '" + sub + "' (choose from 'list', 'get', 'set')").toStdString());
}

} // namespace

int runCli(const QStringList& arguments) {
    try {
        const auto status = dispatch(arguments);
        std::fflush(stdout);
        return status;
    } catch (const HelpRequested&) {
        printHelp(topHelp);
        return 0;
    } catch (const UsageError& error) {
        std::fprintf(stderr, "burl: error: %s\n", error.what());
        return exitUsage;
    } catch (const std::exception& error) {
        std::fflush(stdout);
        std::fprintf(stderr, "burl: %s\n", error.what());
        return 1;
    }
}

} // namespace burl
