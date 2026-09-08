# Hard deps — plugin does not load if trash-put is absent.
local _missing=()
command -v trash-put &>/dev/null || _missing+=(trash-cli)

if (( ${#_missing} )); then
	print -P "%F{yellow}[mo-trash]%f missing: ${_missing[*]} (try: $(_mo_pkg_hint trash-cli)) — plugin not loaded" >&2
	return 1
fi
