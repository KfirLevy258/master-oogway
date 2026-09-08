#!/usr/bin/env bash
# End-to-end: install into a throwaway HOME, exercise every user-facing command
# in a real interactive login shell, then uninstall.
#
# The unit suite sources plugins directly, which cannot see the class of bug
# that only appears once oh-my-zsh has loaded them for real — a lib nothing
# sources, an alias shadowed by load order, a plugin that ships disabled. That
# is what this catches.
#
# Your own HOME is never touched: everything happens under a mktemp -d, and the
# only shared state is the system clipboard and (on macOS) the real ~/.Trash,
# because /usr/bin/trash always writes there regardless of $HOME.
#
# Usage:  bash test/e2e/run.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OMZ="${ZSH:-$HOME/.oh-my-zsh}"

[[ -d "$OMZ" ]] || { echo "e2e: oh-my-zsh not found at $OMZ" >&2; exit 1; }
command -v script >/dev/null || { echo "e2e: needs script(1) for a pty" >&2; exit 1; }

# script(1) takes its command differently on each platform: util-linux wants
# -c "cmd" with the file last, BSD takes the file then the argv. A login shell
# needs a real pty, so there is no portable way around it.
if script --version 2>&1 | grep -qi util-linux; then
	pty() { script -qec "$*" /dev/null; }
else
	pty() { script -q /dev/null "$@"; }
fi

TH="$(mktemp -d)"
cleanup() { rm -rf "$TH"; }
trap cleanup EXIT

ln -s "$OMZ" "$TH/.oh-my-zsh"
cp -R "$REPO" "$TH/src"
printf '[user]\n\tname = e2e\n\temail = e2e@example.invalid\n' > "$TH/.gitconfig"

echo "── installing into $TH"
( printf '\n\n\n\n\n\n'; sleep 30 ) \
	| pty env HOME="$TH" MO_CONFIG_DIR="$TH/.config/master-oogway" \
		bash "$TH/src/install.sh" --no-recommended-packages >/dev/null 2>&1 || true
[[ -L "$TH/.zshrc" ]] || { echo "e2e: install did not link ~/.zshrc" >&2; exit 1; }

# Turn on the plugins that ship commented out, so the sweep covers them. Match
# a name followed by its trailing comment: the plugins=() block also contains
# prose comments, and uncommenting one of those injects its words as plugin
# names (oh-my-zsh then reports "plugin 'is' not found").
sed -i.bak -E 's/^    # (mo-welcome|mo-trash|mo-search)([[:space:]]+#)/    \1\2/' \
	"$TH/.config/master-oogway/zshrc"

cp "$REPO/test/e2e/feature_sweep.zsh" "$TH/sweep.zsh"

echo "── running the sweep in a real login shell"
out="$TH/out.txt"
( sleep 1; printf 'source $HOME/sweep.zsh\nexit\n'; sleep 240 ) \
	| pty env HOME="$TH" "$(command -v zsh)" -l -i > "$out" 2>&1 || true

tr -d '\r' < "$out" | sed 's/\x1b\[[0-9;]*m//g' | sed -n '/── theme/,$p' \
	| grep -E '──|PASS|FAIL|SKIP|passed:|^    - ' || true

echo "── uninstalling"
( printf 'y\ny\nn\nn\n'; sleep 20 ) \
	| pty env HOME="$TH" MO_CONFIG_DIR="$TH/.config/master-oogway" \
		bash "$TH/src/install.sh" --uninstall >/dev/null 2>&1 || true
for f in .zshrc .zshenv .editorconfig; do
	[[ -L "$TH/$f" ]] && { echo "e2e: --uninstall left $f linked" >&2; exit 1; }
done
echo "── uninstall reversed every managed dotfile"

grep -qE 'failed: 0' <(tr -d '\r' < "$out")
