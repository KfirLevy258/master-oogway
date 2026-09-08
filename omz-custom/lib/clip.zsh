# Clipboard helper. The platform layer owns the mechanism (pbcopy on macOS,
# wl-copy/xclip/xsel on Linux); this stays as the name plugins already call.
# Sourced by zshrc.master-oogway along with the rest of lib/.
_mo_clip_string() {
	_mo_clip "$1"
}
