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
	# An alias, not a bare function, so the documented `\rm` escape still
	# reaches /bin/rm: backslash suppresses alias expansion, and a function
	# named rm would swallow it and trash the file anyway.
	alias rm='_mo_trash_rm'

	_mo_trash_rm() {
		if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
			print -r -- "Usage: rm <file> [file ...]"
			print -r -- "  Moves files to the trash instead of deleting them."
			print -r -- '  Use \rm (or `command rm`) to bypass and delete for real.'
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
		(( ${#targets} )) || { print -r -- "rm: no files given" >&2; return 1 }

		local t line abs landed
		local -i failed=0
		for t in "${targets[@]}"; do
			if [[ ! -e "$t" && ! -L "$t" ]]; then
				print -r -- "rm: $t: No such file or directory" >&2
				failed=1
				continue
			fi
			# _mo_trash_put reports the name the file actually landed under —
			# the tool renames on collision, and guessing produced an index
			# entry pointing at somebody else's file.
			if ! line=$(_mo_trash_put "$t"); then
				failed=1
				continue
			fi
			mkdir -p "${MO_TRASH_INDEX:h}" 2>/dev/null || continue
			local IFS=$'\t'
			while read -r abs landed; do
				[[ -n "$landed" ]] || continue
				printf '%s\t%s\t%s\n' "$(date +%s)" "$landed" "$abs" >> "$MO_TRASH_INDEX"
			done <<< "$line"
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

# Names currently in the trash, newest first.
#
# Two sources, because neither is complete on macOS: the directory scan sees
# files Finder trashed but is blocked by TCC unless the terminal has Full Disk
# Access, while the index sees only our own deletions but needs no permission
# (checking one known path inside ~/.Trash is allowed; listing the directory is
# not). Union them, preferring the index so the common case works out of the box.
_mo_trash_names() {
	setopt local_options null_glob
	local -A seen=()
	local -a out=()
	local n

	if [[ -r "$MO_TRASH_INDEX" ]]; then
		while IFS=$'\t' read -r _ n _; do
			[[ -n "$n" ]] || continue
			[[ -e "${MO_TRASH_DIR}/${n}" ]] || continue   # emptied since
			(( ${+seen[$n]} )) && continue
			seen[$n]=1
			out=("$n" "${out[@]}")                        # index is oldest-first
		done < "$MO_TRASH_INDEX"
	fi

	if _mo_trash_dir_readable "$MO_TRASH_DIR"; then
		local f
		for f in "${MO_TRASH_DIR}"/*(ND-om); do
			(( ${+seen[${f:t}]} )) && continue
			seen[${f:t}]=1
			out+=("${f:t}")
		done
	fi

	(( ${#out} )) && printf '%s\n' "${out[@]}"
}

# Print the Full Disk Access hint once, for the operations that genuinely need
# to enumerate the directory. Reporting "nothing to do" when the read was
# refused is what made trash-prune and trash-empty claim success on a full trash.
_mo_trash_need_readdir() {
	_mo_trash_dir_readable "$MO_TRASH_DIR" && return 0
	# Distinguish the two reasons a read can fail. Blaming TCC for a directory
	# that simply is not there sends the user to System Settings for nothing —
	# which is what happened under a relocated HOME, since /usr/bin/trash
	# always writes to the real user's ~/.Trash regardless of $HOME.
	if [[ ! -d "$MO_TRASH_DIR" ]]; then
		print -r -- "${1}: ${MO_TRASH_DIR} does not exist." >&2
		print -r -- "  Set MO_TRASH_DIR if your trash lives elsewhere." >&2
		return 1
	fi
	print -r -- "${1}: cannot read ${MO_TRASH_DIR} — macOS restricts it." >&2
	print -r -- "  Grant your terminal Full Disk Access in System Settings →" >&2
	print -r -- "  Privacy & Security → Full Disk Access, then reopen the shell." >&2
	return 1
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
	local -a names=( ${(f)"$(_mo_trash_names)"} )
	if (( ${#names} == 0 )); then
		if ! _mo_trash_dir_readable "$MO_TRASH_DIR"; then
			_mo_trash_need_readdir trash-list
			print -r -- "  (only files trashed through rm are listed until then)" >&2
			return 1
		fi
		echo "trash-list: trash is empty"
		return 0
	fi
	local n f origin
	{
		print -- "WHEN\tSIZE\tNAME\tORIGINAL"
		for n in "${names[@]}"; do
			f="${MO_TRASH_DIR}/${n}"
			origin=$(_mo_trash_lookup "$n") || origin=""
			printf '%s\t%s\t%s\t%s\n' "$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null)" \
				"$(du -sh "$f" 2>/dev/null | cut -f1)" "$n" "${origin:-—}"
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
	if ! _mo_trash_has_restore; then
		# macOS: pick a file and put it back where our index says it came from.
		local -a names=( ${(f)"$(_mo_trash_names)"} )
		if (( ${#names} == 0 )); then
			_mo_trash_dir_readable "$MO_TRASH_DIR" \
				&& { echo "trash-restore: trash is empty" >&2; return 1 }
			_mo_trash_need_readdir trash-restore
			return 1
		fi
		local chosen
		chosen=$(printf '%s\n' "${names[@]}" | fzf --prompt="Restore> " --height=40%) || return 130
		[[ -n "$chosen" ]] || return 0
		local dest origin
		origin=$(_mo_trash_lookup "$chosen")
		if [[ -n "$origin" ]]; then
			dest="$origin"; mkdir -p "${dest:h}" 2>/dev/null
		else
			dest="${PWD}/${chosen}"
			echo "trash-restore: original location unknown — restoring to $PWD" >&2
		fi
		[[ -e "$dest" ]] && { echo "trash-restore: refusing — '$dest' already exists" >&2; return 1 }
		command mv "${MO_TRASH_DIR}/${chosen}" "$dest" && echo "Restored: $dest"
		return
	fi

	# trash-list prints "DATE TIME /original/path"; fzf picks one line and we
	# pull its original path (fields 3+, may contain spaces). We can't reuse
	# trash-list's own line number: `command trash-restore` builds its OWN
	# 0-based, cwd-scoped, date-sorted candidate list, so any index from here
	# points at the wrong file. Instead we scope trash-restore to the exact
	# path — that yields a one-entry list where index 0 is unambiguous.
	local selection path
	selection=$(command trash-list 2>/dev/null | fzf --prompt="Restore> " --height=40%) || return 0
	# Strip the two date/time tokens with parameter expansion — an awk field
	# rebuild would collapse runs of spaces inside the path itself.
	path="${selection#* }"; path="${path#* }"
	[[ -z "$path" ]] && { echo "trash-restore: could not locate selection" >&2; return 1 }
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
	if ! _mo_trash_has_restore; then
		_mo_trash_need_readdir trash-empty || return 1
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
	_mo_trash_need_readdir trash-prune || return 1
	setopt local_options null_glob
	local -a old=("${MO_TRASH_DIR}"/*(ND.md+${days}) "${MO_TRASH_DIR}"/*(ND/md+${days}))
	(( ${#old} )) || { echo "trash-prune: nothing older than ${days} day(s)"; return 0 }
	printf '  %s\n' "${old[@]:t}"
	command rm -rf -- "${old[@]}"
	# Drop the pruned names so the index does not grow without bound and
	# trash-list stops offering entries that are gone.
	if [[ -w "$MO_TRASH_INDEX" ]]; then
		local tmp="${MO_TRASH_INDEX}.tmp$$"
		awk -F'\t' -v dir="$MO_TRASH_DIR" \
			'{ p = dir "/" $2; if (system("[ -e \"" p "\" ]") == 0) print }' \
			"$MO_TRASH_INDEX" > "$tmp" 2>/dev/null && command mv "$tmp" "$MO_TRASH_INDEX"
	fi
}
