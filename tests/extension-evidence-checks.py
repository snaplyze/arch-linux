#!/usr/bin/env python3
"""Reject incomplete or stale extension behavior receipts; no VM acceptance implied."""
import importlib.util
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location('acceptance', ROOT / 'repository/acceptance-manifest.py')
AM = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AM)
RUN = 'marble-20261009T010203Z-12345678'
PROBE = 'a' * 64


def receipt(phase, feature, session='c2'):
    return (f'EXTENSION_FUNCTIONAL_PASS phase={phase} feature={feature} run_id={RUN} '
            f'session={session} probe_sha256={PROBE} synthetic_unit_fixture=1\n')


class EvidenceChecks(unittest.TestCase):
    def setUp(self):
        self.rows = [receipt(phase, feature) for phase in ('upgrade', 'postreboot')
                     for feature in ('clipboard', 'dash', 'screenshot')]

    def verify(self, rows):
        AM.validate_extension_functional_log(''.join(rows), RUN, PROBE)

    def producer_harness_manifest(self):
        # Execute only the actual array declaration and sha256sum, never the VM main function.
        source = (ROOT / 'tests/vm/run.sh').read_text()
        declaration = re.search(r'(?ms)^    local -a harness_files=\(\n.*?^    \)', source)
        self.assertIsNotNone(declaration, 'actual producer harness declaration is absent')
        script = 'producer_manifest() {\n'+declaration.group(0)+'\nsha256sum -- "${harness_files[@]}"\n}\nproducer_manifest\n'
        return subprocess.check_output(['bash','--noprofile','--norc','-c',script],cwd=ROOT)

    def consume_harness_boundary(self, raw, *, digest=None, readback=None):
        class RuntimeBoundaryReached(Exception): pass
        names = [line.split(b'  ',1)[1] for line in raw.splitlines()]
        records = {'harness.sha256':raw,
                   'evidence/preseal-harness-check.txt':readback if readback is not None else b''.join(name+b': OK\n' for name in names)}
        def read(name, limit):
            if name == 'runtime-inputs.sha256': raise RuntimeBoundaryReached
            value = records[name]; self.assertLessEqual(len(value),limit); return value
        # Reaching runtime inputs proves the real consumer accepted ordered rows, source hashes,
        # exact pre-seal readback and aggregate binding; it is not a complete QEMU receipt.
        with self.assertRaises(RuntimeBoundaryReached):
            AM.validate_runtime_markers(read,{'harnessSha256':digest or AM.sha256_bytes(raw)},AM.SCENARIOS[0],RUN)

    def test_actual_producer_manifest_matches_consumer_order_and_hashes(self):
        self.consume_harness_boundary(self.producer_harness_manifest())

    def test_actual_producer_manifest_rejects_changed_closure_and_identity(self):
        raw = self.producer_harness_manifest(); rows = raw.splitlines(keepends=True)
        wrong_hash = b'b'*64+rows[0][64:]
        cases = {'missing':rows[:-1], 'extra':rows+[b'c'*64+b'  tests/vm/foreign.py\n'],
                 'duplicate':rows[:-1]+[rows[0]], 'reordered':[rows[1],rows[0],*rows[2:]],
                 'changed-source-hash':[wrong_hash,*rows[1:]]}
        for label, altered in cases.items():
            with self.subTest(label=label), self.assertRaises(AM.ManifestError):
                self.consume_harness_boundary(b''.join(altered))
        with self.assertRaises(AM.ManifestError): self.consume_harness_boundary(raw,digest='c'*64)
        with self.assertRaises(AM.ManifestError): self.consume_harness_boundary(raw,readback=b'foreign: OK\n')

    def test_complete_receipts(self):
        self.verify(self.rows)

    def test_each_feature_and_round_is_required(self):
        for index in range(len(self.rows)):
            with self.subTest(index=index), self.assertRaises(AM.ManifestError):
                self.verify(self.rows[:index] + self.rows[index + 1:])

    def test_each_feature_and_round_is_unique(self):
        for row in self.rows:
            with self.subTest(row=row), self.assertRaises(AM.ManifestError):
                self.verify(self.rows + [row])

    def test_stale_or_foreign_identity_rejected(self):
        for before, after in ((RUN, 'marble-20261008T010203Z-12345678'),
                              (PROBE, 'b' * 64), ('session=c2', 'session='),
                              ('phase=upgrade', 'phase=initial'),
                              ('feature=clipboard', 'feature=enabled')):
            with self.subTest(after=after), self.assertRaises(AM.ManifestError):
                self.verify([self.rows[0].replace(before, after), *self.rows[1:]])

    def test_one_round_cannot_mix_sessions(self):
        with self.assertRaises(AM.ManifestError):
            self.verify([self.rows[0].replace('session=c2', 'session=c3'), *self.rows[1:]])

    def test_enabled_state_does_not_replace_behavior(self):
        with self.assertRaises(AM.ManifestError):
            self.verify(['EXTENSIONS enabled=8 errors=0\n'])

    def test_malformed_or_oversized_receipt_rejected(self):
        for extra in ('EXTENSION_FUNCTIONAL_PASS\n', 'EXTENSION_FUNCTIONAL_PASS fake=1\n',
                      self.rows[0].rstrip('\n') + ' x=' + 'a' * 4096 + '\n'):
            with self.subTest(size=len(extra)), self.assertRaises(AM.ManifestError):
                self.verify(self.rows + [extra])


if __name__ == '__main__':
    unittest.main()
