#!/bin/sh
# Sets up tern-omp-groups: the Tern plugin, the omp title rule, Tern's status line and the omp
# reload hook. Run it again to update. See `install.sh --help`.
set -eu

REPO=github.com/vishiod/tern-omp-groups
PLUGIN=omp-groups
OMP_DIR="$HOME/.omp/agent"
RULE="$OMP_DIR/TITLE_SYSTEM.md"
# shellcheck disable=SC2016 # literal backquotes: the first line of omp/TITLE_SYSTEM.md
RULE_MARK='Write a session title as `<CODE>: <title>`'
HOOK="$OMP_DIR/hooks/post/tern-omp-groups.ts"
STATE_DIR="$HOME/.local/state/tern-omp-groups"
SETTINGS="${TERN_CONFIG_DIR:-$HOME/Library/Application Support/Tern}/settings.json"

usage() {
	cat <<'EOF'
Usage: install.sh [--dev | --uninstall]

  (no option)   Install or update the plugin from GitHub, then set up omp and Tern.
  --dev         Link this checkout instead, so Tern reloads the plugin when you save a file.
  --uninstall   Remove the plugin, the title rule, the reload hook and the hook state.

Steps: install the plugin, install the omp title rule (your own rule is kept as
TITLE_SYSTEM.md.bak), turn on Tern's status line, install the omp reload hook, check.
EOF
}

say() { printf '%s\n' "$*"; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

mode=install
case "${1:-}" in
"") ;;
--dev) mode=dev ;;
--uninstall) mode=uninstall ;;
-h | --help)
	usage
	exit 0
	;;
*) die "unknown option $1 (see --help)" ;;
esac

command -v tern >/dev/null 2>&1 || die "tern is not on PATH. Get Tern at https://stencil.so/tern, then run:
  ln -s /Applications/Tern.app/Contents/MacOS/tern /opt/homebrew/bin/tern"

is_our_rule() { [ -f "$1" ] && grep -qF "$RULE_MARK" "$1"; }

if [ "$mode" = uninstall ]; then
	tern plugin remove "$PLUGIN" >/dev/null 2>&1 || tern plugin unlink "$PLUGIN" >/dev/null 2>&1 || true
	if [ -f "$RULE.bak" ]; then
		mv "$RULE.bak" "$RULE"
		say "Restored your title rule from $RULE.bak"
	elif [ -L "$RULE" ] || is_our_rule "$RULE"; then
		rm -f "$RULE"
	fi
	rm -f "$HOOK"
	rm -rf "$STATE_DIR"
	say "Removed $PLUGIN. Sessions the plugin made stay in Tern."
	exit 0
fi

# 1. Plugin. A linked copy and an installed copy cannot both exist.
if [ "$mode" = dev ]; then
	src=$(cd "$(dirname "$0")" && pwd)
	[ -f "$src/plugin.toml" ] || die "--dev needs a checkout. Run ./install.sh --dev in the repository."
	tern plugin remove "$PLUGIN" >/dev/null 2>&1 || true
	tern plugin unlink "$PLUGIN" >/dev/null 2>&1 || true
	tern plugin link "$src"
else
	tern plugin unlink "$PLUGIN" >/dev/null 2>&1 || true
	tern plugin install "$REPO" --force
	src="$(tern plugin dir)/$PLUGIN"
fi
[ -f "$src/omp/TITLE_SYSTEM.md" ] || die "plugin files not found in $src"

# 2. omp title rule. A rule that is not ours is kept as a backup once.
mkdir -p "$OMP_DIR"
if [ -f "$RULE" ] && [ ! -L "$RULE" ] && ! is_our_rule "$RULE" && [ ! -e "$RULE.bak" ]; then
	cp "$RULE" "$RULE.bak"
	say "Kept your title rule as $RULE.bak"
fi
rm -f "$RULE"
if [ "$mode" = dev ]; then
	ln -s "$src/omp/TITLE_SYSTEM.md" "$RULE"
else
	cp "$src/omp/TITLE_SYSTEM.md" "$RULE"
fi

# 3. Tern's status line, which shows the history button. Tern reads settings.json again on change.
if [ -f "$SETTINGS" ] && grep -q '"status_bar"[[:space:]]*:[[:space:]]*true' "$SETTINGS"; then
	:
elif command -v osascript >/dev/null 2>&1; then
	mkdir -p "$(dirname "$SETTINGS")"
	osascript -l JavaScript - "$SETTINGS" >/dev/null <<'JS' || die "could not turn on the status line in $SETTINGS. Add \"status_bar\": true by hand."
ObjC.import("Foundation");
function run(argv) {
	const path = argv[0];
	const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
	const settings = text.isNil() || text.js.trim() === "" ? {} : JSON.parse(text.js);
	settings.status_bar = true;
	const out = $(JSON.stringify(settings, null, 2) + "\n");
	if (!out.writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)) {
		throw new Error("write failed");
	}
}
JS
	say "Turned on Tern's status line"
else
	say "NOTE: add \"status_bar\": true to $SETTINGS to show the history button."
fi

# 4. omp reload hook. omp skips symlinked hooks, so this file re-exports the plugin's hook.
mkdir -p "$(dirname "$HOOK")"
printf 'export { default } from "%s";\n' "$src/omp/reload-hook.ts" >"$HOOK"

# 5. Check.
line=$(tern plugin list 2>/dev/null | grep "^$PLUGIN " || true)
case "$line" in
*ready*) ;;
*) die "the plugin did not load: ${line:-not listed}. Run: tern plugin reload" ;;
esac
command -v omp >/dev/null 2>&1 || say "NOTE: omp is not on PATH. Install it: curl -fsSL https://omp.sh/install | sh"

say "Done: $line"
say "Try it in a Tern pane: omp \"Start work on ABC-123: add a rate limit field. Reply OK only.\""
