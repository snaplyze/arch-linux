#!/usr/bin/env python3
"""Small real archive fixtures for the unsigned inspection resource boundary."""
import importlib.util
import io
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('package_verifier', ROOT / 'repository/verify-package-metadata.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class ArchiveLimits(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='archive-limit-test-', dir=os.environ.get('RUNNER_TEMP'))
        self.addCleanup(self.work.cleanup)
        self.root = pathlib.Path(self.work.name)
        self.temp = self.root / 'temps'
        self.temp.mkdir()
        self.environment = patch.dict(os.environ, RUNNER_TEMP=str(self.temp))
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def archive(self, sizes=(64,), pax=False):
        raw = self.root / 'input.tar'
        with tarfile.open(raw, 'w', format=tarfile.PAX_FORMAT) as archive:
            for index, size in enumerate(sizes):
                member = tarfile.TarInfo('.PKGINFO' if index == 0 else '.BUILDINFO')
                member.size = size
                member.mode = 0o644
                if pax:
                    member.pax_headers = {'comment': 'x' * 1024}
                archive.addfile(member, io.BytesIO(b'x' * size))
        package = self.root / 'input.pkg.tar.zst'
        subprocess.run(['zstd', '-q', '-f', '-o', str(package), str(raw)], check=True)
        return package

    def rejected(self, package, message, **limits):
        patches = [patch.object(verifier, key, value, create=True) for key, value in limits.items()]
        for item in patches:
            item.start()
        try:
            with self.assertRaisesRegex(SystemExit, message):
                verifier.verify_package_archive(package, 'arch-linux-keyring')
        finally:
            for item in patches:
                item.stop()
        self.assertEqual(list(self.temp.iterdir()), [], 'owned decoded output leaked')

    def test_compressed_size_before_child(self):
        self.rejected(self.archive(), 'compressed.*limit', MAX_COMPRESSED_BYTES=4)

    def test_expanded_size(self):
        self.rejected(self.archive(), 'expanded.*limit', MAX_EXPANDED_BYTES=1024)

    def test_member_size_before_payload_read(self):
        self.rejected(self.archive((2048,)), 'member.*limit', MAX_MEMBER_BYTES=1024)

    def test_member_count(self):
        self.rejected(self.archive((64, 64)), 'member count.*limit', MAX_MEMBERS=1)

    def test_aggregate_size(self):
        self.rejected(self.archive((64, 64)), 'aggregate.*limit', MAX_PAYLOAD_BYTES=100)

    def test_extension_header_size(self):
        self.rejected(self.archive(pax=True), 'extension.*limit', MAX_EXTENSION_BYTES=128)

    def typed_archive(self, member, payload=b''):
        raw = self.root / 'typed.tar'
        member.size = len(payload)
        raw.write_bytes(member.tobuf(format=tarfile.GNU_FORMAT) + payload +
                        b'\0' * ((-len(payload)) % 512) + b'\0' * 1024)
        package = self.root / 'typed.pkg.tar.zst'
        subprocess.run(['zstd', '-q', '-f', '-o', str(package), str(raw)], check=True)
        return package

    def test_solaris_pax_header_is_bounded_before_parse(self):
        member = tarfile.TarInfo('solaris-pax')
        member.type = tarfile.SOLARIS_XHDTYPE
        self.rejected(self.typed_archive(member, b'15 comment=abc\n'),
                      'extension header size limit', MAX_EXTENSION_BYTES=4)

    def test_gnu_sparse_rejected_before_auxiliary_map_parser(self):
        member = tarfile.TarInfo('.PKGINFO')
        member.type = tarfile.GNUTYPE_SPARSE
        package = self.typed_archive(member)
        with patch.object(tarfile.TarInfo, '_proc_sparse',
                          side_effect=AssertionError('unbounded sparse parser entered')):
            self.rejected(package, 'sparse.*forbidden')

    def test_all_pax_sparse_variants_rejected_before_map_parser(self):
        variants = [
            ('_proc_gnusparse_00', {'GNU.sparse.size': '1'}),
            ('_proc_gnusparse_01', {'GNU.sparse.map': '0,1'}),
            ('_proc_gnusparse_10', {'GNU.sparse.major': '1', 'GNU.sparse.minor': '0'}),
        ]
        for method, headers in variants:
            with self.subTest(method=method):
                raw = self.root / 'sparse-pax.tar'
                with tarfile.open(raw, 'w', format=tarfile.PAX_FORMAT) as archive:
                    member = tarfile.TarInfo('.PKGINFO')
                    member.pax_headers = headers
                    member.size = 1
                    archive.addfile(member, io.BytesIO(b'x'))
                package = self.root / 'sparse-pax.pkg.tar.zst'
                subprocess.run(['zstd', '-q', '-f', '-o', str(package), str(raw)], check=True)
                with patch.object(tarfile.TarInfo, method,
                                  side_effect=AssertionError('unbounded sparse parser entered')):
                    self.rejected(package, 'sparse.*forbidden')

    def test_truncated_frame_and_cleanup(self):
        package = self.archive()
        package.write_bytes(package.read_bytes()[:-3])
        self.rejected(package, 'integrity check failed')

    def test_oversized_declared_member_before_missing_payload(self):
        raw = self.root / 'declared.tar'
        member = tarfile.TarInfo('.PKGINFO')
        member.size = 4096
        member.mode = 0o644
        raw.write_bytes(member.tobuf())
        package = self.root / 'declared.pkg.tar.zst'
        subprocess.run(['zstd', '-q', '-o', str(package), str(raw)], check=True)
        self.rejected(package, 'member.*limit', MAX_MEMBER_BYTES=1024)

    def test_invalid_tar_cleanup(self):
        raw = self.root / 'invalid.tar'
        raw.write_bytes(b'invalid tar')
        package = self.root / 'invalid.pkg.tar.zst'
        subprocess.run(['zstd', '-q', '-o', str(package), str(raw)], check=True)
        self.rejected(package, 'invalid package tar stream')

    def test_decode_failure_cleanup(self):
        package = self.archive()
        child = self.root / 'failing-zstd'
        child.write_text('#!/usr/bin/python3\nimport sys\n'
                         'if "--test" not in sys.argv:\n'
                         '    sys.stdout.buffer.write(b"partial")\n'
                         '    sys.exit(1)\n')
        child.chmod(0o755)
        with patch.object(verifier.shutil, 'which', return_value=str(child)):
            self.rejected(package, 'cannot decompress package archive')

    def test_expansion_reaps_writer_and_removes_partial_output(self):
        package = self.archive()
        child = self.root / 'expanding-zstd'
        pidfile = self.root / 'pid'
        child.write_text('#!/usr/bin/python3\nimport os,sys,time\n'
                         'if "--test" not in sys.argv:\n'
                         f'    open({str(pidfile)!r}, "w").write(str(os.getpid()))\n'
                         '    while True: os.write(1, b"x" * 4096)\n')
        child.chmod(0o755)
        with patch.object(verifier.shutil, 'which', return_value=str(child)):
            self.rejected(package, 'expanded.*limit', MAX_EXPANDED_BYTES=1024)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(pidfile.read_text()), 0)

    def test_integrity_and_decode_timeouts_reap_children(self):
        # Only the external executable is replaced: run/reap/timeout/temp cleanup remain real.
        for phase in ('test', 'decode'):
            with self.subTest(phase=phase):
                package = self.archive()
                child = self.root / 'slow-zstd'
                pidfile = self.root / 'pid'
                child.write_text('#!/usr/bin/python3\nimport os,sys,time\n'
                                 f'if ("--test" in sys.argv) == {phase == "test"!r}:\n'
                                 f'    open({str(pidfile)!r}, "w").write(str(os.getpid()))\n'
                                 '    time.sleep(30)\n')
                child.chmod(0o755)
                start = time.monotonic()
                with patch.object(verifier.shutil, 'which', return_value=str(child)):
                    self.rejected(package, 'time limit', MAX_INSPECTION_SECONDS=0.15)
                self.assertLess(time.monotonic() - start, 3)
                pid = int(pidfile.read_text())
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
                pidfile.unlink()


if __name__ == '__main__':
    unittest.main()
