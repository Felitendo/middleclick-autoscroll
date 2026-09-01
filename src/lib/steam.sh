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
# Steam compares the installed files against its manifest at every start - by
# size and timestamp rather than by content - and restores whatever differs.
# So the patch is written to look untouched: the bytes the flag costs are taken
# back out of the script's comments and the timestamp is put back afterwards,
# which leaves a file that is byte-for-byte the size Steam recorded and as old
# as Steam left it. A client that verifies its files finds nothing to repair
# and the flag survives however Steam was started - from the menu, from a game
# shortcut, from a launcher like Heroic, from a terminal.
#
# That is the part that has to work, because there is no way to make every
# possible way of starting Steam carry an argument. -noverifyfiles on the
# launcher entries is the second line rather than the first: it covers the case
# where the script has no comments left to pay for the flag and the patch has
# to grow the file. The trade-off is real and belongs to the user, so it is a
# switch of its own rather than part of the general application handling: with
# verification off, Steam no longer repairs a damaged installation by itself.
#
# A patch that does change the size still has to stay out of the way of a
# client that is already running, or the two programs spend the session undoing
# each other: Steam restores the script, the watcher patches it again, Steam
# restores it again, and the client never gets past its update dialog. A patch
# that keeps the size is invisible to that check and goes in either way.
#
# The file comes back on every client update, and the watcher re-applies the
# patch when that happens.

MCA_STEAM_LAUNCH_FLAG='-noverifyfiles'

# Every place a Steam installation is known to live, resolved and de-duplicated
# because ~/.steam/steam is normally a symlink into ~/.local/share.
#
# Which of these is the real one depends on how Steam was installed: Valve's
# own package and the Arch one use ~/.local/share/Steam, Debian's puts it in
# ~/.steam/debian-installation, and the Flatpak and the snap each keep it
# inside the private tree their sandbox gives them.
mca_steam_roots() {
	local candidates=(
		"$MCA_XDG_DATA/Steam"
		"$HOME/.steam/steam"
		"$HOME/.steam/root"
		"$HOME/.steam/debian-installation"
		"$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
		"$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
		"$HOME/snap/steam/common/.local/share/Steam"
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

# mca_steam_running
# Steam records its own process id beside its installation while it runs. The
# file outlives a crash, so the id is checked rather than believed.
mca_steam_running() {
	local f pid
	for f in \
		"$HOME/.steam/steam.pid" \
		"$HOME/.var/app/com.valvesoftware.Steam/.steam/steam.pid" \
		"$HOME/snap/steam/common/.steam/steam.pid"
	do
		[[ -r $f ]] || continue
		pid="$(< "$f")"
		[[ $pid =~ ^[0-9]+$ ]] || continue
		kill -0 "$pid" 2>/dev/null && return 0
	done
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

# mca_steam_deferred <script>
# Whether the patch is being held back rather than simply missing: the script
# was patched before, its own copy is back, and Steam is still running. See
# mca_steam_apply for why that is left alone.
mca_steam_deferred() {
	[[ -e "$MCA_BACKUPDIR/$(mca_backup_name "$1")" ]] && mca_steam_running
}

# mca_steam_waiting
# The same question for the status screen, which has no script in hand.
mca_steam_waiting() {
	local root script
	while IFS= read -r root; do
		script="$(mca_steam_script "$root")" || continue
		mca_steam_script_patched "$script" && continue
		mca_steam_deferred "$script" && return 0
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

# _mca_steam_build <script> <flags> <reclaim: 0|1>
# The patched script on stdout: the flags appended to the line that starts the
# web helper, and - when asked for - the same number of bytes taken back out of
# the script's comments, so that the file Steam finds is the length Steam wrote
# down. Everything else - setting up the container runtime, deciding whether
# the sandbox can be used - is left alone.
#
# Comments are eaten from the bottom up, so the header that says what the
# script is for is the last thing to lose anything, and the '#' itself always
# stays: a line that loses it stops being a comment and starts being a command.
# Fails when the comments are too short to pay for the flags.
_mca_steam_build() {
	local script="$1" flags="$2" reclaim="$3" lineno need=0

	lineno="$(_mca_steam_exec_line "$script")"
	[[ -n $lineno ]] || return 1

	if (( reclaim )); then
		need="$(printf '%s' " $flags" | wc -c)"
		need="${need//[^0-9]/}"
	fi

	# LC_ALL=C so awk counts bytes: a comment with an accent in it is shorter
	# in characters than it is on disk, and it is the disk that Steam measures.
	LC_ALL=C awk -v n="$lineno" -v f=" $flags" -v need="$need" '
		{ lines[NR] = (NR == n ? $0 f : $0) }
		END {
			for (i = NR; i >= 2 && need > 0; i--) {
				if (i == n) continue
				p = index(lines[i], "#")
				if (p == 0) continue
				# Only a line that is nothing but a comment; a trailing one
				# sits behind a command that has to stay intact.
				if (substr(lines[i], 1, p - 1) ~ /[^ \t]/) continue
				can = length(lines[i]) - p
				if (can <= 0) continue
				if (can > need) can = need
				lines[i] = substr(lines[i], 1, length(lines[i]) - can)
				need -= can
			}
			if (need > 0) exit 1
			for (i = 1; i <= NR; i++) print lines[i]
		}
	' "$script"
}

# _mca_steam_same_size <script> <content>
# Whether writing that content leaves the file at the size it has now. Measured
# rather than worked out: a script without a final newline gains one on the way
# through awk, and one byte is all it takes for Steam to notice.
_mca_steam_same_size() {
	local script="$1" content="$2"
	(( $(wc -c < "$script") == $(printf '%s\n' "$content" | wc -c) ))
}

# _mca_steam_refresh_backup <script>
# A client update brings a new version of the script, and the copy kept from
# before it is no longer what putting it back means. Only ever done while the
# script is unpatched, so the copy that replaces it is Steam's own.
_mca_steam_refresh_backup() {
	local script="$1" name
	name="$(mca_backup_name "$script")"

	[[ -e "$MCA_BACKUPDIR/$name" ]] || return 0
	cmp -s -- "$script" "$MCA_BACKUPDIR/$name" && return 0
	cp -p -- "$script" "$MCA_BACKUPDIR/$name" 2>/dev/null || true
}

# _mca_steam_reneutralise <script> <flags>
# An earlier version of this program patched by appending and left the script
# longer than Steam expects, which is a patch that only survives because
# -noverifyfiles is there to stop Steam looking. If the same flags can be made
# to fit, they are: the file goes back to the length and the timestamp Steam
# wrote down and stops depending on that switch.
#
# The new copy is built from the untouched original that was kept when the
# script was first patched, never from the patched file - patching a patched
# file is how a flag ends up in there twice.
_mca_steam_reneutralise() {
	local script="$1" flags="$2" name copy out

	name="$(mca_backup_name "$script")"
	copy="$MCA_BACKUPDIR/$name"
	[[ -f $copy ]] || return 1

	# Already the length Steam expects: there is nothing to gain.
	(( $(wc -c < "$script") == $(wc -c < "$copy") )) && return 1

	out="$(_mca_steam_build "$copy" "$flags" 1)" || return 1
	_mca_steam_same_size "$copy" "$out" || return 1

	if mca_write_if_changed "$script" "$out"$'\n'; then
		MCA_CHANGES=$(( MCA_CHANGES + 1 ))
	fi
	chmod +x -- "$script" 2>/dev/null || true
	touch -r "$copy" -- "$script" 2>/dev/null || true
	mca_ledger_add steam "$script" "$name"
	return 0
}

# mca_steam_apply
# Puts the flags into every Steam installation that has the script, preferring
# the patch that keeps the file's size and falling back to the one that does
# not. Returns 1 when there is no Steam to patch at all.
mca_steam_apply() {
	local root script backup flags found=0 out neutral

	flags="$(mca_flags)"

	while IFS= read -r root; do
		script="$(mca_steam_script "$root")" || continue
		found=1

		if mca_steam_script_patched "$script"; then
			_mca_steam_reneutralise "$script" "$flags" || true
			continue
		fi

		_mca_steam_refresh_backup "$script"

		neutral=1
		if ! { out="$(_mca_steam_build "$script" "$flags" 1)" \
			&& _mca_steam_same_size "$script" "$out"; }
		then
			neutral=0
			out="$(_mca_steam_build "$script" "$flags" 0)" || {
				# A client update changed how the helper is started. Leaving
				# the file alone is the only safe answer: this script is what
				# starts Steam's entire interface.
				mca_note "$(mca_msg "Steam starts its interface in a way this version does not recognise; leaving it alone.")"
				continue
			}
		fi

		# The patch has to grow the file, and it is not patched now but was
		# before: Steam has just put its own copy back. Patching it again
		# while the client watches is what turns one size mismatch into an
		# endless update dialog, and it would not help this session anyway -
		# the helper is started once, at the start. The patch waits for the
		# next apply with Steam closed. A patch that keeps the size has
		# nothing to wait for.
		if (( ! neutral )) && mca_steam_deferred "$script"; then
			mca_note "$(mca_msg "Steam is running and has put its own file back; the change waits until Steam is closed.")"
			continue
		fi

		backup="$(mca_backup "$script")" || continue
		if mca_write_if_changed "$script" "$out"$'\n'; then
			MCA_CHANGES=$(( MCA_CHANGES + 1 ))
		fi
		chmod +x -- "$script" 2>/dev/null || true

		# Steam looks at when the file was last written as well as at how big
		# it is, and the copy taken before the edit still carries the original
		# timestamp. Putting it back costs nothing and removes the other half
		# of what the client would notice.
		touch -r "$MCA_BACKUPDIR/$backup" -- "$script" 2>/dev/null || true

		mca_ledger_add steam "$script" "$backup"
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

# mca_steam_flag_position <packaging>
# Where Steam's own switch goes on a command line. Straight after the program
# for a native or snap entry, because Steam reads its options before the
# steam:// argument that the right-click actions pass. For a Flatpak the first
# token is flatpak itself, which would take the switch for one of its own and
# refuse to start, so there it goes at the end of the arguments - after the
# application id, where flatpak hands everything on to Steam.
mca_steam_flag_position() {
	[[ ${1:-native} == flatpak ]] && { printf 'before-fields\n'; return; }
	printf 'after-program\n'
}

# mca_steam_desktop_apply <id> <source entry> [packaging]
# Steam restores its own files at every start unless it is told not to verify
# them, so the launcher entry carries that switch.
mca_steam_desktop_apply() {
	mca_desktop_apply "$1" "$2" "$MCA_STEAM_LAUNCH_FLAG" \
		"$(mca_steam_flag_position "${3:-native}")"
}
