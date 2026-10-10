// Loaded once through the ordinary Looking Glass UI in the disposable guest.
// No Shell.Eval, unsafe mode, extension callbacks, settings or actor changes.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const ATTRIBUTES = 'standard::type,standard::size,unix::uid,unix::mode,unix::device,unix::inode';
const NOFOLLOW = Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS;
const credentials = new Gio.Credentials();
const uid = credentials.get_unix_user();
const pid = credentials.get_unix_pid();
const source = Gio.File.new_for_uri(import.meta.url);
const codeDirectory = source.get_parent();
const match = /^\/run\/arch-linux-qemu-desktop-code\/((?:marble|luksgrub)-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8})\/(firstlogin|upgrade|postreboot)$/.exec(codeDirectory.get_path());
const directory = match === null ? null : Gio.File.new_for_path(`/run/user/${uid}/arch-linux-qemu-extension-${match[1]}-${match[2]}`);
let identity = null;
const hashes = {observerSha256: '-', probeSha256: '-'};

function sameFile(a, b) {
    return a.get_attribute_uint32('unix::device') === b.get_attribute_uint32('unix::device') &&
        a.get_attribute_uint64('unix::inode') === b.get_attribute_uint64('unix::inode') &&
        a.get_size() === b.get_size();
}
function validFile(info, mode, limit, owner = uid) {
    return info.get_file_type() === Gio.FileType.REGULAR &&
        info.get_attribute_uint32('unix::uid') === owner &&
        (info.get_attribute_uint32('unix::mode') & 0o7777) === mode &&
        info.get_size() >= 1 && info.get_size() <= limit;
}
function privateDirectory(file) {
    const info = file.query_info(ATTRIBUTES, NOFOLLOW, null);
    if (info.get_file_type() !== Gio.FileType.DIRECTORY ||
        info.get_attribute_uint32('unix::uid') !== uid ||
        (info.get_attribute_uint32('unix::mode') & 0o7777) !== 0o700)
        throw new Error('invalid-native-input');
}
function readFile(name, mode, limit, optional = false, owner = uid) {
    const file = (owner === 0 ? codeDirectory : directory).get_child(name);
    let before;
    try { before = file.query_info(ATTRIBUTES, NOFOLLOW, null); }
    catch (error) {
        if (optional && error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND)) return null;
        throw new Error('invalid-native-input');
    }
    if (!validFile(before, mode, limit, owner)) throw new Error('invalid-native-input');
    const stream = file.read(null);
    let bytes;
    try {
        // Query the opened descriptor as well as the pathname. A replaced or
        // symlinked entry must not silently select different bytes.
        const opened = stream.query_info(ATTRIBUTES, null);
        if (!validFile(opened, mode, limit, owner) || !sameFile(before, opened))
            throw new Error('invalid-native-input');
        bytes = stream.read_bytes(limit + 1, null);
        const after = file.query_info(ATTRIBUTES, NOFOLLOW, null);
        const retained = stream.query_info(ATTRIBUTES, null);
        if (bytes.get_size() !== before.get_size() || !validFile(after, mode, limit, owner) ||
            !validFile(retained, mode, limit, owner) || !sameFile(before, after) || !sameFile(before, retained))
            throw new Error('invalid-native-input');
    } finally {
        stream.close(null);
    }
    return {bytes, sha256: GLib.compute_checksum_for_bytes(GLib.ChecksumType.SHA256, bytes)};
}
function json(input) {
    return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(input.bytes.get_data()));
}
function writeReceipt(name, receipt) {
    if (!/^desktop-shell-(?:ready|(?:[1-9]|[1-5][0-9]|6[0-4])-(?:blur-on|blur-off|panel-shown|panel-hidden|panel-overview-only|theme-marble|theme-stock|stop))\.json$/.test(name))
        throw new Error('invalid-receipt-name');
    const text = `${JSON.stringify(receipt)}\n`;
    if (new TextEncoder().encode(text).length > 8192)
        throw new Error('invalid-receipt-size');
    privateDirectory(directory);
    const file = directory.get_child(name);
    try {
        const existing = file.query_info(ATTRIBUTES, NOFOLLOW, null);
        if (!validFile(existing, 0o600, 8192)) throw new Error('invalid-native-input');
    } catch (error) {
        if (!(error instanceof GLib.Error) || !error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND))
            throw new Error('invalid-native-input');
    }
    // PRIVATE gives 0600; REPLACE_DESTINATION replaces an entry rather than
    // following a raced symlink. All names are fixed within the private state.
    file.replace_contents(text, null, false,
        Gio.FileCreateFlags.PRIVATE | Gio.FileCreateFlags.REPLACE_DESTINATION, null);
    const written = file.query_info(ATTRIBUTES, NOFOLLOW, null);
    if (!validFile(written, 0o600, 8192)) throw new Error('invalid-native-input');
}
function fail(code) {
    if (identity === null) return;
    try {
        writeReceipt('desktop-shell-ready.json', {schema: 1, runId: identity.runId, round: identity.round,
            sequence: 0, stage: 'ready', pid, uid, probeSha256: hashes.probeSha256,
            observerSha256: hashes.observerSha256, status: 'failure', code, facts: {}});
    } catch {
        // No raw exceptions, paths or arbitrary native messages are logged.
    }
}

let guardCode = 'invalid-native-input';
try {
    if (match === null || uid < 1 || source.get_basename() !== 'desktop-shell-probe.js' || pid < 2)
        throw new Error('invalid-native-input');
    identity = {runId: match[1], round: match[2], uid, pid};
    for (const file of [codeDirectory, codeDirectory.get_parent(), codeDirectory.get_parent().get_parent()]) {
        const info = file.query_info(ATTRIBUTES, NOFOLLOW, null);
        if (info.get_file_type() !== Gio.FileType.DIRECTORY || info.get_attribute_uint32('unix::uid') !== 0 ||
            (info.get_attribute_uint32('unix::mode') & 0o7777) !== 0o755) throw new Error('invalid-native-input');
    }
    privateDirectory(directory.get_parent());
    privateDirectory(directory);
    if (global.context.unsafe_mode !== false) {
        guardCode = 'unsafe-mode';
        throw new Error('unsafe-mode');
    }
    // Root-owned readable copies cannot be edited in place by the Shell UID.
    hashes.probeSha256 = readFile('desktop-shell-probe.js', 0o555, 65536, false, 0).sha256;
    hashes.observerSha256 = readFile('desktop-extension-observer.js', 0o555, 65536, false, 0).sha256;
    guardCode = 'invalid-metadata';
    const metadata = json(readFile('desktop-shell-metadata.json', 0o600, 8192));
    if (metadata?.schema !== 1 || metadata.uid !== uid || metadata.shellPid !== pid ||
        metadata.probeSha256 !== hashes.probeSha256 || metadata.observerSha256 !== hashes.observerSha256)
        throw new Error('invalid-metadata');
    // Only this source-hashed sibling is imported. No metadata or command
    // field can select a module, path, callback or executable.
    guardCode = 'observer-bootstrap-failure';
    const {startDesktopShellObserver} = await import('./desktop-extension-observer.js');
    startDesktopShellObserver({identity, hashes, runtime: {Main, global, St, Shell},
        readMetadata: () => metadata,
        readCommand: () => {
            privateDirectory(directory);
            const input = readFile('desktop-shell-command.json', 0o600, 8192, true);
            return input === null ? null : {value: json(input), sha256: input.sha256};
        },
        writeReceipt,
        now: () => GLib.get_monotonic_time() / 1000,
        addTimer: (interval, callback) => GLib.timeout_add(GLib.PRIORITY_DEFAULT, interval,
            () => callback() ? GLib.SOURCE_CONTINUE : GLib.SOURCE_REMOVE),
        removeTimer: id => GLib.source_remove(id),
    });
} catch {
    fail(guardCode);
}
