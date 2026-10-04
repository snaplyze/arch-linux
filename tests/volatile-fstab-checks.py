#!/usr/bin/env python3
"""Exercise the emitted production fstab transform without installation or mounts."""
from pathlib import Path
import re
import subprocess
import unittest
import io
import stat
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "arch-linux-installer.sh").read_text()
UUID = b"UUID=12345678-1234-1234-1234-123456789abc"


def production_module():
    match = re.search(r"^volatile_root_fstab_program\(\) \{\n.*?^\}\n", SOURCE, re.M | re.S)
    if match is None:
        raise AssertionError("Missing production function: volatile_root_fstab_program")
    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", "set -euo pipefail\n" + match.group() + "\nvolatile_root_fstab_program"],
        capture_output=True, text=True, timeout=5, check=True,
    )
    namespace = {"__name__": "volatile_fstab_fixture"}
    exec(compile(result.stdout, "production-volatile-fstab", "exec"), namespace)
    if not callable(namespace.get("rewrite_fstab")):
        raise AssertionError("Emitted module must export rewrite_fstab(data: bytes) -> bytes")
    return namespace


def row(options=b"defaults,noatime,compress=zstd,subvol=/@,subvolid=256,ssd,space_cache=v2", source=UUID):
    return source + b"\t/\tbtrfs\t" + options + b"\t0\t0\n"


class VolatileFstabChecks(unittest.TestCase):
    def setUp(self):
        self.rewrite = production_module()["rewrite_fstab"]

    def reject(self, data):
        with self.assertRaises(ValueError):
            self.rewrite(data)

    def test_generated_root_becomes_overlay(self):
        self.assertEqual(self.rewrite(row()), b"overlay\t/\toverlay\tdefaults,noatime\t0\t0\n")

    def test_nonroot_bytes_comments_escaped_paths_and_crlf_survive(self):
        before = b"# original comment\r\n\r\nUUID=abc /home\\040space btrfs defaults,subvol=/@home 0 0\r\n"
        after = b"UUID=def /boot vfat fmask=0077,dmask=0077 0 2\r\n# trailing comment\nUUID=ghi /tab\\011name ext4 defaults 0 2\n"
        self.assertEqual(self.rewrite(before + row().replace(b"\n", b"\r\n") + after),
                         before + b"overlay\t/\toverlay\tdefaults,noatime\t0\t0\n" + after)

    def test_mapper_source_and_empty_generic_fallback(self):
        self.assertEqual(self.rewrite(row(b"compress=zstd,subvol=@", b"/dev/mapper/cryptroot")),
                         b"overlay\t/\toverlay\tdefaults\t0\t0\n")

    def test_canonical_overlay_row_is_idempotent(self):
        data = b"# preserved\r\noverlay\t/\toverlay\trw,nosuid,noexec,noatime\t0\t0\n# last\n"
        self.assertEqual(self.rewrite(data), data)
        self.assertEqual(self.rewrite(self.rewrite(row())), self.rewrite(row()))
        self.reject(data.replace(b"noatime", b"noatime,compress=zstd"))
        self.reject(data.replace(b"overlay\t/", b"UUID=12345678-1234-1234-1234-123456789abc\t/", 1))

    def test_security_and_atime_options_preserve_order(self):
        for options in (b"rw,nodev,nosuid,noexec,nosymfollow,noatime,nodiratime,lazytime",
                        b"ro,dev,suid,exec,symfollow,relatime", b"defaults,strictatime"):
            with self.subTest(options=options):
                self.assertEqual(self.rewrite(row(options + b",compress=zstd:3")),
                                 b"overlay\t/\toverlay\t" + options + b"\t0\t0\n")

    def test_supported_btrfs_options_are_removed(self):
        for option in (b"compress=zstd", b"subvol=/@", b"subvol=@", b"subvolid=1",
                       b"ssd", b"nossd", b"space_cache=v2", b"discard=async") + tuple(
                           b"compress=zstd:" + str(level).encode() for level in range(1, 16)):
            with self.subTest(option=option):
                self.assertEqual(self.rewrite(row(b"nosuid," + option)),
                                 b"overlay\t/\toverlay\tnosuid\t0\t0\n")

    def test_missing_duplicate_and_escaped_root_aliases_reject(self):
        for data in (b"# only comment\n", row() + row(), row().replace(b"\t/\t", b"\t\\057\t"),
                     row() + row().replace(b"\t/\t", b"\t\\057\t")):
            with self.subTest(data=data):
                self.reject(data)

    def test_malformed_root_contract_rejects(self):
        for data in (row().replace(b"btrfs", b"ext4"), row().replace(b"\t0\t0\n", b"\t0\t1\n"),
                     row().replace(b"\t0\t0\n", b"\t1\t0\n"), row().replace(b"\t0\t0\n", b"\t0\n"),
                     row().replace(b"\t0\t0\n", b"\t0\t0\textra\n")):
            with self.subTest(data=data):
                self.reject(data)

    def test_unsupported_sources_reject(self):
        for source in (b"UUID=not-a-uuid", b"UUID=12345678-1234-1234-1234-123456789abg",
                       b"/dev/vda2", b"/dev/mapper/other", b"LABEL=root", b"overlay"):
            with self.subTest(source=source):
                self.reject(row(source=source))

    def test_unknown_filesystem_and_unsafe_options_reject(self):
        for option in (b"compress=zlib", b"compress=zstd:0", b"compress=zstd:16", b"subvol=/@other",
                       b"subvolid=0", b"subvolid=-1", b"space_cache=v1", b"discard=sync",
                       b"nosssd", b"user", b"bind", b"nofail", b"x-systemd.requires=foreign.service", b"unknown", b""):
            with self.subTest(option=option):
                self.reject(row(b"defaults," + option))

    def test_conflicting_security_options_reject(self):
        for first, second in ((b"rw", b"ro"), (b"dev", b"nodev"), (b"suid", b"nosuid"),
                              (b"exec", b"noexec"), (b"symfollow", b"nosymfollow")):
            for options in (first + b"," + second, second + b"," + first):
                with self.subTest(options=options):
                    self.reject(row(options))

    def test_input_bounds_and_controls_reject(self):
        for byte in (b"\0", b"\x01", b"\x0b", b"\x0c", b"\x1b", b"\x7f"):
            with self.subTest(byte=byte):
                self.reject(b"# comment " + byte + b"\n" + row())
        self.reject(row() + b"#" + b"x" * 65536)
        self.reject(row().replace(b"btrfs", b"btrfs\rjunk"))

    def test_arbitrary_persistent_overlay_topology_is_rejected(self):
        namespace = production_module()
        namespace["fd_mount_id"] = lambda fd: b"20"
        for options in (
            b"lowerdir=/lower,upperdir=/persistent/upper,workdir=/persistent/work",
            b"lowerdir=/sysroot:/other,upperdir=/run/systemd/overlay-sysroot/upper,workdir=/run/systemd/overlay-sysroot/work",
            b"lowerdir=/sysroot,upperdir=/persistent/upper,workdir=/run/systemd/overlay-sysroot/work",
            b"lowerdir=/sysroot,upperdir=/run/systemd/overlay-sysroot/upper,workdir=/persistent/work",
            b"lowerdir=/sysroot,lowerdir=/sysroot,upperdir=/run/systemd/overlay-sysroot/upper,workdir=/run/systemd/overlay-sysroot/work",
        ):
            mountinfo = b"20 1 0:5 / / rw - overlay overlay rw," + options + b"\n"
            with self.subTest(options=options), patch("builtins.open", return_value=io.BytesIO(mountinfo)), self.assertRaises(ValueError):
                namespace["root_mount"](51)

    def test_exact_unique_volatile_cmdline_required_and_bounded(self):
        namespace = production_module()
        function = namespace.get("require_volatile_cmdline")
        self.assertTrue(callable(function), "Missing production require_volatile_cmdline")
        with patch("builtins.open", return_value=io.BytesIO(b"rw root=UUID=fixture systemd.volatile=overlay\n")):
            function()
        for data in (
            b"rw root=UUID=fixture\n", b"systemd.volatile=yes", b"systemd.volatile=overlayevil",
            b"systemd.volatile=overlay systemd.volatile=overlay",
            b"systemd.volatile=overlay systemd.volatile=no",
            b"systemd.volatile=overlay\0", b"systemd.volatile=overlay " + b"x" * 65537,
        ):
            with self.subTest(data=data[:80]), patch("builtins.open", return_value=io.BytesIO(data)), self.assertRaises(ValueError):
                function()

    def test_normal_btrfs_adaptation_does_not_open_fstab(self):
        namespace = production_module()
        namespace["root_mount"] = lambda fd: (b"20", b"btrfs")
        with patch.object(namespace["os"], "geteuid", return_value=0), \
                patch.object(namespace["os"], "open", return_value=51) as opened, \
                patch.object(namespace["os"], "close") as closed:
            namespace["adapt"]()
        self.assertEqual(opened.call_count, 1)
        self.assertEqual(opened.call_args.args[0], "/")
        closed.assert_called_once_with(51)

    def adapt_fixture(self, case):
        namespace = production_module()
        native_os = namespace["os"]
        data = row()
        events, opened, closed, written = [], [], [], bytearray()
        parent = SimpleNamespace(st_dev=1, st_ino=2, st_uid=0, st_gid=0, st_mode=stat.S_IFDIR | 0o755)
        original = SimpleNamespace(st_dev=1, st_ino=3, st_uid=0, st_gid=0, st_mode=stat.S_IFREG | 0o644,
                                   st_nlink=1, st_size=len(data), st_mtime_ns=1, st_ctime_ns=1)
        replacement = SimpleNamespace(st_dev=1, st_ino=4, st_uid=0, st_gid=0, st_mode=stat.S_IFREG | 0o600,
                                      st_nlink=1, st_size=0, st_mtime_ns=1, st_ctime_ns=1)
        if case == "foreign-owner": original.st_uid = 1000
        if case == "hardlink": original.st_nlink = 2
        if case == "unsafe-parent": parent.st_mode |= 0o020
        roots = [10]
        reads = [data, b""]
        def open_fd(name, flags, *args, **kwargs):
            opened.append((name, flags))
            if name == "/":
                value = 10 if len(opened) == 1 else 20 + len(roots)
                roots.append(value)
                return value
            if name == "etc": return 11
            if name == "fstab": return 12
            self.assertTrue(name.startswith(".arch-linux-volatile-fstab."))
            events.append("create")
            return 13
        def fstat_fd(fd):
            return {11: parent, 12: original, 13: replacement}[fd]
        def stat_path(name, **kwargs):
            self.assertIs(kwargs["follow_symlinks"], False)
            if name == "etc":
                if case == "parent-replaced": return SimpleNamespace(**{**vars(parent), "st_ino": 99})
                return parent
            if name == "fstab":
                if case == "original-replaced": return SimpleNamespace(**{**vars(original), "st_ino": 99})
                return original
            if case == "temporary-replaced": return SimpleNamespace(**{**vars(replacement), "st_ino": 99})
            return replacement
        def write_fd(fd, pending):
            if case == "zero-write": return 0
            piece = bytes(pending[:2])
            written.extend(piece)
            return len(piece)
        fake_os = SimpleNamespace(**{name: getattr(native_os, name) for name in (
            "O_PATH", "O_DIRECTORY", "O_NOFOLLOW", "O_CLOEXEC", "O_RDONLY", "O_NONBLOCK",
            "O_WRONLY", "O_CREAT", "O_EXCL")})
        fake_os.geteuid = lambda: 0
        fake_os.open, fake_os.fstat, fake_os.stat = open_fd, fstat_fd, stat_path
        fake_os.read = lambda fd, count: reads.pop(0)
        fake_os.write = write_fd
        fake_os.fchmod = lambda fd, mode: events.append(("mode", mode))
        fake_os.fsync = lambda fd: events.append(("sync", fd))
        fake_os.rename = lambda *args, **kwargs: events.append("rename")
        fake_os.unlink = lambda *args, **kwargs: events.append("unlink")
        fake_os.close = closed.append
        namespace["os"] = fake_os
        namespace["require_volatile_cmdline"] = lambda: None
        namespace["root_mount"] = lambda fd: (b"changed" if case == "root-covered" and fd != 10 else b"20", b"overlay")
        namespace["fd_mount_id"] = lambda fd: b"21" if case == "separate-fstab" and fd == 12 else b"20"
        if case == "success": namespace["adapt"]()
        else:
            with self.assertRaises(ValueError): namespace["adapt"]()
        self.assertEqual(sorted(closed), sorted({10, 11, 12, 13} & set(
            [10] + [11 if name == "etc" else 12 if name == "fstab" else 13 for name, _ in opened if name != "/"])
            | set(roots[1:])))
        return events, bytes(written), opened

    def test_actual_fd_lifecycle_short_writes_sync_then_atomic_rename(self):
        events, data, opened = self.adapt_fixture("success")
        self.assertEqual(data, self.rewrite(row()))
        self.assertLess(events.index(("sync", 13)), events.index("rename"))
        self.assertLess(events.index("rename"), events.index(("sync", 11)))
        self.assertIn(("mode", 0o644), events)
        self.assertNotIn("unlink", events)
        for _, flags in opened: self.assertTrue(flags & production_module()["os"].O_NOFOLLOW)

    def test_actual_fd_rejection_never_renames_foreign_or_changed_files(self):
        for case in ("foreign-owner", "hardlink", "unsafe-parent", "parent-replaced", "original-replaced",
                     "root-covered", "separate-fstab", "temporary-replaced", "zero-write"):
            with self.subTest(case=case):
                events, _, _ = self.adapt_fixture(case)
                self.assertNotIn("rename", events)
                if case == "temporary-replaced": self.assertNotIn("unlink", events)
                if case == "zero-write": self.assertIn("unlink", events)


if __name__ == "__main__":
    unittest.main()
