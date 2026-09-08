# Platform primitives — the one place OS differences live.
#
# Nothing under plugins/ or themes/ may call `uname`, read /proc, or use a
# GNU-only flag; it calls a primitive here instead. test/lint_platform.zsh
# enforces that. Keeping the branches in one file means each plugin reads the
# same on every OS, and a third platform is one file rather than a 22-file
# audit.
#
# Each function pairs the Linux implementation (the behaviour master-oogway
# already had) with its macOS counterpart, so the two are reviewable together.

typeset -g _MO_PLATFORM
case "$(command uname -s)" in
	Linux)  _MO_PLATFORM=linux  ;;
	Darwin) _MO_PLATFORM=macos  ;;
	*)      _MO_PLATFORM=linux  ;;   # BSDs are closer to Linux here than to macOS
esac

_mo_is_macos() { [[ "$_MO_PLATFORM" == macos ]] }
_mo_is_linux() { [[ "$_MO_PLATFORM" == linux ]] }

# -- clipboard ------------------------------------------------------------------
_mo_clip() {
	local data="${1}"
	if _mo_is_macos; then
		printf '%s' "$data" | pbcopy
		return
	fi
	if command -v wl-copy &>/dev/null; then
		printf '%s' "$data" | wl-copy
	elif command -v xclip &>/dev/null; then
		printf '%s' "$data" | xclip -selection clipboard
	elif command -v xsel &>/dev/null; then
		printf '%s' "$data" | xsel --clipboard --input
	else
		echo "_mo_clip: no clipboard tool found (try: sudo apt install wl-clipboard)" >&2
		return 1
	fi
}

_mo_paste() {
	if _mo_is_macos; then
		pbpaste
	elif command -v wl-paste &>/dev/null; then
		wl-paste
	elif command -v xclip &>/dev/null; then
		xclip -selection clipboard -o
	else
		return 1
	fi
}

# -- gui ------------------------------------------------------------------------
_mo_open() {
	if _mo_is_macos; then
		open "$@"
	else
		command -v xdg-open &>/dev/null \
			|| { echo "_mo_open: xdg-open not found (install xdg-utils)" >&2; return 1; }
		xdg-open "$@"
	fi
}

# -- dates ----------------------------------------------------------------------
# GNU date takes -d for both epoch and free-form input; BSD date needs -r for an
# epoch and -j -f with an explicit format for parsing, and cannot parse natural
# language at all.
_mo_epoch_to_date() {
	local epoch="$1"; shift
	local -a flags=()
	[[ "${1:-}" == "--utc" ]] && flags=(-u)
	if _mo_is_macos; then
		date $flags -r "$epoch" '+%Y-%m-%d %H:%M:%S'
	else
		date $flags -d "@$epoch" '+%Y-%m-%d %H:%M:%S'
	fi
}

# Returns 1 when the input cannot be parsed, so callers can report it.
_mo_date_to_epoch() {
	local input="$1"; shift
	if _mo_is_macos; then
		date -u -j -f '%Y-%m-%d %H:%M:%S' "$input" '+%s' 2>/dev/null
	else
		date -d "$input" '+%s' 2>/dev/null
	fi
}

# True when the platform's date can parse free-form input like "yesterday".
_mo_date_parses_natural_language() { _mo_is_linux }

# -- cpu ------------------------------------------------------------------------
_mo_cpu_count() {
	if _mo_is_macos; then
		sysctl -n hw.logicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || print -- 1
	else
		nproc 2>/dev/null || command grep -c '^processor' /proc/cpuinfo 2>/dev/null || print -- 1
	fi
}

# Apple Silicon splits cores into performance levels, so a flat count misleads.
# Returns "<level0> <level1>"; on Linux and Intel the second field is 0.
_mo_perf_cores() {
	if _mo_is_macos; then
		local p e
		p=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null) || p=""
		e=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null) || e=""
		if [[ -n "$p" && -n "$e" ]]; then
			print -- "$p $e"
			return
		fi
	fi
	print -- "$(_mo_cpu_count) 0"
}

# The tier names are not fixed across chips: M1-M4 report Performance and
# Efficiency, M5 reports Super and Performance. Read them rather than assume.
_mo_perf_core_names() {
	_mo_is_macos || return 1
	local n0 n1
	n0=$(sysctl -n hw.perflevel0.name 2>/dev/null) || n0=""
	n1=$(sysctl -n hw.perflevel1.name 2>/dev/null) || n1=""
	[[ -n "$n0" && -n "$n1" ]] && print -- "$n0 $n1"
}

# Display string for a core count: "6S+12P" on an M5 Pro, "10P+8E" on an M3
# Pro, a plain count on Linux and Intel.
_mo_core_summary() {
	local -a counts names
	counts=( ${(z)$(_mo_perf_cores)} )
	names=(  ${(z)$(_mo_perf_core_names 2>/dev/null)} )
	if (( ${#names} == 2 )) && (( counts[2] > 0 )); then
		print -- "${counts[1]}${names[1][1]}+${counts[2]}${names[2][1]}"
	else
		print -- "$(_mo_cpu_count)"
	fi
}

# -- memory ---------------------------------------------------------------------
# Returns "<used_bytes> <total_bytes>". Linux uses MemAvailable, which accounts
# for reclaimable cache; macOS counts active + wired + compressed, which is what
# Activity Monitor calls memory in use.
_mo_mem_stats() {
	local used=0 total=0
	if _mo_is_macos; then
		local pagesize
		total=$(sysctl -n hw.memsize 2>/dev/null)  || total=0
		pagesize=$(sysctl -n hw.pagesize 2>/dev/null) || pagesize=4096
		if command -v vm_stat &>/dev/null; then
			used=$(vm_stat 2>/dev/null | awk -v ps="$pagesize" '
				/Pages active/                 {gsub(/\./,"",$3); a=$3}
				/Pages wired down/             {gsub(/\./,"",$4); w=$4}
				/Pages occupied by compressor/ {gsub(/\./,"",$5); c=$5}
				END {printf "%.0f", (a+w+c)*ps}
			')
		fi
	else
		local total_kb avail_kb
		total_kb=$(awk '/^MemTotal:/{print $2}'     /proc/meminfo 2>/dev/null)
		avail_kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)
		if [[ -n "$total_kb" && -n "$avail_kb" ]]; then
			total=$(( total_kb * 1024 ))
			used=$((  (total_kb - avail_kb) * 1024 ))
		fi
	fi
	[[ -z "$used"  ]] && used=0
	[[ -z "$total" ]] && total=0
	print -- "$used $total"
}

# -- load / uptime --------------------------------------------------------------
_mo_load_avg() {
	local raw
	if _mo_is_macos; then
		raw=$(sysctl -n vm.loadavg 2>/dev/null) || raw=""
	else
		raw=$(< /proc/loadavg) 2>/dev/null || raw=""
	fi
	if [[ "$raw" =~ '([0-9]+\.[0-9]+)' ]]; then
		print -- "$match[1]"
	else
		print -- "0.00"
	fi
}

_mo_uptime_secs() {
	if _mo_is_macos; then
		local boot
		boot=$(sysctl -n kern.boottime 2>/dev/null) || boot=""
		if [[ "$boot" =~ 'sec = ([0-9]+)' ]]; then
			print -- $(( $(date +%s) - match[1] ))
			return
		fi
		print -- 0
	else
		local secs
		IFS=. read -r secs _ < /proc/uptime 2>/dev/null || secs=0
		print -- "${secs:-0}"
	fi
}

# -- identity -------------------------------------------------------------------
_mo_os_name() {
	if _mo_is_macos; then
		local name ver
		name=$(sw_vers -productName 2>/dev/null)   || name="macOS"
		ver=$(sw_vers -productVersion 2>/dev/null) || ver=""
		print -- "${name}${ver:+ $ver}"
	else
		local os_name=""
		[[ -r /etc/os-release ]] && os_name=$(
			awk -F= '$1=="PRETTY_NAME"{gsub(/"/,"",$2); print $2; exit}' /etc/os-release
		)
		print -- "${os_name:-$(command uname -s)}"
	fi
}

_mo_kernel() {
	if _mo_is_macos; then
		command uname -r
	else
		print -- "$(< /proc/sys/kernel/osrelease)"
	fi
}

_mo_arch() { command uname -m }

# -- network --------------------------------------------------------------------
# Primary outbound address. On Linux `ip route get` asks the kernel which source
# address it would use, without sending anything; on macOS the default route's
# interface is resolved instead, since en0 is not always the active one.
_mo_local_ip() {
	local ip=""
	if _mo_is_macos; then
		local iface
		for iface in $(route -n get default 2>/dev/null | awk '/interface:/{print $2}') en0 en1 en2 en3; do
			[[ -n "$iface" ]] || continue
			ip=$(ipconfig getifaddr "$iface" 2>/dev/null) && [[ -n "$ip" ]] && { print -- "$ip"; return 0 }
		done
	else
		ip=$(ip -4 route get 1.1.1.1 2>/dev/null \
			| awk '/src/{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')
		[[ -z "$ip" ]] && ip=$(ip -4 addr show 2>/dev/null \
			| awk '/inet /{gsub(/\/.*/, "", $2); if ($2 != "127.0.0.1") {print $2; exit}}')
		[[ -n "$ip" ]] && print -- "$ip"
	fi
	return 0
}

# -- file editing ---------------------------------------------------------------
# GNU sed refuses an argument to -i; BSD sed requires one.
_mo_sed_inplace() {
	local expr="$1" file="$2"
	if _mo_is_macos; then
		sed -i '' "$expr" "$file"
	else
		sed -i "$expr" "$file"
	fi
}

# -- archives -------------------------------------------------------------------
# GNU tar is hardened with flags bsdtar does not have; bsdtar already declines
# to restore owner and permissions for a non-root user, and autodetects
# compression, so the caller never passes -z/-j/-J.
_mo_untar() {
	local archive="$1" dest="${2:-.}"
	mkdir -p "$dest"
	if _mo_is_macos; then
		tar -xf "$archive" -C "$dest"
	else
		tar -xf "$archive" -C "$dest" \
			--no-overwrite-dir --no-same-owner --no-same-permissions
	fi
}

# -- packages -------------------------------------------------------------------
_mo_pkg_manager() { _mo_is_macos && print -- brew || print -- apt }

# Install hint for a package, e.g. "sudo apt install fzf" / "brew install fzf".
_mo_pkg_hint() {
	if _mo_is_macos; then
		print -- "brew install $*"
	else
		print -- "sudo apt install $*"
	fi
}

_mo_brew_prefix() {
	_mo_is_macos || return 1
	if [[ -x /opt/homebrew/bin/brew ]]; then
		print -- /opt/homebrew
	elif [[ -x /usr/local/bin/brew ]]; then
		print -- /usr/local
	elif command -v brew &>/dev/null; then
		brew --prefix
	fi
}
