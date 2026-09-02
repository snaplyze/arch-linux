#!/usr/bin/env python3
"""Bounded framebuffer evidence lifecycle for the real QEMU acceptance harness."""

from __future__ import annotations

import argparse
import datetime as dt
import gzip, hashlib, io, json, math, os, re, socket, stat, struct, subprocess, sys, tempfile, time
from pathlib import Path

SCHEMA, DEVICE, HEAD = 1, "display0", 0
INTERVAL_MS, MAX_GAP_MS = 250, 500
QMP_TIMEOUT_SECONDS = MAX_GAP_MS / 1000
MAX_RAW_SEGMENT = 45 * 1024 * 1024
MAX_RAW_TOTAL = 4 * MAX_RAW_SEGMENT
MAX_SAMPLES, MAX_PPM = 2000, 64 * 1024 * 1024
MAX_LEDGER, MAX_JSON = 4 * 1024 * 1024, 8 * 1024 * 1024
MAX_CONTACT_SEGMENT = 64 * 1024 * 1024
MAX_CONTACT_TOTAL = 4 * MAX_CONTACT_SEGMENT
MAX_EVIDENCE = 500 * 1024 * 1024
MAX_TREE_OBJECTS = 20000
TILE_W, TILE_H, TILE_COLS, TILE_ROWS, MIN_CHANGED_PIXELS = 128, 80, 10, 10, 64
PHASES = ("firstboot", "postreboot")
SEGMENTS = tuple((phase, segment) for phase in PHASES for segment in ("boot", "shutdown"))
LEDGER_NAMES = {f"{phase}-{segment}-frame-ledger.jsonl" for phase, segment in SEGMENTS}
IDENTITY_NAMES = {f"{phase}-qemu.identity" for phase in PHASES}
RAW_DIR_NAMES = {f"{phase}-{segment}" for phase, segment in SEGMENTS}
POLICY = { "device": DEVICE, "head": HEAD, "intervalMs": INTERVAL_MS, "maxGapMs": MAX_GAP_MS,
    "maxEvidenceBytes": MAX_EVIDENCE, }
CONTROL_EVENTS = { "cont-sent", "shutdown-armed", "stop-boot", "challenge-before", "challenge-after",
    "challenge-cleared", }
CONFIRMATIONS = ( "orderedContactSheetsReviewed", "uncertainFramesReviewedAtFullResolution",
    "expectedBootLoginDesktopShutdownStatesVisible", "exactTTYChallengesVisibleOrNotApplicable",
    "noBlockingFirmwareKernelSystemdShutdownOrCommandText", )
CHALLENGE_KEYS = set(
    "challenge before after cleared changedPixels clearChangedPixels restoredPixels input clearInput".split())
SCENARIO_PREFIX = { "minimal-ext4-systemdboot": "minimal", "stock-gnome-ext4-systemdboot": "stock",
    "stock-gnome-btrfs-systemdboot": "btrfs", "stock-gnome-btrfs-grub": "grub",
    "stock-gnome-btrfs-luks2-plymouth-systemdboot": "luks", "stock-gnome-btrfs-luks2-plymouth-grub": "luksgrub",
    "marble-gnome-btrfs-luks2-plymouth-systemdboot": "marble", }
SAFE = re.compile(r"^[a-z0-9][a-z0-9.-]{0,127}$")
HEX40 = re.compile(r"^[a-f0-9]{40}$")
HEX64 = re.compile(r"^[a-f0-9]{64}$")
SOCKET_ID = re.compile(r"^[1-9][0-9]*:[1-9][0-9]*$")
RUN_ID = re.compile(r"^[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$")
REVIEWER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}$")
REPOSITORY_OBJECT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]*$")
HEADER_KEYS = set( "e schema phase segment pid start qmp peerPid peerUid recorderPid recorderStart device head \
intervalMs maxGapMs maxRawBytes maxSamples t initial".split() )
READY_KEYS = set( "schema status phase segment pid start qmp peerPid peerUid recorderPid recorderStart device head \
ppm state".split() )
REVIEW_KEYS = set( "schema verdict reviewer reviewedAt sourceCommit sourceTree runId scenario manifestSha256 \
pendingResultSha256 confirmations notes".split() )
RESULT_KEYS = set( "assertions buildMetadataSha256 contactSheets exitStatus failedPhase frameLedgers harnessSha256 \
inputMode installerSha256 isoSha256 manualReviewStatus manualReviewTemplateSha256 releaseSha256sumsSha256 \
releaseVersion repositoryDatabaseSha256 repositoryDatabaseSignatureSha256 repositoryFilesSha256 \
repositoryFilesSignatureSha256 repositoryManifestSha256 repositoryManifestSignatureSha256 \
repositoryObjects repositoryPackageSetSha256 repositoryPrimaryFingerprint repositoryPublicKeySha256 \
repositorySigningFingerprint repositorySnapshotSha256 retainedEvidenceBytes runId scenario screenshots \
snapshotVerification sourceCommit sourceTree status targetSerial unsignedManifestSha256".split() )

class EvidenceError(RuntimeError):
    """A fail-closed evidence contract violation."""
def demand(condition, message):
    if not condition:
        raise EvidenceError(message)
def exact_int(value, minimum= 0):
    return type(value) is int and value >= minimum
def exact_keys(value, keys, label):
    demand(isinstance(value, dict) and set(value) == keys, f"{label} schema")
def safe_dir(path):
    meta = path.lstat()
    demand(stat.S_ISDIR(meta.st_mode) and not stat.S_ISLNK(meta.st_mode), f"unsafe directory: {path}")
    demand(meta.st_uid == os.getuid(), f"directory owner: {path}")
    demand(stat.S_IMODE(meta.st_mode) == 0o700, f"directory mode: {path}")
    return meta
def ensure_dir(path):
    if not path.exists() and not path.is_symlink():
        path.mkdir(mode=0o700)
    safe_dir(path)
def safe_file(path, modes=(0o600,)):
    meta = path.lstat()
    demand(stat.S_ISREG(meta.st_mode) and not stat.S_ISLNK(meta.st_mode), f"unsafe file: {path}")
    demand(meta.st_uid == os.getuid() and meta.st_nlink == 1, f"file owner/link: {path}")
    demand(stat.S_IMODE(meta.st_mode) in modes, f"file mode: {path}")
    return meta
def run_root(value):
    root = Path(value)
    demand(root.is_absolute(), "run root must be absolute")
    demand(root == root.resolve(strict=True), "run root spelling is not canonical")
    safe_dir(root.parent)
    safe_dir(root)
    return root
def read_bytes(path, limit, modes=(0o600,)):
    meta = safe_file(path, modes)
    demand(meta.st_size <= limit, f"bounded read exceeded: {path.name}")
    with path.open("rb") as handle:
        data = handle.read(limit + 1)
    demand(len(data) <= limit, f"bounded read exceeded: {path.name}")
    return data
def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()
def sha_file(path):
    safe_file(path)
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
def json_bytes(value):
    data = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    demand(len(data) <= MAX_JSON, "JSON output exceeds its hard bound")
    return data
def write_once(path, data, retain=False):
    demand(not path.exists() and not path.is_symlink(), f"output exists: {path}")
    access = os.O_RDWR if retain else os.O_WRONLY
    fd = os.open(path, access | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view) :]
        os.fsync(fd)
    except BaseException:
        os.close(fd)
        raise
    if not retain:
        os.close(fd)
    return fd if retain else None
def write_json(path, value):
    write_once(path, json_bytes(value))
def append_json(path, value, first=False):
    flags = os.O_WRONLY | os.O_NOFOLLOW
    flags |= os.O_CREAT | os.O_EXCL if first else os.O_APPEND
    fd = os.open(path, flags, 0o600)
    try:
        meta = os.fstat(fd)
        demand(meta.st_uid == os.getuid() and meta.st_nlink == 1, "ledger owner/link")
        demand(stat.S_IMODE(meta.st_mode) == 0o600, "ledger mode")
        view = memoryview(json_bytes(value))
        while view:
            view = view[os.write(fd, view) :]
        os.fsync(fd)
    finally:
        os.close(fd)
def load_json(path, limit= MAX_JSON):
    try:
        value = json.loads(read_bytes(path, limit))
    except json.JSONDecodeError as error:
        raise EvidenceError(f"malformed JSON: {path.name}") from error
    demand(isinstance(value, dict), f"JSON object required: {path.name}")
    return value
def load_ledger(path, partial= False):
    data = read_bytes(path, MAX_LEDGER)
    if partial and data and not data.endswith(b"\n"):
        data = data.rsplit(b"\n", 1)[0] + b"\n"
    lines = data.splitlines()
    demand(0 < len(lines) <= MAX_SAMPLES + 32, "ledger record bound")
    records = []
    for line in lines:
        demand(0 < len(line) <= 4096, "ledger line bound")
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise EvidenceError("malformed ledger JSON") from error
        demand(isinstance(value, dict), "ledger record must be an object")
        records.append(value)
    return records
def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
def tree_size(path):
    safe_dir(path)
    total = 0
    objects = 0
    for base, directories, files in os.walk(path, followlinks=False):
        for name in [*directories, *files]:
            objects += 1
            demand(objects <= MAX_TREE_OBJECTS, "evidence tree object bound exceeded")
            meta = (Path(base) / name).lstat()
            allowed = stat.S_ISDIR(meta.st_mode) or stat.S_ISREG(meta.st_mode)
            demand(allowed and not stat.S_ISLNK(meta.st_mode), "evidence tree contains an unsafe object")
            if stat.S_ISREG(meta.st_mode):
                total += meta.st_size
    return total
def preflight_tree(path):
    safe_dir(path)
    for base, directories, files in os.walk(path, followlinks=False):
        for name in directories:
            safe_dir(Path(base) / name)
        for name in files:
            safe_file(Path(base) / name)
def remove_tree(path):
    preflight_tree(path)
    for base, directories, files in os.walk(path, topdown=False, followlinks=False):
        for name in files:
            (Path(base) / name).unlink()
        for name in directories:
            (Path(base) / name).rmdir()
    path.rmdir()
def remove_temporary(path):
    try:
        meta = path.lstat()
    except FileNotFoundError:
        return
    safe = stat.S_ISREG(meta.st_mode) and not stat.S_ISLNK(meta.st_mode)
    if safe and meta.st_uid == os.getuid() and meta.st_nlink == 1:
        path.unlink()
def parse_ppm_data(data):
    demand(len(data) <= MAX_PPM, "PPM byte bound exceeded")
    match = re.match(rb"\AP6\n([1-9][0-9]{0,4}) ([1-9][0-9]{0,4})\n255\n", data)
    demand(match is not None, "PPM header is not exact strict P6")
    width, height = int(match.group(1)), int(match.group(2))
    payload = data[match.end() :]
    demand(width <= 8192 and height <= 8192, "PPM dimensions exceed the bound")
    demand(len(payload) == width * height * 3, "PPM payload/trailing bytes differ")
    return width, height, payload, sha_bytes(data), data
def parse_ppm(path):
    return parse_ppm_data(read_bytes(path, MAX_PPM))
def changed_pixels(left, right):
    demand(left[:2] == right[:2], "frame dimensions differ")
    return sum(left[2][i : i + 3] != right[2][i : i + 3] for i in range(0, len(left[2]), 3))
def require_delta(left, right):
    changed = changed_pixels(left, right)
    minimum = max(MIN_CHANGED_PIXELS, left[0] * left[1] // 20000)
    demand(left[3] != right[3] and changed >= minimum, "frame delta is absent or too small")
    return changed
def process_start(pid):
    try:
        text = Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return None
    end = text.rfind(")")
    fields = [] if end < 0 else text[end + 2 :].split()
    return fields[19] if len(fields) > 19 else None
def exact_qemu(pid, start):
    if process_start(pid) != start:
        return False
    try:
        meta = Path(f"/proc/{pid}").stat()
        executable = Path(f"/proc/{pid}/exe").resolve(strict=True)
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return False
    expected = Path("/usr/bin/qemu-system-x86_64").resolve()
    return meta.st_uid == os.getuid() and executable == expected
class QMP:
    def __init__(self, path, pid, start, timeout= QMP_TIMEOUT_SECONDS):
        meta = path.lstat()
        demand(stat.S_ISSOCK(meta.st_mode) and meta.st_uid == os.getuid(), "QMP socket")
        demand(exact_qemu(pid, start), "QEMU identity")
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.settimeout(timeout)
        self.socket.connect(str(path))
        peer = self.socket.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
        peer_pid, peer_uid, _ = struct.unpack("3i", peer)
        demand(peer_pid == pid and peer_uid == os.getuid(), "QMP peer")
        self.reader = self.socket.makefile("rb", buffering=0)
        self.pid = pid
        self.peer_uid = peer_uid
        self.identity = f"{meta.st_dev}:{meta.st_ino}"
        demand("QMP" in self.read(), "QMP greeting missing")
        self.execute("qmp_capabilities", {})

    def close(self):
        self.reader.close()
        self.socket.close()

    def read(self):
        while True:
            line = self.reader.readline(1024 * 1024 + 1)
            demand(0 < len(line) <= 1024 * 1024, "QMP response missing/oversized")
            value = json.loads(line)
            demand(isinstance(value, dict), "QMP response is not an object")
            if "event" not in value:
                return value

    def execute(self, command, arguments):
        request = {"execute": command, "arguments": arguments}
        self.socket.sendall(json.dumps(request, separators=(",", ":")).encode() + b"\r\n")
        response = self.read()
        demand("error" not in response and "return" in response, f"QMP command failed: {command}")
        return response

    def status(self):
        value = self.execute("query-status", {}).get("return")
        demand(isinstance(value, dict), "QMP status is not an object")
        demand(value.get("status") in {"prelaunch", "running", "shutdown"}, "QMP status")
        running = value.get("running")
        demand(type(running) is bool, "QMP running state type")
        demand(running == (value["status"] == "running"), "QMP running state")
        return str(value["status"])

    def frame(self, path):
        demand(path.is_absolute() and not path.exists() and not path.is_symlink(), "screendump path")
        arguments = {"filename": str(path), "device": DEVICE, "head": HEAD, "format": "ppm"}
        self.execute("screendump", arguments)
        return parse_ppm(path)
def segment_paths(root, phase, segment):
    stem = f"{phase}-{segment}"
    return { "ledger": root / "evidence" / f"{stem}-frame-ledger.jsonl", "raw": root / "frame-raw" / stem,
        "ready": root / "frame-control" / f"{stem}.ready.json", "control": root / "frame-control" / f"{stem}.control", }
def header_record(args, qmp, recorder_start, timestamp):
    initial = "prelaunch" if args.segment == "boot" else "running"
    return { "e": "header", "schema": SCHEMA, "phase": args.phase, "segment": args.segment, "pid": args.qemu_pid,
        "start": args.qemu_start, "qmp": qmp.identity, "peerPid": qmp.pid, "peerUid": qmp.peer_uid,
        "recorderPid": os.getpid(), "recorderStart": recorder_start, "device": DEVICE, "head": HEAD,
        "intervalMs": INTERVAL_MS, "maxGapMs": MAX_GAP_MS, "maxRawBytes": MAX_RAW_SEGMENT, "maxSamples": MAX_SAMPLES,
        "t": timestamp, "initial": initial, }
def ready_record(header, ppm):
    copied = { key: header[key] for key in ( "phase", "segment", "pid", "start", "qmp", "peerPid", "peerUid",
            "recorderPid", "recorderStart", "device", "head", ) }
    return {"schema": SCHEMA, "status": "READY", **copied, "ppm": ppm, "state": header["initial"]}
def read_controls(path, offset):
    data = read_bytes(path, 4096)
    demand(offset <= len(data), "control file shrank")
    tail = data[offset:]
    if tail and not tail.endswith(b"\n"):
        return offset, []
    values = []
    for line in tail.splitlines():
        try:
            text = line.decode("ascii")
        except UnicodeDecodeError as error:
            raise EvidenceError("control event is not ASCII") from error
        match = re.fullmatch(r"([a-z-]+):([a-f0-9]{16})", text)
        demand(match is not None and match.group(1) in CONTROL_EVENTS, "control event")
        values.append((match.group(1), match.group(2)))
    return len(data), values
def store_raw(raw, frame, seen, remaining):
    if frame[3] in seen:
        name, compressed_sha = seen[frame[3]]
        return name, compressed_sha, 0
    name = f"frame-{frame[3]}.ppm.gz"
    compressed = gzip.compress(frame[4], compresslevel=1, mtime=0)
    demand(len(compressed) <= remaining, "recorder raw cap would be exceeded")
    write_once(raw / name, compressed)
    compressed_sha = sha_bytes(compressed)
    seen[frame[3]] = name, compressed_sha
    return name, compressed_sha, len(compressed)
def terminal_record(reason, number, timestamp, exited):
    return {"e": "terminal", "reason": reason, "n": number, "t": timestamp, "qemuExit": exited}
def record_command(args):
    root = run_root(args.run_root)
    safe_dir(root / "evidence")
    ensure_dir(root / "frame-raw")
    ensure_dir(root / "frame-control")
    paths = segment_paths(root, args.phase, args.segment)
    demand(not any(path.exists() or path.is_symlink() for path in paths.values()), "recorder output exists")
    paths["raw"].mkdir(mode=0o700)
    write_once(paths["control"], b"")
    qmp = QMP(Path(args.qmp_socket), args.qemu_pid, args.qemu_start)
    initial = qmp.status()
    expected = "prelaunch" if args.segment == "boot" else "running"
    demand(initial == expected, "recorder initial QMP state")
    recorder_start = process_start(os.getpid())
    demand(recorder_start is not None, "recorder process identity unavailable")
    started = time.monotonic_ns()
    header = header_record(args, qmp, recorder_start, started)
    append_json(paths["ledger"], header, first=True)
    seen = {}
    nonces = set()
    raw_bytes = 0
    sequence = 0
    previous = None
    next_due = started
    offset = 0

    def finish_exit(now):
        demand(previous is not None, "QEMU exited before the first recorder sample")
        demand(now - previous <= MAX_GAP_MS * 1_000_000, "QEMU exit exceeded the recorder gap")
        append_json(paths["ledger"], terminal_record("qemu-exit", sequence, now, True))

    try:
        while True:
            if not exact_qemu(args.qemu_pid, args.qemu_start):
                finish_exit(time.monotonic_ns())
                break
            demand(sequence < MAX_SAMPLES, "recorder sample cap exceeded")
            now = time.monotonic_ns()
            if now < next_due:
                time.sleep((next_due - now) / 1_000_000_000)
            sampled_at = time.monotonic_ns()
            if previous is not None:
                demand(sampled_at - previous <= MAX_GAP_MS * 1_000_000, "recorder sampling gap exceeded")
            temporary = paths["raw"] / f".sample-{sequence:06d}.ppm"
            try:
                try:
                    frame = qmp.frame(temporary)
                except (EvidenceError, OSError, TimeoutError, json.JSONDecodeError):
                    if not exact_qemu(args.qemu_pid, args.qemu_start) and previous is not None:
                        finish_exit(time.monotonic_ns())
                        break
                    raise
                name, compressed_sha, added = store_raw( paths["raw"], frame, seen, MAX_RAW_SEGMENT - raw_bytes )
            finally:
                remove_temporary(temporary)
            raw_bytes += added
            demand(raw_bytes <= MAX_RAW_SEGMENT, "recorder raw cap exceeded")
            gap_ms = 0 if previous is None else (sampled_at - previous) // 1_000_000
            sample = { "e": "sample", "n": sequence, "t": sampled_at, "gapMs": gap_ms, "ppm": frame[3], "raw": name,
                "rawSha": compressed_sha, "w": frame[0], "h": frame[1], }
            append_json(paths["ledger"], sample)
            if sequence == 0:
                demand(qmp.status() == initial, "READY QMP state changed")
                ready_at = time.monotonic_ns()
                ready = {"e": "ready", "n": 0, "t": ready_at, "ppm": frame[3], "state": initial}
                append_json(paths["ledger"], ready)
                write_json(paths["ready"], ready_record(header, frame[3]))
            offset, controls = read_controls(paths["control"], offset)
            for event, nonce in controls:
                demand(nonce not in nonces, "control nonce repeated")
                nonces.add(nonce)
                boot_event = event != "shutdown-armed"
                demand((args.segment == "boot") == boot_event, "control event belongs to another segment")
                demand(qmp.status() == "running", "control event did not observe running QEMU")
                control = { "e": "control", "name": event, "nonce": nonce, "n": sequence, "t": time.monotonic_ns(),
                    "state": "running", }
                append_json(paths["ledger"], control)
                if event == "stop-boot":
                    terminal = terminal_record("requested-stop", sequence, time.monotonic_ns(), False)
                    append_json(paths["ledger"], terminal)
                    return
            sequence += 1
            previous = sampled_at
            next_due += INTERVAL_MS * 1_000_000
    finally:
        qmp.close()
def event_time(records, name):
    found = [item.get("t") for item in records if item.get("e") == "control" and item.get("name") == name]
    demand(len(found) == 1 and exact_int(found[0], 1), f"ledger control event: {name}")
    return found[0]
def was_sampled(records, digest, after=None, before=None,
):
    low = event_time(records, after) if after else None
    high = event_time(records, before) if before else None
    return any( item.get("e") == "sample" and item.get("ppm") == digest and (low is None or item.get("t", -1) > low)
        and (high is None or item.get("t", high + 1) <= high) for item in records )
def comparison_path(root, value):
    path = Path(value)
    allowed = {root / "evidence", root / "frame-work"}
    demand(path.is_absolute() and path.parent in allowed, "comparison frame path")
    return path
def capture_command(args):
    root = run_root(args.run_root)
    demand(bool(SAFE.fullmatch(args.name)), "capture name is unsafe")
    demand(args.name.startswith(f"{args.phase}-"), "capture name/phase")
    temporary_name = args.name in {f"{args.phase}-tty-before", f"{args.phase}-tty-cleared"}
    destination_dir = root / ("frame-work" if temporary_name else "evidence")
    ensure_dir(destination_dir) if temporary_name else safe_dir(destination_dir)
    destination = destination_dir / f"{args.name}.ppm"
    demand(not destination.exists() and not destination.is_symlink(), "capture output already exists")
    ledger = Path(args.ledger)
    demand(ledger == segment_paths(root, args.phase, "boot")["ledger"], "capture ledger path")
    different = parse_ppm(comparison_path(root, args.different_from)) if args.different_from else None
    restore = parse_ppm(comparison_path(root, args.restore_toward)) if args.restore_toward else None
    demand(restore is None or different is not None, "restore comparison lacks different-from")
    qmp = QMP(Path(args.qmp_socket), args.qemu_pid, args.qemu_start)
    identity = load_identity(root / "evidence" / f"{args.phase}-qemu.identity", args.phase)
    header = load_ledger(ledger, partial=True)[0]
    exact_keys(header, HEADER_KEYS, "capture ledger header")
    qemu_binding = int(identity["pid"]) == args.qemu_pid and identity["start_time"] == args.qemu_start
    demand(qemu_binding, "capture QEMU identity")
    demand(header["phase"] == args.phase and header["segment"] == "boot", "capture ledger")
    demand(header["pid"] == args.qemu_pid and header["start"] == args.qemu_start, "capture pid")
    demand(header["qmp"] == identity["qmp_identity"], "capture recorder QMP binding")
    demand(qmp.identity == identity["qmp_capture_identity"], "capture QMP identity")
    demand(qmp.identity != header["qmp"], "capture/recorder QMP sockets are not separate")
    demand(header["peerPid"] == qmp.pid and header["peerUid"] == qmp.peer_uid, "capture peer")
    deadline = time.monotonic() + 10.0
    accepted = None
    candidate_path = None
    try:
        while time.monotonic() < deadline:
            token = os.urandom(4).hex()
            candidate_path = destination_dir / f".capture-{os.getpid()}-{token}.ppm"
            candidate = qmp.frame(candidate_path)
            try:
                if different is not None:
                    require_delta(different, candidate)
                if restore is not None:
                    require_delta(candidate, different)
                    before_delta = changed_pixels(restore, different)
                    demand(changed_pixels(restore, candidate) < before_delta, "frame did not restore")
                records = load_ledger(ledger, partial=True)
                if was_sampled(records, candidate[3], args.after_event):
                    accepted = candidate
                    break
            except EvidenceError:
                pass
            remove_temporary(candidate_path)
            candidate_path = None
            time.sleep(0.1)
        demand(accepted is not None and candidate_path is not None, "no capture satisfied the gate")
        os.rename(candidate_path, destination)
        sync_dir(destination_dir)
    finally:
        if candidate_path is not None and candidate_path.exists() and candidate_path != destination:
            remove_temporary(candidate_path)
        qmp.close()
    print(json.dumps({"status": "PASS", "name": destination.name, "sha256": accepted[3]}, sort_keys=True))
def raw_frame(path, compressed_sha):
    compressed = read_bytes(path, MAX_RAW_SEGMENT)
    demand(sha_bytes(compressed) == compressed_sha, "raw compressed digest")
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as handle:
            data = handle.read(MAX_PPM + 1)
    except (OSError, EOFError) as error:
        raise EvidenceError("raw gzip frame") from error
    demand(len(data) <= MAX_PPM, "raw decompression bound exceeded")
    return parse_ppm_data(data)
def validate_segment(root, phase, segment, challenge):
    paths = segment_paths(root, phase, segment)
    records = load_ledger(paths["ledger"])
    header = records[0]
    exact_keys(header, HEADER_KEYS, "ledger header")
    initial = "prelaunch" if segment == "boot" else "running"
    identity_ok = ( header.get("e") == "header" and header.get("schema") == SCHEMA and header.get("phase") == phase
        and header.get("segment") == segment )
    demand(identity_ok, "ledger header identity")
    demand(type(header.get("schema")) is int and type(header.get("head")) is int, "header integer type")
    demand(header.get("device") == DEVICE and header.get("head") == HEAD, "ledger display")
    demand(header.get("initial") == initial, "ledger initial state")
    demand(exact_int(header.get("pid"), 2), "ledger QEMU pid")
    demand(isinstance(header.get("start"), str) and header["start"].isdigit(), "QEMU start")
    demand(header.get("peerPid") == header["pid"], "ledger QMP peer pid")
    demand(header.get("peerUid") == os.getuid() and type(header.get("peerUid")) is int,
           "ledger QMP peer uid")
    demand(bool(SOCKET_ID.fullmatch(str(header.get("qmp", "")))), "ledger QMP identity")
    demand(exact_int(header.get("recorderPid"), 2), "ledger recorder pid")
    recorder_start = header.get("recorderStart")
    demand(isinstance(recorder_start, str) and recorder_start.isdigit(), "recorder start")
    demand(process_start(header["recorderPid"]) != recorder_start, "frame recorder remains active")
    policy = ( header.get("intervalMs"), header.get("maxGapMs"), header.get("maxRawBytes"), header.get("maxSamples"), )
    demand(policy == (INTERVAL_MS, MAX_GAP_MS, MAX_RAW_SEGMENT, MAX_SAMPLES), "ledger policy")
    demand(exact_int(header.get("t"), 1), "ledger start time")
    samples = []
    controls = []
    raw_map = {}
    nonces = set()
    previous_record = header["t"]
    previous_sample = None
    ready_seen = False
    terminal = None
    for record in records[1:]:
        event = record.get("e")
        demand(exact_int(record.get("t"), previous_record), "ledger timestamp rollback")
        previous_record = record["t"]
        if event == "sample":
            exact_keys(record, {"e", "n", "t", "gapMs", "ppm", "raw", "rawSha", "w", "h"}, "sample")
            demand(type(record.get("n")) is int and record.get("n") == len(samples),
                   "ledger sample sequence")
            delta_ns = 0 if previous_sample is None else record["t"] - previous_sample
            demand(type(record.get("gapMs")) is int and record.get("gapMs") == delta_ns // 1_000_000,
                   "ledger sample gap field")
            demand(delta_ns <= MAX_GAP_MS * 1_000_000, "ledger sample gap exceeds policy")
            demand(bool(HEX64.fullmatch(str(record.get("ppm", "")))), "ledger PPM digest")
            demand(bool(HEX64.fullmatch(str(record.get("rawSha", "")))), "ledger raw digest")
            expected_name = f"frame-{record['ppm']}.ppm.gz"
            demand(record.get("raw") == expected_name and SAFE.fullmatch(expected_name), "raw name")
            demand(exact_int(record.get("w"), 1) and exact_int(record.get("h"), 1), "dimensions differ")
            mapping = record["raw"], record["rawSha"], record["w"], record["h"]
            demand(record["ppm"] not in raw_map or raw_map[record["ppm"]] == mapping, "raw map")
            raw_map[record["ppm"]] = mapping
            samples.append(record)
            previous_sample = record["t"]
        elif event == "ready":
            exact_keys(record, {"e", "n", "t", "ppm", "state"}, "READY")
            ready_ok = len(samples) == 1 and type(record.get("n")) is int and record.get("n") == 0
            ready_ok &= record.get("ppm") == samples[0]["ppm"]
            demand(not ready_seen and ready_ok and record.get("state") == initial, "ledger READY")
            ready_seen = True
        elif event == "control":
            exact_keys(record, {"e", "name", "nonce", "n", "t", "state"}, "control")
            demand(ready_seen, "control appeared before READY")
            demand(record.get("name") in CONTROL_EVENTS, "ledger control name")
            nonce = str(record.get("nonce", ""))
            demand(bool(re.fullmatch(r"[a-f0-9]{16}", nonce)) and nonce not in nonces, "nonce")
            nonces.add(nonce)
            demand(type(record.get("n")) is int and record.get("n") == len(samples) - 1,
                   "control sample binding")
            demand(record.get("state") == "running", "control QMP state")
            controls.append(record)
        elif event == "terminal":
            exact_keys(record, {"e", "reason", "n", "t", "qemuExit"}, "terminal")
            terminal_ok = type(record.get("qemuExit")) is bool and type(record.get("n")) is int
            demand(terminal_ok and terminal is None, "terminal record")
            terminal = record
        else:
            raise EvidenceError("ledger event not allowlisted")
    demand(ready_seen and terminal is records[-1], "ledger READY/terminal closure")
    demand(0 < len(samples) <= MAX_SAMPLES, "ledger sample count")
    demand(terminal["t"] - samples[-1]["t"] <= MAX_GAP_MS * 1_000_000, "terminal gap")
    names = [record["name"] for record in controls]
    if segment == "boot":
        middle = ["challenge-before", "challenge-after", "challenge-cleared"] if challenge else []
        demand(names == ["cont-sent", *middle, "stop-boot"], "boot control chronology")
        expected_terminal = terminal.get("n") == samples[-1]["n"]
        expected_terminal &= terminal.get("reason") == "requested-stop" and terminal.get("qemuExit") is False
        demand(expected_terminal, "boot terminal record")
        demand(was_sampled(records, samples[-1]["ppm"], "cont-sent"), "boot lacks post-cont sample")
    else:
        demand(names == ["shutdown-armed"], "shutdown control chronology")
        expected_terminal = terminal.get("n") == len(samples)
        expected_terminal &= terminal.get("reason") == "qemu-exit" and terminal.get("qemuExit") is True
        demand(expected_terminal, "shutdown terminal record")
        demand(was_sampled(records, samples[-1]["ppm"], "shutdown-armed"), "shutdown lacks sample")
    safe_dir(paths["raw"])
    demand({path.name for path in paths["raw"].iterdir()} == {item[0] for item in raw_map.values()},
           "raw frame closure")
    raw_bytes = 0
    for ppm, (name, compressed_sha, width, height) in raw_map.items():
        frame = raw_frame(paths["raw"] / name, compressed_sha)
        demand(frame[:2] == (width, height) and frame[3] == ppm, "raw frame readback")
        raw_bytes += safe_file(paths["raw"] / name).st_size
    demand(raw_bytes <= MAX_RAW_SEGMENT, "raw segment cap exceeded")
    ready = load_json(paths["ready"], 4096)
    exact_keys(ready, READY_KEYS, "READY file")
    demand(type(ready.get("schema")) is int and ready == ready_record(header, samples[0]["ppm"]),
           "READY file/ledger binding")
    _, written_controls = read_controls(paths["control"], 0)
    expected_controls = [(record["name"], record["nonce"]) for record in controls]
    demand(written_controls == expected_controls, "control file/ledger binding")
    return { "phase": phase, "segment": segment, "header": header, "records": records, "samples": samples,
        "raw": raw_map, "rawBytes": raw_bytes, "ledgerSha256": sha_file(paths["ledger"]), }
def resize(frame):
    output = bytearray(TILE_W * TILE_H * 3)
    for y in range(TILE_H):
        source_y = min(frame[1] - 1, y * frame[1] // TILE_H)
        for x in range(TILE_W):
            source_x = min(frame[0] - 1, x * frame[0] // TILE_W)
            source = (source_y * frame[0] + source_x) * 3
            target = (y * TILE_W + x) * 3
            output[target : target + 3] = frame[2][source : source + 3]
    return bytes(output)
def render_contacts(root, value):
    phase, segment = value["phase"], value["segment"]
    raw_dir = segment_paths(root, phase, segment)["raw"]
    per_sheet = TILE_COLS * TILE_ROWS
    width, height = TILE_W * TILE_COLS, TILE_H * TILE_ROWS
    sheet_count = math.ceil(len(value["samples"]) / per_sheet)
    cache = {}
    cache_bytes = 0
    total = 0
    for index in range(sheet_count):
        chunk = value["samples"][index * per_sheet : (index + 1) * per_sheet]
        payload = bytearray(width * height * 3)
        for tile_index, sample in enumerate(chunk):
            tile = cache.get(sample["ppm"])
            if tile is None:
                name, compressed_sha, _, _ = value["raw"][sample["ppm"]]
                tile = resize(raw_frame(raw_dir / name, compressed_sha))
                cache_bytes += len(tile)
                demand(cache_bytes <= 64 * 1024 * 1024, "contact tile cache bound exceeded")
                cache[sample["ppm"]] = tile
            x0 = tile_index % TILE_COLS * TILE_W
            y0 = tile_index // TILE_COLS * TILE_H
            for row in range(TILE_H):
                source = row * TILE_W * 3
                target = ((y0 + row) * width + x0) * 3
                payload[target : target + TILE_W * 3] = tile[source : source + TILE_W * 3]
        encoded = f"P6\n{width} {height}\n255\n".encode() + payload
        total += len(encoded)
        demand(total <= MAX_CONTACT_SEGMENT, "contact sheet segment cap exceeded")
        name = f"{phase}-{segment}-contact-sheet-{index + 1:03d}.ppm"
        write_once(root / "evidence" / name, bytes(encoded))
    return sheet_count, total
def load_identity(path, phase):
    values = {}
    for line in read_bytes(path, 4096).decode("ascii").splitlines():
        demand(line.count("=") == 1, "QEMU identity line")
        key, value = line.split("=", 1)
        demand(key not in values, "QEMU identity field repeats")
        values[key] = value
    expected = {"phase", "pid", "start_time", "qga_identity", "qmp_identity", "qmp_capture_identity"}
    demand(set(values) == expected and values.get("phase") == phase, "QEMU identity fields differ")
    demand(values["pid"].isdigit() and int(values["pid"]) > 1, "QEMU identity pid")
    demand(values["start_time"].isdigit() and int(values["start_time"]) > 0, "QEMU start")
    sockets = ("qga_identity", "qmp_identity", "qmp_capture_identity")
    demand(all(SOCKET_ID.fullmatch(values[key]) for key in sockets), "QEMU socket identity")
    demand(values["qmp_identity"] != values["qmp_capture_identity"], "QMP sockets are not separate")
    return values
def check_challenge_pair(challenges, run_id):
    demand(isinstance(challenges, dict) and set(challenges) == set(PHASES), "challenge phases differ")
    after = []
    for phase in PHASES:
        item = challenges[phase]
        exact_keys(item, CHALLENGE_KEYS, f"{phase} challenge")
        expected = f"ali-{phase}-{run_id.rsplit('-', 1)[-1]}"
        demand(item.get("challenge") == expected, f"{phase} challenge")
        hashes = []
        for name in ("before", "after", "cleared"):
            value = item.get(name)
            exact_keys(value, {"sha256"}, f"{phase} {name}")
            demand(isinstance(value["sha256"], str) and HEX64.fullmatch(value["sha256"]),
                   f"{phase} {name} digest")
            hashes.append(value["sha256"])
        metrics = [item.get(name) for name in ("changedPixels", "clearChangedPixels", "restoredPixels")]
        demand(all(exact_int(value, 1) for value in metrics[:2]) and exact_int(metrics[2]),
               f"{phase} challenge metrics differ")
        demand(metrics[2] < metrics[0] and len(set(hashes)) == 3, f"{phase} challenge delta")
        demand(item.get("input") == "hmp-no-enter" and item.get("clearInput") == "ctrl-u",
               f"{phase} challenge input")
        after.append(hashes[1])
    demand(after[0] != after[1], "challenge frames repeat")
def owned_files(root):
    evidence = root / "evidence"
    ledgers = {path.name for path in evidence.glob("*-frame-ledger.jsonl")}
    identities = {path.name for path in evidence.glob("*-qemu.identity")}
    demand(ledgers == LEDGER_NAMES and identities == IDENTITY_NAMES, "fixed frame evidence closure")
    paths = [evidence / name for name in sorted(LEDGER_NAMES | IDENTITY_NAMES)]
    paths.extend(sorted(evidence.glob("*.ppm")))
    raw_root = root / "frame-raw"
    safe_dir(raw_root)
    demand({path.name for path in raw_root.iterdir()} == RAW_DIR_NAMES, "raw directory closure")
    for name in sorted(RAW_DIR_NAMES):
        safe_dir(raw_root / name)
        paths.extend(sorted((raw_root / name).iterdir()))
    result = {}
    for path in paths:
        safe_file(path)
        relative = str(path.relative_to(root))
        demand(relative not in result, "owned frame path repeats")
        result[relative] = path
    return result

def check_run_identity(scenario, run_id):
    prefix = SCENARIO_PREFIX.get(scenario)
    valid = prefix is not None and RUN_ID.fullmatch(run_id) is not None
    demand(valid and run_id.startswith(f"{prefix}-"), "scenario/run identity")

def check_run_root(root, run_id):
    demand(root.name == run_id, "run root/run id")

def seal_command(args):
    root = run_root(args.run_root)
    evidence = root / "evidence"
    safe_dir(evidence)
    check_run_identity(args.scenario, args.run_id)
    check_run_root(root, args.run_id)
    demand(bool(HEX40.fullmatch(args.source_commit)), "source commit")
    demand(bool(HEX40.fullmatch(args.source_tree)), "source tree")
    manifest_path = evidence / "frame-evidence-manifest.json"
    template_path = evidence / "manual-review-template.json"
    reserved = (manifest_path, template_path, evidence / "manual-review-receipt.json")
    demand(not any(path.exists() or path.is_symlink() for path in reserved), "seal output exists")
    heavy = ("target.qcow2", "payload.iso", "OVMF_VARS.fd", "payload", "repository")
    demand(not any((root / name).exists() or (root / name).is_symlink() for name in heavy),
           "heavy VM input remains at seal")
    demand(not any(evidence.glob("*-contact-sheet-*.ppm")), "contact sheets exist before seal")
    demand(not any(evidence.glob("*.capture.json")), "retired capture metadata remains")
    minimal = args.scenario == "minimal-ext4-systemdboot"
    values = [validate_segment(root, phase, segment, minimal and segment == "boot") for phase, segment in SEGMENTS]
    by_name = {f"{value['phase']}-{value['segment']}": value for value in values}
    raw_total = sum(value["rawBytes"] for value in values)
    demand(raw_total <= MAX_RAW_TOTAL, "cumulative raw frame cap exceeded")
    identities = {phase: load_identity(evidence / f"{phase}-qemu.identity", phase) for phase in PHASES}
    first_identity = identities["firstboot"]["pid"], identities["firstboot"]["start_time"]
    post_identity = identities["postreboot"]["pid"], identities["postreboot"]["start_time"]
    demand(first_identity != post_identity, "firstboot/postreboot QEMU identity repeats")
    demand(not any(exact_qemu(int(item["pid"]), item["start_time"]) for item in identities.values()),
           "QEMU remains active during seal")
    for value in values:
        identity = identities[value["phase"]]
        header = value["header"]
        binding = header["pid"] == int(identity["pid"]) and header["start"] == identity["start_time"]
        demand(binding and header["qmp"] == identity["qmp_identity"], "ledger/QEMU identity")
    selected_paths = sorted(path for path in evidence.glob("*.ppm") if "-contact-sheet-" not in path.name)
    demand(2 <= len(selected_paths) <= 4, "selected framebuffer count")
    selected = []
    selected_frames = {}
    for path in selected_paths:
        phase = path.name.split("-", 1)[0]
        demand(phase in PHASES, "selected framebuffer phase")
        frame = parse_ppm(path)
        demand(was_sampled(by_name[f"{phase}-boot"]["records"], frame[3]), "selected frame lacks sample")
        selected.append(path.name)
        selected_frames[path.name] = frame
    work = root / "frame-work"
    challenges = {}
    if minimal:
        expected_selected = {f"{phase}-tty.ppm" for phase in PHASES}
        demand({path.name for path in selected_paths} == expected_selected, "Minimal selected frames differ")
        safe_dir(work)
        suffix = args.run_id.rsplit("-", 1)[-1]
        expected_work = {f"{phase}-tty-{kind}.ppm" for phase in PHASES for kind in ("before", "cleared")}
        demand({path.name for path in work.iterdir()} == expected_work, "Minimal work closure")
        for phase in PHASES:
            before = parse_ppm(work / f"{phase}-tty-before.ppm")
            after = selected_frames[f"{phase}-tty.ppm"]
            cleared = parse_ppm(work / f"{phase}-tty-cleared.ppm")
            records = by_name[f"{phase}-boot"]["records"]
            demand(was_sampled(records, before[3], "cont-sent", "challenge-before"), "challenge before window")
            demand(was_sampled(records, after[3], "challenge-before", "challenge-after"),
                   "challenge after window")
            demand(not was_sampled(records, after[3], before="challenge-before"),
                   "challenge frame existed in baseline/firmware history")
            demand(was_sampled(records, cleared[3], "challenge-after", "challenge-cleared"),
                   "challenge clear window")
            delta = require_delta(before, after)
            clear_delta = require_delta(after, cleared)
            restored = changed_pixels(before, cleared)
            demand(restored < delta, "challenge clear did not restore toward login prompt")
            challenges[phase] = { "challenge": f"ali-{phase}-{suffix}", "before": {"sha256": before[3]},
                "after": {"sha256": after[3]}, "cleared": {"sha256": cleared[3]}, "changedPixels": delta,
                "clearChangedPixels": clear_delta, "restoredPixels": restored, "input": "hmp-no-enter",
                "clearInput": "ctrl-u", }
        check_challenge_pair(challenges, args.run_id)
    else:
        demand(not work.exists() and not work.is_symlink(), "non-Minimal run retains challenge work")
    frame_bytes = len(f"P6\n{TILE_W * TILE_COLS} {TILE_H * TILE_ROWS}\n255\n".encode())
    frame_bytes += TILE_W * TILE_COLS * TILE_H * TILE_ROWS * 3
    estimated = sum(math.ceil(len(value["samples"]) / (TILE_COLS * TILE_ROWS)) * frame_bytes for value in values)
    demand(tree_size(root.parent) + estimated <= MAX_EVIDENCE, "contact sheets exceed transient budget")
    segment_manifest = []
    contact_total = 0
    for value in values:
        sheet_count, sheet_bytes = render_contacts(root, value)
        contact_total += sheet_bytes
        segment_manifest.append({ "phase": value["phase"], "segment": value["segment"],
            "samples": len(value["samples"]), "sheets": sheet_count, })
    demand(contact_total <= MAX_CONTACT_TOTAL, "cumulative contact-sheet cap exceeded")
    expected_contacts = { f"{item['phase']}-{item['segment']}-contact-sheet-{index + 1:03d}.ppm"
        for item in segment_manifest for index in range(item["sheets"]) }
    actual_contacts = {path.name for path in evidence.glob("*-contact-sheet-*.ppm")}
    demand(actual_contacts == expected_contacts, "contact-sheet closure")
    file_hashes = {relative: sha_file(path) for relative, path in owned_files(root).items()}
    manifest = { "schema": SCHEMA, "status": "SEALED", "sourceCommit": args.source_commit,
        "sourceTree": args.source_tree, "runId": args.run_id, "scenario": args.scenario, "policy": POLICY,
        "qemuIdentities": identities, "segments": segment_manifest, "selectedFrames": selected,
        "challenges": challenges, "fileHashes": file_hashes, }
    manifest_data = json_bytes(manifest)
    manifest_sha = sha_bytes(manifest_data)
    template = { "schema": SCHEMA, "verdict": "PENDING", "reviewer": "", "reviewedAt": "",
        "sourceCommit": args.source_commit, "sourceTree": args.source_tree, "runId": args.run_id,
        "scenario": args.scenario, "manifestSha256": manifest_sha, "pendingResultSha256": "",
        "confirmations": {name: False for name in CONFIRMATIONS}, "notes": "", }
    control = root / "frame-control"
    safe_dir(control)
    expected_control = {f"{phase}-{segment}.{suffix}" for phase, segment in SEGMENTS
                        for suffix in ("control", "ready.json")}
    demand({path.name for path in control.iterdir()} == expected_control, "frame-control closure")
    preflight_tree(control)
    if work.exists():
        preflight_tree(work)
    demand(tree_size(root.parent) <= MAX_EVIDENCE, "transient cumulative evidence budget exceeded")
    remove_tree(control)
    if work.exists():
        remove_tree(work)
    write_once(manifest_path, manifest_data)
    write_json(template_path, template)
    sync_dir(evidence)
    demand(tree_size(root.parent) <= MAX_EVIDENCE, "sealed cumulative evidence budget exceeded")
    print(json.dumps({"status": "SEALED", "manifestSha256": manifest_sha,
                      "templateSha256": sha_file(template_path)}, sort_keys=True))

MANIFEST_KEYS = { "schema", "status", "sourceCommit", "sourceTree", "runId", "scenario", "policy", "qemuIdentities",
    "segments", "selectedFrames", "challenges", "fileHashes", }

def validate_manifest(root, manifest):
    exact_keys(manifest, MANIFEST_KEYS, "sealed manifest")
    demand(manifest.get("schema") == SCHEMA and type(manifest.get("schema")) is int, "manifest schema")
    demand(manifest.get("status") == "SEALED", "manifest status")
    commit, tree = manifest.get("sourceCommit"), manifest.get("sourceTree")
    scenario, run_id = manifest.get("scenario"), manifest.get("runId")
    demand(bool(HEX40.fullmatch(str(commit))) and bool(HEX40.fullmatch(str(tree))), "source identity")
    check_run_identity(str(scenario), str(run_id))
    check_run_root(root, str(run_id))
    demand(manifest.get("policy") == POLICY, "manifest policy")
    identities = manifest.get("qemuIdentities")
    demand(isinstance(identities, dict) and set(identities) == set(PHASES), "manifest identities differ")
    for phase in PHASES:
        demand(identities[phase] == load_identity(root / "evidence" / f"{phase}-qemu.identity", phase),
               "manifest QEMU identity binding")
    segments = manifest.get("segments")
    demand(isinstance(segments, list) and len(segments) == len(SEGMENTS), "manifest segments differ")
    file_hashes = manifest.get("fileHashes")
    demand(isinstance(file_hashes, dict) and file_hashes, "fileHashes map")
    demand(all(isinstance(key, str) and HEX64.fullmatch(str(value)) for key, value in file_hashes.items()),
           "fileHashes fields differ")
    evidence = root / "evidence"
    contacts = set()
    for expected, item in zip(SEGMENTS, segments, strict=True):
        exact_keys(item, {"phase", "segment", "samples", "sheets"}, "segment")
        phase, segment = expected
        demand((item["phase"], item["segment"]) == expected, "segment order")
        demand(exact_int(item.get("samples"), 1) and item["samples"] <= MAX_SAMPLES, "sample count")
        ledger = load_ledger(evidence / f"{phase}-{segment}-frame-ledger.jsonl")
        demand(item["samples"] == sum(record.get("e") == "sample" for record in ledger),
               "manifest/ledger sample count")
        count = math.ceil(item["samples"] / (TILE_COLS * TILE_ROWS))
        demand(item.get("sheets") == count, "contact sheet count")
        contacts.update(f"{phase}-{segment}-contact-sheet-{index + 1:03d}.ppm" for index in range(count))
    selected = manifest.get("selectedFrames")
    demand(isinstance(selected, list) and 2 <= len(selected) <= 4, "selectedFrames count")
    demand(all(isinstance(name, str) and SAFE.fullmatch(name) and name.endswith(".ppm") for name in selected),
           "selected frame name")
    selected_names = set(selected)
    demand(len(selected_names) == len(selected), "selected frame repeats")
    demand(not any("-contact-sheet-" in name for name in selected_names), "contact is selected")
    demand(all(name.split("-", 1)[0] in PHASES for name in selected_names), "selected phase")
    challenges = manifest.get("challenges")
    demand(isinstance(challenges, dict), "manifest challenges type")
    if scenario == "minimal-ext4-systemdboot":
        demand(selected_names == {f"{phase}-tty.ppm" for phase in PHASES}, "Minimal selected frames differ")
        check_challenge_pair(challenges, str(run_id))
    else:
        demand(challenges == {}, "non-Minimal challenge data remains")
    demand({path.name for path in evidence.glob("*-contact-sheet-*.ppm")} == contacts, "final contact closure")
    demand({path.name for path in evidence.glob("*.ppm")} == contacts | selected_names, "final PPM closure")
    demand(not any(evidence.glob("*.capture.json")), "retired capture metadata remains")
    demand(not (root / "frame-work").exists() and not (root / "frame-control").exists(), "mutable frame state remains")
    owned = owned_files(root)
    demand(set(file_hashes) == set(owned), "fileHashes closure")
    raw_pattern = re.compile(r"frame-[a-f0-9]{64}\.ppm\.gz")
    raw_paths = [relative for relative in owned if relative.startswith("frame-raw/")]
    demand(all(raw_pattern.fullmatch(Path(relative).name) for relative in raw_paths), "raw name")
    for relative, path in owned.items():
        demand(sha_file(path) == file_hashes[relative], "fileHashes readback")
    return str(commit), str(tree), str(run_id), str(scenario)

def parse_review_time(value, template_path):
    pattern = r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"
    demand(isinstance(value, str) and re.fullmatch(pattern, value) is not None, "review time format")
    try:
        parsed = dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
    except ValueError as error:
        raise EvidenceError("review timestamp is invalid") from error
    now = dt.datetime.now(dt.timezone.utc)
    created = dt.datetime.fromtimestamp(safe_file(template_path).st_mtime, dt.timezone.utc)
    demand(created - dt.timedelta(seconds=2) <= parsed <= now + dt.timedelta(minutes=5),
           "review timestamp is outside its accepted interval")

def validate_result_fields(result):
    sha_fields = "buildMetadataSha256 harnessSha256 installerSha256 isoSha256 releaseSha256sumsSha256 \
repositoryDatabaseSha256 repositoryDatabaseSignatureSha256 repositoryFilesSha256 \
repositoryFilesSignatureSha256 repositoryManifestSha256 repositoryManifestSignatureSha256 \
repositoryPackageSetSha256 repositoryPublicKeySha256 repositorySnapshotSha256 unsignedManifestSha256".split()
    demand(all(isinstance(result.get(key), str) and HEX64.fullmatch(result[key]) for key in sha_fields),
           "pending result SHA-256 field")
    fingerprints = (result.get("repositoryPrimaryFingerprint"), result.get("repositorySigningFingerprint"))
    demand(all(isinstance(value, str) and re.fullmatch(r"[A-F0-9]{40}", value) for value in fingerprints),
           "pending result fingerprint")
    mode = result.get("inputMode")
    snapshot = "INDEPENDENT_PASS" if mode == "staged" else "PUBLIC_RELEASE_PAGES_BINDING_PASS"
    demand(mode in {"staged", "public"} and result.get("snapshotVerification") == snapshot,
           "pending result input verification")
    demand(result.get("releaseVersion") == "1.0.0", "pending result release version")
    demand(isinstance(result.get("targetSerial"), str) and
           re.fullmatch(r"ALI100[MSBGLAR][A-F0-9]{12}", result["targetSerial"]), "target serial")
    objects = result.get("repositoryObjects")
    demand(isinstance(objects, list) and len(objects) == 23, "repositoryObjects closure")
    names = []
    for item in objects:
        exact_keys(item, {"name", "sha256", "size"}, "repository object")
        demand(isinstance(item["name"], str) and REPOSITORY_OBJECT.fullmatch(item["name"]), "object name")
        demand(isinstance(item["sha256"], str) and HEX64.fullmatch(item["sha256"]), "object digest")
        demand(exact_int(item["size"], 1), "object size")
        names.append(item["name"])
    demand(names == sorted(set(names)) and len(names) == 23, "repository object order")
    return objects

def repository_object_bytes(objects):
    return "".join(f"{item['name']}\t{item['sha256']}\t{item['size']}\n" for item in objects).encode("ascii")

def validate_review(root):
    evidence = root / "evidence"
    template_path = evidence / "manual-review-template.json"
    receipt_path = evidence / "manual-review-receipt.json"
    manifest_path = evidence / "frame-evidence-manifest.json"
    result_path = root / "result.json"
    for path in (template_path, receipt_path, manifest_path, result_path):
        safe_file(path)
    template = load_json(template_path)
    receipt = load_json(receipt_path)
    manifest = load_json(manifest_path)
    result = load_json(result_path)
    identity = validate_manifest(root, manifest)
    exact_keys(template, REVIEW_KEYS, "review template")
    exact_keys(receipt, REVIEW_KEYS, "review receipt")
    mutable = {"verdict", "reviewer", "reviewedAt", "pendingResultSha256", "confirmations", "notes"}
    demand(all(receipt[key] == template[key] for key in REVIEW_KEYS - mutable), "receipt identity")
    demand(template.get("schema") == SCHEMA and type(template.get("schema")) is int, "review template schema")
    defaults_ok = template.get("verdict") == "PENDING" and template.get("reviewer") == ""
    defaults_ok &= template.get("reviewedAt") == "" and template.get("notes") == ""
    defaults_ok &= template.get("pendingResultSha256") == ""
    expected_confirmations = {name: False for name in CONFIRMATIONS}
    defaults_ok &= template.get("confirmations") == expected_confirmations
    demand(defaults_ok, "review template mutable defaults differ")
    demand(receipt.get("verdict") == "PASS", "manual review is not PASS")
    reviewer = receipt.get("reviewer")
    demand(isinstance(reviewer, str) and REVIEWER.fullmatch(reviewer) is not None, "reviewer")
    parse_review_time(receipt.get("reviewedAt"), template_path)
    confirmations = receipt.get("confirmations")
    demand(isinstance(confirmations, dict) and set(confirmations) == set(CONFIRMATIONS),
           "review confirmations schema")
    demand(all(confirmations[name] is True for name in CONFIRMATIONS), "review confirmation is not true")
    demand(receipt.get("notes") == "", "review notes must remain empty")
    manifest_sha = sha_file(manifest_path)
    demand(template.get("manifestSha256") == manifest_sha, "template manifest binding")
    demand(receipt.get("manifestSha256") == manifest_sha, "receipt manifest binding")
    review_identity = (template["sourceCommit"], template["sourceTree"], template["runId"], template["scenario"])
    demand(review_identity == identity, "review/manifest identity")
    exact_keys(result, RESULT_KEYS, "pending result")
    pending_ok = result.get("status") == "PENDING_VISUAL_REVIEW" and result.get("exitStatus") == 0
    pending_ok &= type(result.get("exitStatus")) is int and result.get("failedPhase") is None
    demand(pending_ok, "pending result status")
    result_identity = tuple(result.get(key) for key in ("sourceCommit", "sourceTree", "runId", "scenario"))
    demand(result_identity == identity, "pending result identity")
    demand(result.get("manualReviewStatus") == "PENDING", "pending manual-review status")
    demand(result.get("manualReviewTemplateSha256") == sha_file(template_path),
           "pending result template binding")
    objects = validate_result_fields(result)
    retained_objects = read_bytes(evidence / "repository-objects.tsv", MAX_JSON, (0o444,))
    demand(retained_objects == repository_object_bytes(objects), "pending result/repository object evidence")
    result_sha = sha_file(result_path)
    demand(receipt.get("pendingResultSha256") == result_sha, "receipt pending-result binding")
    contacts = sorted(path.name for path in evidence.glob("*-contact-sheet-*.ppm"))
    demand(result.get("screenshots") == sorted(manifest["selectedFrames"]), "result screenshots differ")
    demand(result.get("frameLedgers") == sorted(LEDGER_NAMES) and result.get("contactSheets") == contacts,
           "result framebuffer arrays differ")
    assertions = result.get("assertions")
    demand(isinstance(assertions, list) and assertions, "result assertions differ")
    assertion_ids = set()
    for item in assertions:
        exact_keys(item, {"id", "status", "detail"}, "result assertion")
        assertion_id = item.get("id")
        valid_id = isinstance(assertion_id, str) and SAFE.fullmatch(assertion_id) is not None
        demand(valid_id and assertion_id not in assertion_ids, "result assertion id")
        assertion_ids.add(assertion_id)
        demand(item.get("status") == "PASS", "result assertion status")
        demand(isinstance(item.get("detail"), str) and bool(item["detail"]), "assertion detail")
    retained = result.get("retainedEvidenceBytes")
    demand(exact_int(retained) and retained <= MAX_EVIDENCE, "retained evidence bytes differ")
    return { "schema": SCHEMA, "status": "PASS", "sourceCommit": identity[0], "sourceTree": identity[1],
        "runId": identity[2], "scenario": identity[3], "manifestSha256": manifest_sha,
        "templateSha256": sha_file(template_path), "receiptSha256": sha_file(receipt_path),
        "pendingResultSha256": result_sha, }

def budget(transient, raw_bytes, output_bytes):
    demand(transient <= MAX_EVIDENCE, "transient cumulative evidence budget exceeded")
    permanent = transient - raw_bytes + output_bytes
    demand(permanent <= MAX_EVIDENCE, "permanent cumulative evidence budget would be exceeded")
    return permanent

def bound_meta(path, fd):
    meta, linked = os.fstat(fd), safe_file(path)
    value = meta.st_dev, meta.st_ino, meta.st_size
    valid = (meta.st_uid, meta.st_nlink, stat.S_IMODE(meta.st_mode)) == (os.getuid(), 1, 0o600)
    demand(stat.S_ISREG(meta.st_mode) and meta.st_size <= MAX_JSON and valid and
           value == (linked.st_dev, linked.st_ino, linked.st_size), "staged verdict descriptor/path metadata")
    return value
def file_binding(path, fd, expected=None):
    before = bound_meta(path, fd)
    data = os.pread(fd, before[2] + 1, 0)
    demand(len(data) == before[2], "staged verdict size/read")
    demand(bound_meta(path, fd) == before, "staged verdict changed")
    value = before[:2], sha_bytes(data)
    demand(expected is None or value == expected, "staged verdict binding changed")
    return value

def git_text(repo, *args):
    try:
        return subprocess.check_output(
            ["/usr/bin/git", "-C", str(repo), *args], stderr=subprocess.DEVNULL, text=True).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise EvidenceError("Git source binding failed") from error

def verify_current_source(root, commit, tree, current=None):
    result = load_json(root / "result.json")
    harness = read_bytes(root / "harness.sha256", MAX_JSON)
    digest = result.get("harnessSha256")
    demand(isinstance(digest, str) and HEX64.fullmatch(digest) and sha_bytes(harness) == digest,
           "retained harness hash is not result-bound")
    matches = re.findall(rb"(?m)^([a-f0-9]{64})  tests/vm/frame-evidence\.py$", harness)
    demand(len(matches) == 1, "retained harness helper entry is not exact")
    if current is None:
        helper = Path(__file__).resolve(strict=True)
        repo = helper.parents[2]
        demand(git_text(repo, "status", "--porcelain=v1", "--untracked-files=all") == "",
               "current source is dirty")
        current = (git_text(repo, "rev-parse", "HEAD"), git_text(repo, "rev-parse", "HEAD^{tree}"),
                   read_bytes(helper, 81920, (0o644,)))
    head, actual_tree, helper_bytes = current
    demand((head, actual_tree) == (commit, tree), "current source identity is not frozen")
    demand(isinstance(helper_bytes, bytes) and sha_bytes(helper_bytes) == matches[0].decode(),
           "current helper is not harness-bound")

def finalize_command(args, current_source=None):
    root = run_root(args.run_root)
    output = root / "visual-review-verdict.json"
    pending = root / ".visual-review-verdict.pending"
    demand(not output.exists() and not output.is_symlink(), "visual verdict already exists")
    demand(not pending.exists() and not pending.is_symlink(), "pending visual verdict already exists")
    verdict = validate_review(root)
    verify_current_source(root, verdict["sourceCommit"], verdict["sourceTree"], current_source)
    raw = root / "frame-raw"
    preflight_tree(raw)
    common = root.parent
    transient = tree_size(common)
    budget(transient, 0, 0)
    raw_bytes = tree_size(raw)
    value = verdict | { "rawFramesRemoved": True, "budgetBytes": MAX_EVIDENCE, "transientEvidenceBytes": transient, }
    encoded = b""
    for _ in range(8):
        value["cumulativePermanentEvidenceBytes"] = transient - raw_bytes + len(encoded)
        updated = json_bytes(value)
        if updated == encoded:
            break
        encoded = updated
    value["cumulativePermanentEvidenceBytes"] = transient - raw_bytes + len(encoded)
    encoded = json_bytes(value)
    budget(transient, raw_bytes, len(encoded))
    fd = write_once(pending, encoded, retain=True)
    try:
        binding = file_binding(pending, fd)
        sync_dir(root)
        remove_tree(raw)
        file_binding(pending, fd, binding)
        os.rename(pending, output)
        sync_dir(root)
        file_binding(output, fd, binding)
        demand(tree_size(common) == value["cumulativePermanentEvidenceBytes"],
               "cumulative permanent evidence size changed")
        print(json.dumps(value, sort_keys=True))
    finally:
        os.close(fd)

# FRAME_EVIDENCE_SELFTEST_BEGIN
def _selftest_fail(function, *args, **kwargs):
    try:
        function(*args, **kwargs)
    except (EvidenceError, FileNotFoundError, json.JSONDecodeError, OSError):
        return
    raise EvidenceError("bad")
def _selftest_run():
    reject = _selftest_fail
    clone = lambda v: json.loads(json.dumps(v))
    create = write_once
    review = validate_review
    temp = tempfile.TemporaryDirectory()
    def check(condition):
        demand(condition, "test")
    base = Path(temp.name)
    base.chmod(0o700)
    frames = base / "frames"
    ensure_dir(frames)
    pixels = {name: b"\xff" * count * 3 + b"\0" * (4096 - count) * 3
        for name, count in (("black", 0), ("white", 256), ("post", 512), ("clear", 32), ("one", 1))}
    for name, payload in pixels.items():
        create(frames / f"{name}.ppm", b"P6\n64 64\n255\n" + bytes(payload))
    black, white, post, clear, one = (parse_ppm(frames / f"{name}.ppm") for name in pixels)
    check(0 < QMP_TIMEOUT_SECONDS <= MAX_GAP_MS / 1000)
    reject(require_delta, black, black)
    reject(require_delta, black, one)
    capped = base / "capped"
    ensure_dir(capped)
    reject(store_raw, capped, white, {}, 0)
    check(not any(capped.iterdir()))
    for data in (b"P3\n1 1\n255\n0 0 0\n", b"P6\n2 2\n255\n\0", b"P6\n1 1\n255\n\0\0\0x"):
        reject(parse_ppm_data, data)
    os.link(frames / "black.ppm", frames / "hard.ppm")
    reject(parse_ppm, frames / "black.ppm")
    (frames / "hard.ppm").unlink()
    os.symlink("black.ppm", frames / "link.ppm")
    reject(parse_ppm, frames / "link.ppm")
    (frames / "link.ppm").unlink()
    (frames / "black.ppm").chmod(0o644)
    reject(parse_ppm, frames / "black.ppm")
    (frames / "black.ppm").chmod(0o600)
    output = base / "output"
    ensure_dir(output)
    run = output / "minimal-20260901T000000Z-aaaaaaaa"
    ensure_dir(run)
    for name in ("evidence", "frame-raw", "frame-control"):
        ensure_dir(run / name)
    def raw_item(directory, frame):
        compressed = gzip.compress(frame[4], compresslevel=1, mtime=0)
        name = f"frame-{frame[3]}.ppm.gz"
        if not (directory / name).exists():
            create(directory / name, compressed)
        return {"ppm": frame[3], "raw": name, "rawSha": sha_bytes(compressed), "w": frame[0], "h": frame[1]}
    def fixture(phase, segment):
        stamp = 1_000_000_000
        pid = 900001 + (phase == "postreboot")
        after = white if phase == "firstboot" else post
        raw_dir = run / "frame-raw" / f"{phase}-{segment}"
        ensure_dir(raw_dir)
        def sample(number, frame):
            return {"e": "sample", "n": number, "t": stamp + number * 250_000_000,
                "gapMs": 0 if number == 0 else 250, **raw_item(raw_dir, frame)}
        def control(name, number, when, nonce):
            return {"e": "control", "name": name, "nonce": nonce * 16, "n": number, "t": when, "state": "running"}
        args = argparse.Namespace(phase=phase, segment=segment, qemu_pid=pid, qemu_start="777777")
        fake_qmp = argparse.Namespace(identity="7:8", pid=pid, peer_uid=os.getuid())
        header = header_record(args, fake_qmp, "888888", stamp)
        records = [header, sample(0, black), {"e": "ready", "n": 0, "t": stamp + 1,
            "ppm": black[3], "state": header["initial"]}]
        if segment == "shutdown":
            records.append(control("shutdown-armed", 0, stamp + 2, "a"))
            for number in range(1, 101):
                frame = post if number == 100 else (white if number % 2 else black)
                records.append(sample(number, frame))
            return records + [terminal_record("qemu-exit", 101, stamp + 25_000_000_001, True)]
        return records + [ control("cont-sent", 0, stamp + 2, "b"), sample(1, black),
            control("challenge-before", 1, stamp + 250_000_001, "c"), sample(2, after),
            control("challenge-after", 2, stamp + 500_000_001, "d"), sample(3, clear),
            control("challenge-cleared", 3, stamp + 750_000_001, "e"),
            control("stop-boot", 3, stamp + 750_000_002, "f"),
            terminal_record("requested-stop", 3, stamp + 750_000_003, False), ]
    def write_ledger(path, records):
        path.unlink(missing_ok=True)
        for index, record in enumerate(records):
            append_json(path, record, first=index == 0)
    fixtures = {}
    for phase, segment in SEGMENTS:
        paths = segment_paths(run, phase, segment)
        records = fixture(phase, segment)
        fixtures[f"{phase}-{segment}"] = records
        write_ledger(paths["ledger"], records)
        controls = "".join(f"{item['name']}:{item['nonce']}\n" for item in records if item.get("e") == "control")
        create(paths["control"], controls.encode())
        write_json(paths["ready"], ready_record(records[0], records[1]["ppm"]))
    def changed(records, index, **updates):
        copied = clone(records)
        copied[index].update(updates)
        return copied
    def with_gap(nanoseconds):
        copied = clone(fixtures["firstboot-boot"])
        for item in copied[4:]:
            item["t"] += nanoseconds - 250_000_000
        copied[4]["gapMs"] = nanoseconds // 1_000_000
        return copied
    boot = fixtures["firstboot-boot"]
    boot_path = segment_paths(run, "firstboot", "boot")["ledger"]
    swapped = clone(boot)
    swapped[2], swapped[3] = swapped[3], swapped[2]
    negatives = [changed(boot, index, **{field: value}) for index, field, value in (
        (0, "initial", "running"), (0, "head", 1), (0, "schema", True), (0, "head", False),
        (0, "peerPid", 99), (0, "peerUid", os.getuid() + 1), (0, "qmp", "0:0"), (1, "n", False),
        (1, "gapMs", False), (2, "n", False), (3, "n", True), (-1, "n", False))]
    negatives += [
        changed(boot, 0, recorderPid=os.getpid(), recorderStart=process_start(os.getpid())),
        changed(boot, 4, t=boot[0]["t"] - 1),
        with_gap(500_000_001),
        changed(boot, -1, reason="qemu-exit", qemuExit=True), boot[:-1],
        [item for item in boot if item.get("e") != "ready"], swapped, ]
    for records in negatives:
        write_ledger(boot_path, records)
        reject(validate_segment, run, "firstboot", "boot", True)
    write_ledger(boot_path, with_gap(500_000_000))
    validate_segment(run, "firstboot", "boot", True)
    write_ledger(boot_path, boot)
    shutdown_path = segment_paths(run, "postreboot", "shutdown")["ledger"]
    write_ledger(shutdown_path, fixtures["postreboot-shutdown"][:-1])
    reject(validate_segment, run, "postreboot", "shutdown", False)
    write_ledger(shutdown_path, fixtures["postreboot-shutdown"])
    extra = segment_paths(run, "firstboot", "boot")["raw"] / "extra"
    create(extra, b"x")
    reject(validate_segment, run, "firstboot", "boot", True)
    extra.unlink()
    reject(check_challenge_pair, {}, run.name)
    reject(check_run_identity, "minimal-ext4-systemdboot", "stock-" + run.name[8:])
    reject(check_run_root, run, "")
    evdir = run / "evidence"
    work = run / "frame-work"
    ensure_dir(work)
    for phase, pid in (("firstboot", 900001), ("postreboot", 900002)):
        identity = (f"phase={phase}\npid={pid}\nstart_time=777777\nqga_identity=5:6\n"
            "qmp_identity=7:8\nqmp_capture_identity=9:10\n")
        identity_path = evdir / f"{phase}-qemu.identity"
        if phase == "firstboot":
            create(identity_path, identity.replace("qmp_capture_identity=9:10",
                "qmp_capture_identity=7:8").encode())
            reject(load_identity, identity_path, phase)
            identity_path.unlink()
        create(identity_path, identity.encode())
        after = white if phase == "firstboot" else post
        create(work / f"{phase}-tty-before.ppm", black[4])
        create(evdir / f"{phase}-tty.ppm", after[4])
        create(work / f"{phase}-tty-cleared.ppm", clear[4])
    args = argparse.Namespace(run_root=str(run), source_commit="a" * 40, source_tree="b" * 40,
        run_id=run.name, scenario="minimal-ext4-systemdboot")
    heavy = run / "target.qcow2"
    create(heavy, b"heavy")
    reject(seal_command, args)
    heavy.unlink()
    seal_command(args)
    template = evdir / "manual-review-template.json"
    manifest = load_json(evdir / "frame-evidence-manifest.json")
    def cell(frame, index):
        x0, y0 = index % TILE_COLS * TILE_W, index // TILE_COLS * TILE_H
        return b"".join(frame[2][((y0 + row) * frame[0] + x0) * 3:
            ((y0 + row) * frame[0] + x0 + TILE_W) * 3] for row in range(TILE_H))
    sheets = [parse_ppm(evdir / f"firstboot-shutdown-contact-sheet-{index:03d}.ppm") for index in (1, 2)]
    expected = [resize(black if index % 2 == 0 else white) for index in range(100)] + [resize(post)]
    actual = [cell(sheets[index // 100], index % 100) for index in range(101)]
    check(actual == expected and actual != list(reversed(expected)))
    check(not any(b"".join(cell(sheets[1], index) for index in range(1, 100))))
    for field, value in (("after", None), ("changedPixels", True), ("input", "enter"),
        ("challenge", "ali-firstboot-bbbbbbbb")):
        bad = clone(manifest["challenges"])
        bad["firstboot"][field] = value
        reject(check_challenge_pair, bad, run.name)
    objects = [{"name": f"Arch_Linux+Pkg_{index:02d}.pkg.tar.zst", "sha256": f"{index:064x}",
        "size": index + 1} for index in range(23)]
    result = dict.fromkeys(RESULT_KEYS, "f" * 64)
    result.update({ "status": "PENDING_VISUAL_REVIEW", "exitStatus": 0, "failedPhase": None,
        "sourceCommit": "a" * 40, "sourceTree": "b" * 40, "runId": run.name, "scenario": args.scenario,
        "inputMode": "staged", "snapshotVerification": "INDEPENDENT_PASS", "releaseVersion": "1.0.0",
        "repositoryPrimaryFingerprint": "A" * 40, "repositorySigningFingerprint": "B" * 40,
        "targetSerial": "ALI100M123456789ABC",
        "manualReviewStatus": "PENDING", "manualReviewTemplateSha256": sha_file(template),
        "screenshots": sorted(manifest["selectedFrames"]), "frameLedgers": sorted(LEDGER_NAMES),
        "contactSheets": sorted(path.name for path in evdir.glob("*-contact-sheet-*.ppm")),
        "assertions": [{"id": "fixture", "status": "PASS", "detail": "verified"}],
        "repositoryObjects": objects,
        "retainedEvidenceBytes": tree_size(output), })
    tsv = evdir / "repository-objects.tsv"
    create(tsv, repository_object_bytes(objects))
    tsv.chmod(0o444)
    helper_bytes = b"fixture helper\n"
    harness_path = run / "harness.sha256"
    create(harness_path, f"{sha_bytes(helper_bytes)}  tests/vm/frame-evidence.py\n".encode())
    result["harnessSha256"] = sha_file(harness_path)
    result_path = run / "result.json"
    write_json(result_path, result)
    receipt = load_json(template)
    receipt.update(verdict="PASS", reviewer="reviewer",
        reviewedAt=dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        pendingResultSha256=sha_file(result_path))
    receipt["confirmations"] = dict.fromkeys(CONFIRMATIONS, True)
    receipt_path = evdir / "manual-review-receipt.json"
    write_json(receipt_path, receipt)
    current = ("a" * 40, "b" * 40, helper_bytes)
    reject(verify_current_source, run, *current[:2], current[:2] + (b"changed",))
    reject(verify_current_source, run, *current[:2], (current[0], "c" * 40, helper_bytes))
    manifest_path = evdir / "frame-evidence-manifest.json"
    good_manifest = read_bytes(manifest_path, MAX_JSON)
    good_template = read_bytes(template, MAX_JSON)
    good = read_bytes(receipt_path, MAX_JSON)
    good_result = read_bytes(result_path, MAX_JSON)
    def replace(path, value):
        path.unlink(missing_ok=True)
        create(path, value if isinstance(value, bytes) else json_bytes(value))
    def reject_receipt(value):
        replace(receipt_path, value)
        reject(review, run)
        replace(receipt_path, good)
    bad_manifest = json.loads(good_manifest)
    bad_manifest["segments"][0]["samples"] = 5
    replace(manifest_path, bad_manifest)
    replace(template, json.loads(good_template) | {"manifestSha256": sha_file(manifest_path)})
    replace(result_path, json.loads(good_result) | {"manualReviewTemplateSha256": sha_file(template)})
    replace(receipt_path, json.loads(good) | {"manifestSha256": sha_file(manifest_path),
        "pendingResultSha256": sha_file(result_path)})
    reject(review, run)
    for path, data in ((manifest_path, good_manifest), (template, good_template),
        (result_path, good_result), (receipt_path, good)):
        replace(path, data)
    receipt_path.unlink()
    reject(review, run)
    create(receipt_path, good)
    for key, value in (("verdict", "FAIL"), ("manifestSha256", "c" * 64),
        ("pendingResultSha256", "c" * 64), ("sourceTree", "c" * 40),
        ("reviewedAt", "2999-01-01T00:00:00Z")):
        reject_receipt(json.loads(good) | {key: value})
    bad = json.loads(good)
    bad["confirmations"][CONFIRMATIONS[0]] = 1
    reject_receipt(bad)
    zero = clone(objects)
    zero[0]["size"] = 0
    unsafe = clone(objects)
    unsafe[0]["name"] = "../bad"
    for key, value in (("repositoryObjects", []), ("repositoryObjects", objects[:-1] + [objects[-2]]),
        ("repositoryObjects", list(reversed(objects))), ("repositoryObjects", zero),
        ("repositoryObjects", unsafe), ("installerSha256", "F" * 64),
        ("repositoryPrimaryFingerprint", "a" * 40),
        ("snapshotVerification", "PUBLIC_RELEASE_PAGES_BINDING_PASS"),
        ("releaseVersion", "1.0.1"), ("targetSerial", "bad")):
        reject(validate_result_fields, result | {key: value})
    for bad_result in ( result | {"unexpected": True}, result | {"screenshots": []},
        result | {"repositoryObjects": [objects[0] | {"size": 99}, *objects[1:]]},
        result | {"assertions": [{"id": "fixture", "status": "FAIL", "detail": "bad"}]}, ):
        replace(result_path, bad_result)
        replace(receipt_path, json.loads(good) | {"pendingResultSha256": sha_file(result_path)})
        reject(review, run)
    replace(result_path, good_result)
    replace(receipt_path, good)
    extra_selected = evdir / "firstboot-extra.ppm"
    create(extra_selected, black[4])
    reject(review, run)
    extra_selected.unlink()
    contact = next(evdir.glob("*-contact-sheet-*.ppm"))
    saved_contact = run / "saved-contact.ppm"
    os.rename(contact, saved_contact)
    reject(review, run)
    os.rename(saved_contact, contact)
    contact_data = read_bytes(contact, MAX_PPM)
    replace(contact, contact_data[:-1] + bytes([contact_data[-1] ^ 1]))
    reject(review, run)
    replace(contact, contact_data)
    alias = run / "contact-hardlink"
    os.link(contact, alias)
    reject(review, run)
    alias.unlink()
    raw = next((run / "frame-raw").glob("*/*"))
    raw_data = read_bytes(raw, MAX_RAW_SEGMENT)
    replace(raw, raw_data + b"x")
    reject(review, run)
    replace(raw, raw_data)
    reject(budget, MAX_EVIDENCE + 1, 0, 0)
    reject(budget, MAX_EVIDENCE, 0, 1)
    staged = run / "staged"
    fd = create(staged, b"verdict", True)
    binding = file_binding(staged, fd)
    alias = run / "alias"
    os.link(staged, alias)
    reject(file_binding, staged, fd, binding)
    alias.unlink()
    os.pwrite(fd, b"x", 0)
    reject(file_binding, staged, fd, binding)
    os.pwrite(fd, b"v", 0)
    file_binding(staged, fd, binding)
    os.symlink(staged.name, alias)
    reject(file_binding, alias, fd, binding)
    alias.unlink()
    staged.unlink()
    replace(staged, b"verdict")
    reject(file_binding, staged, fd, binding)
    os.close(fd)
    reject(file_binding, staged, fd, binding)
    staged.unlink()
    preserve = run / "frame-raw-preserve"
    ensure_dir(preserve)
    create(preserve / "sentinel", b"preserve")
    blocker = output / "transient-overflow"
    blocker.touch(mode=0o600)
    with blocker.open("r+b") as handle:
        handle.truncate(MAX_EVIDENCE)
    final_args = argparse.Namespace(run_root=str(run))
    reject(finalize_command, final_args, current)
    check((run / "frame-raw").is_dir())
    check(not (run / "visual-review-verdict.json").exists())
    blocker.unlink()
    finalize_command(final_args, current)
    check(not (run / "frame-raw").exists())
    check((run / "visual-review-verdict.json").is_file())
    check((preserve / "sentinel").is_file())
    temp.cleanup()
# FRAME_EVIDENCE_SELFTEST_END

def build_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    commands = parser.add_subparsers(dest="command")
    root_parent = argparse.ArgumentParser(add_help=False)
    root_parent.add_argument("--run-root", required=True)
    qmp_parent = argparse.ArgumentParser(add_help=False, parents=[root_parent])
    qmp_parent.add_argument("--qmp-socket", required=True)
    qmp_parent.add_argument("--qemu-pid", type=int, required=True)
    qmp_parent.add_argument("--qemu-start", required=True)
    qmp_parent.add_argument("--phase", choices=PHASES, required=True)
    record = commands.add_parser("record", parents=[qmp_parent])
    record.add_argument("--segment", choices=("boot", "shutdown"), required=True)
    capture = commands.add_parser("capture", parents=[qmp_parent])
    capture.add_argument("--name", required=True)
    capture.add_argument("--ledger", required=True)
    capture.add_argument("--after-event", choices=tuple(sorted(CONTROL_EVENTS)))
    capture.add_argument("--different-from")
    capture.add_argument("--restore-toward")
    seal = commands.add_parser("seal", parents=[root_parent])
    seal.add_argument("--source-commit", required=True)
    seal.add_argument("--source-tree", required=True)
    seal.add_argument("--run-id", required=True)
    seal.add_argument("--scenario", choices=tuple(SCENARIO_PREFIX), required=True)
    commands.add_parser("finalize-review", parents=[root_parent])
    return parser

def main():
    parser = build_parser()
    args = parser.parse_args()
    if args.self_test:
        demand(args.command is None, "--self-test cannot be combined with a command")
        _selftest_run()
        return
    demand(args.command is not None, "one command is required")
    actions = { "record": record_command, "capture": capture_command, "seal": seal_command,
        "finalize-review": finalize_command, }
    actions[args.command](args)

if __name__ == "__main__":
    try:
        main()
    except (EvidenceError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"frame evidence failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
