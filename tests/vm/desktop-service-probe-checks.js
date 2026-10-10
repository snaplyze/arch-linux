#!/usr/bin/gjs -m
// Native transport fixtures on a private bus; never run against a desktop bus.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
if (!GLib.getenv('DESKTOP_SERVICE_PROBE_PRIVATE_BUS'))
    throw new Error('Use DESKTOP_SERVICE_PROBE_PRIVATE_BUS=1 dbus-run-session -- gjs -m tests/vm/desktop-service-probe-checks.js');
const probe = await import('./guest/desktop-service-probe.js');
const connection = Gio.bus_get_sync(Gio.BusType.SESSION, null);
let checks = 0;
function check(value, name) {
    if (!value) throw new Error(`FAIL: ${name}`);
    checks++;
}
function own(name) {
    const result = connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
        'org.freedesktop.DBus', 'RequestName', new GLib.Variant('(su)', [name, 4]),
        new GLib.VariantType('(u)'), Gio.DBusCallFlags.NONE, 1000, null);
    check(result.deep_unpack()[0] === 1, 'fixture exclusively owns private service');
}
own('org.gnome.SessionManager');
own('org.kde.StatusNotifierWatcher');
let inhibitors = ['/org/gnome/SessionManager/Inhibitor1'];
let appId = 'caffeine-gnome-extension';
let reason = 'Inhibited by Caffeine GNOME extension';
let flags = 8;
let hang = false;
const manager = Gio.DBusExportedObject.wrapJSObject(`<node><interface name="org.gnome.SessionManager"><method name="GetInhibitors"><arg type="ao" direction="out"/></method></interface></node>`, {
    GetInhibitorsAsync(_params, invocation) {
        if (!hang) invocation.return_value(new GLib.Variant('(ao)', [inhibitors]));
    },
});
manager.export(connection, '/org/gnome/SessionManager');
const inhibitor = Gio.DBusExportedObject.wrapJSObject(`<node><interface name="org.gnome.SessionManager.Inhibitor"><method name="GetAppId"><arg type="s" direction="out"/></method><method name="GetReason"><arg type="s" direction="out"/></method><method name="GetFlags"><arg type="u" direction="out"/></method></interface></node>`, {
    GetAppId() { return appId; }, GetReason() { return reason; }, GetFlags() { return flags; },
});
inhibitor.export(connection, '/org/gnome/SessionManager/Inhibitor1');
let items = [':99.1/ForeignItem'];
let mode = 'normal';
let lastSender = null;
const watcher = Gio.DBusExportedObject.wrapJSObject(`<node><interface name="org.kde.StatusNotifierWatcher"><method name="RegisterStatusNotifierItem"><arg type="s" direction="in"/></method><property name="RegisteredStatusNotifierItems" type="as" access="read"/><signal name="StatusNotifierItemRegistered"><arg type="s"/></signal><signal name="StatusNotifierItemUnregistered"><arg type="s"/></signal></interface></node>`, {
    get RegisteredStatusNotifierItems() { return items; },
    RegisterStatusNotifierItemAsync([entry], invocation) {
        lastSender = invocation.get_sender();
        if (mode === 'reject') {
            invocation.return_dbus_error('org.kde.Rejected', 'PRIVATE_SENTINEL');
            return;
        }
        if (mode === 'hang') return;
        // Verify the actual exported object rather than only accepting a string.
        connection.call(lastSender, '/StatusNotifierItem', 'org.freedesktop.DBus.Properties',
            'GetAll', new GLib.Variant('(s)', ['org.kde.StatusNotifierItem']),
            new GLib.VariantType('(a{sv})'), Gio.DBusCallFlags.NONE, 1000, null,
            (c, res) => {
                try {
                    const properties = c.call_finish(res).deep_unpack()[0];
                    check(properties.Id.deep_unpack() === 'arch-linux-acceptance', 'owned item serves configured ID');
                    check(properties.Menu.deep_unpack() === '/NO_DBUSMENU', 'item avoids foreign DBusMenu');
                    check(properties.Status.deep_unpack() === 'Active', 'item active');
                    check(entry === `${lastSender}/StatusNotifierItem`, 'registration binds sender and path');
                    const observed = mode === 'wrong-entry' ? ':99.2/StatusNotifierItem' : entry;
                    items.push(observed);
                    if (mode !== 'missing-signal') watcher.emit_signal('StatusNotifierItemRegistered', new GLib.Variant('(s)', [observed]));
                    invocation.return_value(null);
                } catch {
                    invocation.return_dbus_error('org.kde.Invalid', 'fixture failed');
                }
            });
    },
});
watcher.export(connection, '/StatusNotifierWatcher');
let watcherExported = true;
const subscription = connection.signal_subscribe('org.freedesktop.DBus', 'org.freedesktop.DBus',
    'NameOwnerChanged', '/org/freedesktop/DBus', null, Gio.DBusSignalFlags.NONE,
    (_c, _s, _p, _i, _m, args) => {
        const [name, , owner] = args.deep_unpack();
        if (owner !== '') return;
        const entry = `${name}/StatusNotifierItem`;
        if (!items.includes(entry)) return;
        items = items.filter(i => i !== entry);
        if (mode !== 'missing-removal-signal')
            watcher.emit_signal('StatusNotifierItemUnregistered', new GLib.Variant('(s)', [entry]));
    });
function noLeak(result) {
    check(!JSON.stringify(result).includes('PRIVATE_SENTINEL'), 'sanitized facts');
}
try {
    for (const flag of [8, 4]) {
        flags = flag;
        const result = await probe.observeCaffeineInhibitor(connection, {expectedFlags: flag});
        check(result.status === 'found' && result.matchingCount === 1, 'exact Caffeine inhibitor found');
    }
    flags = 8;
    for (const mutation of ['foreign-id', 'foreign-reason', 'wrong-flags', 'empty', 'too-many', 'duplicate', 'unknown-path']) {
        appId = mutation === 'foreign-id' ? 'PRIVATE_SENTINEL' : 'caffeine-gnome-extension';
        reason = mutation === 'foreign-reason' ? 'PRIVATE_SENTINEL' : 'Inhibited by Caffeine GNOME extension';
        flags = mutation === 'wrong-flags' ? 4 : 8;
        inhibitors = mutation === 'empty' ? [] : mutation === 'too-many' ? Array(129).fill('/org/gnome/SessionManager/Inhibitor1') : mutation === 'duplicate' ? Array(2).fill('/org/gnome/SessionManager/Inhibitor1') : mutation === 'unknown-path' ? ['/org/gnome/SessionManager/Missing'] : ['/org/gnome/SessionManager/Inhibitor1'];
        const result = await probe.observeCaffeineInhibitor(connection, {expectedFlags: 8});
        check(result.status === (['too-many', 'duplicate', 'unknown-path'].includes(mutation) ? 'failure' : 'not-found'), mutation);
        noLeak(result);
    }
    check((await probe.observeCaffeineInhibitor(connection, {expectedFlags: 12})).status === 'failure', 'reject unsupported flags');
    check((await probe.observeCaffeineInhibitor(connection, null)).status === 'failure', 'malformed Caffeine options rejected');
    const badControl = await probe.registerSyntheticStatusNotifierItem(connection, null);
    check(badControl.observation.status === 'failure', 'malformed item options rejected');
    hang = true;
    const before = GLib.get_monotonic_time();
    check((await probe.observeCaffeineInhibitor(connection, {expectedFlags: 8})).status === 'failure', 'hung manager rejected');
    check(GLib.get_monotonic_time() - before < 4e6, 'hung manager bounded');
    hang = false;
    for (const testMode of ['normal', 'wrong-entry', 'missing-signal', 'reject', 'hang']) {
        mode = testMode;
        items = [':99.1/ForeignItem'];
        const control = await probe.registerSyntheticStatusNotifierItem(connection,
            {id: 'arch-linux-acceptance', iconName: 'utilities-terminal-symbolic'});
        check(control.observation.status === (mode === 'normal' ? 'registered' : 'failure'), `registration ${mode}`);
        noLeak(control.observation);
        if (mode === 'normal') {
            const removed = await control.close();
            check(removed.status === 'unregistered' && removed.absent && removed.signal, 'owned close requires absence and signal');
            check(items.includes(':99.1/ForeignItem'), 'foreign item preserved');
            check((await control.close()).status === 'unregistered', 'close idempotent');
        } else {
            await control.close();
        }
        const [owned] = connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
            'NameHasOwner', new GLib.Variant('(s)', [lastSender]), new GLib.VariantType('(b)'), Gio.DBusCallFlags.NONE, 1000, null).deep_unpack();
        check(!owned, `owned connection closed after ${mode}`);
    }
    mode = 'normal';
    items = [':99.1/ForeignItem'];
    const removalControl = await probe.registerSyntheticStatusNotifierItem(connection,
        {id: 'arch-linux-acceptance', iconName: 'utilities-terminal-symbolic'});
    check(removalControl.observation.status === 'registered', 'removal control registered');
    mode = 'missing-removal-signal';
    const removalResult = await removalControl.close();
    check(removalResult.status === 'failure' && !removalResult.signal,
        'property absence without removal event insufficient');
    check(!connection.is_closed(), 'caller connection preserved');
    watcher.unexport();
    watcherExported = false;
    const malformedWatcher = Gio.DBusExportedObject.wrapJSObject(`<node><interface name="org.kde.StatusNotifierWatcher"><method name="RegisterStatusNotifierItem"><arg type="s" direction="in"/></method><property name="RegisteredStatusNotifierItems" type="s" access="read"/><signal name="StatusNotifierItemRegistered"><arg type="s"/></signal></interface></node>`, {
        get RegisteredStatusNotifierItems() { return 'PRIVATE_SENTINEL'; },
        RegisterStatusNotifierItemAsync([entry], invocation) {
            lastSender = invocation.get_sender();
            malformedWatcher.emit_signal('StatusNotifierItemRegistered', new GLib.Variant('(s)', [entry]));
            invocation.return_value(null);
        },
    });
    malformedWatcher.export(connection, '/StatusNotifierWatcher');
    try {
        const malformedControl = await probe.registerSyntheticStatusNotifierItem(connection,
            {id: 'arch-linux-acceptance', iconName: 'utilities-terminal-symbolic'});
        check(malformedControl.observation.status === 'failure', 'malformed property cannot prove registration');
        noLeak(malformedControl.observation);
        const [owned] = connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
            'NameHasOwner', new GLib.Variant('(s)', [lastSender]), new GLib.VariantType('(b)'), Gio.DBusCallFlags.NONE, 1000, null).deep_unpack();
        check(!owned, 'malformed registration closes owned connection');
    } finally { malformedWatcher.unexport(); }
    print(`DESKTOP_SERVICE_PROBE_CHECKS PASS checks=${checks} runtime=private-dbus-fixtures`);
} finally {
    connection.signal_unsubscribe(subscription);
    if (watcherExported) watcher.unexport();
    inhibitor.unexport(); manager.unexport();
}
