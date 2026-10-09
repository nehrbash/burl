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

## Development

The root contains the QML shell and `plugin/`; `cli/` contains the Python
appearance tool. `bin/` contains runtime helpers and `scripts/` contains
rendering and validation tools. Guix recipes live in Cellar.

Run `make check` for JavaScript regressions. `make check-lifecycle` exercises
native QML components in a running Wayland session with the Burl plugin on
`QML_IMPORT_PATH`. The probes use separate instances of Quickshell.

The optional Org/task integration requires a compatible Emacs configuration;
it is not required to use the desktop shell. Guix actions are configurable
command arrays; the default action runs `guix pull`.
