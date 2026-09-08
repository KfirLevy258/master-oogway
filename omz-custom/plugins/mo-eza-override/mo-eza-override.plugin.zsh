# Remove this file to use the system ls as-is.

source "${0:h}/requirements.zsh" || return

# Two upstream eza changes make the obvious `alias ls="eza -F"` unusable, and
# both hit every platform — Ubuntu 24.04 packages 0.18.2, so this is not a
# macOS quirk:
#
#   0.18.0  --classify gained an optional value. Written as a bare -F it
#           swallows the next token unless that token looks like a flag, so
#           `ls somedir` dies with:
#             error: invalid value 'somedir' for '--classify [<WHEN>]'
#           Binding the value with = keeps the path positional.
#
#   0.23.0  eza reads path names from stdin when stdin is not a TTY and no
#           path operand was given. In a script, a pipeline or a preview pane
#           that means `ls` silently lists nothing — or blocks forever waiting
#           on a pipe that never closes.
#
# So: bind the value, and always pass an operand. `ls` is a function rather
# than an alias because deciding whether an operand is present needs to look
# at the arguments.
_mo_eza_ls() {
	local arg
	for arg in "$@"; do
		# The first non-option word is a path operand, so eza has something to
		# list and will not fall back to reading stdin.
		[[ "$arg" == -* ]] && continue
		eza --classify=auto "$@"
		return
	done
	eza --classify=auto "$@" .
}

alias ls="_mo_eza_ls"   # --hyperlink has a known bug when piping
alias lsa="ls -A"
alias ll="lsa -l --smart-group --time-style=long-iso"
alias l="ls -l --no-user --smart-group --time-style=long-iso"
alias la="l -A"
alias lg="ls --git"
tree() {
	local arg
	local args=()
	for arg in "$@"; do
		[[ "$arg" == "-d" ]] && args+=("-D") || args+=("$arg")
	done
	lg --tree "${args[@]}"
}
