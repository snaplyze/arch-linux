#!/usr/bin/env python3
"""Exercise the actual fixed QMP keyboard program without a guest or Shell."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DesktopInput(unittest.TestCase):
    def run_input(self, operation, uid="1000", round_name="upgrade", run_id="marble-20261010T124324Z-0faa5d0f"):
        source = (ROOT / "tests/vm/run.sh").read_text()
        program = source.split("<<'EXTENSION_INPUT_PY'\n", 1)[1].split("\nEXTENSION_INPUT_PY", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            socket = path / "qmp.sock"
            socket.touch()
            identity = f"{socket.stat().st_dev}:{socket.stat().st_ino}"
            module = path / "boundary.py"
            module.write_text('''import json, pathlib, time
time.sleep = lambda _: None
def demand(value, message):
    if not value: raise ValueError(message)
def exact_qemu(pid, start): return pid == 123 and start == '456'
class Transport:
    def sendall(self, value):
        with pathlib.Path(__file__).with_name('input.jsonl').open('a') as output:
            output.write(value.decode().strip()+'\\n')
class QMP:
    def __init__(self, path, pid, start):
        demand(exact_qemu(pid, start), 'identity mismatch')
        self.connection = Transport()
    def read(self): return {'return': {}}
    def close(self): pass
''')
            arguments = ["python3", "-c", program, str(module), str(socket), identity,
                         "123", "456", operation, uid, round_name]
            if operation == "looking-glass":
                arguments.append(run_id)
            result = subprocess.run(arguments,
                                    capture_output=True, text=True, timeout=5)
            log = path / "input.jsonl"
            events = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, events

    def test_normal_looking_glass_loads_only_fixed_observer(self):
        result, events = self.run_input("looking-glass")
        self.assertEqual(result.returncode, 0, result.stderr)
        keys = [[key["data"] for key in event["arguments"]["keys"]] for event in events]
        self.assertEqual(keys[0], ["alt", "f2"])
        self.assertEqual(keys[1:4], [["l"], ["g"], ["ret"]])
        self.assertEqual(keys[-1], ["ret"])
        plain = {"spc": " ", "apostrophe": "'", "slash": "/", "minus": "-", "dot": "."}
        shifted = {"9": "(", "0": ")", "semicolon": ":"}
        typed = ""
        for stroke in keys[4:-1]:
            if len(stroke) == 2 and stroke[0] == "shift":
                typed += shifted.get(stroke[1], stroke[1].upper())
            else:
                self.assertEqual(len(stroke), 1)
                typed += plain.get(stroke[0], stroke[0])
        self.assertEqual(typed, "await import('file:///run/arch-linux-qemu-desktop-code/"
                         "marble-20261010T124324Z-0faa5d0f/upgrade/desktop-shell-probe.js')")
        self.assertTrue(all(event["execute"] == "send-key" for event in events))

    def test_overview_uses_real_super_key(self):
        result, events = self.run_input("overview")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events[0]["arguments"]["keys"], [{"type": "qcode", "data": "meta_l"}])

    def test_caffeine_uses_real_scoped_binding(self):
        result, events = self.run_input("caffeine")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([key["data"] for key in events[0]["arguments"]["keys"]], ["meta_l", "f7"])

    def test_invalid_fixed_import_identity_sends_no_input(self):
        for uid, round_name, run_id in [("0", "upgrade", "marble-20261010T124324Z-0faa5d0f"),
                                        ("1000;id", "upgrade", "marble-20261010T124324Z-0faa5d0f"),
                                        ("1000", "../upgrade", "marble-20261010T124324Z-0faa5d0f"),
                                        ("1000", "upgrade", "../../observer")]:
            with self.subTest(uid=uid, round_name=round_name, run_id=run_id):
                result, events = self.run_input("looking-glass", uid, round_name, run_id)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(events, [])

    def test_unknown_operation_sends_no_input(self):
        result, events = self.run_input("eval")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, [])


if __name__ == "__main__":
    unittest.main()
