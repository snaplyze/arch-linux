// Read-only predicates for the accepted GNOME 51, Blur My Shell 74 and
// Just Perfection 37 source layouts. This module neither drives UI nor writes
// settings. Its caller must perform the real UI actions and bound any polling.
const STAGES = new Set([
    'blur-on', 'blur-off', 'panel-shown', 'panel-hidden',
    'panel-overview-only', 'theme-marble', 'theme-stock',
]);
const object = value => value !== null && typeof value === 'object';
const method = (value, name) => (object(value) || typeof value === 'function') && typeof value[name] === 'function';
const finite = value => typeof value === 'number' && Number.isFinite(value);
const boundedArray = (value, limit) => Array.isArray(value) && value.length <= limit;

/**
 * Observe a single applied desktop effect. Runtime contains Main, global, St
 * and (for blur-on) Shell. Expected supplies monitorCount (1..16) for blur,
 * or themePath (absolute local CSS path for Marble, null for Stock).
 *
 * ready means the native predicates matched at this instant; not-ready means
 * an applied state has not matched yet. failure denotes invalid input/runtime
 * or a sanitized native observation error. Facts contain no paths or messages.
 * Panel stages assume the caller selected the top panel position.
 */
export function observeDesktopExtension(stage, runtime, expected) {
    const selectedStage = STAGES.has(stage) ? stage : null;
    const result = (status, code, facts = {}) => ({status, stage: selectedStage, code, facts});
    if (selectedStage === null)
        return result('failure', 'invalid-stage');

    try {
        if (!object(expected))
            return result('failure', 'invalid-expected');
        if (!object(runtime) || !object(runtime.Main) || !object(runtime.Main.layoutManager) ||
            !object(runtime.global) || !object(runtime.global.context))
            return result('failure', 'invalid-runtime');
        if (runtime.global.context.unsafe_mode !== false)
            return result('failure', 'unsafe-mode');
        const {Main, global, St, Shell} = runtime;
        const layout = Main.layoutManager;

        if (stage.startsWith('blur-')) {
            if (!Number.isInteger(expected.monitorCount) || expected.monitorCount < 1 || expected.monitorCount > 16)
                return result('failure', 'invalid-expected');
            if (!boundedArray(layout.monitors, 16) || !object(layout.overviewGroup))
                return result('failure', 'invalid-runtime');
            if (stage === 'blur-on' && (!object(St) || typeof St.Widget !== 'function' ||
                !object(Shell) || typeof Shell.BlurEffect !== 'function' || !object(Main.overview)))
                return result('failure', 'invalid-runtime');
            const feature = global.blur_my_shell?._overview_blur;
            if (!object(feature))
                return result('not-ready', 'blur-feature-absent');
            const group = feature.overview_background_group;
            const managers = feature.overview_background_managers;
            if (!method(group, 'get_parent') || !method(group, 'get_children') || !boundedArray(managers, 16))
                return result('failure', 'invalid-blur-runtime');
            const children = group.get_children();
            if (!boundedArray(children, 16))
                return result('failure', 'invalid-blur-runtime');
            const monitorCountMatches = layout.monitors.length === expected.monitorCount;
            if (stage === 'blur-off') {
                // Blur74 disable removes children, detaches the retained group
                // and destroys/empties its per-monitor background managers.
                const detached = group.get_parent() === null;
                const facts = {monitorCountMatches, disabled: feature.enabled === false,
                    detached, widgetCount: children.length, managerCount: managers.length};
                const ready = monitorCountMatches && facts.disabled && detached &&
                    children.length === 0 && managers.length === 0;
                return result(ready ? 'ready' : 'not-ready', ready ? 'blur-removed' : 'blur-state-mismatch', facts);
            }
            const attached = group.get_parent() === layout.overviewGroup;
            const overviewVisible = Main.overview.visible === true;
            let activeWidgets = 0;
            const monitorIndices = new Set();
            const widgetIdentities = new Set();
            for (const manager of managers) {
                if (!object(manager) || !Number.isInteger(manager._monitorIndex) ||
                    manager._monitorIndex < 0 || manager._monitorIndex >= expected.monitorCount ||
                    monitorIndices.has(manager._monitorIndex))
                    continue;
                monitorIndices.add(manager._monitorIndex);
                const pipeline = manager._bms_pipeline;
                if (!object(pipeline) || !boundedArray(pipeline.effects, 32))
                    continue;
                const widget = pipeline.actor;
                if (!(widget instanceof St.Widget) || widget.name !== 'bms-overview-blurred-widget' ||
                    widgetIdentities.has(widget) ||
                    widget.get_parent() !== group || !children.includes(widget) ||
                    widget.visible !== true || widget.mapped !== true)
                    continue;
                widgetIdentities.add(widget);
                const nativeBlur = pipeline.effects.some(effect => effect instanceof Shell.BlurEffect &&
                    effect.get_actor() === widget && effect.get_enabled() === true &&
                    finite(effect.radius) && effect.radius > 0);
                if (nativeBlur)
                    activeWidgets++;
            }
            const facts = {monitorCountMatches, enabled: feature.enabled === true,
                attached, overviewVisible, widgetCount: children.length,
                managerCount: managers.length, activeWidgets};
            const ready = monitorCountMatches && facts.enabled && attached && overviewVisible &&
                children.length === expected.monitorCount && managers.length === expected.monitorCount &&
                activeWidgets === expected.monitorCount;
            return result(ready ? 'ready' : 'not-ready', ready ? 'blur-applied' : 'blur-state-mismatch', facts);
        }

        if (stage.startsWith('panel-')) {
            const panel = layout.panelBox;
            const height = Main.panel?.height;
            if (!method(panel, 'get_parent') || !object(layout.uiGroup) || !object(layout.overviewGroup) ||
                !finite(height) || height <= 0 || height > 4096 || !finite(panel.translation_y))
                return result('failure', 'invalid-panel-runtime');
            const chromeParent = panel.get_parent() === layout.uiGroup;
            const overviewParent = panel.get_parent() === layout.overviewGroup;
            const zeroOffset = panel.translation_y === 0;
            const hiddenTopOffset = panel.translation_y === -height;
            const visible = panel.visible === true;
            const mapped = panel.mapped === true;
            const overviewVisible = Main.overview.visible === true;
            const facts = {chromeParent, overviewParent, zeroOffset, hiddenTopOffset,
                visible, mapped, overviewVisible};
            const ready = stage === 'panel-shown' ? chromeParent && zeroOffset && visible && mapped :
                overviewParent && (stage === 'panel-hidden' ? hiddenTopOffset :
                    zeroOffset && visible && mapped && overviewVisible);
            return result(ready ? 'ready' : 'not-ready', ready ? 'panel-applied' : 'panel-state-mismatch', facts);
        }

        const path = expected.themePath;
        const validPath = typeof path === 'string' && path.length <= 4096 && path.startsWith('/') &&
            path.endsWith('.css') && !/[\x00-\x1f\x7f]/.test(path) &&
            !path.split('/').slice(1).some(part => part === '' || part === '.' || part === '..');
        if (stage === 'theme-marble' ? !validPath : path !== null)
            return result('failure', 'invalid-expected');
        if (!method(Main, 'getThemeStylesheet') || !object(St) ||
            !method(St.ThemeContext, 'get_for_stage') || !object(global.stage))
            return result('failure', 'invalid-theme-runtime');
        const context = St.ThemeContext.get_for_stage(global.stage);
        if (!method(context, 'get_theme'))
            return result('failure', 'invalid-theme-runtime');
        const theme = context.get_theme();
        if (!object(theme))
            return result('failure', 'invalid-theme-runtime');
        const selected = Main.getThemeStylesheet();
        const loaded = theme.application_stylesheet;
        if ((selected !== null && !method(selected, 'get_path')) ||
            (loaded !== null && !method(loaded, 'get_path')))
            return result('failure', 'invalid-theme-runtime');
        const selectedMatches = stage === 'theme-stock' ? selected === null :
            selected !== null && selected.get_path() === path;
        const loadedMatches = stage === 'theme-stock' ? loaded === null :
            loaded !== null && loaded.get_path() === path;
        const ready = selectedMatches && loadedMatches;
        return result(ready ? 'ready' : 'not-ready', ready ? 'theme-applied' : 'theme-state-mismatch',
            {selectedMatches, loadedMatches});
    } catch {
        return result('failure', 'observation-error');
    }
}

const RUN_ID = /^(?:marble|luksgrub)-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$/;
const ROUNDS = new Set(['firstlogin', 'upgrade', 'postreboot']);
const HASH = /^[a-f0-9]{64}$/;
const exactKeys = (value, keys) => object(value) && !Array.isArray(value) &&
    Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
const cssPath = value => typeof value === 'string' && value.length <= 4096 &&
    value.startsWith('/') && value.endsWith('.css') && !/[\x00-\x1f\x7f]/.test(value) &&
    !value.split('/').slice(1).some(part => part === '' || part === '.' || part === '..');

/**
 * Start one finite observer with injected native I/O, monotonic milliseconds
 * and an owned 100ms timer. readCommand returns null when no command exists,
 * otherwise {value: parsedCommand, sha256: exactCommandFileBytesSha256}.
 * The caller's identity/hashes are independently derived from its own native
 * process and files; metadata never supplies executable input or runtime.
 * Re-reading an unchanged command file is harmless. Changing a completed or
 * pending sequence, skipping a sequence, or issuing work early is fatal.
 */
export function startDesktopShellObserver(adapter) {
    let active = false;
    let errorCode = null;
    let timer = null;
    const control = {get active() { return active; }, get errorCode() { return errorCode; }};
    if (!object(adapter)) { errorCode = 'invalid-adapter'; return control; }
    const {identity, hashes, runtime} = adapter;
    if (!object(identity) || typeof identity.runId !== 'string' || !RUN_ID.test(identity.runId) ||
        !ROUNDS.has(identity.round) || !Number.isInteger(identity.uid) || identity.uid < 1 || identity.uid > 4294967294 ||
        !Number.isInteger(identity.pid) || identity.pid < 2 || identity.pid > 2147483647 ||
        !object(hashes) || typeof hashes.observerSha256 !== 'string' || !HASH.test(hashes.observerSha256) ||
        typeof hashes.probeSha256 !== 'string' || !HASH.test(hashes.probeSha256) ||
        !['readMetadata', 'readCommand', 'writeReceipt', 'now', 'addTimer', 'removeTimer'].every(key => method(adapter, key))) {
        errorCode = 'invalid-adapter';
        return control;
    }
    const emit = (sequence, stage, status, code, facts = {}) => {
        const filename = sequence === 0 ? 'desktop-shell-ready.json' : `desktop-shell-${sequence}-${stage}.json`;
        adapter.writeReceipt(filename, {schema: 1, runId: identity.runId, round: identity.round,
            sequence, stage, pid: identity.pid, uid: identity.uid,
            probeSha256: hashes.probeSha256, observerSha256: hashes.observerSha256, status, code, facts});
    };
    const finish = () => {
        active = false;
        if (timer !== null) {
            const owned = timer;
            timer = null;
            try { adapter.removeTimer(owned); } catch { errorCode = 'observer-io-failure'; }
        }
    };
    const fatal = (code, command = null, facts = {}) => {
        errorCode = code;
        try { emit(command?.sequence ?? 0, command?.stage ?? 'ready', 'failure', code, facts); }
        catch { errorCode = 'observer-io-failure'; }
        finally { finish(); }
        return false;
    };
    let metadata;
    let started;
    try {
        metadata = adapter.readMetadata();
        if (!exactKeys(metadata, ['schema', 'runId', 'round', 'uid', 'shellPid',
            'observerSha256', 'probeSha256', 'monitorCount', 'themePath']) ||
            metadata.schema !== 1 || metadata.runId !== identity.runId || metadata.round !== identity.round ||
            metadata.uid !== identity.uid || metadata.shellPid !== identity.pid ||
            metadata.observerSha256 !== hashes.observerSha256 || metadata.probeSha256 !== hashes.probeSha256 ||
            !Number.isInteger(metadata.monitorCount) || metadata.monitorCount < 1 || metadata.monitorCount > 16 ||
            (metadata.themePath !== null && !cssPath(metadata.themePath)))
            return fatal('invalid-metadata'), control;
        if (!object(runtime) || !object(runtime.global) || !object(runtime.global.context) ||
            runtime.global.context.unsafe_mode !== false)
            return fatal('unsafe-mode'), control;
        if (!object(runtime.Main) || !object(runtime.Main.layoutManager) || !object(runtime.Main.overview) ||
            !method(runtime.Main, 'getThemeStylesheet') || !object(runtime.global.stage) ||
            !object(runtime.St) || typeof runtime.St.Widget !== 'function' ||
            !method(runtime.St.ThemeContext, 'get_for_stage') || !object(runtime.Shell) ||
            typeof runtime.Shell.BlurEffect !== 'function' ||
            !boundedArray(runtime.Main.layoutManager.monitors, 16) ||
            runtime.Main.layoutManager.monitors.length !== metadata.monitorCount ||
            !method(runtime.Main.layoutManager.panelBox, 'get_parent') ||
            !object(runtime.Main.layoutManager.uiGroup) || !object(runtime.Main.layoutManager.overviewGroup))
            return fatal('invalid-runtime'), control;
        started = adapter.now();
        if (!finite(started) || started < 0 || started > Number.MAX_SAFE_INTEGER)
            return fatal('invalid-clock'), control;
    } catch {
        fatal('observer-io-failure');
        return control;
    }
    let lastTime = started;
    let lastSequence = 0;
    let lastStage = null;
    let lastDigest = null;
    let pending = null;
    const expected = {monitorCount: metadata.monitorCount, themePath: metadata.themePath};
    const tick = () => {
        if (!active) return false;
        try {
            if (runtime.global.context.unsafe_mode !== false)
                return fatal('unsafe-mode', pending);
            const time = adapter.now();
            if (!finite(time) || time < lastTime || time > Number.MAX_SAFE_INTEGER)
                return fatal('invalid-clock', pending);
            lastTime = time;
            if (time - started >= 300000)
                return fatal('observer-timeout', pending);
            const input = adapter.readCommand();
            if (input !== null) {
                if (!exactKeys(input, ['value', 'sha256']) || typeof input.sha256 !== 'string' || !HASH.test(input.sha256))
                    return fatal('invalid-command');
                const command = input.value;
                if (!exactKeys(command, ['schema', 'runId', 'round', 'sequence', 'stage']) ||
                    command.schema !== 1 || command.runId !== identity.runId || command.round !== identity.round ||
                    !Number.isInteger(command.sequence) || command.sequence < 1 || command.sequence > 64 ||
                    (!STAGES.has(command.stage) && command.stage !== 'stop'))
                    return fatal('invalid-command');
                if (command.sequence === lastSequence && command.stage === lastStage && input.sha256 === lastDigest) {
                    // The driver leaves its atomic command file in place while
                    // waiting for a receipt; repeated reads are not new work.
                } else if (pending !== null || command.sequence !== lastSequence + 1) {
                    return fatal('command-sequence-invalid');
                } else {
                    lastSequence = command.sequence;
                    lastStage = command.stage;
                    lastDigest = input.sha256;
                    pending = {sequence: command.sequence, stage: command.stage, started: time};
                }
            }
            if (pending === null) return true;
            if (pending.stage === 'stop') {
                emit(pending.sequence, 'stop', 'ready', 'observer-stopped');
                finish();
                return false;
            }
            if (time - pending.started >= 30000)
                return fatal('command-timeout', pending);
            const observation = observeDesktopExtension(pending.stage, runtime,
                pending.stage === 'theme-stock' ? {...expected, themePath: null} : expected);
            if (observation.status === 'failure')
                return fatal(observation.code, pending, observation.facts);
            if (observation.status === 'ready') {
                emit(pending.sequence, pending.stage, 'ready', observation.code, observation.facts);
                pending = null;
            }
            return true;
        } catch {
            return fatal('observer-io-failure', pending);
        }
    };
    try {
        active = true;
        timer = adapter.addTimer(100, tick);
        if (!Number.isInteger(timer) || timer < 1) {
            timer = null;
            fatal('observer-io-failure');
            return control;
        }
        emit(0, 'ready', 'ready', 'observer-started', {unsafeMode: false});
    } catch {
        fatal('observer-io-failure');
    }
    return control;
}
