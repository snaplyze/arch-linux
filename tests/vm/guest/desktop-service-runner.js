#!/usr/bin/gjs -m
// Fixed-file user-session adapter for source-bound desktop acceptance.
import Gio from 'gi://Gio';
import GioUnix from 'gi://GioUnix';
import GLib from 'gi://GLib';
import System from 'system';

const NOFOLLOW = 131072, CLOEXEC = 524288, DIRECTORY = 65536;
const STAGES = ['indicator-register', 'indicator-remove', 'caffeine-observe', 'stop'];
const RUN_ID = /^(marble|luksgrub)-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$/;
const ROUNDS = ['firstlogin', 'upgrade', 'postreboot'];
const SHA = /^[a-f0-9]{64}$/;
const encoder = new TextEncoder();
function exactKeys(value, keys) {
    return value !== null && typeof value === 'object' && !Array.isArray(value) &&
        Object.keys(value).sort().join(',') === [...keys].sort().join(',');
}
function info(fd, uid, mode, type) {
    const metadata = Gio.File.new_for_path(`/proc/self/fd/${fd}`).query_info(
        'standard::type,standard::size,unix::mode,unix::uid', Gio.FileQueryInfoFlags.NONE, null);
    if (metadata.get_file_type() !== type || metadata.get_attribute_uint32('unix::uid') !== uid ||
        (metadata.get_attribute_uint32('unix::mode') & 0o7777) !== mode)
        throw new Error('Unsafe native file');
    return metadata;
}
export function openStateDirectory(path, uid) {
    const fd = GLib.open(path, DIRECTORY | NOFOLLOW | CLOEXEC, 0);
    if (fd < 0) throw new Error('Cannot open directory');
    try { info(fd, uid, 0o700, Gio.FileType.DIRECTORY); return fd; }
    catch (error) { GLib.close(fd); throw error; }
}
export function openCodeDirectory(path, owner = 0) {
    const file = Gio.File.new_for_path(path);
    for (const parent of [file, file.get_parent(), file.get_parent().get_parent()]) {
        const metadata = parent.query_info('standard::type,unix::uid,unix::mode', Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        if (metadata.get_file_type() !== Gio.FileType.DIRECTORY || metadata.get_attribute_uint32('unix::uid') !== owner ||
            (metadata.get_attribute_uint32('unix::mode') & 0o7777) !== 0o755) throw new Error('Unsafe code directory');
    }
    const fd = GLib.open(path, DIRECTORY | NOFOLLOW | CLOEXEC, 0);
    if (fd < 0) throw new Error('Cannot open code directory');
    try { info(fd, owner, 0o755, Gio.FileType.DIRECTORY); return fd; }
    catch (error) { GLib.close(fd); throw error; }
}
export function readPinnedFile(dir, name, uid, mode, limit) {
    if (!/^[a-zA-Z0-9.-]+$/.test(name) || name.startsWith('.') || !Number.isInteger(limit) || limit < 1)
        throw new Error('Invalid fixed file');
    // O_NONBLOCK also prevents a substituted FIFO from blocking before its type check.
    const fd = GLib.open(`/proc/self/fd/${dir}/${name}`, NOFOLLOW | CLOEXEC | 2048, 0);
    if (fd < 0) throw new Error('Cannot open fixed file');
    try {
        const metadata = info(fd, uid, mode, Gio.FileType.REGULAR);
        if (metadata.get_size() > limit) throw new Error('Oversized file');
        const stream = new GioUnix.InputStream({fd, close_fd: false});
        const chunks = []; let size = 0;
        while (true) {
            const chunk = stream.read_bytes(limit + 1 - size, null).toArray();
            if (!chunk.length) break;
            size += chunk.length;
            if (size > limit) throw new Error('Oversized read');
            chunks.push(chunk);
        }
        const bytes = new Uint8Array(size); let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
        return {bytes, fd};
    } catch (error) { GLib.close(fd); throw error; }
}
export function validateSourceHash(bytes, expected) {
    if (!SHA.test(expected) || GLib.compute_checksum_for_data(GLib.ChecksumType.SHA256, bytes) !== expected)
        throw new Error('Source mismatch');
    return true;
}
export function readRootSource(dir, name) {
    if (!['desktop-service-runner.js', 'desktop-service-probe.js'].includes(name))
        throw new Error('Invalid source name');
    // The user may replace a directory entry, which O_NOFOLLOW/FD pinning guards.
    // Root ownership and 0555 also prevent in-place edits between hash and import.
    return readPinnedFile(dir, name, 0, 0o555, 65536);
}
export function validateMetadata(value, runId, round, uid) {
    if (!exactKeys(value, ['schema', 'runId', 'round', 'uid', 'probeSha256', 'serviceSha256', 'expectedFlags']) ||
        value.schema !== 1 || !RUN_ID.test(runId) || !ROUNDS.includes(round) ||
        value.runId !== runId || value.round !== round || value.uid !== uid ||
        !Number.isInteger(uid) || uid < 1 || !SHA.test(value.probeSha256) || !SHA.test(value.serviceSha256) ||
        ![4, 8].includes(value.expectedFlags)) throw new Error('Invalid metadata');
    return value;
}
function validateCommand(value, identity) {
    if (!exactKeys(value, ['schema', 'runId', 'round', 'sequence', 'stage']) || value.schema !== 1 ||
        value.runId !== identity.runId || value.round !== identity.round ||
        !Number.isInteger(value.sequence) || value.sequence < 1 || value.sequence > 32 ||
        !STAGES.includes(value.stage)) throw new Error('Invalid command');
    return {schema: 1, runId: identity.runId, round: identity.round, sequence: value.sequence, stage: value.stage};
}

// One active stage. The adapter provides native operations, receipt output and bounded timers.
export class ServiceCommandRunner {
    constructor(identity, pid, adapter) {
        this.identity = identity; this.pid = pid; this.adapter = adapter;
        this.started = adapter.now(); this.completed = new Map();
        this.sequence = 0; this.pending = null; this.item = null;
        this.failed = false; this.stopped = false;
    }
    receipt(command, status, code, facts) {
        const i = this.identity;
        this.adapter.emit({schema: 1, runId: i.runId, round: i.round,
            sequence: command.sequence, stage: command.stage, pid: this.pid, uid: i.uid,
            probeSha256: i.probeSha256, serviceSha256: i.serviceSha256, status, code, facts});
    }
    async closeOwned() {
        const item = this.item; this.item = null;
        if (!item) return true;
        try {
            const result = await item.close();
            return result.status === 'unregistered' && result.absent === true && result.signal === true;
        } catch { return false; }
    }
    async reject(command, code) {
        if (this.failed) return;
        this.failed = true;
        const closed = await this.closeOwned();
        const safe = {sequence: Number.isInteger(command?.sequence) && command.sequence >= 1 && command.sequence <= 32 ? command.sequence : 32,
            stage: STAGES.includes(command?.stage) ? command.stage : 'stop'};
        this.receipt(safe, 'failure', code, {closed});
    }
    async accept(value) {
        if (this.failed) return;
        let command;
        try { command = validateCommand(value, this.identity); }
        catch { await this.reject(value, 'command-rejected'); return; }
        const canonical = JSON.stringify(command);
        if (this.completed.get(command.sequence) === canonical) return;
        if (this.adapter.now() - this.started >= 300000) {
            await this.reject(command, 'observer-timeout'); return;
        }
        if (this.pending) {
            if (this.pending === canonical) return;
            await this.reject(command, 'command-rejected'); return;
        }
        if (this.stopped || command.sequence !== this.sequence + 1) {
            await this.reject(command, 'replay-rejected'); return;
        }
        this.pending = canonical;
        let cancelTimeout, timedOut = false;
        const timeout = new Promise((_, reject) => {
            cancelTimeout = this.adapter.schedule(30000, () => { timedOut = true; reject(new Error('Command timeout')); });
        });
        try {
            const work = this.execute(command);
            const result = await Promise.race([work, timeout]);
            if (!this.failed) {
                this.receipt(command, 'ready', result.code, result.facts);
                this.completed.set(command.sequence, canonical);
                this.sequence = command.sequence;
            }
        } catch {
            await this.reject(command, this.adapter.now() - this.started >= 300000 ? 'observer-timeout' : timedOut ? 'command-timeout' : 'probe-failed');
        } finally {
            cancelTimeout(); this.pending = null;
        }
    }
    async execute(command) {
        if (command.stage === 'indicator-register') {
            if (this.item) throw new Error('Already registered');
            const item = await this.adapter.register();
            if (this.failed) { await item.close(); throw new Error('Stopped registration'); }
            this.item = item;
            if (item.observation.status !== 'registered' || item.observation.registered !== true || item.observation.signal !== true)
                throw new Error('Registration not observed');
            return {code: 'indicator-registered', facts: {registered: true, signal: true}};
        }
        if (command.stage === 'indicator-remove') {
            if (!this.item || !await this.closeOwned()) throw new Error('Removal not observed');
            return {code: 'indicator-removed', facts: {absent: true, signal: true}};
        }
        if (command.stage === 'caffeine-observe') {
            const result = await this.adapter.observe();
            if (!['found', 'not-found'].includes(result.status) || !Number.isInteger(result.count) ||
                result.count < 0 || result.count > 128 || !Number.isInteger(result.matchingCount) ||
                result.matchingCount < 0 || result.matchingCount > result.count ||
                (result.status === 'found') !== (result.matchingCount > 0)) throw new Error('Invalid inhibitor observation');
            return {code: 'inhibitor-observed', facts: {count: result.count, matchingCount: result.matchingCount,
                found: result.status === 'found'}};
        }
        if (!await this.closeOwned()) throw new Error('Stop cleanup failed');
        this.stopped = true;
        return {code: 'observer-stopped', facts: {closed: true}};
    }
}
function schedule(milliseconds, callback) {
    const timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, milliseconds, () => {
        callback(); return GLib.SOURCE_CONTINUE;
    });
    return () => GLib.source_remove(timer);
}
function readJSON(dir, name, uid, limit) {
    const input = readPinnedFile(dir, name, uid, 0o600, limit);
    try { return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(input.bytes)); }
    finally { GLib.close(input.fd); }
}
export function writeReceipt(dir, name, uid, value) {
    if (!/^desktop-service-(ready|(?:[1-9]|[12][0-9]|3[0-2])-(?:indicator-register|indicator-remove|caffeine-observe|stop))\.json$/.test(name))
        throw new Error('Invalid receipt name');
    const bytes = encoder.encode(`${JSON.stringify(value)}\n`);
    const temporary = Gio.File.new_for_path(`/proc/self/fd/${dir}/${name}.pending`);
    const destination = Gio.File.new_for_path(`/proc/self/fd/${dir}/${name}`);
    const fd = GLib.open(temporary.get_path(), 1 | 64 | 128 | CLOEXEC | NOFOLLOW, 0o600);
    if (fd < 0) throw new Error('Receipt collision');
    try {
        try {
            info(fd, uid, 0o600, Gio.FileType.REGULAR);
            const stream = new GioUnix.OutputStream({fd, close_fd: false});
            stream.write_all(bytes, null);
            if (GLib.fsync(fd) !== 0) throw new Error('Receipt flush failed');
        } finally { GLib.close(fd); }
        // Same-directory native move publishes complete bytes and rejects existing targets.
        temporary.move(destination, Gio.FileCopyFlags.NONE, null, null);
        if (GLib.fsync(dir) !== 0) throw new Error('Directory flush failed');
    } finally {
        try { temporary.delete(null); } catch {}
    }
}
async function main(args) {
    const [state, runId, round] = args;
    const code = `/run/arch-linux-qemu-desktop-code/${runId}/${round}`;
    const credentials = Gio.Credentials.new();
    const uid = credentials.get_unix_user(), pid = credentials.get_unix_pid();
    if (args.length !== 3 || !RUN_ID.test(runId ?? '') || !ROUNDS.includes(round) ||
        state !== `/run/user/${uid}/arch-linux-qemu-extension-${runId}-${round}` ||
        Gio.File.new_for_uri(import.meta.url).get_path() !== `${code}/desktop-service-runner.js`)
        throw new Error('Invalid runner identity');
    const dir = openStateDirectory(state, uid);
    const codeDir = openCodeDirectory(code);
    let helperInput = null, connection = null, engine = null;
    const cancelTimers = [];
    let finish;
    const finished = new Promise(resolve => { finish = resolve; });
    let terminating = false;
    const closeBus = () => {
        if (connection && !connection.is_closed()) {
            connection.get_stream().close(null);
            connection.run_dispose();
        }
        connection = null;
    };
    const terminate = async () => {
        if (terminating) return;
        terminating = true;
        if (engine) { engine.failed = true; await engine.closeOwned(); }
        closeBus();
        finish();
    };
    try {
        const identity = validateMetadata(readJSON(dir, 'desktop-service-metadata.json', uid, 4096), runId, round, uid);
        const source = readRootSource(codeDir, 'desktop-service-runner.js');
        try { validateSourceHash(source.bytes, identity.serviceSha256); } finally { GLib.close(source.fd); }
        helperInput = readRootSource(codeDir, 'desktop-service-probe.js');
        validateSourceHash(helperInput.bytes, identity.probeSha256);
        const helper = await import(`file:///proc/self/fd/${helperInput.fd}`);
        GLib.close(helperInput.fd); helperInput = null;
        if (!GLib.getenv('DBUS_SESSION_BUS_ADDRESS')) throw new Error('Missing explicit session bus');
        const busBudget = new Gio.Cancellable();
        const cancelBusTimeout = schedule(5000, () => busBudget.cancel());
        try {
            connection = await new Promise((resolve, reject) => Gio.bus_get(Gio.BusType.SESSION, busBudget, (_source, result) => {
                try { resolve(Gio.bus_get_finish(result)); } catch (error) { reject(error); }
            }));
        } finally { cancelBusTimeout(); }
        connection.set_exit_on_close(false);
        const emit = receipt => {
            if (receipt.code === 'observer-stopped') closeBus();
            const name = receipt.sequence === 0 ? 'desktop-service-ready.json' :
                `desktop-service-${receipt.sequence}-${receipt.stage}.json`;
            try { writeReceipt(dir, name, uid, receipt); }
            catch { terminate(); return; }
            if (receipt.status === 'failure') terminate();
            if (receipt.code === 'observer-stopped') cancelTimers.push(schedule(30000, finish));
        };
        engine = new ServiceCommandRunner(identity, pid, {
            now: () => GLib.get_monotonic_time() / 1000, schedule, emit,
            register: () => helper.registerSyntheticStatusNotifierItem(connection,
                {id: 'arch-linux-desktop-acceptance', iconName: 'utilities-terminal-symbolic'}),
            observe: () => helper.observeCaffeineInhibitor(connection, {expectedFlags: identity.expectedFlags}),
        });
        engine.receipt({sequence: 0, stage: 'ready'}, 'ready', 'observer-started', {});
        cancelTimers.push(schedule(300000, terminate));
        const poll = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
            if (terminating) return GLib.SOURCE_CONTINUE;
            // Absence before the first command is normal. Every present file still passes
            // native NOFOLLOW, owner, mode, bounded read and exact-object validation.
            const commandPath = Gio.File.new_for_path(`/proc/self/fd/${dir}/desktop-service-command.json`);
            try {
                commandPath.query_info('standard::type', Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            } catch (error) {
                if (error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND)) return GLib.SOURCE_CONTINUE;
                engine.reject(null, 'command-rejected').catch(terminate);
                return GLib.SOURCE_CONTINUE;
            }
            try { engine.accept(readJSON(dir, 'desktop-service-command.json', uid, 2048)).catch(terminate); }
            catch { engine.reject(null, 'command-rejected').catch(terminate); }
            return GLib.SOURCE_CONTINUE;
        });
        cancelTimers.push(() => GLib.source_remove(poll));
        const signal = GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 15, () => {
            terminate(); return GLib.SOURCE_CONTINUE;
        });
        cancelTimers.push(() => GLib.source_remove(signal));
        await finished;
        await engine.closeOwned();
    } finally {
        for (const cancel of cancelTimers) cancel();
        if (helperInput) GLib.close(helperInput.fd);
        closeBus();
        GLib.close(codeDir);
        GLib.close(dir);
    }
}
if (System.programPath === Gio.File.new_for_uri(import.meta.url).get_path()) {
    try { await main(ARGV); }
    catch { printerr('DESKTOP_SERVICE_RUNNER failure'); System.exit(1); }
}
