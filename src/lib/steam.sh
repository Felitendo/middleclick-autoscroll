# shellcheck shell=bash
#
# Steam.
#
# Steam's interface is CEF, so the feature is there - but Steam builds the
# command line for its web helper itself and offers no way to add to it. The
# only place to get an argument in is the shell script that starts the helper,
# which lives inside Steam's own installation:
#
#   ~/.local/share/Steam/ubuntu12_64/steamwebhelper_sniper_wrap.sh
#
# Steam checksums that script at every start and restores it when it differs,
# which is why the launcher gets -noverifyfiles as well. The trade-off is real
# and belongs to the user, so this is a switch of its own rather than part of
# the general application handling: with verification off, Steam no longer
# repairs a damaged installation by itself.
#
# The file comes back on every client update, and the watcher re-applies the
# patch when that happens.

MCA_STEAM_EXEC='exec ./steamwebhelper "$@"'
MCA_STEAM_LAUNCH_FLAG='-noverifyfiles'

# Every place a Steam installation is known to live, resolved and de-duplicated
# because ~/.steam/steam is normally a symlink into ~/.local/share.
mca_steam_roots() {
	local candidates=(
		"$MCA_XDG_DATA/Steam"
		"$HOME/.steam/steam"
		"$HOME/.steam/root"
		"$HOME/.steam/debian-installation"
		"$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
	)
	local dir real
	local -A seen=()

	for dir in "${candidates[@]}"; do
		[[ -d $dir ]] || continue
		real="$(readlink -f -- "$dir" 2>/dev/null)" || continue
		[[ -n ${seen[$real]+set} ]] && continue
		seen[$real]=1
		printf '%s\n' "$real"
	done
}

# The script to patch inside a Steam installation. Newer clients start the
# helper through a wrapper inside the container runtime; older ones exec it
# from steamwebhelper.sh directly, and that one forwards its arguments too.
mca_steam_script() {
	local root="$1" f
	for f in \
		"$root/ubuntu12_64/steamwebhelper_sniper_wrap.sh" \
		"$root/ubuntu12_64/steamwebhelper.sh"
	do
		[[ -f $f && -w $f ]] && { printf '%s\n' "$f"; return 0; }
	done
	return 1
}

mca_steam_installed() {
	local root
	while IFS= read -r root; do
		mca_steam_script "$root" > /dev/null && return 0
	done < <(mca_steam_roots)
	return 1
}

# mca_steam_script_patched <script>
mca_steam_script_patched() {
	grep -q -- "$MCA_FEATURE" "$1" 2>/dev/null
}

mca_steam_patched() {
	local root script
	while IFS= read -r root; do
		script="$(mca_steam_script "$root")" || continue
		mca_steam_script_patched "$script" && return 0
	done < <(mca_steam_roots)
	return 1
}

# _mca_steam_exec_line <script>
# The line number of the command that starts the web helper: the last
# uncommented line that both names steamwebhelper and forwards "$@". Both the
# current layout (exec ./steamwebhelper "$@" inside the container wrapper) and
# the older one (steamwebhelper.sh handing the arguments to the runtime entry
# point) end in exactly that.
_mca_steam_exec_line() {
	awk '
		/^[[:space:]]*#/ { next }
		/steamwebhelper/ && /"\$@"/ { n = NR }
		END { if (n) print n }
	' "$1" 2>/dev/null
}

# mca_steam_apply
# Appends the flags to the line that starts the web helper. Everything else in
# the script - setting up the container runtime, deciding whether the sandbox
# can be used - is left alone.
mca_steam_apply() {
	local root script backup flags lineno found=0 out

	flags="$(mca_flags)"

	while IFS= read -r root; do
		script="$(mca_steam_script "$root")" || continue
		found=1

		mca_steam_script_patched "$script" && { MCA_TOUCHED+=("$script"); continue; }

		lineno="$(_mca_steam_exec_line "$script")"
		if [[ -z $lineno ]]; then
			# A client update changed how the helper is started. Leaving the
			# file alone is the only safe answer: this script is what starts
			# Steam's entire interface.
			mca_note "$(mca_msg "Steam starts its interface in a way this version does not recognise; leaving it alone.")"
			continue
		fi

		out="$(awk -v n="$lineno" -v f=" $flags" 'NR == n { $0 = $0 f } { print }' "$script")" || continue

		backup="$(mca_backup "$script")" || continue
		if mca_write_if_changed "$script" "$out"$'\n'; then
			MCA_CHANGES=$(( MCA_CHANGES + 1 ))
		fi
		chmod +x -- "$script" 2>/dev/null || true
		mca_ledger_add steam "$script" "$backup"
		MCA_TOUCHED+=("$script")
	done < <(mca_steam_roots)

	(( found ))
}

# mca_steam_revert <script> <backup name>
mca_steam_revert() {
	local script="$1" backup="$2"

	if [[ -n $backup && -f "$MCA_BACKUPDIR/$backup" ]]; then
		if [[ -e $script ]]; then
			cp -p -- "$MCA_BACKUPDIR/$backup" "$script" 2>/dev/null || true
			chmod +x -- "$script" 2>/dev/null || true
		fi
		rm -f -- "$MCA_BACKUPDIR/$backup"
		return 0
	fi

	# No backup to fall back on - take the flags back out of the exec line.
	[[ -f $script ]] || return 1
	local tmp
	tmp="$(mktemp "${script}.XXXXXX")" || return 1
	sed "s| $MCA_FLAG||g" "$script" > "$tmp" && mv -f "$tmp" "$script" || { rm -f "$tmp"; return 1; }
	chmod +x -- "$script" 2>/dev/null || true
	return 0
}

# mca_steam_desktop_apply <id> <source entry>
# Steam restores its own files at every start unless it is told not to verify
# them, so the launcher entry carries that switch. It goes directly after the
# program because Steam reads its options before the steam:// argument that the
# right-click actions pass.
mca_steam_desktop_apply() {
	mca_desktop_apply "$1" "$2" "$MCA_STEAM_LAUNCH_FLAG" after-program
}
