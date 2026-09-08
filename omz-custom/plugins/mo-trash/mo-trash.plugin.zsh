source "${0:h}/requirements.zsh" || return

# MO_TRASH_DIR is used by trash-empty (du) and trash-prune. On Linux the trash
# tool ignores it and uses its own XDG location; on macOS it is ~/.Trash.
: ${MO_TRASH_DIR:=$(_mo_trash_dir)}

# macOS keeps Finder's "Put Back" location in a private database, so restoring
# to the original path needs an index of our own. Written on every rm; entries
# for files trashed by Finder are simply absent.
: ${MO_TRASH_INDEX:=${MO_CONFIG_DIR:-$HOME/.config/master-oogway}/trash-index.tsv}

if _mo_trash_has_restore; then
	alias rm="$(_mo_trash_tool)"
else
	# Wrap instead of aliasing so the original path can be recorded.
	rm() {
		if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
			echo "Usage: rm <file> [file ...]"
			echo "  Moves files to the trash instead of deleting them."
			echo "  Use \\rm to bypass and delete for real."
			return
		fi
		local -a targets=()
		local a
		# Flags are meaningless once the delete becomes a move, and would be
		# taken as filenames by the trash tool.
		for a in "$@"; do
			[[ "$a" == -* ]] && continue
			targets+=("$a")
		done
		(( ${#targets} )) || { echo "rm: no files given" >&2; return 1; }

		local t abs base landed
		local -i failed=0
		for t in "${targets[@]}"; do
			if [[ ! -e "$t" && ! -L "$t" ]]; then
				echo "rm: $t: No such file or directory" >&2
				failed=1
				continue
			fi
			abs="${t:A}"; base="${t:t}"
			if _mo_trash_put "$t"; then
				landed="$base"
				# The tool renames on collision; find what it actually became.
				[[ -e "${MO_TRASH_DIR}/${base}" ]] \
					|| landed=$(command ls -t "$MO_TRASH_DIR" 2>/dev/null | head -1)
				mkdir -p "${MO_TRASH_INDEX:h}" 2>/dev/null \
					&& printf '%s\t%s\t%s\n' "$(date +%s)" "$landed" "$abs" >> "$MO_TRASH_INDEX"
			else
				failed=1
			fi
		done
		return $failed
	}
fi

# Original path for a trashed name, from our index. Last match wins: a name can
# be reused after an earlier entry is emptied.
_mo_trash_lookup() {
	[[ -r "$MO_TRASH_INDEX" ]] || return 1
	awk -F'\t' -v n="$1" '$2 == n {p = $3} END {if (p) print p}' "$MO_TRASH_INDEX"
}

trash-list() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		echo "Usage: trash-list"
		echo "  Show trashed files: original path and deletion date, newest first."
		return
	fi
	if _mo_trash_has_restore; then
		command trash-list 2>/dev/null | sort -k1,2r
		return
	fi
	setopt local_options null_glob
	local -a items=("${MO_TRASH_DIR}"/*(ND-om))
	(( ${#items} )) || { echo "trash-list: trash is empty"; return 0; }
	local f origin
	{
		print -- "WHEN\tSIZE\tNAME\tORIGINAL"
		for f in "${items[@]}"; do
			origin=$(_mo_trash_lookup "${f:t}") || origin=""
			printf '%s\t%s\t%s\t%s\n' "$(date -r "$f" '+%Y-%m-%d %H:%M')" \
				"$(du -sh "$f" 2>/dev/null | cut -f1)" "${f:t}" "${origin:-—}"
		done
	} | column -t -s $'\t'
}

trash-restore() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		echo "Usage: trash-restore"
		echo "  fzf-pick a trashed file and restore it to its original location."
		return
	fi
	if ! command -v fzf &>/dev/null; then
		echo "trash-restore: fzf not installed (try: $(_mo_pkg_hint fzf))" >&2
		return 1
	fi
	# trash-list prints "DATE TIME /original/path"; fzf picks one line and we
	# pull its original path (fields 3+, may contain spaces). We can't reuse
	# trash-list's own line number: `command trash-restore` builds its OWN
	# 0-based, cwd-scoped, date-sorted candidate list, so any index from here
	# points at the wrong file. Instead we scope trash-restore to the exact
	# path — that yields a one-entry list where index 0 is unambiguous.
	if ! _mo_trash_has_restore; then
		# macOS: pick a file and put it back where our index says it came from.
		setopt local_options null_glob
		local -a items=("${MO_TRASH_DIR}"/*(ND-om))
		(( ${#items} )) || { echo "trash-restore: trash is empty" >&2; return 1; }
		local chosen
		chosen=$(printf '%s\n' "${items[@]:t}" | fzf --prompt="Restore> " --height=40%) || return 130
		[[ -n "$chosen" ]] || return 0
		local dest origin
		origin=$(_mo_trash_lookup "$chosen")
		if [[ -n "$origin" ]]; then
			dest="$origin"; mkdir -p "${dest:h}" 2>/dev/null
		else
			dest="${PWD}/${chosen}"
			echo "trash-restore: original location unknown — restoring to $PWD" >&2
		fi
		[[ -e "$dest" ]] && { echo "trash-restore: refusing — '$dest' already exists" >&2; return 1; }
		command mv "${MO_TRASH_DIR}/${chosen}" "$dest" && echo "Restored: $dest"
		return
	fi

	local selection path
	selection=$(command trash-list 2>/dev/null | fzf --prompt="Restore> " --height=40%) || return 0
	# Strip the two date/time tokens with parameter expansion — an awk field
	# rebuild would collapse runs of spaces inside the path itself.
	path="${selection#* }"; path="${path#* }"
	[[ -z "$path" ]] && { echo "trash-restore: could not locate selection" >&2; return 1; }
	# Ceiling: if the SAME path was trashed multiple times, the scoped list
	# has several entries and index 0 restores the oldest version, not
	# necessarily the line picked in fzf.
	echo 0 | command trash-restore "$path"
}

trash-empty() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		echo "Usage: trash-empty"
		echo "  Permanently delete all files in the trash (shows size first)."
		return
	fi
	local size src
	src="${MO_TRASH_DIR}/files"
	_mo_trash_has_restore || src="${MO_TRASH_DIR}"
	size=$(du -sh "$src" 2>/dev/null | cut -f1)
	echo "Trash size: ${size:-0}"
	printf '%s' "Permanently delete everything in the trash? [y/N] "
	local ans
	read -r ans
	[[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]] || return 1
	if _mo_trash_has_restore; then
		command trash-empty
	else
		setopt local_options null_glob
		local -a items=("${MO_TRASH_DIR}"/*(ND))
		(( ${#items} )) && command rm -rf -- "${items[@]}"
		: > "$MO_TRASH_INDEX" 2>/dev/null
	fi
}

trash-prune() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]]; then
		echo "Usage: trash-prune <days>"
		echo "  Remove trash entries older than <days> days."
		echo "  Example: trash-prune 30"
		return
	fi
	local days="$1"
	if [[ ! "$days" =~ ^[0-9]+$ ]]; then
		echo "trash-prune: expected a number of days, got '$days'" >&2
		return 1
	fi
	if _mo_trash_has_restore; then
		command trash-empty --trash-dir="$MO_TRASH_DIR" "$days"
		return
	fi
	setopt local_options null_glob
	local -a old=("${MO_TRASH_DIR}"/*(ND.md+${days}) "${MO_TRASH_DIR}"/*(ND/md+${days}))
	(( ${#old} )) || { echo "trash-prune: nothing older than ${days} day(s)"; return 0; }
	printf '  %s\n' "${old[@]:t}"
	command rm -rf -- "${old[@]}"
}
