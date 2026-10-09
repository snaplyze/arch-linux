#!/usr/bin/env python3
"""Reject incomplete or stale extension behavior receipts; no VM acceptance implied."""
import importlib.util
from pathlib import Path
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
