die() {
    printf '%s\n' "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

set_firefox_paths() {
    FIREFOX_DIR=$1
    PREF_DIR="$FIREFOX_DIR/defaults/pref"
    PREF_SOURCE="$REPO_DIR/autoconfig/defaults/pref/tridactyl-godmode.js"
    PREF_TARGET="$PREF_DIR/tridactyl-godmode.js"
    CFG_SOURCE="$REPO_DIR/autoconfig/tridactyl-godmode.cfg"
    CFG_TARGET="$FIREFOX_DIR/tridactyl-godmode.cfg"
    ACTOR_SOURCE="$REPO_DIR/autoconfig/tridactyl-godmode-key-handoff-child.sys.mjs"
    ACTOR_TARGET="$FIREFOX_DIR/tridactyl-godmode-key-handoff-child.sys.mjs"
    STATE_TARGET="$FIREFOX_DIR/tridactyl-godmode.state"
    LOCK_TARGET="$FIREFOX_DIR/.tridactyl-godmode.lock"
    TRANSACTION_DIR="$FIREFOX_DIR/.tridactyl-godmode.transaction"
}

directory_is_safe() {
    directory=$1
    mode=$(stat -c %a "$directory") || return 1
    [ -d "$directory" ] &&
        [ ! -L "$directory" ] &&
        [ "$(stat -c %u "$directory")" = "$(stat -c %u "$FIREFOX_DIR")" ] &&
        [ $((0$mode & 0022)) -eq 0 ]
}

check_install_directories() {
    directory_is_safe "$FIREFOX_DIR" || die "$FIREFOX_DIR has unsafe ownership or permissions"
    directory_is_safe "$PREF_DIR" || die "$PREF_DIR has unsafe ownership or permissions"
}

check_install_identity() {
    [ "$(id -u)" = "$(stat -c %u "$FIREFOX_DIR")" ] ||
        die "run as the owner of $FIREFOX_DIR; use sudo only for a root-owned installation"
}

acquire_install_lock() {
    if [ -e "$LOCK_TARGET" ] || [ -L "$LOCK_TARGET" ]; then
        [ -f "$LOCK_TARGET" ] &&
            [ ! -L "$LOCK_TARGET" ] &&
            [ "$(stat -c %a "$LOCK_TARGET")" = "600" ] &&
            [ "$(stat -c %u "$LOCK_TARGET")" = "$(stat -c %u "$FIREFOX_DIR")" ] ||
            die "$LOCK_TARGET has unsafe ownership or permissions"
    fi
    exec 9>> "$LOCK_TARGET" || die "could not open $LOCK_TARGET"
    chmod 0600 "$LOCK_TARGET"
    flock -n 9 || die "another Godmode lifecycle operation is running"
}

restore_transaction_target() {
    key=$1
    target=$2
    backup="$TRANSACTION_DIR/$key.backup"
    absent="$TRANSACTION_DIR/$key.absent"

    if [ -e "$backup" ] || [ -L "$backup" ]; then
        rm -f "$target" && mv -f "$backup" "$target"
    elif [ -e "$absent" ]; then
        rm -f "$target"
    fi
}

rollback_transaction() {
    [ -e "$TRANSACTION_DIR" ] || return 0
    [ -d "$TRANSACTION_DIR" ] &&
        [ ! -L "$TRANSACTION_DIR" ] &&
        [ "$(stat -c %a "$TRANSACTION_DIR")" = "700" ] &&
        [ "$(stat -c %u "$TRANSACTION_DIR")" = "$(stat -c %u "$FIREFOX_DIR")" ] ||
        return 1

    failed=0
    restore_transaction_target cfg "$CFG_TARGET" || failed=1
    restore_transaction_target pref "$PREF_TARGET" || failed=1
    restore_transaction_target actor "$ACTOR_TARGET" || failed=1
    restore_transaction_target state "$STATE_TARGET" || failed=1
    if [ "$failed" -ne 0 ]; then
        rm -f "$PREF_TARGET"
        return 1
    fi
    rm -rf "$TRANSACTION_DIR"
}

recover_transaction() {
    rollback_transaction || die "transaction recovery failed; backups remain in $TRANSACTION_DIR"
}

begin_transaction() {
    mkdir -m 0700 "$TRANSACTION_DIR" || die "could not create $TRANSACTION_DIR"
}

backup_transaction_target() {
    key=$1
    target=$2
    if [ -e "$target" ] || [ -L "$target" ]; then
        mv -f "$target" "$TRANSACTION_DIR/$key.backup"
    else
        : > "$TRANSACTION_DIR/$key.absent"
    fi
}

check_firefox_installation() {
    [ -f "$FIREFOX_DIR/application.ini" ] || die "$FIREFOX_DIR is not a Firefox installation"
    [ -d "$PREF_DIR" ] || die "$PREF_DIR does not exist"
}

require_firefox_stopped() {
    require_command pgrep
    for process_name in firefox firefox-bin; do
        if pgrep -x "$process_name" >/dev/null 2>&1; then
            die "close all Firefox processes first"
        else
            status=$?
            [ "$status" -eq 1 ] || die "pgrep failed while checking $process_name"
        fi
    done
}

check_autoconfig_conflicts() {
    for pref_file in "$PREF_DIR"/*.js; do
        [ -e "$pref_file" ] || continue
        [ "$pref_file" = "$PREF_TARGET" ] && continue
        if grep -Eq 'general\.config\.(filename|obscure_value|sandbox_enabled)' "$pref_file"; then
            die "conflicting AutoConfig preferences found in $pref_file"
        else
            status=$?
            [ "$status" -eq 1 ] || die "could not inspect $pref_file"
        fi
    done
}

state_for_files() {
    cfg_state=$(cksum < "$1") || return 1
    pref_state=$(cksum < "$2") || return 1
    actor_state=$(cksum < "$3") || return 1
    printf 'format 1 1\ncfg %s\npref %s\nactor %s\n' \
        "$cfg_state" "$pref_state" "$actor_state"
}

recorded_state() {
    awk -v key="$1" '
        $1 == key { print $2 " " $3; found = 1; exit }
        END { if (!found) exit 1 }
    ' "$STATE_TARGET"
}

state_file_is_valid() {
    [ -f "$STATE_TARGET" ] && [ ! -L "$STATE_TARGET" ] || return 1
    case "$(recorded_state format)" in
        "1 0") recorded_state cfg >/dev/null && recorded_state pref >/dev/null ;;
        "1 1") recorded_state cfg >/dev/null && recorded_state pref >/dev/null &&
            recorded_state actor >/dev/null ;;
        *) return 1 ;;
    esac
}

state_tracks_actor() {
    [ "$(recorded_state format)" = "1 1" ]
}

state_matches_file() {
    key=$1
    file=$2
    [ ! -e "$file" ] || [ "$(cksum < "$file")" = "$(recorded_state "$key")" ]
}

state_matches_existing_targets() {
    state_file_is_valid &&
        state_matches_file cfg "$CFG_TARGET" &&
        state_matches_file pref "$PREF_TARGET" &&
        { ! state_tracks_actor || state_matches_file actor "$ACTOR_TARGET"; }
}

state_matches_complete_install() {
    [ -f "$STATE_TARGET" ] && [ ! -L "$STATE_TARGET" ] &&
        state_tracks_actor &&
        [ -f "$CFG_TARGET" ] && [ -f "$PREF_TARGET" ] &&
        [ -f "$ACTOR_TARGET" ] &&
        state_matches_existing_targets
}

file_is_safely_installed() {
    file=$1
    [ -f "$file" ] &&
        [ ! -L "$file" ] &&
        [ "$(stat -c %a "$file")" = "644" ] &&
        [ "$(stat -c %u "$file")" = "$(stat -c %u "$FIREFOX_DIR")" ]
}

installed_files_are_safe() {
    file_is_safely_installed "$CFG_TARGET" &&
        file_is_safely_installed "$PREF_TARGET" &&
        file_is_safely_installed "$ACTOR_TARGET" &&
        file_is_safely_installed "$STATE_TARGET" &&
        [ -f "$LOCK_TARGET" ] &&
        [ ! -L "$LOCK_TARGET" ] &&
        [ "$(stat -c %a "$LOCK_TARGET")" = "600" ] &&
        [ "$(stat -c %u "$LOCK_TARGET")" = "$(stat -c %u "$FIREFOX_DIR")" ]
}

check_untracked_target() {
    target=$1
    source=$2
    if [ -e "$target" ] || [ -L "$target" ]; then
        [ -f "$target" ] && [ ! -L "$target" ] &&
            cmp -s "$source" "$target" ||
            die "$target exists without matching installation state"
    fi
}

check_existing_install() {
    if [ -e "$STATE_TARGET" ] || [ -L "$STATE_TARGET" ]; then
        state_matches_existing_targets || die "installed Godmode files were modified"
        if ! state_tracks_actor; then
            check_untracked_target "$ACTOR_TARGET" "$ACTOR_SOURCE"
        fi
    else
        check_untracked_target "$CFG_TARGET" "$CFG_SOURCE"
        check_untracked_target "$PREF_TARGET" "$PREF_SOURCE"
        check_untracked_target "$ACTOR_TARGET" "$ACTOR_SOURCE"
    fi
}

check_existing_uninstall() {
    if [ -e "$STATE_TARGET" ] || [ -L "$STATE_TARGET" ]; then
        state_matches_existing_targets || die "installed Godmode files were modified"
    else
        check_untracked_target "$CFG_TARGET" "$CFG_SOURCE"
        check_untracked_target "$PREF_TARGET" "$PREF_SOURCE"
    fi
}

should_remove_actor() {
    [ -e "$STATE_TARGET" ] && [ ! -L "$STATE_TARGET" ] && state_tracks_actor
}

current_payload_is_installed() {
    cmp -s "$CFG_SOURCE" "$CFG_TARGET" &&
        cmp -s "$PREF_SOURCE" "$PREF_TARGET" &&
        cmp -s "$ACTOR_SOURCE" "$ACTOR_TARGET"
}
