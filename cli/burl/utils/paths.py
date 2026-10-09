import hashlib
import json
import os
import shutil
import tempfile
from pathlib import Path

config_dir = Path(os.getenv("XDG_CONFIG_HOME", Path.home() / ".config"))
data_dir = Path(os.getenv("XDG_DATA_HOME", Path.home() / ".local/share"))
state_dir = Path(os.getenv("XDG_STATE_HOME", Path.home() / ".local/state"))
cache_dir = Path(os.getenv("XDG_CACHE_HOME", Path.home() / ".cache"))
pictures_dir = Path(os.getenv("XDG_PICTURES_DIR", Path.home() / "Pictures"))
videos_dir = Path(os.getenv("XDG_VIDEOS_DIR", Path.home() / "Videos"))

c_config_dir = config_dir / "burl"
c_data_dir = data_dir / "burl"
c_state_dir = state_dir / "burl"
c_cache_dir = cache_dir / "burl"

user_config_path = c_config_dir / "cli.json"
cli_data_dir = Path(__file__).parent.parent / "data"
templates_dir = cli_data_dir / "templates"
user_templates_dir = c_config_dir / "templates"
theme_dir = c_state_dir / "theme"

scheme_path = c_state_dir / "scheme.json"
scheme_data_dir = cli_data_dir / "schemes"
scheme_cache_dir = c_cache_dir / "schemes"

# Wallpaper directory resolution order:
#   1. QS_WALLPAPERS_DIR env var (or legacy BURL_WALLPAPERS_DIR)
#   2. ~/.config/burl/shell.json `paths.wallpaperDir` (set by the QML
#      shell — the canonical user-facing setting)
#   3. $XDG_PICTURES_DIR/Wallpapers fallback
def _resolve_wallpapers_dir() -> Path:
    env = os.getenv("QS_WALLPAPERS_DIR") or os.getenv("BURL_WALLPAPERS_DIR")
    if env:
        return Path(env)
    shell_json = c_config_dir / "shell.json"
    if shell_json.exists():
        try:
            data = json.loads(shell_json.read_text())
            if (p := data.get("paths", {}).get("wallpaperDir")):
                return Path(os.path.expanduser(p))
        except (json.JSONDecodeError, OSError):
            pass
    return pictures_dir / "Wallpapers"


wallpapers_dir = _resolve_wallpapers_dir()
wallpaper_path_path = c_state_dir / "wallpaper/path.txt"
wallpaper_link_path = c_state_dir / "wallpaper/current"
wallpaper_thumbnail_path = c_state_dir / "wallpaper/thumbnail.jpg"
wallpapers_cache_dir = c_cache_dir / "wallpapers"

screenshots_dir = os.getenv("BURL_SCREENSHOTS_DIR", pictures_dir / "Screenshots")
screenshots_cache_dir = c_cache_dir / "screenshots"

recordings_dir = os.getenv("BURL_RECORDINGS_DIR", videos_dir / "Recordings")
recording_path = c_state_dir / "record/recording.mp4"
recording_notif_path = c_state_dir / "record/notifid.txt"


def compute_hash(path: Path | str) -> str:
    sha = hashlib.sha256()

    with open(path, "rb") as f:
        while chunk := f.read(8192):
            sha.update(chunk)

    return sha.hexdigest()


def atomic_dump(path: Path, content: dict[str, any]) -> None:
    with tempfile.NamedTemporaryFile("w") as f:
        json.dump(content, f)
        f.flush()
        shutil.move(f.name, path)
