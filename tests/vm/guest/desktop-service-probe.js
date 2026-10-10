// Public session-bus observations for real-input desktop acceptance.
// No Shell evaluation, service-name ownership, settings changes or raw D-Bus data in receipts.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const SESSION = 'org.gnome.SessionManager';
const WATCHER = 'org.kde.StatusNotifierWatcher';
const WATCHER_PATH = '/StatusNotifierWatcher';
const ITEM_PATH = '/StatusNotifierItem';
const CALL_MS = 1500;
const WAIT_MS = 10000;
const MAX_ITEMS = 128;

function validConnection(connection) {
    return connection instanceof Gio.DBusConnection && !connection.is_closed() &&
        /^:\d+\.\d+$/.test(connection.get_unique_name() ?? '');
}
function deadline(milliseconds) {
    const cancellable = new Gio.Cancellable();
    const timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, milliseconds, () => {
        cancellable.cancel();
        return GLib.SOURCE_CONTINUE;
    });
    return {cancellable, clear() { GLib.source_remove(timer); }};
}
function call(connection, destination, path, iface, method, params, type, cancellable) {
    return new Promise((resolve, reject) => connection.call(destination, path, iface, method,
        params, new GLib.VariantType(type), Gio.DBusCallFlags.NO_AUTO_START, CALL_MS,
        cancellable, (c, result) => {
            try { resolve(c.call_finish(result)); } catch (error) { reject(error); }
        }));
}
async function busCall(connection, method, params, type, cancellable) {
    return call(connection, 'org.freedesktop.DBus', '/org/freedesktop/DBus',
        'org.freedesktop.DBus', method, params, type, cancellable);
}
async function owner(connection, name, cancellable) {
    const [value] = (await busCall(connection, 'GetNameOwner',
        new GLib.Variant('(s)', [name]), '(s)', cancellable)).deep_unpack();
    if (!/^:\d+\.\d+$/.test(value)) throw new Error('Invalid owner');
    return value;
}
function boundedStrings(value, paths = false) {
    if (!Array.isArray(value) || value.length > MAX_ITEMS || value.some(s =>
        typeof s !== 'string' || s.length > 256 || (paths && !/^\/[A-Za-z0-9_/]+$/.test(s))) ||
        new Set(value).size !== value.length)
        throw new Error('Invalid list');
    return value;
}

// A foreign inhibitor or an empty list is not a Caffeine activation receipt.
// The caller obtains the positive/control transition through actual GNOME input.
export async function observeCaffeineInhibitor(connection, options = {}) {
    const failure = {status: 'failure', count: 0, matchingCount: 0};
    if (!options || typeof options !== 'object' || Array.isArray(options)) return failure;
    const {expectedFlags} = options;
    if (!validConnection(connection) || ![4, 8].includes(expectedFlags)) return failure;
    const budget = deadline(5000);
    try {
        const service = await owner(connection, SESSION, budget.cancellable);
        const [raw] = (await call(connection, service, '/org/gnome/SessionManager', SESSION,
            'GetInhibitors', null, '(ao)', budget.cancellable)).deep_unpack();
        const paths = boundedStrings(raw, true);
        let matchingCount = 0;
        for (const path of paths) {
            const values = await Promise.all([
                ['GetAppId', '(s)'], ['GetReason', '(s)'], ['GetFlags', '(u)'],
            ].map(async ([method, type]) => (await call(connection, service, path,
                `${SESSION}.Inhibitor`, method, null, type, budget.cancellable)).deep_unpack()[0]));
            if (values[0] === 'caffeine-gnome-extension' &&
                values[1] === 'Inhibited by Caffeine GNOME extension' && values[2] === expectedFlags)
                matchingCount++;
        }
        if (await owner(connection, SESSION, budget.cancellable) !== service)
            throw new Error('Service changed');
        return {status: matchingCount ? 'found' : 'not-found', count: paths.length, matchingCount};
    } catch {
        return failure;
    } finally {
        budget.clear();
    }
}

// Standard SNI properties used by AppIndicator66; no menu/pixmap/activation payload.
const ITEM_XML = `<node><interface name="org.kde.StatusNotifierItem">
<property name="Category" type="s" access="read"/><property name="Id" type="s" access="read"/>
<property name="Title" type="s" access="read"/><property name="Status" type="s" access="read"/>
<property name="WindowId" type="i" access="read"/><property name="IconThemePath" type="s" access="read"/>
<property name="Menu" type="o" access="read"/><property name="ItemIsMenu" type="b" access="read"/>
<property name="IconName" type="s" access="read"/><property name="IconPixmap" type="a(iiay)" access="read"/>
<property name="OverlayIconName" type="s" access="read"/><property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
<property name="AttentionIconName" type="s" access="read"/><property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
<property name="AttentionMovieName" type="s" access="read"/>
<method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
<method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
<method name="ProvideXdgActivationToken"><arg type="s" direction="in"/></method>
<method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
<method name="XAyatanaSecondaryActivate"><arg type="u" direction="in"/></method>
<method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
</interface></node>`;
function privateConnection(cancellable) {
    return new Promise((resolve, reject) => {
        // Require the caller's explicit session address; never autolaunch a bus.
        const address = GLib.getenv('DBUS_SESSION_BUS_ADDRESS');
        if (!address) { reject(new Error('Missing session bus address')); return; }
        Gio.DBusConnection.new_for_address(address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            null, cancellable, (_source, result) => {
                try { resolve(Gio.DBusConnection.new_for_address_finish(result)); } catch (error) { reject(error); }
            });
    });
}
async function closeConnection(connection) {
    if (!connection || connection.is_closed()) return true;
    const budget = deadline(1500);
    try {
        await new Promise((resolve, reject) => connection.close(budget.cancellable, (c, result) => {
            try { c.close_finish(result); resolve(); } catch (error) { reject(error); }
        }));
        return connection.is_closed();
    } catch {
        // Dispose only this independently created connection, never the caller's bus.
        // Closing the owned Unix transport prevents a cancelled close from leaving
        // an item name alive. This is a socket close, with no flush or peer wait.
        try { connection.get_stream().close(null); } catch {}
        connection.run_dispose();
        return false;
    } finally { budget.clear(); }
}
function delay(milliseconds) {
    return new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, milliseconds, () => {
        resolve(); return GLib.SOURCE_REMOVE;
    }));
}
async function waitForEntry(connection, service, entry, seen, present, cancellable) {
    const until = GLib.get_monotonic_time() + WAIT_MS * 1000;
    do {
        const [variant] = (await call(connection, service, WATCHER_PATH,
            'org.freedesktop.DBus.Properties', 'Get',
            new GLib.Variant('(ss)', [WATCHER, 'RegisteredStatusNotifierItems']), '(v)', cancellable)).deep_unpack();
        if (variant.get_type_string() !== 'as') throw new Error('Invalid property');
        const items = boundedStrings(variant.deep_unpack());
        if (seen() && items.includes(entry) === present &&
            await owner(connection, WATCHER, cancellable) === service)
            return true;
        await delay(100);
    } while (!cancellable.is_cancelled() && GLib.get_monotonic_time() < until);
    return false;
}

// Keep the returned control alive until close(). Failure closes the owned item bus immediately.
// AppIndicator66 preserves the registration argument verbatim in its signals/property. Its
// supported sender+path form provides exact identity; path-only registration cannot do so.
export async function registerSyntheticStatusNotifierItem(connection, options = {}) {
    const failed = {status: 'failure', registered: false, signal: false};
    const failedControl = () => ({observation: failed,
        close: async () => ({status: 'failure', absent: false, signal: false})});
    if (!options || typeof options !== 'object' || Array.isArray(options)) return failedControl();
    const {id, iconName} = options;
    if (!validConnection(connection) || typeof id !== 'string' || !/^[a-zA-Z0-9-]{1,64}$/.test(id) ||
        typeof iconName !== 'string' || !/^[a-zA-Z0-9-]{1,96}$/.test(iconName)) return failedControl();
    const budget = deadline(WAIT_MS + 2500);
    let itemConnection = null, exported = null, registered = false, removed = false;
    let registrationSubscription = 0, removalSubscription = 0;
    let closeResult = null;
    const unsubscribe = () => {
        if (registrationSubscription) connection.signal_unsubscribe(registrationSubscription);
        if (removalSubscription) connection.signal_unsubscribe(removalSubscription);
        registrationSubscription = removalSubscription = 0;
    };
    const cleanup = async () => {
        const closed = await closeConnection(itemConnection);
        exported?.unexport();
        unsubscribe();
        return closed;
    };
    try {
        const service = await owner(connection, WATCHER, budget.cancellable);
        itemConnection = await privateConnection(budget.cancellable);
        itemConnection.set_exit_on_close(false);
        const [expectedBus, actualBus] = await Promise.all([connection, itemConnection].map(async c =>
            (await busCall(c, 'GetId', null, '(s)', budget.cancellable)).deep_unpack()[0]));
        if (expectedBus !== actualBus) throw new Error('Wrong bus');
        const entry = `${itemConnection.get_unique_name()}${ITEM_PATH}`;
        exported = Gio.DBusExportedObject.wrapJSObject(ITEM_XML, {
            Category: 'ApplicationStatus', Id: id, Title: 'Desktop acceptance', Status: 'Active',
            WindowId: 0, IconThemePath: '', Menu: '/NO_DBUSMENU', ItemIsMenu: false,
            IconName: iconName, IconPixmap: [], OverlayIconName: '', OverlayIconPixmap: [],
            AttentionIconName: '', AttentionIconPixmap: [], AttentionMovieName: '',
            ContextMenu() {}, Activate() {}, ProvideXdgActivationToken() {},
            SecondaryActivate() {}, XAyatanaSecondaryActivate() {}, Scroll() {},
        });
        exported.export(itemConnection, ITEM_PATH);
        const subscribe = (signal, handler) => connection.signal_subscribe(service, WATCHER,
            signal, WATCHER_PATH, null, Gio.DBusSignalFlags.NONE,
            (_c, sender, _path, _iface, _name, args) => {
                if (sender === service && args.get_type_string() === '(s)' &&
                    args.deep_unpack()[0] === entry) handler();
            });
        registrationSubscription = subscribe('StatusNotifierItemRegistered', () => { registered = true; });
        removalSubscription = subscribe('StatusNotifierItemUnregistered', () => { removed = true; });
        await call(itemConnection, service, WATCHER_PATH, WATCHER, 'RegisterStatusNotifierItem',
            new GLib.Variant('(s)', [entry]), '()', budget.cancellable);
        if (!await waitForEntry(connection, service, entry, () => registered, true, budget.cancellable))
            throw new Error('Registration not observed');
        return {
            observation: {status: 'registered', registered: true, signal: true},
            async close() {
                if (closeResult) return closeResult;
                const removalBudget = deadline(WAIT_MS + 2500);
                try {
                    if (!await closeConnection(itemConnection)) throw new Error('Close failed');
                    const absent = await waitForEntry(connection, service, entry,
                        () => removed, false, removalBudget.cancellable);
                    closeResult = {status: absent ? 'unregistered' : 'failure', absent, signal: removed};
                } catch {
                    closeResult = {status: 'failure', absent: false, signal: false};
                } finally {
                    removalBudget.clear();
                    exported.unexport();
                    unsubscribe();
                }
                return closeResult;
            },
        };
    } catch {
        await cleanup();
        return failedControl();
    } finally {
        budget.clear();
    }
}
