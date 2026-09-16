#!/usr/bin/env python3
"""Regression checks for the per-user Marble GTK4 activation helper."""

from contextlib import redirect_stderr, redirect_stdout
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import stat
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = ROOT / "packages/arch-linux-marble-profile/gtk4-session"
SERVICE_PATH = ROOT / "packages/arch-linux-marble-profile/arch-linux-marble-gtk4.service"


def load_helper():
    loader = importlib.machinery.SourceFileLoader("gtk4_session", str(HELPER_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


gtk4 = load_helper()


class UserFixture:
    def __init__(self, root):
        self.root = Path(root)
        self.home = self.root / "home/alice"
        self.home.mkdir(parents=True)
        self.marker = self.root / "var/lib/arch-linux-marble/gtk4-enabled"
        self.marker.parent.mkdir(parents=True)
        self.marker.write_bytes(b"")
        self.uid = os.getuid()

    @property
    def default_config(self):
        return self.home / ".config"

    @property
    def state(self):
        return self.home / ".local/state/arch-linux-marble/gtk4.json"

    def apply(self, config_home=None, theme="Colloid-Dark"):
        return gtk4.apply_user(
            home=self.home,
            config_home=config_home,
            marker_path=self.marker,
            theme_reader=lambda: theme,
            uid=self.uid,
            marker_uid=self.uid,
        )

    def remove(self, config_home=None):
        return gtk4.remove_user(home=self.home, config_home=config_home, uid=self.uid)


class Gtk4SessionChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.fixture = UserFixture(self.temporary.name)

    def css_paths(self, config_home=None):
        root = config_home or self.fixture.default_config
        return root / "gtk-4.0/gtk.css", root / "gtk-4.0/gtk-dark.css"

    def test_apply_replaces_both_css_files_without_backups_and_is_idempotent(self):
        css, dark = self.css_paths()
        css.parent.mkdir(parents=True)
        css.write_text("user css\n")
        dark.write_text("user dark css\n")
        servers = css.parent / "servers"
        servers.write_text("keep me\n")

        self.assertTrue(self.fixture.apply())
        first_state = self.fixture.state.read_bytes()
        self.assertEqual(css.read_bytes(), gtk4.CSS_BYTES)
        self.assertEqual(dark.read_bytes(), gtk4.CSS_BYTES)
        self.assertEqual(servers.read_text(), "keep me\n")
        self.assertEqual(sorted(p.name for p in css.parent.iterdir()),
                         ["gtk-dark.css", "gtk.css", "servers"])

        self.assertTrue(self.fixture.apply())
        self.assertEqual(self.fixture.state.read_bytes(), first_state)
        self.assertEqual(css.read_bytes(), gtk4.CSS_BYTES)
        self.assertEqual(dark.read_bytes(), gtk4.CSS_BYTES)

    def test_custom_xdg_config_path_is_recorded_and_removed_without_session_env(self):
        custom = self.fixture.root / "custom/config"
        css, dark = self.css_paths(custom)
        self.assertTrue(self.fixture.apply(custom))
        state = json.loads(self.fixture.state.read_text())
        self.assertEqual(state, {"paths": [str(css), str(dark)], "version": 1})

        self.fixture.remove()
        self.assertFalse(css.exists())
        self.assertFalse(dark.exists())
        self.assertFalse(self.fixture.state.exists())

    def test_css_symlinks_are_replaced_without_modifying_targets(self):
        css, dark = self.css_paths()
        css.parent.mkdir(parents=True)
        target_one = self.fixture.root / "target-one"
        target_two = self.fixture.root / "target-two"
        target_one.write_text("one\n")
        target_two.write_text("two\n")
        css.symlink_to(target_one)
        dark.symlink_to(target_two)

        self.assertTrue(self.fixture.apply())
        self.assertTrue(css.is_file())
        self.assertFalse(css.is_symlink())
        self.assertTrue(dark.is_file())
        self.assertFalse(dark.is_symlink())
        self.assertEqual(target_one.read_text(), "one\n")
        self.assertEqual(target_two.read_text(), "two\n")

    def test_foreign_directory_preflight_prevents_partial_replacement(self):
        css, dark = self.css_paths()
        css.parent.mkdir(parents=True)
        css.write_text("preserve before failure\n")
        dark.mkdir()

        with self.assertRaises(gtk4.UnsafePathError):
            self.fixture.apply()

        self.assertEqual(css.read_text(), "preserve before failure\n")
        self.assertTrue(dark.is_dir())
        self.assertFalse(self.fixture.state.exists())

    def test_mid_write_failure_removes_partial_helper_content(self):
        css, dark = self.css_paths()
        real_write = gtk4._atomic_write

        def fail_second(path, content, uid):
            if path.name == "gtk-dark.css":
                raise gtk4.HelperError("injected write failure")
            return real_write(path, content, uid)

        with mock.patch.object(gtk4, "_atomic_write", side_effect=fail_second):
            with self.assertRaisesRegex(gtk4.HelperError, "injected write failure"):
                self.fixture.apply()

        self.assertFalse(css.exists())
        self.assertFalse(dark.exists())
        self.assertFalse(self.fixture.state.exists())

    def test_remove_preserves_modified_css_and_foreign_directories(self):
        css, dark = self.css_paths()
        self.fixture.apply()
        css.write_text("replacement chosen by user\n")
        dark.unlink()
        dark.mkdir()

        self.fixture.remove()

        self.assertEqual(css.read_text(), "replacement chosen by user\n")
        self.assertTrue(dark.is_dir())
        self.assertFalse(self.fixture.state.exists())

    def test_remove_handles_missing_and_corrupt_state_using_current_config(self):
        css, dark = self.css_paths()
        css.parent.mkdir(parents=True)
        css.write_bytes(gtk4.CSS_BYTES)
        dark.write_bytes(gtk4.CSS_BYTES)
        self.fixture.remove()
        self.assertFalse(css.exists())
        self.assertFalse(dark.exists())

        css.write_bytes(gtk4.CSS_BYTES)
        dark.write_text("not ours\n")
        self.fixture.state.parent.mkdir(parents=True, exist_ok=True)
        self.fixture.state.write_text("not json")
        self.fixture.remove()
        self.assertFalse(css.exists())
        self.assertEqual(dark.read_text(), "not ours\n")
        self.assertFalse(self.fixture.state.exists())

    def test_disabled_marker_or_theme_cleans_only_owned_files(self):
        css, dark = self.css_paths()
        self.fixture.apply()
        self.fixture.marker.unlink()
        self.assertFalse(self.fixture.apply())
        self.assertFalse(css.exists())
        self.assertFalse(dark.exists())

        self.fixture.marker.write_bytes(b"")
        self.fixture.apply()
        css.write_text("user replacement\n")
        self.assertFalse(self.fixture.apply(theme="Adwaita"))
        self.assertEqual(css.read_text(), "user replacement\n")
        self.assertFalse(dark.exists())

    def test_marker_must_be_regular_and_have_the_exact_required_owner(self):
        self.assertTrue(gtk4.valid_marker(self.fixture.marker, self.fixture.uid))
        self.assertFalse(gtk4.valid_marker(self.fixture.marker, self.fixture.uid + 1))
        self.fixture.marker.unlink()
        target = self.fixture.root / "marker-target"
        target.write_bytes(b"")
        self.fixture.marker.symlink_to(target)
        self.assertFalse(gtk4.valid_marker(self.fixture.marker, self.fixture.uid))

    def test_unsafe_config_parent_symlink_is_refused_without_touching_target(self):
        external = self.fixture.root / "external"
        external.mkdir()
        (external / "gtk-4.0").mkdir()
        sentinel = external / "gtk-4.0/servers"
        sentinel.write_text("untouched\n")
        linked_config = self.fixture.home / ".config"
        linked_config.symlink_to(external)

        with self.assertRaises(gtk4.UnsafePathError):
            self.fixture.apply()

        self.assertEqual(sentinel.read_text(), "untouched\n")
        self.assertFalse((external / "gtk-4.0/gtk.css").exists())

    def test_status_reports_without_mutating(self):
        css, dark = self.css_paths()
        before = sorted(str(p.relative_to(self.fixture.root))
                        for p in self.fixture.root.rglob("*"))
        self.assertEqual(
            gtk4.status_user(self.fixture.home, None, self.fixture.marker,
                             lambda: "Colloid-Dark", self.fixture.uid, self.fixture.uid),
            "inactive",
        )
        self.assertEqual(before, sorted(str(p.relative_to(self.fixture.root))
                                        for p in self.fixture.root.rglob("*")))

        self.fixture.apply()
        css_mtime = css.stat().st_mtime_ns
        dark_mtime = dark.stat().st_mtime_ns
        self.assertEqual(
            gtk4.status_user(self.fixture.home, None, self.fixture.marker,
                             lambda: "Colloid-Dark", self.fixture.uid, self.fixture.uid),
            "active",
        )
        self.assertEqual((css.stat().st_mtime_ns, dark.stat().st_mtime_ns),
                         (css_mtime, dark_mtime))

    def test_uid_min_parser_uses_configured_value_and_default(self):
        configured = self.fixture.root / "login.defs"
        configured.write_text("# UID_MIN 900\n UID_MIN   1250 # local users\n")
        self.assertEqual(gtk4.read_uid_min(configured), 1250)
        self.assertEqual(gtk4.read_uid_min(self.fixture.root / "missing"), 1000)
        configured.write_text("UID_MIN invalid\n")
        self.assertEqual(gtk4.read_uid_min(configured), 1000)

    def test_remove_all_builds_sanitized_commands_for_regular_local_users(self):
        passwd = self.fixture.root / "passwd"
        alice_home = self.fixture.root / "home/alice-dispatch"
        daemon_home = self.fixture.root / "srv/daemon"
        missing_home = self.fixture.root / "home/missing"
        alice_home.mkdir(parents=True)
        daemon_home.mkdir(parents=True)
        regular_uid = self.fixture.uid
        passwd.write_text(
            f"root:x:0:0:root:/root:/bin/bash\n"
            f"daemon:x:999:999:daemon:{daemon_home}:/usr/bin/nologin\n"
            f"alice:x:{regular_uid}:{regular_uid}:Alice:{alice_home}:/bin/bash\n"
            f"missing:x:1300:1300:Missing:{missing_home}:/bin/bash\n"
        )
        runtime_root = self.fixture.root / "run/user"
        runtime = runtime_root / str(regular_uid)
        runtime.mkdir(parents=True)
        bus = socket.socket(socket.AF_UNIX)
        self.addCleanup(bus.close)
        bus.bind(str(runtime / "bus"))
        helper = Path("/usr/lib/arch-linux-marble-profile/gtk4-session")

        commands = gtk4.build_remove_all_commands(
            passwd_path=passwd,
            runtime_root=runtime_root,
            helper_path=helper,
            uid_min_value=1000,
        )

        self.assertEqual(len(commands), 2)
        stop, remove = commands
        clean_prefix = ["/usr/bin/runuser", "-u", "alice", "--", "/usr/bin/env", "-i"]
        self.assertEqual(stop[:6], clean_prefix)
        self.assertIn("XDG_RUNTIME_DIR=" + str(runtime), stop)
        self.assertIn("DBUS_SESSION_BUS_ADDRESS=unix:path=" + str(runtime / "bus"), stop)
        self.assertEqual(stop[-4:], ["/usr/bin/systemctl", "--user", "stop",
                                     "arch-linux-marble-gtk4.service"])
        self.assertEqual(remove[:6], clean_prefix)
        self.assertIn("HOME=" + str(alice_home), remove)
        self.assertEqual(remove[-2:], [str(helper), "remove"])
        self.assertNotIn("daemon", " ".join(" ".join(command) for command in commands))

    def test_dispatcher_skips_system_users_and_inactive_user_bus(self):
        passwd = self.fixture.root / "passwd"
        bob_home = self.fixture.root / "home/bob"
        bob_home.mkdir(parents=True)
        passwd.write_text(f"bob:x:1000:1000:Bob:{bob_home}:/bin/bash\n")
        commands = gtk4.build_remove_all_commands(
            passwd_path=passwd,
            runtime_root=self.fixture.root / "run/user",
            helper_path=Path("/helper"),
            uid_min_value=1000,
        )
        self.assertEqual(len(commands), 1)
        self.assertEqual(commands[0][-2:], ["/helper", "remove"])
        self.assertNotIn("systemctl", commands[0])

    def test_cli_help_validation_and_privilege_boundaries(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(gtk4.main(["--help"]), 0)
        self.assertIn("{apply,remove,status,remove-all}", out.getvalue())

        err = io.StringIO()
        with redirect_stderr(err):
            self.assertNotEqual(gtk4.main(["bogus"]), 0)
        with mock.patch.object(gtk4.os, "geteuid", return_value=0):
            err = io.StringIO()
            with redirect_stderr(err):
                self.assertNotEqual(gtk4.main(["apply"]), 0)
            self.assertIn("must not run as root", err.getvalue())
        with mock.patch.object(gtk4.os, "geteuid", return_value=1000):
            err = io.StringIO()
            with redirect_stderr(err):
                self.assertNotEqual(gtk4.main(["remove-all"]), 0)
            self.assertIn("requires root", err.getvalue())

    def test_service_has_non_blocking_gnome_pre_session_lifecycle(self):
        sections = {}
        current = None
        for line in SERVICE_PATH.read_text().splitlines():
            if line.startswith("["):
                current = line[1:-1]
                sections[current] = {}
            elif line and not line.startswith("#"):
                key, value = line.split("=", 1)
                sections[current][key] = value
        self.assertEqual(sections["Unit"]["Before"], "gnome-session-pre.target")
        self.assertEqual(sections["Unit"]["PartOf"], "gnome-session-pre.target")
        self.assertNotIn("Requires", sections["Unit"])
        self.assertEqual(sections["Service"]["Type"], "oneshot")
        self.assertEqual(sections["Service"]["RemainAfterExit"], "yes")
        self.assertEqual(sections["Service"]["ExecStart"],
                         "-/usr/lib/arch-linux-marble-profile/gtk4-session apply")
        self.assertEqual(sections["Service"]["ExecStop"],
                         "-/usr/lib/arch-linux-marble-profile/gtk4-session remove")
        self.assertEqual(sections["Install"]["WantedBy"], "gnome-session-pre.target")


if __name__ == "__main__":
    unittest.main(verbosity=2)
