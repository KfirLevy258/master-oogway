# Every plugin loads, parses, and its commands behave. Assertions that depend
# on the OS are branched, so this suite is meaningful on Linux and macOS alike.

_mo_t() {
	local plug="$1"; shift
	zsh -c "
		setopt EXTENDED_GLOB
		export ZSH_CUSTOM='$MO_ROOT/omz-custom'
		for f in '$MO_ROOT'/omz-custom/lib/*.zsh(#qN); do source \$f; done
		source '$MO_ROOT/omz-custom/plugins/$plug/$plug.plugin.zsh' 2>/dev/null
		$*
	" 2>&1
}

source "$MO_ROOT/omz-custom/lib/platform.zsh"

# ── every plugin parses and documents itself ─────────────────────────────────
local d n
for d in "$MO_ROOT"/omz-custom/plugins/mo-*(N/); do
	n="${d:t}"
	assert_ok "$n parses"     zsh -n "$d/$n.plugin.zsh"
	assert_ok "$n has README" test -f "$d/README.md"
done

# ── the platform-sensitive behaviour ─────────────────────────────────────────
assert_eq "1024" "$(_mo_t mo-shell-tools 'calc "2^10"')" "calc works"

assert_contains "$(_mo_t mo-shell-tools 'epoch --utc 1700000000')" "2023-11-14 22:13:20" \
	"epoch renders an epoch in UTC"
assert_eq "1700000000" "$(TZ=Asia/Jerusalem _mo_t mo-shell-tools "epoch --utc '2023-11-14 22:13:20'")" \
	"epoch parses an ISO datetime as UTC when asked"
assert_eq "1699992800" "$(TZ=Asia/Jerusalem _mo_t mo-shell-tools "epoch '2023-11-14 22:13:20'")" \
	"epoch parses a bare ISO datetime as local time"

# clip must actually reach the clipboard, not fall through to printing.
# Save and restore it: running the suite should not cost the tester whatever
# they had copied.
if _mo_is_macos || _mo_paste >/dev/null 2>&1; then
	local _saved_clip
	_saved_clip=$(_mo_paste 2>/dev/null)
	_mo_t mo-shell-tools "print -- clip-probe-$$ | clip" >/dev/null 2>&1
	assert_eq "clip-probe-$$" "$(_mo_paste)" "clip writes to the system clipboard"
	[[ -n "$_saved_clip" ]] && _mo_clip "$_saved_clip"
else
	print -r -- "  skip   clip writes to the system clipboard (no clipboard tool)"
fi

assert_match "$(_mo_t mo-build '_mo_build_jobs_value')" '^[0-9]+$' "build job count is numeric"
assert_true "build uses more than one core" "$(_mo_t mo-build '_mo_build_jobs_value') > 1"

# extract, for both a GNU-flag-sensitive and a compressed-variant archive.
local td=$(mktemp -d); command mkdir -p "$td/s" "$td/o"; print -- hi > "$td/s/f.txt"
tar -czf "$td/a.tar.gz" -C "$td/s" f.txt
_mo_t mo-files "cd '$td/o' && extract '$td/a.tar.gz'" >/dev/null
assert_eq "hi" "$(command cat "$td/o/f.txt" 2>/dev/null)" "extract handles .tar.gz"
command rm -rf "$td"

assert_contains "$(_mo_t mo-process 'psgrep zsh')" "zsh" "psgrep finds a running zsh"
assert_contains "$(_mo_t mo-git 'alias gs')" "git status" "git aliases load"

# ── platform-specific expectations ───────────────────────────────────────────
if _mo_is_macos; then
	assert_eq "" "$(_mo_t mo-colorize-override 'alias ip 2>/dev/null')" \
		"no ip alias on macOS, which has no ip"
	assert_eq "" "$(_mo_t mo-colorize-override 'alias dmesg 2>/dev/null')" \
		"no dmesg alias on macOS, whose dmesg takes no --color"
	# NEVER `lan-ssh setup` here. It is not a query: it writes a SendEnv
	# stanza into the tester's ~/.ssh/config, installs a crontab entry and
	# tries to drop a file into /etc/ssh/sshd_config.d. An earlier version of
	# this assertion relied on macOS refusing the whole subcommand; when the
	# refusal was removed the test silently began configuring the machine it
	# was running on. `status` and `help` only read.
	assert_not_contains "$(_mo_t mo-cli 'master-oogway lan-ssh status' 2>&1)" \
		"not supported on macOS" "lan-ssh is available on macOS"
	assert_contains "$(_mo_t mo-cli 'master-oogway lan-ssh help' 2>&1)" "lan-ssh" \
		"lan-ssh help renders"
	# The one genuinely platform-specific piece: deriving the LAN CIDR without
	# iproute2. Format only — the value depends on the tester's network.
	assert_match "$(MO_LAN_SUBNET= bash -c '
		'"$(sed -n '/^detect_subnet()/,/^}$/p' "$MO_ROOT/omz-custom/plugins/mo-cli/lan_scan.sh")"'
		SUBNET=""; detect_subnet' 2>/dev/null)" \
		'^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' \
		"lan_scan derives a CIDR subnet without iproute2"
	assert_contains "$(_mo_t mo-brew 'type bup')" "bup" "mo-brew loads on macOS"
else
	assert_eq "" "$(_mo_t mo-brew 'type bup 2>/dev/null')" "mo-brew declines on Linux"
fi

assert_contains "$(_mo_t mo-colorize-override 'alias grep')" "--color=auto" "grep is colorized"

# ── no plugin may hardcode a package manager ─────────────────────────────────
assert_eq "" "$(command grep -rln 'sudo apt install' $MO_ROOT/omz-custom/plugins/mo-*/ 2>/dev/null \
	| xargs -I{} sh -c 'command grep -q "platform-lint:" {} || echo {}')" \
	"no plugin hardcodes apt outside a declared Linux-only file"
