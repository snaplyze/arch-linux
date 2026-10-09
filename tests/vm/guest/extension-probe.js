#!/usr/bin/gjs -m
// Disposable GTK application: observes only synthetic test clipboard values.
import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const [state, runId, round] = ARGV;
if (!state || !/^marble-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$/.test(runId) || !['upgrade', 'postreboot'].includes(round))
    throw new Error('Invalid probe identity');
const sha = text => GLib.compute_checksum_for_string(GLib.ChecksumType.SHA256, text, -1);
const [sourceBytes] = Gio.File.new_for_path(`${state}/probe.js`).load_bytes(null);
const probeSha256 = GLib.compute_checksum_for_bytes(GLib.ChecksumType.SHA256, sourceBytes);
const pid = new Gio.Credentials().get_unix_pid();
const a = `archlinux-${runId}-${round}-a`;
const b = `archlinux-${runId}-${round}-b`;
let step = 'copy-a';
let writing = false;

function receipt(stage, value = '') {
    const output = JSON.stringify({schema: 1, runId, round, probeSha256, stage,
        valueSha256: value ? sha(value) : '-', pid}) + '\n';
    Gio.File.new_for_path(`${state}/${stage}.json`).replace_contents(
        output, null, false, Gio.FileCreateFlags.PRIVATE, null);
}

const app = new Gtk.Application({application_id: `org.archlinux.QemuExtensionProbe.${round}`});
app.connect('activate', () => {
    const window = new Gtk.ApplicationWindow({application: app,
        title: 'Arch Linux extension acceptance', default_width: 640, default_height: 240});
    const entry = new Gtk.Entry({text: a, hexpand: true});
    window.set_child(entry);
    const clipboard = Gdk.Display.get_default().get_clipboard();
    const setText = text => {
        writing = true; entry.set_text(text); entry.grab_focus(); entry.select_region(0, -1); writing = false;
    };
    clipboard.connect('changed', () => {
        if (!['copy-a', 'copy-b', 'history-a', 'history-b'].includes(step)) return;
        clipboard.read_text_async(null, (object, result) => {
            let text;
            try { text = object.read_text_finish(result); } catch { return; }
            // Unknown clipboard contents are neither stored nor logged.
            if (step === 'copy-a' && text === a) {
                step = 'copy-b'; setText(b); receipt('copied-a', a);
            } else if (step === 'copy-b' && text === b) {
                step = 'history-a'; setText(''); receipt('copied-b', b);
            } else if (step === 'history-a' && text === a) {
                receipt('history-a', a); step = 'paste-a';
            } else if (step === 'history-b' && text === b) {
                receipt('history-b', b); step = 'paste-b';
            }
        });
    });
    entry.connect('changed', () => {
        if (writing) return;
        if (step === 'paste-a' && entry.get_text() === a) {
            step = 'history-b'; setText(''); receipt('pasted-a', a);
        } else if (step === 'paste-b' && entry.get_text() === b) {
            step = 'done'; setText(''); receipt('pasted-b', b);
        }
    });
    window.connect('notify::is-active', () => {
        if (window.is_active()) receipt('dash-ready');
    });
    const monitors = Gdk.Display.get_default().get_monitors();
    if (monitors.get_n_items() !== 1) throw new Error('Probe requires one guest monitor');
    const monitor = monitors.get_item(0); const geometry = monitor.get_geometry();
    Gio.File.new_for_path(`${state}/display.json`).replace_contents(JSON.stringify({
        width: geometry.width, height: geometry.height, scale: monitor.get_scale_factor()
    }) + '\n', null, false, Gio.FileCreateFlags.PRIVATE, null);
    window.present(); entry.grab_focus(); entry.select_region(0, -1);
    GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 300, () => {
        app.quit(); return GLib.SOURCE_REMOVE;
    });
});
app.run([]);
