import json
import os
import re
import subprocess
from pathlib import Path
import tempfile
import shutil
import fcntl
import sys

from burl.utils.colour import get_dynamic_colours
from burl.utils.logging import log_exception, log_message
from burl.utils.paths import (
    c_state_dir,
    config_dir,
    data_dir,
    templates_dir,
    theme_dir,
    user_config_path,
    user_templates_dir,
)


def gen_conf(colours: dict[str, str]) -> str:
    conf = ""
    for name, colour in colours.items():
        conf += f"${name} = {colour}\n"
    return conf


def gen_scss(colours: dict[str, str]) -> str:
    scss = ""
    for name, colour in colours.items():
        scss += f"${name}: #{colour};\n"
    return scss


def gen_replace(colours: dict[str, str], template: Path, hash: bool = False) -> str:
    template = template.read_text()
    for name, colour in colours.items():
        template = template.replace(f"{{{{ ${name} }}}}", f"#{colour}" if hash else colour)
    return template


def gen_replace_dynamic(colours: dict[str, str], template: Path, mode: str) -> str:
    def fill_colour(match: re.Match) -> str:
        data = match.group(1).strip().split(".")
        if len(data) != 2:
            return match.group()
        col, form = data
        if col not in colours_dyn or not hasattr(colours_dyn[col], form):
            return match.group()
        return getattr(colours_dyn[col], form)

    # match atomic {{ . }} pairs
    dotField = r"\{\{((?:(?!\{\{|\}\}).)*)\}\}"

    # match {{ mode }}
    modeField = r"\{\{\s*mode\s*\}\}"

    colours_dyn = get_dynamic_colours(colours)
    template_content = template.read_text()

    template_filled = re.sub(dotField, fill_colour, template_content) 
    template_filled = re.sub(modeField, mode, template_filled)

    return template_filled


def c2s(c: str, *i: list[int]) -> str:
    """Hex to ANSI sequence (e.g. ffffff, 11 -> \x1b]11;rgb:ff/ff/ff\x1b\\)"""
    return f"\x1b]{';'.join(map(str, i))};rgb:{c[0:2]}/{c[2:4]}/{c[4:6]}\x1b\\"


def gen_sequences(colours: dict[str, str]) -> str:
    """
    10: foreground
    11: background
    12: cursor
    17: selection
    4:
        0 - 7: normal colours
        8 - 15: bright colours
        16+: 256 colours
    """
    return (
        c2s(colours["onSurface"], 10)
        + c2s(colours["surface"], 11)
        + c2s(colours["secondary"], 12)
        + c2s(colours["secondary"], 17)
        + c2s(colours["term0"], 4, 0)
        + c2s(colours["term1"], 4, 1)
        + c2s(colours["term2"], 4, 2)
        + c2s(colours["term3"], 4, 3)
        + c2s(colours["term4"], 4, 4)
        + c2s(colours["term5"], 4, 5)
        + c2s(colours["term6"], 4, 6)
        + c2s(colours["term7"], 4, 7)
        + c2s(colours["term8"], 4, 8)
        + c2s(colours["term9"], 4, 9)
        + c2s(colours["term10"], 4, 10)
        + c2s(colours["term11"], 4, 11)
        + c2s(colours["term12"], 4, 12)
        + c2s(colours["term13"], 4, 13)
        + c2s(colours["term14"], 4, 14)
        + c2s(colours["term15"], 4, 15)
        + c2s(colours["primary"], 4, 16)
        + c2s(colours["secondary"], 4, 17)
        + c2s(colours["tertiary"], 4, 18)
    )


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


@log_exception
def apply_terms(sequences: str) -> None:
    state = c_state_dir / "sequences.txt"
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text(sequences)

    pts_path = Path("/dev/pts")
    for pt in pts_path.iterdir():
        if pt.name.isdigit():
            try:
                # Non-blocking so a stuck terminal doesn't hang the whole apply.
                import os
                fd = os.open(str(pt), os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
                try:
                    os.write(fd, sequences.encode())
                finally:
                    os.close(fd)
            except (PermissionError, OSError, BlockingIOError):
                # Skip terminals that are busy, closed, or inaccessible
                pass


def hyprctl(arguments: list[str], action: str) -> str:
    try:
        result = subprocess.run(["hyprctl", *arguments], check=True,
                                capture_output=True, text=True, timeout=5)
        return result.stdout
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or f"exit status {error.returncode}").strip()
        raise RuntimeError(f"Hyprland {action} failed: {detail}") from error
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"Hyprland {action} failed: {error}") from error


def lua_string(value: str) -> str:
    # Decimal byte escapes avoid JSON's Lua-incompatible Unicode escapes.
    return '"' + "".join(f"\\{byte:03d}" for byte in value.encode("utf-8")) + '"'


@log_exception
def apply_hypr(conf: str) -> None:
    write_file(config_dir / "hypr/scheme/current.conf", conf)
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return
    monitors = json.loads(hyprctl(["-j", "monitors", "all"], "monitor query"))
    if not isinstance(monitors, list):
        raise ValueError("Hyprland monitor query did not return a list")
    disabled = []
    for monitor in monitors:
        if monitor.get("disabled") is True:
            name = monitor.get("name")
            if not isinstance(name, str) or not name:
                raise ValueError("Hyprland disabled monitor has no output name")
            disabled.append(name)
    errors = []
    try:
        hyprctl(["reload"], "reload")
    except RuntimeError as error:
        errors.append(str(error))
    for name in disabled:
        try:
            hyprctl(["eval", f"hl.monitor({{ output = {lua_string(name)}, disabled = true }})"],
                    f"restore disabled output {name!r}")
        except RuntimeError as error:
            errors.append(str(error))
    if errors:
        raise RuntimeError("; ".join(errors))


@log_exception
def apply_discord(scss: str) -> None:
    import tempfile

    # Only the client-mod config dirs (Vencord, Equicord, ...) read this file.
    # Vanilla/Flatpak Discord never does, so there is nothing to generate for
    # unless one of these actually exists.
    clients = ("Equicord", "Vencord", "BetterDiscord", "equibop", "vesktop", "legcord")
    installed = [client for client in clients if (config_dir / client).is_dir()]
    if not installed:
        log_message("apply_discord(): no client-mod config dir found, skipping")
        return

    sass_bin = shutil.which("sass")
    if sass_bin is None:
        log_message(
            "apply_discord(): found client-mod dir(s) "
            f"{', '.join(installed)} but no `sass` (dart-sass) binary on "
            "PATH, skipping theme generation"
        )
        return

    with tempfile.TemporaryDirectory("w") as tmp_dir:
        (Path(tmp_dir) / "_colours.scss").write_text(scss)
        conf = subprocess.check_output([sass_bin, "-I", tmp_dir, templates_dir / "discord.scss"], text=True)

    for client in installed:
        write_file(config_dir / client / "themes/burl.theme.css", conf)

@log_exception
def apply_pandora(colours: dict[str, str], mode: str) -> None:
    template = gen_replace(colours, templates_dir / "pandora.json", hash=True)
    template = template.replace("{{ $mode }}", mode)
    write_file(data_dir / "PandoraLauncher/themes/burl.json", template)


@log_exception
def apply_spicetify(colours: dict[str, str], mode: str) -> None:
    template = gen_replace(colours, templates_dir / f"spicetify-{mode}.ini")
    write_file(config_dir / "spicetify/Themes/burl/color.ini", template)
    try:
        subprocess.run(["spicetify", "refresh"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass


@log_exception
def apply_fuzzel(colours: dict[str, str]) -> None:
    template = gen_replace(colours, templates_dir / "fuzzel.ini")
    write_file(config_dir / "fuzzel/fuzzel.ini", template)


@log_exception
def apply_satty(colours: dict[str, str]) -> None:
    # Two files: config.toml carries the annotation palette, overrides.css the
    # toolbar chrome. Satty's generic GTK-4 widgets are already covered by the
    # ~/.config/gtk-4.0/gtk.css Guix deploys from (desktop burl) --
    # overrides.css exists because satty's own toolbars ship a hardcoded
    # translucent-black sheet that gtk.css does not reach.
    template = gen_replace(colours, templates_dir / "satty.toml", hash=True)
    write_file(config_dir / "satty/config.toml", template)

    css = gen_replace(colours, templates_dir / "satty-overrides.css", hash=True)
    write_file(config_dir / "satty/overrides.css", css)


@log_exception
def apply_btop(colours: dict[str, str]) -> None:
    template = gen_replace(colours, templates_dir / "btop.theme", hash=True)
    write_file(config_dir / "btop/themes/burl.theme", template)
    subprocess.run(["killall", "-USR2", "btop"], stderr=subprocess.DEVNULL)


@log_exception
def apply_nvtop(colours: dict[str, str]) -> None:
    template = gen_replace(colours, templates_dir / "nvtop.colors", hash=True)
    write_file(config_dir / "nvtop/nvtop.colors", template)


@log_exception
def apply_htop(colours: dict[str, str]) -> None:
    template = gen_replace(colours, templates_dir / "htop.theme", hash=True)
    write_file(config_dir / "htop/htoprc", template)
    subprocess.run(["killall", "-USR2", "htop"], stderr=subprocess.DEVNULL)


# GTK theming is NOT here: ~/.config/gtk-{3,4}.0/gtk.css and the
# gtk-theme/icon-theme/color-scheme dconf keys are owned by Guix
# ((desktop burl) + common-gtk-dconf-service in home/oceania.scm).
# It used to be an apply_gtk() here, which fought the declarative dconf entries
# for the same keys -- last writer won, and after a `guix home reconfigure' that
# was Guix, leaving GTK apps on a static theme that ignores the palette.  The
# scheme is a fixed named one, so nothing about GTK needs to be decided at
# runtime.  Changing scheme or light/dark mode now needs a reconfigure to reach
# GTK apps.


@log_exception
def apply_qt(colours: dict[str, str], mode: str) -> None:
    template = gen_replace(colours, templates_dir / f"qt{mode}.colors", hash=True)
    write_file(config_dir / "qt5ct/colors/burl.colors", template)
    write_file(config_dir / "qt6ct/colors/burl.colors", template)

    qtct = (templates_dir / "qtct.conf").read_text()
    qtct = qtct.replace("{{ $mode }}", mode.capitalize())

    for ver in 5, 6:
        conf = qtct.replace("{{ $config }}", str(config_dir / f"qt{ver}ct"))

        if ver == 5:
            conf += """
[Fonts]
fixed="Monospace,12,-1,5,50,0,0,0,0,0"
general="Sans Serif,12,-1,5,50,0,0,0,0,0"
"""
        else:
            conf += """
[Fonts]
fixed="Monospace,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
general="Sans Serif,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
"""
        write_file(config_dir / f"qt{ver}ct/qt{ver}ct.conf", conf)


@log_exception
def apply_warp(colours: dict[str, str], mode: str) -> None:
    warp_mode = "darker" if mode == "dark" else "lighter"

    template = gen_replace(colours, templates_dir / "warp.yaml", hash=True)
    template = template.replace("{{ $warp_mode }}", warp_mode)
    write_file(data_dir / "warp-terminal/themes/burl.yaml", template)


@log_exception
def apply_cava(colours: dict[str, str]) -> None:
    template = gen_replace(colours, templates_dir / "cava.conf", hash=True)
    write_file(config_dir / "cava/config", template)
    subprocess.run(["killall", "-USR2", "cava"], stderr=subprocess.DEVNULL)


@log_exception
def apply_user_templates(colours: dict[str, str], mode: str) -> None:
    if not user_templates_dir.is_dir():
        return

    for file in user_templates_dir.iterdir():
        if file.is_file():
            content = gen_replace_dynamic(colours, file, mode)
            write_file(theme_dir / file.name, content)


def apply_colours(colours: dict[str, str], mode: str) -> None:
    lock_file = c_state_dir / "theme.lock"
    c_state_dir.mkdir(parents=True, exist_ok=True)
    
    with open(lock_file, "a") as lock_fd:
        fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)
        try:
            cfg = json.loads(user_config_path.read_text())["theme"]
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            cfg = {}

        def check(key: str) -> bool:
            return cfg[key] if key in cfg else True

        if check("enableTerm"):
            apply_terms(gen_sequences(colours))
        if check("enableHypr"):
            apply_hypr(gen_conf(colours))
        if check("enableDiscord"):
            apply_discord(gen_scss(colours))
        if check("enableSpicetify"):
            apply_spicetify(colours, mode)
        if check("enablePandora"):
            apply_pandora(colours, mode)
        if check("enableFuzzel"):
            apply_fuzzel(colours)
        if check("enableSatty"):
            apply_satty(colours)
        if check("enableBtop"):
            apply_btop(colours)
        if check("enableNvtop"):
            apply_nvtop(colours)
        if check("enableHtop"):
            apply_htop(colours)
        if check("enableQt"):
            apply_qt(colours, mode)
        if check("enableWarp"):
            apply_warp(colours, mode)
        if check("enableCava"):
            apply_cava(colours)
        apply_user_templates(colours, mode)
