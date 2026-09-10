# oh-my-zsh does not source $ZSH_CUSTOM/lib; nor does a zshrc seeded before it.
[[ -n ${_MO_PLATFORM_LOADED-} ]] || source "${0:h}/../../lib/platform.zsh"

source "${0:h}/requirements.zsh" || return

# Homebrew helpers. Arch-aware via _mo_brew_prefix, so the same config works on
# Apple Silicon (/opt/homebrew) and Intel (/usr/local).

: ${MO_BREW_CACHE_FILE:=${HOME}/.config/master-oogway/brew-outdated.count}
: ${MO_BREW_CACHE_TTL:=3600}

# A count cheap enough to call from a prompt: it must never shell out to brew
# synchronously, because `brew outdated` takes seconds. Reads a cache file and
# refreshes it in the background at most once per TTL. A cold cache reports 0
# rather than blocking or guessing. The theme does not use it today; it is here
# so a prompt segment can be added without also having to solve the latency.
_mo_brew_outdated_count() {
	local f="$MO_BREW_CACHE_FILE"
	local -i now age
	now=$(date +%s)

	if [[ -r "$f" ]]; then
		age=$(( now - $(date -r "$f" +%s) ))
	else
		age=$(( MO_BREW_CACHE_TTL + 1 ))
	fi

	if (( age > MO_BREW_CACHE_TTL )); then
		mkdir -p "${f:h}" 2>/dev/null
		# Detached so a slow or offline brew never blocks the prompt.
		# wc, not grep -c: grep exits 1 on zero matches, which would short-circuit
		# the move and leave the cache permanently cold on an up-to-date machine.
		(
			local n
			n=$(brew outdated --quiet 2>/dev/null | command wc -l | command tr -d ' ')
			[[ "$n" == <-> ]] || n=0
			print -- "$n" > "$f.tmp" && command mv "$f.tmp" "$f"
		) &>/dev/null &!
	fi

	if [[ -r "$f" ]]; then
		local c="$(<$f)"
		[[ "$c" == <-> ]] && { print -- "$c"; return 0 }
	fi
	print -- 0
}

_mo_brew_need_fzf() {
	command -v fzf &>/dev/null && return 0
	echo "${1}: fzf not installed (try: brew install fzf)" >&2
	return 1
}

bup() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		echo "Usage: bup"
		echo "  Update Homebrew, upgrade all formulae and casks, then clean up."
		return
	fi
	print -P "%F{cyan}==> brew update%f"    && brew update    || return 1
	print -P "%F{cyan}==> brew upgrade%f"   && brew upgrade   || return 1
	print -P "%F{cyan}==> brew cleanup%f"   && brew cleanup   || return 1
	# Otherwise _mo_brew_outdated_count reports a stale count until the TTL lapses.
	command rm -f "$MO_BREW_CACHE_FILE" 2>/dev/null
	print -P "%F{green}%BUP TO DATE ✓%b%f"
}

bi() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		echo "Usage: bi [search-term]"
		echo "  Fuzzy-pick formulae and casks to install. TAB selects several."
		return
	fi
	_mo_brew_need_fzf bi || return 1
	local -a picks
	picks=( ${(f)"$(
		{ brew formulae; brew casks } 2>/dev/null \
			| fzf -m --query="${1:-}" --height=60% --reverse \
				  --prompt="install> " \
				  --preview 'brew info {} 2>/dev/null | head -40'
	)"} )
	(( ${#picks} )) || return 0
	brew install "${picks[@]}"
}

bun() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		echo "Usage: bun"
		echo "  Fuzzy-pick installed packages to uninstall. TAB selects several."
		return
	fi
	_mo_brew_need_fzf bun || return 1
	local -a picks
	picks=( ${(f)"$(
		brew list --formula --cask 2>/dev/null \
			| fzf -m --height=60% --reverse --prompt="uninstall> " \
				  --preview 'brew info {} 2>/dev/null | head -40'
	)"} )
	(( ${#picks} )) || return 0
	brew uninstall "${picks[@]}"
}

bs() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]]; then
		echo "Usage: bs <term>"
		echo "  Search formulae and casks; shows full info for the match you pick."
		return
	fi
	local -a hits
	hits=( ${(f)"$(brew search "$@" 2>/dev/null | command grep -v '^==>' | command grep -v '^$')"} )
	(( ${#hits} )) || { echo "bs: no matches for '$*'"; return 1; }
	if command -v fzf &>/dev/null; then
		local pick
		pick=$(printf '%s\n' "${hits[@]}" | fzf --height=60% --reverse \
			--prompt="info> " --preview 'brew info {} 2>/dev/null | head -40') || return 130
		[[ -n "$pick" ]] && brew info "$pick"
	else
		printf '%s\n' "${hits[@]}"
	fi
}

bl() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		echo "Usage: bl"
		echo "  Browse top-level packages (brew leaves) with their dependencies."
		return
	fi
	if command -v fzf &>/dev/null; then
		brew leaves 2>/dev/null | fzf --height=60% --reverse --prompt="leaves> " \
			--preview 'echo "── deps ──"; brew deps --tree {} 2>/dev/null | head -30
echo; echo "── used by ──"; brew uses --installed {} 2>/dev/null | head -10'
	else
		brew leaves
	fi
}

bout() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		echo "Usage: bout"
		echo "  Show outdated packages and refresh the cached count."
		return
	fi
	command rm -f "$MO_BREW_CACHE_FILE" 2>/dev/null
	brew outdated --verbose
}
