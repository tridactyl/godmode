#!/bin/sh

set -eu

[ "$#" -le 1 ] || {
    printf '%s\n' "usage: $0 [FIREFOX_DIR]" >&2
    exit 2
}
[ "$#" -eq 0 ] || [ -n "$1" ] || {
    printf '%s\n' "error: FIREFOX_DIR cannot be empty" >&2
    exit 2
}

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$REPO_DIR/scripts/common.sh"

set_firefox_paths "${1:-${FIREFOX_DIR:-/usr/lib/firefox-developer-edition}}"
require_command awk
require_command cksum
require_command cmp
require_command grep
require_command id
require_command install
require_command flock
require_command stat
check_firefox_installation
require_firefox_stopped
[ -f "$PREF_SOURCE" ] && [ -f "$CFG_SOURCE" ] && [ -f "$ACTOR_SOURCE" ] ||
    die "AutoConfig source files are missing"
[ -w "$FIREFOX_DIR" ] && [ -w "$PREF_DIR" ] || die "installation is not writable; run this script with sudo"
check_install_directories
check_install_identity
acquire_install_lock
recover_transaction
check_existing_install
check_autoconfig_conflicts

if current_payload_is_installed && state_matches_complete_install && installed_files_are_safe; then
    printf '%s\n' "Tridactyl Godmode is already installed in $FIREFOX_DIR"
    exit 0
fi

begin_transaction
CFG_TMP="$TRANSACTION_DIR/cfg.new"
PREF_TMP="$TRANSACTION_DIR/pref.new"
STATE_TMP="$TRANSACTION_DIR/state.new"
ACTOR_TMP="$TRANSACTION_DIR/actor.new"
SUCCESS=0

cleanup() {
    status=$?
    set +e
    if [ "$SUCCESS" -ne 1 ]; then
        if ! rollback_transaction; then
            printf '%s\n' "error: rollback failed; backups remain in $TRANSACTION_DIR" >&2
        fi
    fi
    return "$status"
}
trap cleanup 0
trap 'exit 1' 1 2 3 15

install -m 0644 "$CFG_SOURCE" "$CFG_TMP"
install -m 0644 "$PREF_SOURCE" "$PREF_TMP"
install -m 0644 "$ACTOR_SOURCE" "$ACTOR_TMP"
state_for_files "$CFG_TMP" "$PREF_TMP" "$ACTOR_TMP" > "$STATE_TMP"
chmod 0644 "$STATE_TMP"

backup_transaction_target cfg "$CFG_TARGET"
mv -f "$CFG_TMP" "$CFG_TARGET"

backup_transaction_target pref "$PREF_TARGET"
mv -f "$PREF_TMP" "$PREF_TARGET"

backup_transaction_target actor "$ACTOR_TARGET"
mv -f "$ACTOR_TMP" "$ACTOR_TARGET"

backup_transaction_target state "$STATE_TARGET"
mv -f "$STATE_TMP" "$STATE_TARGET"

cmp -s "$CFG_SOURCE" "$CFG_TARGET" || die "failed to verify $CFG_TARGET"
cmp -s "$PREF_SOURCE" "$PREF_TARGET" || die "failed to verify $PREF_TARGET"
cmp -s "$ACTOR_SOURCE" "$ACTOR_TARGET" || die "failed to verify $ACTOR_TARGET"
state_matches_complete_install || die "failed to verify $STATE_TARGET"
installed_files_are_safe || die "installed files have unsafe metadata"

SUCCESS=1
rm -rf "$TRANSACTION_DIR"
trap - 0 1 2 3 15

printf '%s\n' "Installed Tridactyl Godmode AutoConfig in $FIREFOX_DIR"
printf '%s\n' "Start Firefox and run ./verify.sh '$FIREFOX_DIR' to verify the installed files."
