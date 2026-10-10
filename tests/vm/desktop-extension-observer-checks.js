#!/usr/bin/gjs -m
// Fake native objects check the observer's predicates, not a live Shell session.
let observer;
try {
    observer = await import('./guest/desktop-extension-observer.js');
} catch {
    throw new Error('FAIL: desktop extension observer is missing or cannot load');
}

let checks = 0;
function check(name, stage, edit, status = 'not-ready', expected = {}) {
    const runtime = fixture();
    edit(runtime);
    const result = observer.observeDesktopExtension(stage, runtime, expected);
    const wantedStage = ['blur-on', 'blur-off', 'panel-shown', 'panel-hidden',
        'panel-overview-only', 'theme-marble', 'theme-stock'].includes(stage) ? stage : null;
    if (result.status !== status || result.stage !== wantedStage)
        throw new Error(`FAIL: ${name}`);
    // Arbitrary native errors, names and paths must never enter the result.
    if (JSON.stringify(result).includes('PRIVATE_SENTINEL'))
        throw new Error(`FAIL: ${name} leaks native data`);
    if (JSON.stringify(result).length > 1024 || typeof result.code !== 'string' ||
        !Object.values(result.facts).every(value => typeof value === 'boolean' ||
            (Number.isInteger(value) && value >= 0 && value <= 16)))
        throw new Error(`FAIL: ${name} returns unbounded facts`);
    checks++;
}

class Widget {
    constructor(parent, name = 'bms-overview-blurred-widget') {
        this.parent = parent;
        this.name = name;
        this.children = [];
        this.translation_y = 0;
        this.visible = true;
        this.mapped = true;
    }
    get_parent() { return this.parent; }
    get_children() { return this.children; }
}
class BlurEffect {
    constructor(actor) { this.actor = actor; this.radius = 30; this.enabled = true; }
    get_actor() { return this.actor; }
    get_enabled() { return this.enabled; }
}
function fixture() {
    const ui = new Widget(null, 'uiGroup');
    const overview = new Widget(ui, 'overviewGroup');
    const group = new Widget(overview, 'bms-overview-backgroundgroup');
    const widget = new Widget(group);
    const effect = new BlurEffect(widget);
    const manager = {_monitorIndex: 0, _bms_pipeline: {actor: widget, effects: [effect]}};
    group.children = [widget];
    const theme = {application_stylesheet: {get_path: () => '/usr/share/themes/Marble/gnome-shell/gnome-shell.css'}};
    return {
        Main: {
            layoutManager: {uiGroup: ui, overviewGroup: overview, panelBox: new Widget(ui), monitors: [{}]},
            panel: {height: 32},
            overview: {visible: true},
            getThemeStylesheet: () => ({get_path: () => '/usr/share/themes/Marble/gnome-shell/gnome-shell.css'}),
        },
        global: {context: {unsafe_mode: false}, stage: {}, blur_my_shell: {_overview_blur: {
            enabled: true, overview_background_group: group, overview_background_managers: [manager],
        }}},
        St: {Widget, ThemeContext: {get_for_stage: () => ({get_theme: () => theme})}},
        Shell: {BlurEffect},
        testTheme: theme,
    };
}
const noop = () => {};
const blur = {monitorCount: 1};
const marble = {themePath: '/usr/share/themes/Marble/gnome-shell/gnome-shell.css'};
const feature = r => r.global.blur_my_shell._overview_blur;
const pipeline = r => feature(r).overview_background_managers[0]._bms_pipeline;
check('attached native blur is ready', 'blur-on', noop, 'ready', blur);
check('missing extension cannot prove blur', 'blur-on', r => delete r.global.blur_my_shell, 'not-ready', blur);
check('disabled feature cannot prove blur', 'blur-on', r => feature(r).enabled = false, 'not-ready', blur);
check('wrong group parent cannot prove blur', 'blur-on', r => feature(r).overview_background_group.parent = r.Main.layoutManager.uiGroup, 'not-ready', blur);
check('missing widget cannot prove blur', 'blur-on', r => pipeline(r).actor = null, 'not-ready', blur);
check('wrong widget name cannot prove blur', 'blur-on', r => pipeline(r).actor.name = 'PRIVATE_SENTINEL', 'not-ready', blur);
check('detached widget cannot prove blur', 'blur-on', r => pipeline(r).actor.parent = null, 'not-ready', blur);
check('unattached effect cannot prove blur', 'blur-on', r => pipeline(r).effects[0].actor = null, 'not-ready', blur);
check('zero radius cannot prove blur', 'blur-on', r => pipeline(r).effects[0].radius = 0, 'not-ready', blur);
check('hidden overview cannot prove rendered blur', 'blur-on', r => r.Main.overview.visible = false, 'not-ready', blur);
check('unmapped widget cannot prove rendered blur', 'blur-on', r => pipeline(r).actor.mapped = false, 'not-ready', blur);
check('hidden widget cannot prove rendered blur', 'blur-on', r => pipeline(r).actor.visible = false, 'not-ready', blur);
check('disabled native effect cannot prove rendered blur', 'blur-on', r => pipeline(r).effects[0].enabled = false, 'not-ready', blur);
check('missing native type rejected', 'blur-on', r => delete r.Shell, 'failure', blur);
check('non-native effect cannot prove blur', 'blur-on', r => pipeline(r).effects = [{radius: 30, get_actor: () => pipeline(r).actor}], 'not-ready', blur);
check('wrong monitor identity cannot prove blur', 'blur-on', r => feature(r).overview_background_managers[0]._monitorIndex = 1, 'not-ready', blur);
check('missing monitor cannot prove blur', 'blur-on', noop, 'not-ready', {monitorCount: 2});
const twoMonitors = r => {
    r.Main.layoutManager.monitors.push({});
    const group = feature(r).overview_background_group;
    const widget = new Widget(group);
    group.children.push(widget);
    feature(r).overview_background_managers.push({_monitorIndex: 1,
        _bms_pipeline: {actor: widget, effects: [new BlurEffect(widget)]}});
};
check('each monitor has an attached native blur', 'blur-on', twoMonitors, 'ready', {monitorCount: 2});
check('duplicate monitor identity cannot prove all monitors', 'blur-on', r => {
    twoMonitors(r); feature(r).overview_background_managers[1]._monitorIndex = 0;
}, 'not-ready', {monitorCount: 2});
check('duplicate widget cannot prove all monitors', 'blur-on', r => {
    twoMonitors(r);
    feature(r).overview_background_managers[1]._bms_pipeline = pipeline(r);
}, 'not-ready', {monitorCount: 2});
check('one unblurred monitor cannot prove all monitors', 'blur-on', r => {
    twoMonitors(r); feature(r).overview_background_managers[1]._bms_pipeline.effects = [];
}, 'not-ready', {monitorCount: 2});
check('non-finite radius cannot prove blur', 'blur-on', r => pipeline(r).effects[0].radius = Infinity, 'not-ready', blur);
check('non-native widget cannot prove blur', 'blur-on', r => {
    pipeline(r).actor = {name: 'bms-overview-blurred-widget', visible: true,
        mapped: true, get_parent: () => feature(r).overview_background_group};
}, 'not-ready', blur);
const off = r => {
    feature(r).enabled = false;
    feature(r).overview_background_group.parent = null;
    feature(r).overview_background_group.children = [];
    feature(r).overview_background_managers = [];
};
check('removed overview blur is ready', 'blur-off', off, 'ready', blur);
check('setting-only disabled is insufficient', 'blur-off', r => feature(r).enabled = false, 'not-ready', blur);
check('missing extension is not a disabled feature receipt', 'blur-off', r => delete r.global.blur_my_shell, 'not-ready', blur);
check('retained children prevent disabled feature receipt', 'blur-off', r => {
    off(r); feature(r).overview_background_group.children = [new Widget(null)];
}, 'not-ready', blur);
check('shown chrome panel is ready', 'panel-shown', noop, 'ready');
check('shown panel needs chrome parent', 'panel-shown', r => r.Main.layoutManager.panelBox.parent = r.Main.layoutManager.overviewGroup);
check('shown panel needs zero offset', 'panel-shown', r => r.Main.layoutManager.panelBox.translation_y = -32);
check('invisible panel is not shown', 'panel-shown', r => r.Main.layoutManager.panelBox.visible = false);
check('unmapped panel is not shown', 'panel-shown', r => r.Main.layoutManager.panelBox.mapped = false);
const hidden = r => { r.Main.layoutManager.panelBox.parent = r.Main.layoutManager.overviewGroup; r.Main.layoutManager.panelBox.translation_y = -32; };
check('fully hidden top panel is ready', 'panel-hidden', hidden, 'ready');
check('fully hidden panel needs correct offset', 'panel-hidden', r => { hidden(r); r.Main.layoutManager.panelBox.translation_y = 0; });
check('fully hidden panel needs correct parent', 'panel-hidden', r => r.Main.layoutManager.panelBox.translation_y = -32);
check('overview-only panel is ready', 'panel-overview-only', r => r.Main.layoutManager.panelBox.parent = r.Main.layoutManager.overviewGroup, 'ready');
check('overview-only panel must not be translated away', 'panel-overview-only', hidden);
check('closed overview cannot show overview-only panel', 'panel-overview-only', r => {
    r.Main.layoutManager.panelBox.parent = r.Main.layoutManager.overviewGroup;
    r.Main.overview.visible = false;
});
check('invisible overview panel is not shown', 'panel-overview-only', r => {
    r.Main.layoutManager.panelBox.parent = r.Main.layoutManager.overviewGroup;
    r.Main.layoutManager.panelBox.visible = false;
});
check('unmapped overview panel is not shown', 'panel-overview-only', r => {
    r.Main.layoutManager.panelBox.parent = r.Main.layoutManager.overviewGroup;
    r.Main.layoutManager.panelBox.mapped = false;
});
check('loaded Marble theme is ready', 'theme-marble', noop, 'ready', marble);
check('selected-only theme is insufficient', 'theme-marble', r => r.testTheme.application_stylesheet = null, 'not-ready', marble);
check('wrong live theme is insufficient', 'theme-marble', r => r.testTheme.application_stylesheet = {get_path: () => '/PRIVATE_SENTINEL'}, 'not-ready', marble);
check('loaded-only theme is insufficient', 'theme-marble', r => r.Main.getThemeStylesheet = () => null, 'not-ready', marble);
check('Stock theme requires both null', 'theme-stock', r => { r.Main.getThemeStylesheet = () => null; r.testTheme.application_stylesheet = null; }, 'ready', {themePath: null});
check('Stock selection with old live theme is insufficient', 'theme-stock', r => r.Main.getThemeStylesheet = () => null, 'not-ready', {themePath: null});
check('non-null resource selection is not Stock default', 'theme-stock', r => {
    r.Main.getThemeStylesheet = () => ({get_path: () => null});
    r.testTheme.application_stylesheet = null;
}, 'not-ready', {themePath: null});
check('non-null resource live theme is not Stock default', 'theme-stock', r => {
    r.Main.getThemeStylesheet = () => null;
    r.testTheme.application_stylesheet = {get_path: () => null};
}, 'not-ready', {themePath: null});
check('missing live theme is not Stock', 'theme-stock', r => r.St.ThemeContext.get_for_stage = () => ({get_theme: () => null}), 'failure', {themePath: null});
check('unsafe mode rejected', 'panel-shown', r => r.global.context.unsafe_mode = true, 'failure');
check('missing unsafe mode flag rejected', 'panel-shown', r => delete r.global.context.unsafe_mode, 'failure');
check('malformed expected monitor count rejected', 'blur-on', noop, 'failure', {monitorCount: 0});
check('unbounded expected monitor count rejected', 'blur-on', noop, 'failure', {monitorCount: 17});
check('malformed theme path rejected', 'theme-marble', noop, 'failure', {themePath: 'relative.css'});
check('missing runtime rejected', 'panel-shown', r => delete r.Main.layoutManager, 'failure');
check('unknown stage rejected', 'unknown', noop, 'failure');
check('unknown stage contents never reflected', 'PRIVATE_SENTINEL', noop, 'failure');
check('native exception sanitized', 'theme-marble', r => r.Main.getThemeStylesheet = () => { throw new Error('PRIVATE_SENTINEL'); }, 'failure', marble);
check('GI class static ThemeContext API is accepted', 'theme-marble', r => {
    r.St.ThemeContext = class {
        static get_for_stage() { return {get_theme: () => r.testTheme}; }
    };
}, 'ready', marble);
check('observation does not write native state', 'blur-on', r => {
    const seen = new Set();
    const freeze = value => {
        if (!value || typeof value !== 'object' || seen.has(value)) return;
        seen.add(value);
        for (const child of Object.values(value)) freeze(child);
        Object.freeze(value);
    };
    // Extension callbacks are deliberately unusable; only native getters may
    // be consulted. Frozen objects turn attempted assignments into exceptions.
    feature(r).enable = () => { throw new Error('PRIVATE_SENTINEL'); };
    feature(r).disable = () => { throw new Error('PRIVATE_SENTINEL'); };
    freeze(r);
}, 'ready', Object.freeze(blur));
if (typeof observer.startDesktopShellObserver !== 'function')
    throw new Error('FAIL: finite desktop Shell controller is missing');

const identity = {runId: 'marble-20261010T111246Z-e638a253', round: 'firstlogin', uid: 1000, pid: 4321};
const hashes = {observerSha256: 'a'.repeat(64), probeSha256: 'b'.repeat(64)};
function controllerFixture() {
    const receipts = [];
    let time = 0;
    let callback;
    let removed = 0;
    const state = {metadata: {schema: 1, ...identity, shellPid: identity.pid,
        observerSha256: hashes.observerSha256, probeSha256: hashes.probeSha256,
        monitorCount: 1, themePath: marble.themePath}, command: null, commandSha256: 'e'.repeat(64)};
    delete state.metadata.pid;
    const adapter = {identity, hashes, runtime: fixture(), readMetadata: () => state.metadata,
        readCommand: () => state.command === null ? null : {value: state.command, sha256: state.commandSha256},
        writeReceipt: (name, receipt) => receipts.push({name, receipt}), now: () => time,
        addTimer: (interval, tick) => { if (interval !== 100) throw new Error('Wrong timer interval'); callback = tick; return 7; },
        removeTimer: id => { if (id !== 7) throw new Error('Wrong timer identity'); removed++; }};
    return {adapter, state, receipts, setTime: value => time = value,
        tick: () => callback(), removed: () => removed,
        command: (sequence, stage) => state.command = {schema: 1, runId: identity.runId, round: identity.round, sequence, stage}};
}
function controllerCheck(name, run) {
    try { run(controllerFixture()); } catch { throw new Error(`FAIL: ${name}`); }
    checks++;
}
function require(value) { if (!value) throw new Error('Assertion failed'); }
const last = f => f.receipts.at(-1).receipt;
controllerCheck('verified controller publishes ready identity', f => {
    const control = observer.startDesktopShellObserver(f.adapter);
    require(control.active && f.receipts.length === 1 && f.receipts[0].name === 'desktop-shell-ready.json');
    require(last(f).status === 'ready' && last(f).sequence === 0 && last(f).stage === 'ready' &&
        last(f).code === 'observer-started' && last(f).facts.unsafeMode === false && last(f).uid === 1000 && last(f).pid === 4321);
});
for (const [field, bad] of [['uid', 1001], ['shellPid', 4322], ['observerSha256', 'c'.repeat(64)],
    ['probeSha256', 'd'.repeat(64)], ['schema', 2], ['round', 'upgrade'], ['monitorCount', 17],
    ['themePath', '/tmp/../PRIVATE_SENTINEL.css']]) {
    controllerCheck(`metadata ${field} mismatch rejected before timer`, f => {
        f.state.metadata[field] = bad;
        const control = observer.startDesktopShellObserver(f.adapter);
        require(!control.active && last(f).status === 'failure' && last(f).code === 'invalid-metadata');
        require(!JSON.stringify(f.receipts).includes('PRIVATE_SENTINEL'));
    });
}
controllerCheck('unknown metadata keys rejected', f => {
    f.state.metadata.execute = 'PRIVATE_SENTINEL';
    require(!observer.startDesktopShellObserver(f.adapter).active && last(f).status === 'failure');
});
controllerCheck('unsafe startup rejected', f => {
    f.adapter.runtime.global.context.unsafe_mode = true;
    require(!observer.startDesktopShellObserver(f.adapter).active && last(f).code === 'unsafe-mode');
});
controllerCheck('incomplete native runtime cannot publish ready', f => {
    delete f.adapter.runtime.Main.layoutManager;
    const control = observer.startDesktopShellObserver(f.adapter);
    require(!control.active && last(f).status === 'failure' && last(f).code === 'invalid-runtime');
});
controllerCheck('native monitor mismatch cannot publish ready', f => {
    f.adapter.runtime.Main.layoutManager.monitors.push({});
    require(!observer.startDesktopShellObserver(f.adapter).active && last(f).code === 'invalid-runtime');
});
controllerCheck('unsafe transition stops owned timer', f => {
    const control = observer.startDesktopShellObserver(f.adapter);
    f.adapter.runtime.global.context.unsafe_mode = true; f.tick();
    require(!control.active && f.removed() === 1 && last(f).code === 'unsafe-mode');
});
controllerCheck('ready command produces exact sequence receipt once', f => {
    observer.startDesktopShellObserver(f.adapter); f.command(1, 'panel-shown'); f.tick(); f.tick();
    require(f.receipts.length === 2 && f.receipts[1].name === 'desktop-shell-1-panel-shown.json' &&
        last(f).status === 'ready' && last(f).sequence === 1);
});
controllerCheck('delayed native state is polled until ready', f => {
    const control = observer.startDesktopShellObserver(f.adapter);
    f.adapter.runtime.Main.layoutManager.panelBox.translation_y = -32;
    f.command(1, 'panel-shown'); f.tick(); require(f.receipts.length === 1);
    f.setTime(1000); f.adapter.runtime.Main.layoutManager.panelBox.translation_y = 0; f.tick();
    require(control.active && f.receipts.length === 2 && last(f).status === 'ready');
});
controllerCheck('Stock observation derives null without losing bound Marble path', f => {
    const control = observer.startDesktopShellObserver(f.adapter);
    f.adapter.runtime.Main.getThemeStylesheet = () => null;
    f.adapter.runtime.testTheme.application_stylesheet = null;
    f.command(1, 'theme-stock'); f.tick();
    require(control.active && last(f).status === 'ready' && last(f).code === 'theme-applied');
    f.adapter.runtime.Main.getThemeStylesheet = () => ({get_path: () => marble.themePath});
    f.adapter.runtime.testTheme.application_stylesheet = {get_path: () => marble.themePath};
    f.command(2, 'theme-marble'); f.tick();
    require(control.active && last(f).sequence === 2 && last(f).status === 'ready');
});
controllerCheck('command deadline rejects late native state and cleans timer', f => {
    const control = observer.startDesktopShellObserver(f.adapter);
    f.adapter.runtime.Main.layoutManager.panelBox.translation_y = -32;
    f.command(1, 'panel-shown'); f.tick(); f.setTime(30000);
    f.adapter.runtime.Main.layoutManager.panelBox.translation_y = 0; f.tick();
    require(!control.active && f.removed() === 1 && last(f).code === 'command-timeout' && last(f).status === 'failure');
});
controllerCheck('idle controller has an overall deadline', f => {
    const control = observer.startDesktopShellObserver(f.adapter); f.setTime(300000); f.tick();
    require(!control.active && f.removed() === 1 && last(f).code === 'observer-timeout');
});
controllerCheck('sequence gap is rejected', f => {
    const control = observer.startDesktopShellObserver(f.adapter); f.command(2, 'panel-shown'); f.tick();
    require(!control.active && last(f).code === 'command-sequence-invalid' && f.removed() === 1);
});
controllerCheck('completed sequence cannot change stage', f => {
    const control = observer.startDesktopShellObserver(f.adapter); f.command(1, 'panel-shown'); f.tick();
    f.command(1, 'panel-hidden'); f.tick();
    require(!control.active && last(f).code === 'command-sequence-invalid');
});
controllerCheck('completed sequence cannot change command bytes', f => {
    const control = observer.startDesktopShellObserver(f.adapter); f.command(1, 'panel-shown'); f.tick();
    f.state.commandSha256 = 'f'.repeat(64); f.tick();
    require(!control.active && last(f).code === 'command-sequence-invalid');
});
controllerCheck('new command cannot replace a pending observation', f => {
    const control = observer.startDesktopShellObserver(f.adapter);
    f.adapter.runtime.Main.layoutManager.panelBox.translation_y = -32;
    f.command(1, 'panel-shown'); f.tick(); f.command(2, 'panel-hidden'); f.tick();
    require(!control.active && last(f).code === 'command-sequence-invalid');
});
for (const edit of [f => f.command(1, 'PRIVATE_SENTINEL'), f => { f.command(1, 'panel-shown'); f.state.command.runId = 'PRIVATE_SENTINEL'; },
    f => { f.command(1, 'panel-shown'); f.state.command.extra = true; }, f => f.command(65, 'stop')]) {
    controllerCheck('malformed command never makes an arbitrary receipt path', f => {
        const control = observer.startDesktopShellObserver(f.adapter); edit(f); f.tick();
        require(!control.active && last(f).code === 'invalid-command' && !JSON.stringify(f.receipts).includes('PRIVATE_SENTINEL'));
    });
}
controllerCheck('stop acknowledges ordered command and cancels owned timer', f => {
    const control = observer.startDesktopShellObserver(f.adapter); f.command(1, 'stop'); require(f.tick() === false);
    require(!control.active && f.removed() === 1 && f.receipts[1].name === 'desktop-shell-1-stop.json' &&
        last(f).status === 'ready' && last(f).code === 'observer-stopped');
});
controllerCheck('backward clock terminates observer', f => {
    const control = observer.startDesktopShellObserver(f.adapter); f.setTime(100); f.tick(); f.setTime(99); f.tick();
    require(!control.active && last(f).code === 'invalid-clock' && f.removed() === 1);
});
controllerCheck('native I/O errors never leak and cancel timer', f => {
    const control = observer.startDesktopShellObserver(f.adapter);
    f.adapter.readCommand = () => { throw new Error('PRIVATE_SENTINEL'); }; f.tick();
    require(!control.active && last(f).code === 'observer-io-failure' && f.removed() === 1 &&
        !JSON.stringify(f.receipts).includes('PRIVATE_SENTINEL'));
});
controllerCheck('ready receipt write failure cleans created timer', f => {
    f.adapter.writeReceipt = () => { throw new Error('PRIVATE_SENTINEL'); };
    const control = observer.startDesktopShellObserver(f.adapter);
    require(!control.active && control.errorCode === 'observer-io-failure' && f.removed() === 1);
});
print(`DESKTOP_EXTENSION_OBSERVER_CHECKS PASS checks=${checks} runtime=fake-native`);
