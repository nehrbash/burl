import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "cli"))
from burl.utils import theme


class HyprlandTheme(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = self.root / "hypr/scheme/current.conf"
        self.path.parent.mkdir(parents=True)
        self.path.write_text("old palette")
        self.enterContext(patch.object(theme, "config_dir", self.root))
        self.enterContext(patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "test-instance"}))

    def test_palette_replaced_atomically_before_reload(self):
        replace = os.replace
        events = []

        def install(source, destination):
            self.assertEqual(source.parent, self.path.parent)
            self.assertEqual(destination, self.path)
            self.assertEqual(self.path.read_text(), "old palette")
            self.assertEqual(source.read_text(), "$primary = aabbcc\n")
            replace(source, destination)
            events.append("write")

        def reload(command, **kwargs):
            self.assertIn(command, [["hyprctl", "-j", "monitors", "all"], ["hyprctl", "reload"]])
            self.assertTrue(kwargs["check"])
            self.assertGreater(kwargs["timeout"], 0)
            self.assertLessEqual(kwargs["timeout"], 5)
            self.assertEqual(self.path.read_text(), "$primary = aabbcc\n")
            events.append("query" if "monitors" in command else "reload")
            return subprocess.CompletedProcess(command, 0, stdout="[]")

        with patch.object(theme.os, "replace", side_effect=install), patch.object(theme.subprocess, "run", side_effect=reload):
            theme.apply_hypr("$primary = aabbcc\n")
        self.assertEqual(events, ["write", "query", "reload"])
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_write_failure_preserves_old_palette_and_does_not_reload(self):
        output = io.StringIO()
        with patch.object(theme.os, "replace", side_effect=PermissionError("read-only target")), patch.object(theme.subprocess, "run") as run, contextlib.redirect_stdout(output):
            theme.apply_hypr("new palette")
        run.assert_not_called()
        self.assertEqual(self.path.read_text(), "old palette")
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])
        self.assertIn("read-only target", output.getvalue())

    def test_offline_write_does_not_require_hyprctl(self):
        with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": ""}), patch.object(theme.subprocess, "run") as run:
            theme.apply_hypr("offline palette")
        run.assert_not_called()
        self.assertEqual(self.path.read_text(), "offline palette")

    def test_reload_failure_logs_compositor_diagnostic(self):
        failure = subprocess.CalledProcessError(1, ["hyprctl", "reload"], stderr="invalid configuration")
        output = io.StringIO()
        with patch.object(theme.subprocess, "run", side_effect=[subprocess.CompletedProcess([], 0, stdout="[]"), failure]), contextlib.redirect_stdout(output):
            theme.apply_hypr("new palette")
        self.assertEqual(self.path.read_text(), "new palette")
        self.assertIn("Hyprland reload failed: invalid configuration", output.getvalue())

    def test_missing_cli_is_logged_after_palette_write(self):
        output = io.StringIO()
        with patch.object(theme.subprocess, "run", side_effect=FileNotFoundError("hyprctl is missing")), contextlib.redirect_stdout(output):
            theme.apply_hypr("new palette")
        self.assertEqual(self.path.read_text(), "new palette")
        self.assertIn("hyprctl is missing", output.getvalue())

    def test_reload_timeout_is_logged(self):
        output = io.StringIO()
        with patch.object(theme.subprocess, "run", side_effect=[subprocess.CompletedProcess([], 0, stdout="[]"), subprocess.TimeoutExpired(["hyprctl", "reload"], 5)]), contextlib.redirect_stdout(output):
            theme.apply_hypr("new palette")
        self.assertIn("timed out", output.getvalue())
        self.assertEqual(self.path.read_text(), "new palette")

    def test_reload_restores_only_disabled_outputs_with_safe_lua_strings(self):
        names = ['eDP-1', 'port"\\\n\x00é; os.exit(7) --']
        monitors = [{"name": "DP-2", "disabled": False},
                    {"name": names[0], "disabled": True},
                    {"name": "DP-3"},
                    {"name": names[1], "disabled": True}]
        commands = []

        def run(command, **kwargs):
            self.assertEqual(self.path.read_text(), "new palette")
            self.assertTrue(kwargs["check"])
            self.assertEqual(kwargs["timeout"], 5)
            commands.append(command)
            return subprocess.CompletedProcess(command, 0, stdout=json.dumps(monitors) if command[1] == "-j" else "ok")

        with patch.object(theme.subprocess, "run", side_effect=run):
            theme.apply_hypr("new palette")
        self.assertEqual(commands[:2], [["hyprctl", "-j", "monitors", "all"], ["hyprctl", "reload"]])
        self.assertEqual(len(commands), 4)
        for name, command in zip(names, commands[2:]):
            self.assertEqual(command[:2], ["hyprctl", "eval"])
            program = "hl = { monitor = function(t) assert(t.disabled == true); io.write(t.output) end }; " + command[2]
            result = subprocess.run(["lua", "-e", program], check=True, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.stdout, name)

    def test_query_failure_aborts_reload_and_logs_diagnostic(self):
        output = io.StringIO()
        failure = subprocess.CalledProcessError(1, ["hyprctl", "-j", "monitors", "all"], stderr="IPC unavailable")
        with patch.object(theme.subprocess, "run", side_effect=failure) as run, contextlib.redirect_stdout(output):
            theme.apply_hypr("new palette")
        self.assertEqual(run.call_count, 1)
        self.assertIn("Hyprland monitor query failed: IPC unavailable", output.getvalue())
        self.assertEqual(self.path.read_text(), "new palette")

    def test_invalid_monitor_response_aborts_reload(self):
        for response in ["not json", "{}", '[{"disabled":true}]']:
            with self.subTest(response=response):
                output = io.StringIO()
                with patch.object(theme.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout=response)) as run, contextlib.redirect_stdout(output):
                    theme.apply_hypr("new palette")
                self.assertEqual(run.call_count, 1)
                self.assertIn('Error during execution of "apply_hypr()"', output.getvalue())

    def test_restore_attempts_all_disabled_outputs_even_after_reload_failure(self):
        output = io.StringIO()
        monitors = [{"name": "eDP-1", "disabled": True}, {"name": "DP-4", "disabled": True}]
        results = [subprocess.CompletedProcess([], 0, stdout=json.dumps(monitors)),
                   subprocess.CalledProcessError(1, ["hyprctl", "reload"], stderr="partial reload failed"),
                   subprocess.CalledProcessError(1, ["hyprctl", "eval"], stderr="output restore failed"),
                   subprocess.CompletedProcess([], 0, stdout="ok")]
        with patch.object(theme.subprocess, "run", side_effect=results) as run, contextlib.redirect_stdout(output):
            theme.apply_hypr("new palette")
        self.assertEqual(run.call_count, 4)
        self.assertIn("Hyprland reload failed: partial reload failed", output.getvalue())
        self.assertIn("restore disabled output 'eDP-1' failed: output restore failed", output.getvalue())


if __name__ == "__main__":
    unittest.main()
