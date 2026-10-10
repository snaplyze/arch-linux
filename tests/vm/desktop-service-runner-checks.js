#!/usr/bin/gjs -m
// Offline protocol and native NOFOLLOW fixtures. No desktop/session bus access.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
const runner = await import('./guest/desktop-service-runner.js');
const uid = Gio.Credentials.new().get_unix_user();
const identity = {schema: 1, runId: 'marble-20261010T123456Z-abcdef12', round: 'upgrade', uid,
    probeSha256: 'a'.repeat(64), serviceSha256: 'b'.repeat(64), expectedFlags: 8};
let checks = 0;
function check(value, name) { if (!value) throw new Error(`FAIL: ${name}`); checks++; }
function rejects(fn, name) { let failed = false; try { fn(); } catch { failed = true; } check(failed, name); }
const tmp = GLib.dir_make_tmp('desktop-service-runner-checks-XXXXXX');
GLib.chmod(tmp, 0o700);
let dir;
try {
    dir = runner.openStateDirectory(tmp, uid);
    const codeRoot = `${tmp}/code`, codeRun = `${codeRoot}/run`, codeRound = `${codeRun}/round`;
    for (const path of [codeRoot, codeRun, codeRound]) { GLib.mkdir(path, 0o755); GLib.chmod(path, 0o755); }
    const codeFd = runner.openCodeDirectory(codeRound, uid); GLib.close(codeFd);
    check(true, 'separate immutable code closure accepted');
    for (const path of [codeRoot, codeRun, codeRound]) {
        GLib.chmod(path, 0o777);
        rejects(() => runner.openCodeDirectory(codeRound, uid), 'writable code ancestor rejected');
        GLib.chmod(path, 0o755);
    }
    rejects(() => runner.openCodeDirectory(codeRound, uid + 1), 'foreign code closure rejected');
    const codeLink = `${tmp}/code-link`;
    Gio.File.new_for_path(codeLink).make_symbolic_link(codeRound, null);
    rejects(() => runner.openCodeDirectory(codeLink, uid), 'symlink code closure rejected');
    Gio.File.new_for_path(codeLink).delete(null);
    for (const path of [codeRound, codeRun, codeRoot]) Gio.File.new_for_path(path).delete(null);

    const file = Gio.File.new_for_path(`${tmp}/metadata.json`);
    file.replace_contents('{}\n', null, false, Gio.FileCreateFlags.PRIVATE, null);
    const input = runner.readPinnedFile(dir, 'metadata.json', uid, 0o600, 64);
    try { check(new TextDecoder().decode(input.bytes) === '{}\n', 'bounded native read'); } finally { GLib.close(input.fd); }
    GLib.chmod(`${tmp}/metadata.json`, 0o644);
    rejects(() => runner.readPinnedFile(dir, 'metadata.json', uid, 0o600, 64), 'wrong mode rejected');
    GLib.chmod(`${tmp}/metadata.json`, 0o600);
    rejects(() => runner.readPinnedFile(dir, 'metadata.json', uid + 1, 0o600, 64), 'wrong owner rejected');
    rejects(() => runner.readPinnedFile(dir, 'metadata.json', uid, 0o600, 2), 'oversized file rejected');
    const link = Gio.File.new_for_path(`${tmp}/link.json`);
    link.make_symbolic_link('metadata.json', null);
    rejects(() => runner.readPinnedFile(dir, 'link.json', uid, 0o600, 64), 'symlink rejected');
    rejects(() => runner.readPinnedFile(dir, '../metadata.json', uid, 0o600, 64), 'path escape rejected');
    check(typeof runner.readRootSource === 'function', 'immutable source guard exists');
    const sourceCopy = Gio.File.new_for_path(`${tmp}/desktop-service-probe.js`);
    sourceCopy.replace_contents('export const marker = 7;\n', null, false, Gio.FileCreateFlags.PRIVATE, null);
    GLib.chmod(sourceCopy.get_path(), 0o555);
    rejects(() => runner.readRootSource(dir, 'desktop-service-probe.js'), 'user-owned source cannot be imported');
    GLib.chmod(sourceCopy.get_path(), 0o600);
    rejects(() => runner.readRootSource(dir, 'desktop-service-probe.js'), 'mutable source cannot be imported');
    rejects(() => runner.openStateDirectory(`${tmp}/link.json`, uid), 'non-directory rejected');
    GLib.chmod(tmp, 0o755);
    rejects(() => runner.openStateDirectory(tmp, uid), 'unsafe directory mode rejected');
    GLib.chmod(tmp, 0o700);
    runner.writeReceipt(dir, 'desktop-service-ready.json', uid, {schema: 1, facts: {ready: true}});
    const receiptFile = runner.readPinnedFile(dir, 'desktop-service-ready.json', uid, 0o600, 1024);
    try { check(JSON.parse(new TextDecoder().decode(receiptFile.bytes)).facts.ready === true, 'native receipt written'); } finally { GLib.close(receiptFile.fd); }
    rejects(() => runner.writeReceipt(dir, 'desktop-service-ready.json', uid, {}), 'receipt overwrite rejected');
    rejects(() => runner.writeReceipt(dir, '../escape.json', uid, {}), 'receipt path escape rejected');
    check(runner.validateMetadata(identity, identity.runId, identity.round, uid).expectedFlags === 8, 'valid metadata accepted');
    for (const change of [{schema: 2}, {uid: uid + 1}, {round: 'unknown'}, {runId: 'PRIVATE_SENTINEL'},
        {probeSha256: 'A'.repeat(64)}, {expectedFlags: 12}, {extra: true}]) {
        rejects(() => runner.validateMetadata({...identity, ...change}, identity.runId, identity.round, uid), 'malformed metadata rejected');
    }
    rejects(() => runner.validateSourceHash(new Uint8Array([1]), identity.probeSha256), 'source hash mismatch rejected');
    const helperFile = Gio.File.new_for_path(`${tmp}/helper.js`);
    helperFile.replace_contents('export const marker = 7;\n', null, false, Gio.FileCreateFlags.PRIVATE, null);
    GLib.chmod(`${tmp}/helper.js`, 0o500);
    const helperInput = runner.readPinnedFile(dir, 'helper.js', uid, 0o500, 4096);
    try {
        helperFile.move(Gio.File.new_for_path(`${tmp}/helper-retained.js`), Gio.FileCopyFlags.NONE, null, null);
        helperFile.replace_contents('export const marker = 99;\n', null, false, Gio.FileCreateFlags.PRIVATE, null);
        const imported = await import(`file:///proc/self/fd/${helperInput.fd}`);
        check(imported.marker === 7, 'helper import uses pinned inode despite pathname replacement');
    } finally { GLib.close(helperInput.fd); }
    const bytes = new TextEncoder().encode('fixture');
    check(runner.validateSourceHash(bytes, GLib.compute_checksum_for_data(GLib.ChecksumType.SHA256, bytes)), 'matching source hash accepted');
    function fixture() {
        const receipts = [];
        let closed = 0, registrationResolve;
        let now = 0;
        const scheduled = [];
        let delayed = false;
        const adapter = {
            now: () => now,
            schedule(ms, callback) { const task = {ms, callback, active: true}; scheduled.push(task); return () => { task.active = false; }; },
            emit: r => receipts.push(r),
            register: async () => delayed ? new Promise(resolve => { registrationResolve = resolve; }) : control(),
            observe: async () => ({status: 'not-found', count: 2, matchingCount: 0}),
        };
        function control() { return {observation: {status: 'registered', registered: true, signal: true},
            close: async () => { closed++; return {status: 'unregistered', absent: true, signal: true}; }}; }
        return {engine: new runner.ServiceCommandRunner(identity, 12345, adapter), receipts,
            closed: () => closed, adapter, control, delayed: () => { delayed = true; },
            resolve: () => registrationResolve(control()), advance: value => { now = value; },
            expire: () => { for (const task of [...scheduled]) if (task.active) task.callback(); }};
    }
    const command = (sequence, stage) => ({schema: 1, runId: identity.runId, round: identity.round, sequence, stage});
    const good = fixture();
    await good.engine.accept(command(1, 'indicator-register'));
    check(good.receipts[0].code === 'indicator-registered' && good.receipts[0].facts.signal, 'positive registration receipt');
    await good.engine.accept(command(1, 'indicator-register'));
    check(good.receipts.length === 1, 'identical completed replay ignored');
    await good.engine.accept(command(2, 'caffeine-observe'));
    check(good.receipts[1].status === 'ready' && good.receipts[1].facts.found === false && good.receipts[1].facts.count === 2, 'Caffeine negative control retained');
    await good.engine.accept(command(3, 'indicator-remove'));
    check(good.closed() === 1 && good.receipts[2].facts.absent, 'remove closes own resource');
    await good.engine.accept(command(4, 'stop'));
    check(good.receipts[3].code === 'observer-stopped' && good.engine.stopped, 'stop state receipt');
    for (const bad of [command(2, 'stop'), {...command(1, 'stop'), schema: 2},
        {...command(1, 'stop'), extra: 'PRIVATE_SENTINEL'}, command(1, 'invalid')]) {
        const f = fixture();
        await f.engine.accept(bad);
        check(f.engine.failed && f.receipts[0].status === 'failure', 'malformed command rejects');
        check(!JSON.stringify(f.receipts).includes('PRIVATE_SENTINEL'), 'failure receipt sanitized');
    }
    const replay = fixture();
    await replay.engine.accept(command(1, 'indicator-register'));
    await replay.engine.accept(command(1, 'stop'));
    check(replay.engine.failed && replay.closed() === 1, 'altered replay rejects and closes item');
    const pending = fixture(); pending.delayed();
    const first = pending.engine.accept(command(1, 'indicator-register'));
    await Promise.resolve();
    await pending.engine.accept(command(2, 'caffeine-observe'));
    check(pending.engine.failed, 'command replacement while pending rejects');
    pending.resolve(); await first;
    check(pending.closed() === 1, 'late registration after failure cleaned');
    const timeout = fixture(); timeout.delayed();
    const work = timeout.engine.accept(command(1, 'indicator-register'));
    await Promise.resolve(); timeout.expire(); await work;
    check(timeout.engine.failed && timeout.receipts[0].code === 'command-timeout', 'command deadline rejects with typed code');
    timeout.resolve(); await Promise.resolve(); await Promise.resolve();
    check(timeout.closed() === 1, 'late registration after timeout cleaned');
    const overall = fixture();
    await overall.engine.accept(command(1, 'indicator-register'));
    overall.advance(300001);
    await overall.engine.accept(command(2, 'caffeine-observe'));
    check(overall.engine.failed && overall.closed() === 1, 'overall deadline closes owned item');
    const broken = fixture();
    broken.adapter.observe = async () => ({status: 'found', count: 'PRIVATE_SENTINEL', matchingCount: 1});
    await broken.engine.accept(command(1, 'caffeine-observe'));
    check(broken.engine.failed && !JSON.stringify(broken.receipts).includes('PRIVATE_SENTINEL'), 'malformed helper facts rejected');
    print(`DESKTOP_SERVICE_RUNNER_CHECKS PASS checks=${checks} runtime=offline-protocol+native-fd-fixtures`);
} finally {
    if (dir !== undefined) GLib.close(dir);
    for (const name of ['link.json', 'metadata.json', 'desktop-service-ready.json', 'helper.js', 'helper-retained.js', 'desktop-service-probe.js']) { try { Gio.File.new_for_path(`${tmp}/${name}`).delete(null); } catch {} }
    Gio.File.new_for_path(tmp).delete(null);
}
