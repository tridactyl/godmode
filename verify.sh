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

if [ "$#" -eq 0 ]; then
    require_command node
    node --check < "$REPO_DIR/autoconfig/tridactyl-godmode.cfg"
    node --check < "$REPO_DIR/autoconfig/defaults/pref/tridactyl-godmode.js"
    node --check "$REPO_DIR/autoconfig/tridactyl-godmode-key-handoff-child.sys.mjs"
    node "$REPO_DIR/tests/autoconfig.test.js"
    node "$REPO_DIR/tests/key-handoff-actor.test.mjs"
    sh "$REPO_DIR/tests/lifecycle.sh"
    sh -n "$REPO_DIR/scripts/common.sh"
    sh -n "$REPO_DIR/tests/lifecycle.sh"
    sh -n "$REPO_DIR/install.sh"
    sh -n "$REPO_DIR/uninstall.sh"
    sh -n "$REPO_DIR/verify.sh"
    printf '%s\n' "Source verification passed."
    exit 0
fi

set_firefox_paths "$1"
require_command awk
require_command cksum
require_command cmp
require_command grep
require_command stat
check_firefox_installation
check_install_directories
[ ! -e "$TRANSACTION_DIR" ] || die "an incomplete transaction must be recovered with install.sh or uninstall.sh"
check_autoconfig_conflicts
current_payload_is_installed || die "installed files differ from the repository payload"
state_matches_complete_install || die "installation state is missing or invalid"
installed_files_are_safe || die "installed files have unsafe metadata"

printf '%s\n' "Installed files match the repository payload."
