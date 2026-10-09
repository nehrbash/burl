import json
import multiprocessing
import time
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "cli"))
from burl.utils import scheme


class SchemeTransitions(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / "scheme.json"
        self.path_patch = patch.object(scheme, "scheme_path", self.path)
        self.path_patch.start()
        self.current = scheme.Scheme(None)
        self.current.save()

    def tearDown(self):
        self.path_patch.stop()
        self.directory.cleanup()

    def test_selection_is_one_complete_write(self):
        with patch.object(scheme, "atomic_dump", wraps=scheme.atomic_dump) as write:
            self.current.select("catppuccin", "latte")
        self.assertEqual(write.call_count, 1)
        self.assertEqual((self.current.name, self.current.flavour, self.current.mode),
                         ("catppuccin", "latte", "light"))
        self.assertEqual(json.loads(self.path.read_text())["mode"], "light")
        self.current.select("nocturne", "default")
        self.assertEqual(self.current.mode, "dark")

    def test_invalid_choice_preserves_saved_and_current_palette(self):
        before = self.path.read_bytes()
        for arguments in [("unknown",), ("catppuccin", "unknown"),
                          ("nocturne", "default", "light")]:
            with self.assertRaises(ValueError):
                self.current.select(*arguments)
            self.assertEqual(self.path.read_bytes(), before)
            self.assertEqual(self.current.name, "nocturne")

    def test_dynamic_failure_does_not_change_selection(self):
        before = self.path.read_bytes()
        with patch("burl.utils.material.get_colours_for_image", side_effect=FileNotFoundError):
            with self.assertRaises(ValueError):
                self.current.select("dynamic", "default")
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(self.current.name, "nocturne")

    def test_dynamic_uses_candidate_configuration(self):
        colours = self.current.colours
        with patch("burl.utils.material.get_colours_for_image", return_value=colours) as generate:
            self.current.select("dynamic", "hard", "light", "neutral")
        candidate = generate.call_args.kwargs["scheme"]
        self.assertEqual((candidate.flavour, candidate.mode, candidate.variant),
                         ("hard", "light", "neutral"))


class ApplicationUpdates(unittest.TestCase):
    def test_concurrent_updates_are_serialized_without_dropping_one(self):
        from burl.utils import theme
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "cli.json"
            log = root / "calls"
            import re
            keys = re.findall(r'check\("([^"]+)"\)', Path(theme.__file__).read_text())
            config.write_text(json.dumps({"theme": dict.fromkeys(keys, False)}))

            def apply(colours, mode):
                with log.open("a") as stream:
                    stream.write("start\n")
                time.sleep(0.05)
                with log.open("a") as stream:
                    stream.write("end\n")

            with patch.object(theme, "c_state_dir", root), patch.object(theme, "user_config_path", config), \
                 patch.object(theme, "apply_user_templates", apply):
                processes = [multiprocessing.get_context("fork").Process(
                    target=theme.apply_colours, args=({}, "dark")) for _ in range(3)]
                for process in processes:
                    process.start()
                for process in processes:
                    process.join(5)
                    if process.is_alive():
                        process.kill()
                        process.join()
                    self.assertEqual(process.exitcode, 0)
            self.assertEqual(log.read_text().splitlines(), ["start", "end"] * 3)


if __name__ == "__main__":
    unittest.main()
