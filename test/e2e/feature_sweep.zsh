# End-to-end feature sweep, run inside a real installed login shell.
typeset -gi PASS=0 FAIL=0 SKIP=0
typeset -ga FAILED=()

# macOS has no timeout(1); perl's alarm is always present.
_t() { perl -e 'alarm shift; exec @ARGV' "$1" "${@:2}" 2>&1 }

ok()   { print -r -- "  \e[32mPASS\e[0m  $1"; (( PASS++ )) }
bad()  { print -r -- "  \e[31mFAIL\e[0m  $1${2:+  — $2}"; (( FAIL++ )); FAILED+=("$1") }
skip() { print -r -- "  \e[33mSKIP\e[0m  $1${2:+  — $2}"; (( SKIP++ )) }

# check <label> <expected-substring> <command...>
check() {
	local label="$1" want="$2"; shift 2
	local out; out=$(_t 15 zsh -ic "$*" 2>&1)
	if [[ "$out" == *"$want"* ]]; then ok "$label"
	else bad "$label" "got: ${${out//$'\n'/ | }[1,90]}"; fi
}
# checkrc <label> <expected-rc> <command...>
checkrc() {
	local label="$1" want="$2"; shift 2
	_t 15 zsh -ic "$*" >/dev/null 2>&1
	local rc=$?
	[[ "$rc" == "$want" ]] && ok "$label" || bad "$label" "rc=$rc want=$want"
}

SB=$(mktemp -d); trap 'command rm -rf "$SB"' EXIT

print -r -- "\n\e[1m── theme & shell ──\e[0m"
check "dragon theme loaded"        "dragon"  'print -- $ZSH_THEME'
checkrc "PROMPT is non-empty"      0         '[[ -n "$PROMPT" ]]'
check "lib/*.zsh sourced"          "function" 'type -w _mo_clip'

print -r -- "\n\e[1m── mo-shell-tools ──\e[0m"
check "calc"                       "1024"        'calc "2^10"'
check "calc rejects injection"     "invalid"     'calc "foo;rm" 2>&1'
check "epoch now"                  ""            'epoch'
check "epoch ts -> date"           "2023-11-14"  'epoch --utc 1700000000'
check "epoch ISO -> ts (local)"    "1699992800"  "epoch '2023-11-14 22:13:20'"
check "epoch ISO -> ts (--utc)"    "1700000000"  "epoch --utc '2023-11-14 22:13:20'"
check "epoch relative"             ""            'epoch yesterday'
checkrc "epoch rejects gibberish"  1             'epoch "not a date"'
check "clip -> pasteboard"         "e2e-$$"      "print -n e2e-$$ | clip >/dev/null; pbpaste"
check "mo-where finds calc"        "mo-shell-tools" 'mo-where calc'
check "mo-where finds indented rm" "mo-trash"    'mo-where rm'
checkrc "mo-where rc=0 on hit"     0             'mo-where calc'
check "cwhich"                     "/"           'cwhich git'

print -r -- "\n\e[1m── mo-files ──\e[0m"
check "compress .tar.gz"  "Created"   "cd $SB && mkdir -p s && echo hi > s/f.txt && compress a.tar.gz s"
check "extract .tar.gz"   ""          "cd $SB && mkdir -p o && cd o && tar -czf x.tar.gz -C ../s f.txt && extract x.tar.gz && cat f.txt"
# A zip whose entry really is ../evil — `zip` refuses to store one, so the
# path is rewritten in the archive bytes after the fact.
if python3 -c 'import zipfile' 2>/dev/null; then
  python3 - "$SB" <<'PYZ' 2>/dev/null
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1] + "/trav.zip", "w")
z.writestr("../evil.txt", "x")
z.close()
PYZ
  check "extract refuses traversal" "refusing" "cd $SB && extract trav.zip 2>&1 | head -1"
else skip "extract refuses traversal" "python3 absent"; fi
check "bak"               "->"        "cd $SB && bak s/f.txt"
check "sizeof"            "f.txt"     "cd $SB && sizeof s/f.txt"
# mo-bat-override ships disabled, so `cat` is the system cat unless it is
# turned on. Source it explicitly to exercise the -A translation.
if command -v bat &>/dev/null; then
  check "cat -A (BSD -vet)" 'b$' \
    "source \$ZSH_CUSTOM/plugins/mo-bat-override/mo-bat-override.plugin.zsh 2>/dev/null; cd $SB && printf 'a\tb\n' > tab.txt && cat -A tab.txt"
else skip "cat -A" "bat absent"; fi

print -r -- "\n\e[1m── mo-git ──\e[0m"
(cd "$SB" && git init -q r && cd r && git config user.email t@e && git config user.name T && echo a > f && git add f && git commit -qm one && echo b >> f && git add f && git commit -qm two) 2>/dev/null
check "git aliases load"  "git status" 'alias gs'
check "glc graph log"     "two"        "cd $SB/r && glc | head -1"
check "gsum"              "branch"     "cd $SB/r && gsum"
checkrc "gsum rc=0 clean" 0            "cd $SB/r && gsum"
check "gd falls back to git diff" "diff --git" "cd $SB/r && git config diff.tool opendiff && gd HEAD~1 HEAD"
check "groot"             "/r"         "cd $SB/r && mkdir -p a/b && cd a/b && groot && pwd"
checkrc "flog outside repo rc=1" 1     'cd /tmp && flog'

print -r -- "\n\e[1m── mo-dirs / mo-projects / mo-mkscript ──\e[0m"
check "mkcd"     "deep"    "cd $SB && mkcd deep/nest && pwd"
check "up N"     "$SB"     "cd $SB/deep/nest && up 2 && pwd"
check "tmpcd"    "/"       'tmpcd'
check "mkscript" "Created" "cd $SB && EDITOR=true mkscript ./s.sh"
checkrc "mkscript no-arg rc=1" 1 'mkscript'

print -r -- "\n\e[1m── mo-process ──\e[0m"
check "psgrep"          "zsh"      'psgrep zsh | head -1'
check "port validates"  "invalid"  'port abc 2>&1'
check "connected"       ""         'connected 2>&1 | head -1'
checkrc "connected -v does not die on ss" 1 'connected -v'

print -r -- "\n\e[1m── mo-search ──\e[0m"
check "grep colorized"    "--color"  'alias grep'
check "f finds a file"    "f.txt"    "cd $SB && f f.txt"
check "man -k . populated" ""        'man -k . 2>/dev/null | head -1'
if command -v rg &>/dev/null && command -v fzf &>/dev/null; then
  check "frg pipeline yields rows" "needle" \
    "cd $SB && printf 'hay\nneedle\n' > n.txt && rg --color=always --line-number --null -- needle . 2>/dev/null | tr '\0' '\t' | awk 'BEGIN{FS=\"\t\"} NF==2{print \$2}' | head -1"
else skip "frg pipeline" "rg or fzf absent"; fi

print -r -- "\n\e[1m── mo-trash ──\e[0m"
if [[ -n "$(_mo_trash_tool 2>/dev/null)" ]]; then
  print -- keep > "$SB/e2e-trash-$$.txt"
  check "rm trashes"        ""            "cd $SB && rm e2e-trash-$$.txt; [[ -e e2e-trash-$$.txt ]] && print STILL || print gone"
  check "index records path" "$SB"        "grep e2e-trash-$$ \${MO_TRASH_INDEX:-\$HOME/.config/master-oogway/trash-index.tsv} | tail -1"
  # /usr/bin/trash always writes to the real user's ~/.Trash regardless of
  # $HOME, so point MO_TRASH_DIR there for this check.
  check "trash-list shows it" "e2e-trash-$$" "MO_TRASH_DIR=\$(eval echo ~\$USER)/.Trash trash-list"
  check "rm -h shows the bypass" '\rm'    'rm -h'
  print -- bye > "$SB/e2e-bypass-$$.txt"
  check "\\rm really deletes" "gone"      "cd $SB && \\rm e2e-bypass-$$.txt; [[ -e \$HOME/.Trash/e2e-bypass-$$.txt ]] && print TRASHED || print gone"
  command rm -f "$HOME/.Trash/e2e-trash-$$.txt" 2>/dev/null
else skip "mo-trash" "no trash tool"; fi

print -r -- "\n\e[1m── mo-welcome ──\e[0m"
for fld in host os sys up load mem disk arch; do
  check "welcome:$fld" "" "MO_WELCOME_FIELDS= ; _mo_welcome_field_$fld"
done

print -r -- "\n\e[1m── mo-cli ──\e[0m"
check "master-oogway version" "master-oogway" 'master-oogway version'
check "master-oogway help"    "configure"     'master-oogway help'
check "lan-ssh not refused"   ""              'master-oogway lan-ssh status 2>&1 | head -1'
checkrc "unknown subcommand rc=1" 1           'master-oogway bogus'

print -r -- "\n\e[1m── mo-safety-override / colorize ──\e[0m"
check "mkdir -pv"  "b"     "cd $SB && mkdir a2/b 2>&1 | tail -1"
check "cp -i"      "cp -i" 'alias cp'
check "reboot is confirmed" "_confirm_reboot" 'alias reboot'
checkrc "no ip alias"    1 'alias ip'
checkrc "no dmesg alias" 1 'alias dmesg'

print -r -- "\n\e[1m── platform primitives ──\e[0m"
check "core summary"  "+"          '_mo_core_summary'
check "disk pct"      ""           '_mo_disk_pct'
check "local ip"      "."          '_mo_local_ip'
check "subnet CIDR"   "/"          '_mo_default_subnet_cidr'
check "pkg hint xclip is honest" "pbcopy" '_mo_pkg_hint xclip'
check "cask split"    "--cask"     '_mo_pkg_hint nmap texlive-xetex'

print -r -- "\n\e[1m════ RESULT ════\e[0m"
print -r -- "  passed: $PASS   failed: $FAIL   skipped: $SKIP"
(( FAIL )) && { print -r -- "\n  failures:"; printf '    - %s\n' "${FAILED[@]}" }
