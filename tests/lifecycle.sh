#!/bin/sh

set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tridactyl-godmode.XXXXXX")
FIREFOX_DIR="$TEST_ROOT/firefox"
BIN_DIR="$TEST_ROOT/bin"
REAL_MV=$(command -v mv)
export REAL_MV

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup 0 1 2 3 15

mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$BIN_DIR/pgrep"
PATH="$BIN_DIR:$PATH"
export PATH

make_firefox() {
    version=$1
    rm -rf "$FIREFOX_DIR"
    mkdir -p "$FIREFOX_DIR/defaults/pref"
    printf '[App]\nVersion=%s\n' "$version" > "$FIREFOX_DIR/application.ini"
}

record_state() {
    cfg_state=$(cksum < "$FIREFOX_DIR/tridactyl-godmode.cfg")
    pref_state=$(cksum < "$FIREFOX_DIR/defaults/pref/tridactyl-godmode.js")
    printf 'format 1 0\ncfg %s\npref %s\n' "$cfg_state" "$pref_state" \
        > "$FIREFOX_DIR/tridactyl-godmode.state"
}

make_firefox 999.0a1
"$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null
"$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null
"$REPO_DIR/verify.sh" "$FIREFOX_DIR" >/dev/null

rm "$FIREFOX_DIR/tridactyl-godmode.cfg"
"$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null
"$REPO_DIR/verify.sh" "$FIREFOX_DIR" >/dev/null

chmod 0666 "$FIREFOX_DIR/tridactyl-godmode.cfg" \
    "$FIREFOX_DIR/tridactyl-godmode.state"
"$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null
"$REPO_DIR/verify.sh" "$FIREFOX_DIR" >/dev/null

printf '\n// Simulated older managed payload.\n' \
    >> "$FIREFOX_DIR/tridactyl-godmode.cfg"
record_state
old_cfg_state=$(cksum < "$FIREFOX_DIR/tridactyl-godmode.cfg")
old_pref_state=$(cksum < "$FIREFOX_DIR/defaults/pref/tridactyl-godmode.js")
old_install_state=$(cksum < "$FIREFOX_DIR/tridactyl-godmode.state")

cat > "$BIN_DIR/mv" <<'EOF'
#!/bin/sh
for argument do
    destination=$argument
done
if [ "${FAIL_MV_TARGET:-}" = "$destination" ] && [ ! -e "$FAIL_MV_MARKER" ]; then
    : > "$FAIL_MV_MARKER"
    exit 1
fi
exec "$REAL_MV" "$@"
EOF
chmod +x "$BIN_DIR/mv"
FAIL_MV_TARGET="$FIREFOX_DIR/defaults/pref/tridactyl-godmode.js"
FAIL_MV_MARKER="$TEST_ROOT/mv-failed"
export FAIL_MV_TARGET FAIL_MV_MARKER
if "$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null 2>&1; then
    printf '%s\n' "Expected injected install failure" >&2
    exit 1
fi
unset FAIL_MV_TARGET FAIL_MV_MARKER
rm "$BIN_DIR/mv"
[ "$(cksum < "$FIREFOX_DIR/tridactyl-godmode.cfg")" = "$old_cfg_state" ]
[ "$(cksum < "$FIREFOX_DIR/defaults/pref/tridactyl-godmode.js")" = "$old_pref_state" ]
[ "$(cksum < "$FIREFOX_DIR/tridactyl-godmode.state")" = "$old_install_state" ]
[ ! -e "$FIREFOX_DIR/.tridactyl-godmode.transaction" ]

mkdir -m 0700 "$FIREFOX_DIR/.tridactyl-godmode.transaction"
mv "$FIREFOX_DIR/tridactyl-godmode.cfg" \
    "$FIREFOX_DIR/.tridactyl-godmode.transaction/cfg.backup"
install -m 0644 "$REPO_DIR/autoconfig/tridactyl-godmode.cfg" \
    "$FIREFOX_DIR/tridactyl-godmode.cfg"

"$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null
"$REPO_DIR/verify.sh" "$FIREFOX_DIR" >/dev/null

printf '\n// Untracked local modification.\n' \
    >> "$FIREFOX_DIR/tridactyl-godmode.cfg"
if "$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null 2>&1; then
    printf '%s\n' "Expected install to reject a modified payload" >&2
    exit 1
fi

make_firefox 155.0b1
"$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null
rm "$FIREFOX_DIR/defaults/pref/tridactyl-godmode.js"
"$REPO_DIR/uninstall.sh" "$FIREFOX_DIR" >/dev/null
[ ! -e "$FIREFOX_DIR/tridactyl-godmode.cfg" ]
[ ! -e "$FIREFOX_DIR/tridactyl-godmode.state" ]

make_firefox 155.0b1
printf '%s\n' 'pref("general.config.filename", "other.cfg");' \
    > "$FIREFOX_DIR/defaults/pref/other.js"
if "$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null 2>&1; then
    printf '%s\n' "Expected install to reject conflicting AutoConfig" >&2
    exit 1
fi

make_firefox 155.0b1
chmod 0777 "$FIREFOX_DIR"
if "$REPO_DIR/install.sh" "$FIREFOX_DIR" >/dev/null 2>&1; then
    printf '%s\n' "Expected install to reject an unsafe target directory" >&2
    exit 1
fi

printf '%s\n' "Install lifecycle tests passed."
