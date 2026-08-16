# shellcheck shell=bash
#
# Putting the flag where the application will read it, and taking it back out.
#
# There are two ways in, and the order matters:
#
#   1. A flag file. Arch's Electron and Chromium wrappers read extra arguments
#      from $XDG_CONFIG_HOME/<name>-flags.conf. This is the good one - it is the
#      supported way to pass arguments, it survives package upgrades untouched,
#      and it applies however the program is started, including from a terminal.
#
#   2. A desktop entry. For applications that ship their own binary with no
#      wrapper - most vendor packages, every Flatpak - there is nowhere else to
#      put an argument, so a copy of the entry with the flag appended goes into
#      ~/.local/share/applications, where it shadows the system one.
#
# Nothing outside $HOME is ever written to.

MCA_MARK_BEGIN='# >>> middleclick-autoscroll'
MCA_MARK_END='# <<< middleclick-autoscroll'

# ---------------------------------------------------------------------------
# Command lines
# ---------------------------------------------------------------------------

# _mca_exec_insert_at <exec line>
# Where an argument has to go: after the program and its own arguments, but
# before the first field code (%U and friends) or Flatpak's @@ markers, which
# are placeholders the launcher expands rather than arguments.
_mca_exec_insert_at() {
	local rest="$1" tok idx=0

	while [[ -n $rest ]]; do
		while [[ $rest == ' '* ]]; do rest="${rest# }"; idx=$(( idx + 1 )); done
		[[ -n $rest ]] || break
		tok="${rest%% *}"
		case "$tok" in
			%[a-zA-Z]|@@|@@u) printf '%s\n' "$idx"; return 0 ;;
		esac
		rest="${rest:${#tok}}"
		idx=$(( idx + ${#tok} ))
	done

	printf '%s\n' "$(( ${#1} ))"
}

# _mca_exec_after_program <exec line>
# The position just after the program name, for arguments that a program only
# accepts before its positional ones.
_mca_exec_after_program() {
	local rest="$1" idx=0 tok

	while [[ $rest == ' '* ]]; do rest="${rest# }"; idx=$(( idx + 1 )); done
	tok="${rest%% *}"
	printf '%s\n' "$(( idx + ${#tok} ))"
}

# mca_exec_inject <exec line> [flags] [position: before-fields|after-program]
# The same line with the given flags added, defaulting to the configured ones.
# Prints nothing and returns 1 when there was nothing to change, so callers can
# tell a real edit from a no-op without diffing.
#
# An --enable-blink-features that is already there is extended rather than
# repeated: Chromium keeps the last occurrence of the option and drops the
# rest, so a second one would silently disable whatever the first turned on.
mca_exec_inject() {
	local line="$1" flagstr="${2:-}" where="${3:-before-fields}"
	local flag value existing at changed=0
	local -a flags

	[[ -n $flagstr ]] || flagstr="$(mca_flags)"
	read -r -a flags <<< "$flagstr"

	for flag in "${flags[@]}"; do
		if [[ $flag == --enable-blink-features=* ]]; then
			value="${flag#--enable-blink-features=}"
			if [[ $line =~ --enable-blink-features=([A-Za-z0-9,_-]*) ]]; then
				existing="${BASH_REMATCH[1]}"
				[[ ",$existing," == *",$value,"* ]] && continue
				line="${line/--enable-blink-features=$existing/--enable-blink-features=${existing:+$existing,}$value}"
				changed=1
				continue
			fi
		fi

		[[ " $line " == *" $flag "* ]] && continue

		if [[ $where == after-program ]]; then
			at="$(_mca_exec_after_program "$line")"
			line="${line:0:$at} $flag${line:$at}"
		else
			at="$(_mca_exec_insert_at "$line")"
			if (( at >= ${#line} )); then
				line="${line% } $flag"
			else
				line="${line:0:$at}$flag ${line:$at}"
			fi
		fi
		changed=1
	done

	(( changed )) || return 1
	printf '%s\n' "$line"
}

# ---------------------------------------------------------------------------
# Flag files
# ---------------------------------------------------------------------------

# mca_flags_apply <program>
# Writes the flags into the file the program's launcher reads. Returns 0 when
# the program has such a file (whether or not anything needed changing), 1 when
# it has none and the desktop entry route has to be used instead.
mca_flags_apply() {
	local prog="$1" name target='' existing_target=''
	local -a candidates=()

	mapfile -t candidates < <(mca_flags_candidates "$prog" | awk '!seen[$0]++')
	(( ${#candidates[@]} )) || return 1

	# A wrapper that offers several files reads the first one that exists and
	# ignores the rest, so an existing file is always the right one to edit.
	for name in "${candidates[@]}"; do
		if [[ -f "$MCA_XDG_CONFIG/$name" ]]; then
			existing_target="$name"
			_mca_flags_write "$MCA_XDG_CONFIG/$name"
		fi
	done
	[[ -n $existing_target ]] && return 0

	# None exists yet. The last candidate is the wrapper's own fallback - the
	# generic electron-flags.conf rather than electron43-flags.conf - so
	# creating that one also covers every other application using the same
	# shared Electron.
	target="${candidates[-1]}"
	_mca_flags_write "$MCA_XDG_CONFIG/$target"
	return 0
}

# _mca_flags_write <file>
# Adds the flags as a marked block, or merges into an --enable-blink-features
# line that is already in the file.
_mca_flags_write() {
	local file="$1" content='' line flag value existing merged=0 block=''
	local -a flags
	local created=0

	read -r -a flags <<< "$(mca_flags)"

	[[ -f $file ]] || created=1
	if (( ! created )); then
		content="$(< "$file")"
		# Already ours: the block is rewritten below, so drop the old one first.
		if [[ $content == *"$MCA_MARK_BEGIN"* ]]; then
			content="$(_mca_flags_drop_block "$file")"
		fi
	fi

	# Merge into a blink-features line the user (or a distribution) put there.
	if [[ $content == *--enable-blink-features=* ]]; then
		local out=''
		while IFS= read -r line; do
			if [[ $line =~ ^[[:space:]]*--enable-blink-features=([A-Za-z0-9,_-]*)[[:space:]]*$ ]]; then
				existing="${BASH_REMATCH[1]}"
				if [[ ",$existing," != *",$MCA_FEATURE,"* ]]; then
					line="--enable-blink-features=${existing:+$existing,}$MCA_FEATURE"
				fi
				merged=1
			fi
			out+="$line"$'\n'
		done <<< "$content"
		content="${out%$'\n'}"
	fi

	for flag in "${flags[@]}"; do
		(( merged )) && [[ $flag == --enable-blink-features=* ]] && continue
		block+="$flag"$'\n'
	done

	if [[ -n $block ]]; then
		content="${content:+$content$'\n'}$MCA_MARK_BEGIN"$'\n'"$block$MCA_MARK_END"
	fi

	if mca_write_if_changed "$file" "$content"$'\n'; then
		MCA_CHANGES=$(( MCA_CHANGES + 1 ))
	fi

	if (( created )); then
		mca_ledger_add flags "$file" created
	elif (( merged )) && [[ -z $block ]]; then
		mca_ledger_add flags "$file" merged
	elif (( merged )); then
		mca_ledger_add flags "$file" merged+block
	else
		mca_ledger_add flags "$file" block
	fi

	# Every application whose flag file was touched counts as covered, so the
	# status line can say how many there are.
	MCA_TOUCHED+=("$file")
	return 0
}

_mca_flags_drop_block() {
	awk -v b="$MCA_MARK_BEGIN" -v e="$MCA_MARK_END" '
		$0 == b { skip = 1; next }
		$0 == e { skip = 0; next }
		!skip
	' "$1" 2>/dev/null
}

# mca_flags_revert <file> <detail>
mca_flags_revert() {
	local file="$1" detail="$2" content line out='' existing new

	[[ -f $file ]] || return 0

	case "$detail" in
		created)
			# Only remove the file if nothing but our block ended up in it;
			# anything else means the user started using it in the meantime.
			content="$(_mca_flags_drop_block "$file")"
			if [[ -z ${content//[[:space:]]/} ]]; then
				rm -f -- "$file"
				return 0
			fi
			;;
	esac

	content="$(_mca_flags_drop_block "$file")"

	if [[ $detail == merged* ]]; then
		while IFS= read -r line; do
			if [[ $line =~ ^[[:space:]]*--enable-blink-features=([A-Za-z0-9,_-]*)[[:space:]]*$ ]]; then
				existing="${BASH_REMATCH[1]}"
				new="${existing//$MCA_FEATURE/}"
				new="${new//,,/,}"; new="${new#,}"; new="${new%,}"
				[[ -z $new ]] && continue
				line="--enable-blink-features=$new"
			fi
			out+="$line"$'\n'
		done <<< "$content"
		content="${out%$'\n'}"
	fi

	if [[ -z ${content//[[:space:]]/} ]]; then
		rm -f -- "$file"
	else
		printf '%s\n' "$content" > "$file"
	fi
	return 0
}

# ---------------------------------------------------------------------------
# Desktop entries
# ---------------------------------------------------------------------------

# _mca_desktop_transform <file> [flags] [position]
# The whole file with every Exec line rewritten - the main one and the one in
# each Desktop Action, because those are the right-click menu entries and a
# user who starts Steam from "Library" expects the same behaviour there.
_mca_desktop_transform() {
	local file="$1" flags="${2:-}" where="${3:-before-fields}"
	local line rest new marked=0

	while IFS= read -r line || [[ -n $line ]]; do
		case "$line" in
			Exec=*)
				rest="${line#Exec=}"
				new="$(mca_exec_inject "$rest" "$flags" "$where")" && line="Exec=$new"
				;;
			# A D-Bus activated entry is started through its service file and
			# the Exec line is never used, so the flag would go nowhere.
			DBusActivatable=true)
				line='DBusActivatable=false'
				;;
			# A marker from an older version; the current one is written below.
			X-MCA-*)
				continue
				;;
		esac

		printf '%s\n' "$line"

		if (( ! marked )) && [[ $line =~ ^[[:space:]]*\[Desktop\ Entry\][[:space:]]*$ ]]; then
			printf 'X-MCA-Generated=%s\n' "$MCA_VERSION"
			marked=1
		fi
	done < "$file"
}

# mca_desktop_apply <id> <source entry> [flags] [position]
# Puts a patched copy in ~/.local/share/applications, or patches the entry in
# place when it already lives there.
mca_desktop_apply() {
	local id="$1" src="$2" flags="${3:-}" where="${4:-before-fields}"
	local target="$MCA_APPDIR/$id.desktop" content backup

	if [[ "$src" == "$target" ]]; then
		# The user's own entry - an AppImage, a web app shortcut, something
		# installed by hand. There is nowhere to shadow it from, so it is
		# edited directly and the original is kept.
		grep -q '^X-MCA-Generated=' "$src" 2>/dev/null && return 0

		content="$(_mca_desktop_transform "$src" "$flags" "$where")"
		[[ -n $content ]] || return 1
		[[ "$content" == "$(< "$src")" ]] && return 0

		backup="$(mca_backup "$src")" || return 1
		if mca_write_if_changed "$src" "$content"$'\n'; then
			MCA_CHANGES=$(( MCA_CHANGES + 1 ))
		fi
		mca_ledger_add inplace "$src" "$backup"
		MCA_TOUCHED+=("$src")
		return 0
	fi

	content="$(_mca_desktop_transform "$src" "$flags" "$where")"
	[[ -n $content ]] || return 1

	mkdir -p "$MCA_APPDIR" 2>/dev/null || return 1

	# Something is already shadowing this entry. If it is not ours it is the
	# user's own override and is left exactly as it is.
	if [[ -e $target ]] && ! grep -q '^X-MCA-Generated=' "$target" 2>/dev/null; then
		return 1
	fi

	if mca_write_if_changed "$target" "$content"$'\n'; then
		MCA_CHANGES=$(( MCA_CHANGES + 1 ))
	fi
	mca_ledger_add shadow "$target" "$src"
	MCA_TOUCHED+=("$target")
	return 0
}

# ---------------------------------------------------------------------------
# Autostart entries
# ---------------------------------------------------------------------------
# Applications that start themselves at login write their own entry into
# ~/.config/autostart, pointing straight at their binary. Those bypass the
# desktop entry in the menu completely, which is why Discord launched at login
# used to behave differently from Discord launched from the menu.

mca_autostart_apply() {
	local dir="$MCA_XDG_CONFIG/autostart" file exec_line prog content backup

	[[ -d $dir ]] || return 0

	for file in "$dir"/*.desktop; do
		[[ -f $file ]] || continue
		grep -q '^X-MCA-Generated=' "$file" 2>/dev/null && continue

		exec_line="$(mca_desktop_get "$file" Exec)"
		[[ -n $exec_line ]] || continue

		mca_exec_program "$exec_line" || continue
		prog="$MCA_PROG"
		mca_is_chromium "$prog" || continue

		content="$(_mca_desktop_transform "$file")"
		[[ -n $content ]] || continue
		[[ "$content" == "$(< "$file")" ]] && continue

		backup="$(mca_backup "$file")" || continue
		if mca_write_if_changed "$file" "$content"$'\n'; then
			MCA_CHANGES=$(( MCA_CHANGES + 1 ))
		fi
		mca_ledger_add inplace "$file" "$backup"
		MCA_TOUCHED+=("$file")
	done
}

# ---------------------------------------------------------------------------
# Spotify
# ---------------------------------------------------------------------------
# The official client is CEF rather than Electron and, when installed through
# spotify-launcher, is started by a program that builds its own command line.
# That launcher has a configuration file with a slot for exactly this.

mca_spotify_apply() {
	local file="$MCA_XDG_CONFIG/spotify-launcher.conf" content line out='' backup
	local found_section=0 found_args=0

	mca_have spotify-launcher || return 0

	if [[ -f $file ]]; then
		content="$(< "$file")"
		while IFS= read -r line; do
			if [[ $line =~ ^[[:space:]]*\[spotify\][[:space:]]*$ ]]; then
				found_section=1
			elif [[ $line =~ ^[[:space:]]*extra_arguments[[:space:]]*=[[:space:]]*\[(.*)\][[:space:]]*$ ]]; then
				local args="${BASH_REMATCH[1]}"
				found_args=1
				if [[ $args != *"$MCA_FEATURE"* ]]; then
					line="extra_arguments = [${args:+$args, }\"$MCA_FLAG\"]"
				fi
			fi
			out+="$line"$'\n'
		done <<< "$content"
		content="${out%$'\n'}"
	fi

	if (( ! found_args )); then
		(( found_section )) || content="${content:+$content$'\n'}[spotify]"
		content="${content:+$content$'\n'}extra_arguments = [\"$MCA_FLAG\"]"
	fi

	[[ -f $file ]] && backup="$(mca_backup "$file")"

	if mca_write_if_changed "$file" "$content"$'\n'; then
		MCA_CHANGES=$(( MCA_CHANGES + 1 ))
	fi
	mca_ledger_add inplace "$file" "${backup:-}"
	MCA_TOUCHED+=("$file")
	return 0
}

# ---------------------------------------------------------------------------
# Undo
# ---------------------------------------------------------------------------

mca_revert_all() {
	local kind path detail

	[[ -f $MCA_LEDGER ]] || return 0

	# Backwards, so a file that was recorded twice ends up at its oldest state.
	while IFS=$'\t' read -r kind path detail; do
		[[ -n $path ]] || continue
		case "$kind" in
			shadow)
				# Only remove what is still recognisably ours.
				if [[ -f $path ]] && grep -q '^X-MCA-Generated=' "$path" 2>/dev/null; then
					rm -f -- "$path"
					MCA_CHANGES=$(( MCA_CHANGES + 1 ))
				fi
				;;
			inplace)
				if [[ -n $detail && -f "$MCA_BACKUPDIR/$detail" ]]; then
					if [[ -e $path ]] || [[ -d "$(dirname -- "$path")" ]]; then
						cp -p -- "$MCA_BACKUPDIR/$detail" "$path" 2>/dev/null \
							&& MCA_CHANGES=$(( MCA_CHANGES + 1 ))
					fi
					rm -f -- "$MCA_BACKUPDIR/$detail"
				elif [[ -f $path ]]; then
					# No backup: the file did not exist before we wrote it.
					rm -f -- "$path"
					MCA_CHANGES=$(( MCA_CHANGES + 1 ))
				fi
				;;
			flags)
				mca_flags_revert "$path" "$detail" \
					&& MCA_CHANGES=$(( MCA_CHANGES + 1 ))
				;;
			steam)
				mca_steam_revert "$path" "$detail" \
					&& MCA_CHANGES=$(( MCA_CHANGES + 1 ))
				;;
		esac
	done < <(tac "$MCA_LEDGER" 2>/dev/null)

	rm -f -- "$MCA_LEDGER"
	rmdir "$MCA_BACKUPDIR" 2>/dev/null || true
	return 0
}
