source "$MO_ROOT/omz-custom/lib/platform.zsh"

# -- cpu ------------------------------------------------------------------------
assert_match "$(_mo_cpu_count)" '^[0-9]+$' "cpu_count is an integer"
assert_true "cpu_count > 0" "$(_mo_cpu_count) > 0"

typeset -a pe=( ${(z)$(_mo_perf_cores)} )
assert_eq 2 ${#pe} "perf_cores returns two fields"
assert_match "${pe[1]}" '^[0-9]+$' "perf cores integer"
assert_match "${pe[2]}" '^[0-9]+$' "efficiency cores integer"

# -- memory ---------------------------------------------------------------------
typeset -a mem=( ${(z)$(_mo_mem_stats)} )
assert_eq 2 ${#mem} "mem_stats returns two fields"
assert_true "mem total > 0" "${mem[2]} > 0"
assert_true "mem used in range" "${mem[1]} > 0 && ${mem[1]} <= ${mem[2]}"

# -- load / uptime --------------------------------------------------------------
assert_match "$(_mo_load_avg)" '^[0-9]+\.[0-9]+$' "load_avg is decimal"
assert_match "$(_mo_uptime_secs)" '^[0-9]+$' "uptime_secs is an integer"
assert_true "uptime > 0" "$(_mo_uptime_secs) > 0"

# -- identity -------------------------------------------------------------------
if _mo_is_macos; then
	assert_contains "$(_mo_os_name)" "macOS" "os_name reports the macOS product version"
else
	assert_true "os_name is non-empty on Linux" "${#$(_mo_os_name)} > 0"
fi
assert_match "$(_mo_kernel)" '^[0-9]+\.' "kernel looks like a version"

# -- dates ----------------------------------------------------------------------
assert_eq "2023-11-14 22:13:20" "$(_mo_epoch_to_date 1700000000 --utc)" "epoch_to_date UTC"
assert_eq 1700000000 "$(_mo_date_to_epoch '2023-11-14 22:13:20')" "date_to_epoch roundtrip"

# -- clipboard ------------------------------------------------------------------
_mo_clip "mo-clip-test-$$"
assert_eq "mo-clip-test-$$" "$(_mo_paste)" "clip roundtrip"

# -- sed ------------------------------------------------------------------------
local tmp=$(mktemp)
print -l -- alpha beta gamma > "$tmp"
_mo_sed_inplace '/beta/d' "$tmp"
assert_eq "alpha
gamma" "$(command cat "$tmp")" "sed_inplace deletes a line"
command rm -f "$tmp"

# -- untar ----------------------------------------------------------------------
local td=$(mktemp -d)
mkdir -p "$td/src" "$td/out"
print -- hello > "$td/src/f.txt"
tar -czf "$td/a.tar.gz" -C "$td/src" f.txt
_mo_untar "$td/a.tar.gz" "$td/out"
assert_eq "hello" "$(command cat "$td/out/f.txt")" "untar extracts"
command rm -rf "$td"

# -- brew -----------------------------------------------------------------------
if _mo_is_macos; then
	assert_match "$(_mo_brew_prefix)" '^(/opt/homebrew|/usr/local)?$' "brew_prefix is a known location"
fi

# -- local ip -------------------------------------------------------------------
assert_match "$(_mo_local_ip)" '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^$' "local_ip is IPv4 or empty"

# Core tier names are read from the chip, never assumed: M1-M4 report
# Performance/Efficiency, M5 reports Super/Performance.
assert_match "$(_mo_core_summary)" '^[0-9]+[A-Z]\+[0-9]+[A-Z]$|^[0-9]+$' "core_summary is well-formed"
if _mo_is_macos; then
	typeset -a cn=( ${(z)$(_mo_perf_core_names)} )
	assert_true "perf_core_names returns two names on Apple Silicon" "${#cn} == 2"
fi

# -- platform detection ---------------------------------------------------------
assert_match "$_MO_PLATFORM" '^(linux|macos)$' "platform is detected"
assert_contains "$(_mo_pkg_hint fzf)" "fzf" "pkg_hint names the package"
if _mo_is_macos; then
	assert_contains "$(_mo_pkg_hint fzf)" "brew install" "macOS hint uses brew"
else
	assert_contains "$(_mo_pkg_hint fzf)" "apt install"  "Linux hint uses apt"
fi
