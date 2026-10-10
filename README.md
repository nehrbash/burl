# Burl

Burl is a Hyprland desktop shell built with Quickshell and a C++ QML plugin.
It includes a panel, launcher, notifications, lock screen, media controls,
wallpaper tools and an animated woodland desktop.

The [Cellar Guix channel](https://github.com/nehrbash/cellar) packages Burl and
provides its Home and System services. Personal machine configuration belongs
in the consuming Home/System configuration.

`burl-shell` runs the shell; `burl-shell ipc` addresses its IPC interface.
`burl scheme` and `burl wallpaper` manage appearance. User settings and state
live under the XDG configuration, state and cache directories. The shell's
settings UI writes `~/.config/burl/shell.json`; keep that file writable.

Apps → Burl launch preferences selects applications for Burl actions. File and
media choices can follow the desktop's MIME associations with “Desktop default”.
These preferences do not change system defaults or compositor keybindings.
Selected applications are saved by desktop-entry ID and resolved when launched;
custom command arrays remain supported in `general.apps`.

Wallpaper & style → Colours selects a palette for panels, text and controls.
Nocturne pairs neutral dark surfaces with brass accents; other schemes include
light appearances where supported. Painted artwork keeps its original colours.

## Launcher search

Type filters can follow the query: `steam >app` is equivalent to `>app steam`.
Use `>app|roam steam` to search both types, or `>app steam >roam notes` for
independent queries. Text before the first filter applies to every branch.
Singular and plural type names work; Tab completes filter names.

Exact names rank first, followed by prefixes, whole-word starts, substrings,
and fuzzy matches. Every query word must match; app descriptions and keywords
can contribute lower-ranked results. Long words tolerate one typing error.
Arrows navigate spatially within matching nodes; Tab and Shift+Tab cycle by
rank. Clearing the search restores unrestricted graph browsing.

## Hyprland integration

Cellar installs the Lua modules under `~/.config/hypr/burl/`. In a custom
Hyprland Lua configuration, load the theme after loading optional plugins:

```lua
local config = os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config"
local burl = dofile(config .. "/hypr/burl/init.lua")
local theme = burl.theme()
theme.apply()
burl.layer_rules()
```

`theme.apply(overrides)` accepts a nested `hl.config` table to override colour
roles. `theme.rgb(role)` and `theme.rgba(role, alpha)` supply colours for custom
rules and title-bar buttons. Missing palette entries use Nocturne defaults.
Personal layouts, bindings, application rules and plugin loading remain in
the consuming configuration. Cellar's default configuration imports Burl directly.

Theme changes atomically write `hypr/scheme/current.conf` and reload the active
Hyprland instance, preserving disabled outputs. Offline changes take effect at the next compositor start;
reload failures are logged and the saved palette remains available for retry.
Disable this integration with `theme.enableHypr: false` in `burl/cli.json`.

The same directory provides `lib.lua` (bindings, submaps and rules),
`actions.lua` (Burl IPC and desktop actions), and configurable workspace
autostart and scratchpad helpers. Import the helpers you use with `dofile`;
construct them during config loading so their state follows the compositor's
configuration lifecycle. They do not choose your keybindings or applications.

## Development

The root contains the QML shell and `plugin/`; `cli/` contains the Python
appearance tool. `bin/` contains runtime helpers and `scripts/` contains
rendering and validation tools. Guix recipes live in Cellar.

Run `make check` for behavioral regressions. `make check-lifecycle` exercises
native QML components in a running Wayland session with the Burl plugin on
`QML_IMPORT_PATH`. The probes use separate instances of Quickshell.
See [state models](docs/README.org) for lifecycle diagrams and focused native checks.

The optional Org/task integration requires a compatible Emacs configuration;
it is not required to use the desktop shell. Guix actions are configurable
command arrays; the default action runs `guix pull`.

Desktop defaults can be supplied as JSON through `BURL_DEFAULTS_FILE`.
Values in the writable `shell.json` override those defaults. Restart the shell
after changing the defaults file. Optional personal integrations use
`BURL_CALENDAR_FILE`, `BURL_EMACS_STATE_DB`, `BURL_ORG_ROAM_DB`, and
`BURL_EMACS_INTEGRATION=1` for task actions. They are disabled by default.

`BURL_MANAGE_LLAMA=1` lets performance mode pause a running Shepherd
`llama-server` service and resume it afterward. It is disabled by default.

The Windows boot action is hidden unless `session.commands.windows` is set
in the desktop defaults or user settings. Its command must select the next
boot target without prompting; Burl reboots only after it succeeds.
