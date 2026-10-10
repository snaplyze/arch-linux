#!/usr/bin/env bash
# Sourced only by the installed-system verifier, after the GTK probe cleanup.
# shellcheck disable=SC2154 # The sourcing verifier supplies session and scenario identity.

desktop_native_state=''
desktop_native_trusted=''
desktop_native_round=''
desktop_native_uid=''
desktop_native_code=''
desktop_native_checker='/run/arch-linux-qemu-desktop-receipt.py'

load_desktop_native_state() {
    [[ "${phase}" =~ ^extension-(firstlogin|upgrade|postreboot)-native-([a-z-]+)$ ]] || return 1
    desktop_native_round="${BASH_REMATCH[1]}"
    [[ "${run_id}" =~ ^(marble|luksgrub)-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || return 1
    case "${scenario}:${input_mode}:${desktop_native_round}" in
        stock-gnome-btrfs-luks2-plymouth-grub:staged:firstlogin|stock-gnome-btrfs-luks2-plymouth-grub:staged:postreboot|\
        marble-gnome-btrfs-luks2-plymouth-systemdboot:staged:upgrade|marble-gnome-btrfs-luks2-plymouth-systemdboot:staged:postreboot|\
        marble-gnome-btrfs-luks2-plymouth-systemdboot:public:firstlogin|marble-gnome-btrfs-luks2-plymouth-systemdboot:public:postreboot) ;;
        *) return 1 ;;
    esac
    desktop_native_uid="$(id -u "${username}")"
    [[ "${desktop_native_uid}" =~ ^[1-9][0-9]*$ ]] || return 1
    desktop_native_state="/run/user/${desktop_native_uid}/arch-linux-qemu-extension-${run_id}-${desktop_native_round}"
    desktop_native_trusted="/run/arch-linux-qemu-desktop-functional/${run_id}/${desktop_native_round}"
    desktop_native_code="/run/arch-linux-qemu-desktop-code/${run_id}/${desktop_native_round}"
}

desktop_native_require_session() {
    local session package version shell_pid bus_pid
    session="$(wait_for_user_session)"
    [ "$(session_property "${session}" User)" = "${desktop_native_uid}" ]
    [ "$(session_property "${session}" Service)" = gdm-password ]
    [ "$(session_property "${session}" Type)" = wayland ]
    [ "$(session_property "${session}" State)" = active ]
    for package in gnome-shell mutter gdm; do
        version="$(installed_package_version_exact "${package}")"
        [[ "${version#*:}" = 51.* ]] || return 1
    done
    if [ "${input_mode}:${scenario}" = staged:marble-gnome-btrfs-luks2-plymouth-systemdboot ]; then
        gnome51_require_platform
        [ -f "${gnome51_migration_state}/transaction-proven" ]
    fi
    shell_pid="$(wait_for_gnome_shell "${desktop_native_uid}")"
    bus_pid="$(run_in_user_session "${desktop_native_uid}" /usr/bin/gjs -c '
const Gio=imports.gi.Gio, GLib=imports.gi.GLib;
const owner=name=>Gio.DBus.session.call_sync("org.freedesktop.DBus","/org/freedesktop/DBus",
"org.freedesktop.DBus","GetConnectionUnixProcessID",new GLib.Variant("(s)",[name]),
new GLib.VariantType("(u)"),Gio.DBusCallFlags.NO_AUTO_START,5000,null).deep_unpack()[0];
const pid=owner("org.gnome.Shell");
if(owner("org.kde.StatusNotifierWatcher")!==pid) imports.system.exit(1);
print(pid);')"
    [ "${shell_pid}" = "${bus_pid}" ]
    printf '%s\n%s\n' "${session}" "${shell_pid}"
}

desktop_native_schema() {
    case "$1" in
        caffeine) printf '%s\n' /usr/share/gnome-shell/extensions/caffeine@patapon.info/schemas org.gnome.shell.extensions.caffeine ;;
        blur) printf '%s\n' /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas org.gnome.shell.extensions.blur-my-shell.overview ;;
        blur-pipeline) printf '%s\n' /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas org.gnome.shell.extensions.blur-my-shell ;;
        panel) printf '%s\n' /usr/share/gnome-shell/extensions/just-perfection-desktop@just-perfection/schemas org.gnome.shell.extensions.just-perfection ;;
        theme) printf '%s\n' /usr/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com/schemas org.gnome.shell.extensions.user-theme ;;
        *) return 1 ;;
    esac
}

desktop_native_setting() {
    local operation="$1" kind="$2" key="$3"; shift 3
    local -a schema=()
    mapfile -t schema < <(desktop_native_schema "${kind}")
    [ "${#schema[@]}" -eq 2 ]
    if [ -f "${schema[0]}/gschemas.compiled" ]; then
        run_in_user_session "${desktop_native_uid}" /usr/bin/gsettings --schemadir "${schema[0]}" \
            "${operation}" "${schema[1]}" "${key}" "$@"
    else
        run_in_user_session "${desktop_native_uid}" /usr/bin/gsettings "${operation}" "${schema[1]}" "${key}" "$@"
    fi
}

desktop_native_save_settings() {
    local path value
    printf '[]\n' >"${desktop_native_trusted}/settings.json"
    chmod 0600 -- "${desktop_native_trusted}/settings.json"
    for path in /org/gnome/shell/extensions/caffeine/toggle-shortcut \
        /org/gnome/shell/extensions/caffeine/user-enabled /org/gnome/shell/extensions/caffeine/screen-blank \
        /org/gnome/shell/extensions/blur-my-shell/overview/blur \
        /org/gnome/shell/extensions/blur-my-shell/overview/pipeline \
        /org/gnome/shell/extensions/blur-my-shell/pipelines \
        /org/gnome/shell/extensions/just-perfection/panel \
        /org/gnome/shell/extensions/just-perfection/panel-in-overview \
        /org/gnome/shell/extensions/just-perfection/top-panel-position \
        /org/gnome/shell/extensions/user-theme/name; do
        value="$(run_in_user_session "${desktop_native_uid}" /usr/bin/dconf read "${path}")"
        jq --arg path "${path}" --arg value "${value}" '. + [{path:$path,value:$value}]' \
            "${desktop_native_trusted}/settings.json" >"${desktop_native_trusted}/settings.next"
        chmod 0600 -- "${desktop_native_trusted}/settings.next"
        mv -- "${desktop_native_trusted}/settings.next" "${desktop_native_trusted}/settings.json"
    done
}

desktop_native_restore_settings() {
    local filter="${1:-all}" path encoded value rows
    # Validate the entire snapshot and finish its producer before any dconf write.
    # A failing process substitution otherwise becomes a successful empty loop.
    rows="$(python3 - "${desktop_native_checker}" "${desktop_native_trusted}" "${filter}" <<'DESKTOP_SETTINGS_ROWS_PY'
import importlib.util, os, pathlib, stat, sys
sys.dont_write_bytecode = True
try:
 path = pathlib.Path(sys.argv[1]); info = path.lstat()
 assert stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o500
 spec = importlib.util.spec_from_file_location('desktop_restoration', path)
 module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
 module.print_settings_rows(sys.argv[2], sys.argv[3])
except (OSError, ValueError, AssertionError, TypeError, KeyError):
 print('DESKTOP_NATIVE_RECEIPT_FAIL reason=invalid-scoped-settings', file=sys.stderr)
 raise SystemExit(1)
DESKTOP_SETTINGS_ROWS_PY
)" || return 1
    while IFS=$'\t' read -r path encoded; do
        case "${filter}:${path}" in panel:/org/gnome/shell/extensions/just-perfection/panel|panel:/org/gnome/shell/extensions/just-perfection/panel-in-overview) ;;
            all:*) ;; *) continue ;; esac
        value="$(printf '%s' "${encoded}" | base64 --decode)"
        if [ -n "${value}" ]; then
            run_in_user_session "${desktop_native_uid}" /usr/bin/dconf write "${path}" "${value}"
        else
            run_in_user_session "${desktop_native_uid}" /usr/bin/dconf reset "${path}"
        fi
        [ "$(run_in_user_session "${desktop_native_uid}" /usr/bin/dconf read "${path}")" = "${value}" ]
    done <<<"${rows}"
}

prepare_desktop_native_probe() {
    local name monitor_count theme_path expected_flags=8
    local -a session=()
    command -v jq >/dev/null && command -v python3 >/dev/null && [ -x /usr/bin/gjs ]
    mapfile -t session < <(desktop_native_require_session)
    [ "${#session[@]}" -eq 2 ]
    # This native fixture observes top-position panels and the default native pipeline.
    # Reject an unsupported override before creating state or changing a setting.
    [ "$(desktop_native_setting get panel top-panel-position)" = 0 ]
    [ "$(desktop_native_setting get blur pipeline)" = "'pipeline_default'" ]
    local -a blur_schema=()
    mapfile -t blur_schema < <(desktop_native_schema blur-pipeline)
    run_in_user_session "${desktop_native_uid}" /usr/bin/gjs -c '
const Gio=imports.gi.Gio;
const source=Gio.SettingsSchemaSource.new_from_directory(ARGV[0],Gio.SettingsSchemaSource.get_default(),false);
const schema=source.lookup(ARGV[1],false);
const settings=new Gio.Settings({settings_schema:schema});
if (!settings.get_value("pipelines").equal(settings.get_default_value("pipelines"))) imports.system.exit(1);
' "${blur_schema[0]}" "${blur_schema[1]}"
    local original_theme
    original_theme="$(desktop_native_setting get theme name)"
    case "${original_theme}" in "''"|"'ArchLinux-Marble-Blue-Filled-Dark'") ;; *) return 1 ;; esac
    if [ "${scenario}" = stock-gnome-btrfs-luks2-plymouth-grub ]; then [ "${original_theme}" = "''" ]; fi
    [ ! -e "${desktop_native_state}" ] && [ ! -L "${desktop_native_state}" ]
    [ ! -e "${desktop_native_trusted}" ] && [ ! -L "${desktop_native_trusted}" ]
    # Parent root components are harness-owned; refuse links or foreign modes.
    for name in /run/arch-linux-qemu-desktop-functional "/run/arch-linux-qemu-desktop-functional/${run_id}"; do
        if [ ! -e "${name}" ] && [ ! -L "${name}" ]; then install -d -o0 -g0 -m0700 -- "${name}"; fi
        [ -d "${name}" ] && [ ! -L "${name}" ] && [ "$(stat -c '%u:%a' "${name}")" = 0:700 ]
    done
    install -d -o0 -g0 -m0700 -- "${desktop_native_trusted}"
    local original_theme_path=null
    if [ "${original_theme}" != "''" ]; then
        original_theme_path='"/usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark/gnome-shell/gnome-shell.css"'
    fi
    jq -n --argjson blur "$(desktop_native_setting get blur blur)" \
        --argjson panel "$(desktop_native_setting get panel panel)" \
        --argjson panelInOverview "$(desktop_native_setting get panel panel-in-overview)" \
        --argjson theme "${original_theme_path}" \
        '{blur:$blur,panel:$panel,panelInOverview:$panelInOverview,theme:$theme}' \
        >"${desktop_native_trusted}/original-state.json"
    chmod 0600 -- "${desktop_native_trusted}/original-state.json"
    run_in_user_session "${desktop_native_uid}" /usr/bin/mkdir -m0700 -- "${desktop_native_state}"
    for name in /run/arch-linux-qemu-desktop-code "/run/arch-linux-qemu-desktop-code/${run_id}"; do
        if [ ! -e "${name}" ] && [ ! -L "${name}" ]; then install -d -o0 -g0 -m0755 -- "${name}"; fi
        [ -d "${name}" ] && [ ! -L "${name}" ] && [ "$(stat -c '%u:%a' "${name}")" = 0:755 ]
    done
    [ ! -e "${desktop_native_code}" ] && [ ! -L "${desktop_native_code}" ]
    install -d -o0 -g0 -m0755 -- "${desktop_native_code}"
    for name in desktop-shell-probe desktop-extension-observer desktop-service-runner desktop-service-probe; do
        [ -f "/run/arch-linux-qemu-${name}.js" ] && [ ! -L "/run/arch-linux-qemu-${name}.js" ]
        [ "$(stat -c '%u:%a' "/run/arch-linux-qemu-${name}.js")" = 0:500 ]
        install -o0 -g0 -m0555 -- \
            "/run/arch-linux-qemu-${name}.js" "${desktop_native_code}/${name}.js"
    done
    [ -f "${desktop_native_checker}" ] && [ ! -L "${desktop_native_checker}" ]
    [ "$(stat -c '%u:%a' "${desktop_native_checker}")" = 0:500 ]
    desktop_native_save_settings
    # Caffeine60 context-control: never=0, always=1, for-apps=2. Never uses idle=8.
    desktop_native_setting set caffeine toggle-shortcut "['<Super>F7']"
    desktop_native_setting set caffeine user-enabled false
    desktop_native_setting set caffeine screen-blank "'never'"
    desktop_native_setting set panel top-panel-position 0
    monitor_count="$(run_in_user_session "${desktop_native_uid}" /usr/bin/gjs -c '
const Gio=imports.gi.Gio, GLib=imports.gi.GLib;
const value=Gio.DBus.session.call_sync("org.gnome.Mutter.DisplayConfig","/org/gnome/Mutter/DisplayConfig",
"org.gnome.Mutter.DisplayConfig","GetCurrentState",null,null,Gio.DBusCallFlags.NO_AUTO_START,5000,null).deep_unpack();
print(value[2].length);')"
    [[ "${monitor_count}" =~ ^([1-9]|1[0-6])$ ]] || return 1
    theme_path=null
    if [ "${scenario}" = marble-gnome-btrfs-luks2-plymouth-systemdboot ]; then
        theme_path='"/usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark/gnome-shell/gnome-shell.css"'
    fi
    jq -n --arg runId "${run_id}" --arg round "${desktop_native_round}" --argjson uid "${desktop_native_uid}" \
        --argjson shellPid "${session[1]}" --arg session "${session[0]}" \
        --arg bootId "$(cat /proc/sys/kernel/random/boot_id)" \
        '{schema:1,runId:$runId,round:$round,uid:$uid,shellPid:$shellPid,session:$session,bootId:$bootId}' >"${desktop_native_trusted}/context.json"
    chmod 0600 -- "${desktop_native_trusted}/context.json"
    local probe_hash observer_hash service_hash
    probe_hash="$(sha256sum "${desktop_native_code}/desktop-shell-probe.js" | awk '{print $1}')"
    observer_hash="$(sha256sum "${desktop_native_code}/desktop-extension-observer.js" | awk '{print $1}')"
    jq -n --arg runId "${run_id}" --arg round "${desktop_native_round}" --argjson uid "${desktop_native_uid}" \
        --argjson shellPid "${session[1]}" --arg probeSha256 "${probe_hash}" --arg observerSha256 "${observer_hash}" \
        --argjson monitorCount "${monitor_count}" --argjson themePath "${theme_path}" \
        '{schema:1,runId:$runId,round:$round,uid:$uid,shellPid:$shellPid,probeSha256:$probeSha256,observerSha256:$observerSha256,monitorCount:$monitorCount,themePath:$themePath}' \
        >"${desktop_native_trusted}/desktop-shell-metadata.json"
    probe_hash="$(sha256sum "${desktop_native_code}/desktop-service-probe.js" | awk '{print $1}')"
    service_hash="$(sha256sum "${desktop_native_code}/desktop-service-runner.js" | awk '{print $1}')"
    jq -n --arg runId "${run_id}" --arg round "${desktop_native_round}" --argjson uid "${desktop_native_uid}" \
        --arg probeSha256 "${probe_hash}" --arg serviceSha256 "${service_hash}" --argjson expectedFlags "${expected_flags}" \
        '{schema:1,runId:$runId,round:$round,uid:$uid,probeSha256:$probeSha256,serviceSha256:$serviceSha256,expectedFlags:$expectedFlags}' \
        >"${desktop_native_trusted}/desktop-service-metadata.json"
    for name in shell service; do
        chmod 0600 -- "${desktop_native_trusted}/desktop-${name}-metadata.json"
        install -o "${desktop_native_uid}" -g "$(id -g "${username}")" -m0600 -- \
            "${desktop_native_trusted}/desktop-${name}-metadata.json" "${desktop_native_state}/desktop-${name}-metadata.json"
    done
    run_in_user_session "${desktop_native_uid}" /usr/bin/gjs -m "${desktop_native_code}/desktop-service-runner.js" \
        "${desktop_native_state}" "${run_id}" "${desktop_native_round}" </dev/null >/dev/null 2>&1 &
    printf 'DESKTOP_PROBE_IDENTITY uid=%s round=%s\n' "${desktop_native_uid}" "${desktop_native_round}"
}

desktop_native_wait_receipt() {
    local kind="$1" sequence="$2" stage="$3" expected="${4:-any}" filename deadline=$((SECONDS + 35))
    filename="desktop-${kind}-${sequence}-${stage}.json"
    if [ "${sequence}" -eq 0 ]; then filename="desktop-${kind}-ready.json"; fi
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if [ -e "${desktop_native_state}/${filename}" ] || [ -L "${desktop_native_state}/${filename}" ]; then
            python3 "${desktop_native_checker}" verify "${desktop_native_uid}" "${run_id}" "${desktop_native_round}" \
                "${kind}" "${sequence}" "${stage}" "${expected}"
            return
        fi
        sleep 0.1
    done
    printf 'DESKTOP_NATIVE_RECEIPT_FAIL kind=%s stage=%s reason=missing-receipt\n' "${kind}" "${stage}" >&2
    return 1
}

desktop_native_command() {
    local kind="$1" stage="$2" expected="${3:-any}" sequence
    sequence="$(jq -er '.sequence + 1' "${desktop_native_trusted}/${kind}-sequence.json")"
    jq -n --arg runId "${run_id}" --arg round "${desktop_native_round}" --argjson sequence "${sequence}" --arg stage "${stage}" \
        '{schema:1,runId:$runId,round:$round,sequence:$sequence,stage:$stage}' >"${desktop_native_trusted}/${kind}-command.json"
    chmod 0600 -- "${desktop_native_trusted}/${kind}-command.json"
    install -o "${desktop_native_uid}" -g "$(id -g "${username}")" -m0600 -- \
        "${desktop_native_trusted}/${kind}-command.json" "${desktop_native_state}/desktop-${kind}-command.next"
    run_in_user_session "${desktop_native_uid}" /usr/bin/mv -- \
        "${desktop_native_state}/desktop-${kind}-command.next" "${desktop_native_state}/desktop-${kind}-command.json"
    desktop_native_wait_receipt "${kind}" "${sequence}" "${stage}" "${expected}"
}

cleanup_desktop_native_probe() {
    local pid deadline
    desktop_native_restore_settings
    if [ "$(desktop_native_setting get blur blur)" = true ]; then
        desktop_native_command shell blur-on
    else
        desktop_native_command shell blur-off
    fi
    desktop_native_verify_panel_setting
    case "$(desktop_native_setting get theme name)" in
        "''") desktop_native_command shell theme-stock ;;
        "'ArchLinux-Marble-Blue-Filled-Dark'") desktop_native_command shell theme-marble ;;
        *) return 1 ;;
    esac
    desktop_native_command shell stop
    desktop_native_command service stop
    pid="$(jq -er '.pid' "${desktop_native_trusted}/service-identity.json")"
    python3 "${desktop_native_checker}" terminate-service "${desktop_native_uid}" "${run_id}" "${desktop_native_round}" service 0 stop
    deadline=$((SECONDS + 10))
    while [ -d "/proc/${pid}" ] && [ "${SECONDS}" -lt "${deadline}" ]; do sleep 0.1; done
    [ ! -d "/proc/${pid}" ]
    desktop_native_require_session >/dev/null
    # Validate the complete root-custodied positive/control history before emitting.
    python3 "${desktop_native_checker}" complete "${desktop_native_uid}" "${run_id}" "${desktop_native_round}" shell 0 ready \
        >"${desktop_native_trusted}/completion.txt"
    chmod 0600 -- "${desktop_native_trusted}/completion.txt"
    # Exact allowlist: retain compact root-bound receipts, remove only owned user files.
    python3 "${desktop_native_checker}" cleanup "${desktop_native_uid}" "${run_id}" "${desktop_native_round}" shell 0 ready
    cat -- "${desktop_native_trusted}/completion.txt"
}

desktop_native_verify_panel_setting() {
    local stage
    if [ "$(desktop_native_setting get panel panel)" = true ]; then stage=panel-shown
    elif [ "$(desktop_native_setting get panel panel-in-overview)" = true ]; then stage=panel-overview-only
    else stage=panel-hidden; fi
    desktop_native_command shell "${stage}"
}

run_desktop_native_phase() {
    local operation
    load_desktop_native_state
    operation="${phase#extension-"${desktop_native_round}"-native-}"
    if [ "${operation}" != prepare ]; then desktop_native_require_session >/dev/null; fi
    case "${operation}" in
        prepare) prepare_desktop_native_probe ;;
        ready) desktop_native_wait_receipt shell 0 ready; desktop_native_wait_receipt service 0 ready ;;
        indicator-register|indicator-remove) desktop_native_command service "${operation}" ;;
        caffeine-baseline|caffeine-off) desktop_native_command service caffeine-observe off ;;
        caffeine-on) desktop_native_command service caffeine-observe on ;;
        blur-enable)
            desktop_native_setting reset blur-pipeline pipelines
            desktop_native_setting set blur pipeline "'pipeline_default'"
            desktop_native_setting set blur blur true ;;
        blur-disable) desktop_native_setting set blur blur false ;;
        blur-on|blur-off) desktop_native_command shell "${operation}" ;;
        panel-shown)
            desktop_native_setting set panel panel-in-overview false
            desktop_native_setting set panel panel true
            desktop_native_command shell panel-shown ;;
        panel-hidden)
            desktop_native_setting set panel panel-in-overview false
            desktop_native_setting set panel panel false
            desktop_native_command shell panel-hidden ;;
        panel-overview-prepare)
            desktop_native_setting set panel panel false
            desktop_native_setting set panel panel-in-overview true ;;
        panel-overview-only) desktop_native_command shell panel-overview-only ;;
        panel-restore)
            desktop_native_restore_settings panel
            desktop_native_verify_panel_setting ;;
        theme-stock) desktop_native_setting set theme name "''"; desktop_native_command shell theme-stock ;;
        theme-marble)
            [ "${scenario}" = marble-gnome-btrfs-luks2-plymouth-systemdboot ]
            desktop_native_setting set theme name "'ArchLinux-Marble-Blue-Filled-Dark'"
            desktop_native_command shell theme-marble ;;
        cleanup) cleanup_desktop_native_probe ;;
        restore) desktop_native_restore_settings ;;
        *) return 1 ;;
    esac
}
