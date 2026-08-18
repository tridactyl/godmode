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
require_command flock
require_command id
require_command stat
check_firefox_installation
require_firefox_stopped
[ -w "$FIREFOX_DIR" ] && [ -w "$PREF_DIR" ] || die "installation is not writable; run this script with sudo"
check_install_directories
check_install_identity
acquire_install_lock
recover_transaction
check_existing_uninstall

rm -f "$PREF_TARGET"
[ ! -e "$PREF_TARGET" ] || die "failed to remove $PREF_TARGET"
rm -f "$CFG_TARGET"
[ ! -e "$CFG_TARGET" ] || die "failed to remove $CFG_TARGET"
if should_remove_actor; then
    rm -f "$ACTOR_TARGET"
    [ ! -e "$ACTOR_TARGET" ] || die "failed to remove $ACTOR_TARGET"
fi
rm -f "$STATE_TARGET"
[ ! -e "$STATE_TARGET" ] || die "failed to remove $STATE_TARGET"
rm -f "$LOCK_TARGET"

printf '%s\n' "Removed Tridactyl Godmode AutoConfig from $FIREFOX_DIR"
