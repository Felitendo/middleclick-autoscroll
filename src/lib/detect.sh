# shellcheck shell=bash
#
# Finding the applications and deciding which of them are Chromium underneath.
#
# The detection is deliberately conservative. A wrong "yes" appends an unknown
# argument to something that is not Chromium, and plenty of programs treat an
# unrecognised argument as a file name to open - so every rule here is a
# positive one, and anything that cannot be identified is reported as unknown
# rather than guessed at.

# Files that only ever sit next to a Chromium or Electron binary. Any single one
# is conclusive; together they cover both bundled Electron (app.asar, the
# swiftshader libraries) and plain CEF (libcef).
#
# Deliberately not in here: libEGL.so and libffmpeg.so. Chromium ships both, but
# so does the system - /usr/lib/libEGL.so exists on any machine with Mesa - and
# a marker that can be somebody else's file is not a marker.
MCA_MARKERS=(
	chrome_crashpad_handler chrome-sandbox chrome_100_percent.pak
	icudtl.dat v8_context_snapshot.bin snapshot_blob.bin resources.pak
	libvk_swiftshader.so LICENSES.chromium.html libcef.so
)

# The markers that still mean something when the whole of a tree is searched
# rather than just the directory the binary sits in - inside a Flatpak, a snap
# or an AppImage, where there is no "next to the binary" to look at.
#
# Three of the names above are missing here on purpose. icudtl.dat is ICU's
# data file and not Chromium's: a Flutter application ships one in data/, and
# a whole-tree search would find it. snapshot_blob.bin and resources.pak are
# the same kind of shared name. Next to a binary they are still evidence,
# because nothing but Chromium unpacks its payload there - a few directories
# deeper they are not.
MCA_MARKERS_STRICT=(
	chrome_crashpad_handler chrome-sandbox chrome_100_percent.pak
	v8_context_snapshot.bin libvk_swiftshader.so LICENSES.chromium.html
	libcef.so app.asar
)

# Shared directories, where a marker belongs to the system rather than to the
# program that happens to live there. An application ships its payload in a
# directory of its own; nothing unpacks Chromium straight into /usr/lib.
MCA_SYSTEM_DIRS=(
	/ /bin /lib /lib32 /lib64 /sbin /usr /usr/bin /usr/lib /usr/lib32
	/usr/lib64 /usr/libexec /usr/sbin /usr/local /usr/local/bin
	/usr/local/lib /usr/local/libexec /opt
)

# The same thing for the layouts that put a machine triplet in the path.
# Debian and Ubuntu keep the shared libraries in /usr/lib/x86_64-linux-gnu
# rather than /usr/lib, so that directory is every bit as shared as /usr/lib is
# elsewhere and a marker sitting in it belongs to nobody in particular.
MCA_SYSTEM_DIR_GLOBS=(
	'/usr/lib/*-linux-gnu*' '/usr/lib32/*-linux-gnu*'
	'/usr/lib64/*-linux-gnu*' '/usr/local/lib/*-linux-gnu*'
)

# Where snapd mounts the installed snaps. /snap is the usual place and the one
# the shims point into; distributions that keep /snap free of a top-level
# directory use the second.
MCA_SNAP_DIRS=(/snap /var/lib/snapd/snap)

# Strings in a launcher script that mean it starts a Chromium or Electron
# process, for the wrappers whose command line is assembled out of variables and
# cannot be followed from the outside.
#
# Only strings that no other kind of program has a reason to contain. The word
# "chromium" on its own is not one of them: /usr/bin/xdg-open lists every
# browser it knows how to start, and that is not a browser.
#
# The flag file convention is one distribution's packaging habit and says
# nothing about the engine either, so it is not in here.
#
# CHROMIUM_FLAGS and CHROME_WRAPPER earn their place: they are the variables
# the Debian, Fedora and openSUSE Chromium wrappers and Google's own Chrome
# wrapper build their command line out of, and nothing else sets them.
MCA_SCRIPT_HINTS='ELECTRON_|app\.asar|chrome-sandbox|libcef|enable-blink-features|ozone-platform-hint|CHROMIUM_FLAGS|CHROME_WRAPPER|CHROME_VERSION_EXTRA'

# ---------------------------------------------------------------------------
# Desktop entries
# ---------------------------------------------------------------------------

# Where Flatpak and snapd put the launchers they export. Both add these to
# XDG_DATA_DIRS themselves, through a file in /etc/profile.d - but only for a
# session that was started after they were installed, and only for a session
# manager that reads it at all. They are appended, after everything XDG names,
# so a directory that is already in the search path keeps its own position and
# the ones that were missing are still scanned.
mca_extra_desktop_dirs() {
	printf '%s\n' \
		"$MCA_XDG_DATA/flatpak/exports/share/applications" \
		/var/lib/flatpak/exports/share/applications \
		/var/lib/snapd/desktop/applications
}

# The directories a desktop entry can come from, most specific first - which is
# also XDG lookup order, so the first file found for an id is the one that is
# actually used.
mca_desktop_dirs() {
	local dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" d
	local -A seen=()

	while IFS= read -r d; do
		[[ -n $d ]] || continue
		d="${d%/}"
		[[ -n ${seen[$d]+set} ]] && continue
		seen[$d]=1
		printf '%s\n' "$d"
	done < <(
		printf '%s\n' "$MCA_APPDIR"
		while IFS= read -r -d: d; do
			[[ -n $d ]] && printf '%s/applications\n' "${d%/}"
		done <<< "${dirs}:"
		mca_extra_desktop_dirs
	)
}

# _mca_desktop_read <file>
# Every key the scan needs, in one pass and without a single fork. There are a
# couple of hundred desktop entries on an ordinary system, and doing this with
# one awk per key per file is the difference between a menu that redraws and a
# menu that pauses.
DE_TYPE='' DE_HIDDEN='' DE_EXEC='' DE_NAME='' DE_CATEGORIES='' DE_MIME='' DE_OURS=''

_mca_desktop_read() {
	local file="$1" line ingroup=0

	DE_TYPE=''; DE_HIDDEN=''; DE_EXEC=''; DE_NAME=''
	DE_CATEGORIES=''; DE_MIME=''; DE_OURS=''

	while IFS= read -r line || [[ -n $line ]]; do
		case "$line" in
			'[Desktop Entry]'*) ingroup=1; continue ;;
			'['*)               ingroup=0; continue ;;
		esac
		(( ingroup )) || continue

		# Locale variants are Name[de]= and never match these patterns, which
		# is what we want: the untranslated key is the identifying one.
		case "$line" in
			Exec=*)            [[ -n $DE_EXEC ]] || DE_EXEC="${line#Exec=}" ;;
			Name=*)            [[ -n $DE_NAME ]] || DE_NAME="${line#Name=}" ;;
			Type=*)            DE_TYPE="${line#Type=}" ;;
			Hidden=*)          DE_HIDDEN="${line#Hidden=}" ;;
			Categories=*)      DE_CATEGORIES="${line#Categories=}" ;;
			MimeType=*)        DE_MIME="${line#MimeType=}" ;;
			# Only a generated shadow. An entry we edited in place carries
			# X-MCA-Patched and is still the application's real entry, so it
			# has to stay in the scan.
			X-MCA-Generated=*) DE_OURS=1 ;;
		esac
	done < "$file"
}

# mca_exec_program <exec line>
# The program a desktop entry actually starts: the first token that is not an
# environment prefix, resolved to an absolute path. The result is left in
# MCA_PROG rather than printed - the scan calls this for every desktop entry on
# the system, and a command substitution each time is a fork each time.
#
# Fails for entries this tool has no safe way to rewrite: anything routed
# through a shell, where the real program is inside a quoted string.
MCA_PROG=''

mca_exec_program() {
	local line="$1" tok prog=''
	local -a tokens

	MCA_PROG=''

	# Field codes are placeholders, not arguments, and quotes only ever wrap
	# whole tokens here; splitting on whitespace is enough to find token one.
	read -r -a tokens <<< "$line"

	for tok in "${tokens[@]}"; do
		tok="${tok%\"}"; tok="${tok#\"}"
		tok="${tok%\'}"; tok="${tok#\'}"
		[[ -z $tok ]] && continue
		[[ $tok == *=* && $tok != /* ]] && continue   # VAR=value prefix
		[[ $tok == env ]] && continue
		prog="$tok"
		break
	done

	[[ -n $prog ]] || return 1

	case "${prog##*/}" in
		sh|bash|dash|zsh|fish) return 1 ;;
	esac

	# PATH is searched here rather than with `command -v`, which is a builtin
	# but would have to be read back through a command substitution, and that
	# is a fork per desktop entry.
	if [[ $prog != /* ]]; then
		local d found=''
		local -a pathdirs
		IFS=: read -r -a pathdirs <<< "$PATH"
		for d in "${pathdirs[@]}"; do
			[[ -n $d ]] || continue
			if [[ -x "$d/$prog" && ! -d "$d/$prog" ]]; then found="$d/$prog"; break; fi
		done
		[[ -n $found ]] || return 1
		prog="$found"
	fi

	MCA_PROG="$prog"
}

# mca_exec_flatpak_id <exec line>
# The application id out of a `flatpak run ...` command line, in MCA_PROG.
mca_exec_flatpak_id() {
	local line="$1" tok seen_run=0
	local -a tokens
	read -r -a tokens <<< "$line"

	MCA_PROG=''
	for tok in "${tokens[@]}"; do
		if (( ! seen_run )); then
			[[ $tok == run ]] && seen_run=1
			continue
		fi
		[[ $tok == -* || $tok == @@* || $tok == %* ]] && continue
		[[ $tok == *.*.* ]] || continue
		MCA_PROG="$tok"
		return 0
	done
	return 1
}

# mca_exec_is_steam_link <exec line> <program>
# Whether an entry starts something inside Steam rather than starting Steam
# itself: it carries a steam:// address of its own. Steam writes one of those
# for every game somebody asks for a shortcut to, and the client's own entry
# never has one - it takes an address from the outside, through %U.
mca_exec_is_steam_link() {
	local line="$1" prog="$2"

	[[ $line == *steam://* ]] || return 1
	mca_prog_is_steam "$prog"
}

# _mca_prog_is_steam_name <program>
# The launcher under one of the names Valve and the distributions give it.
_mca_prog_is_steam_name() {
	case "${1##*/}" in
		steam|steam-runtime|steam-native|steam-jupiter) return 0 ;;
	esac
	return 1
}

# _mca_prog_is_steam_wrapper <program>
# Whether a script in front of the client is a way of starting Steam. People
# put one there to add a switch of their own, and an entry pointing at it is a
# Steam start like any other - but the script is not named after Steam, so
# nothing above recognises it.
#
# Getting this wrong is worse than it sounds: such a script tends to mention
# the flag it is there to add, which is one of the markers that say "Chromium"
# to the hint scan. The entry then ends up being handled as an application and
# is given the flag on its command line, where Steam ignores it, instead of
# being handed to the Steam module that knows how to reach the web helper.
#
# Only the handover is followed, and only one step of it: the client's own
# launcher is already recognised by name, so a wrapper in front of it is the
# whole of what is left.
_mca_prog_is_steam_wrapper() {
	local prog="$1" head='' target

	[[ $prog == /* && -f $prog && -r $prog ]] || return 1

	# Two characters, read in the shell: the scan asks this about every program
	# on the system, and most of them are binaries whose first line is the whole
	# file.
	read -r -N 2 head < "$prog" 2>/dev/null || return 1
	[[ $head == '#!' ]] || return 1

	target="$(_mca_script_target "$prog")" || return 1
	[[ -n $target ]] || return 1
	_mca_prog_is_steam_name "$target"
}

# mca_prog_is_steam <program>
# Whether running this program starts the Steam client. Every packaging is in
# here and every name Valve and the distributions give the launcher, because
# the answer decides whether an entry gets Steam's own switch - and an entry
# that starts Steam without it undoes the web helper patch on the way up.
#
# The program is what a scan leaves behind: an absolute path for a native
# install, flatpak:<id> or snap:<name> for the other two.
mca_prog_is_steam() {
	local prog="$1"

	_mca_prog_is_steam_name "$prog" && return 0
	[[ $prog == flatpak:com.valvesoftware.Steam || $prog == snap:steam ]] && return 0
	_mca_prog_is_steam_wrapper "$prog"
}

# ---------------------------------------------------------------------------
# Is this Chromium?
# ---------------------------------------------------------------------------

# Answers are cached against size and mtime, because the systemd path unit can
# fire several times in a row while a package installs and each miss costs a
# scan of a 200 MB binary.
#
# The file is read once into memory rather than searched per lookup: a scan
# asks about every program on the system, and an awk per question is most of
# the time the scan takes.
declare -A MCA_DETECT_MEMO=()
declare -A MCA_DETECT_CACHE=()
MCA_CACHE_LOADED=0
MCA_CACHE_DIRTY=0

# Size and mtime for every program the scan is about to ask about, collected in
# one call. Checking a cache entry is still stale needs a stat, and one stat per
# program on the system was most of what a warm scan spent its time on.
declare -A MCA_STAT=()

_mca_stat_batch() {
	local name st
	(( $# )) || return 0
	while IFS=$'\t' read -r name st; do
		[[ -n $name ]] && MCA_STAT["$name"]="$st"
	done < <(stat -Lc '%n	%s:%Y' -- "$@" 2>/dev/null)
	return 0
}

# The first line of the cache file, and the reason it is there: the verdicts
# below it are keyed on size and mtime, so an entry for a file that has not
# changed is never looked at again. A cache written when a verdict meant
# something else - before an AppImage could come out as anything but "no" -
# would therefore keep answering the old way forever. Bumping this is how such
# a cache gets dropped instead.
MCA_CACHE_FORMAT='# middleclick-autoscroll detect 2'

_mca_cache_load() {
	local path stamp verdict first=1

	(( MCA_CACHE_LOADED )) && return 0
	MCA_CACHE_LOADED=1

	[[ -r "$MCA_CACHEDIR/detect" ]] || return 0
	while IFS=$'\t' read -r path stamp verdict; do
		if (( first )); then
			first=0
			[[ $path == "$MCA_CACHE_FORMAT" ]] || return 0
			continue
		fi
		[[ -n $path && -n $stamp ]] || continue
		MCA_DETECT_CACHE["$path"]="$stamp"$'\t'"$verdict"
	done < "$MCA_CACHEDIR/detect"
	return 0
}

# Written back once, at exit, instead of after every miss.
mca_cache_flush() {
	local path entry tmp

	(( MCA_CACHE_DIRTY )) || return 0
	mkdir -p "$MCA_CACHEDIR" 2>/dev/null || return 0

	tmp="$(mktemp "$MCA_CACHEDIR/detect.XXXXXX")" || return 0
	printf '%s\n' "$MCA_CACHE_FORMAT" > "$tmp"
	for path in "${!MCA_DETECT_CACHE[@]}"; do
		entry="${MCA_DETECT_CACHE[$path]}"
		printf '%s\t%s\n' "$path" "$entry" >> "$tmp"
	done
	mv -f "$tmp" "$MCA_CACHEDIR/detect" 2>/dev/null || rm -f "$tmp"
	MCA_CACHE_DIRTY=0
	return 0
}

# _mca_has_markers <directory>
_mca_has_markers() {
	local dir="$1" m s

	[[ -d $dir ]] || return 1
	dir="${dir%/}"
	for s in "${MCA_SYSTEM_DIRS[@]}"; do
		[[ $dir == "$s" ]] && return 1
	done
	for s in "${MCA_SYSTEM_DIR_GLOBS[@]}"; do
		# Unquoted on purpose - these are patterns, not names.
		# shellcheck disable=SC2053
		[[ $dir == $s ]] && return 1
	done

	for m in "${MCA_MARKERS[@]}"; do
		[[ -e "$dir/$m" ]] && return 0
	done
	[[ -e "$dir/resources/app.asar" || -e "$dir/app.asar" ]] && return 0
	return 1
}

# _mca_find_markers <directory> <depth>
# The same question for a whole tree, which is the shape a Flatpak, a snap and
# an unpacked AppImage come in: everything the application ships is somewhere
# under one root and there is no single directory that is "next to the binary".
# Hence the narrower list - see MCA_MARKERS_STRICT.
_mca_find_markers() {
	local root="$1" depth="$2" m
	local -a names=()

	[[ -d $root ]] || return 1

	for m in "${MCA_MARKERS_STRICT[@]}"; do
		(( ${#names[@]} )) && names+=(-o)
		names+=(-name "$m")
	done

	[[ -n "$(find "$root" -maxdepth "$depth" \
		\( "${names[@]}" \) -print -quit 2>/dev/null)" ]]
}

# The plain assignments the script made before it handed over, for
# _mca_script_subst to read. A variable of its own rather than something passed
# around: every caller of _mca_script_target reads it through a command
# substitution, so each call already works on a copy and there is nothing here
# that two of them could collide over.
declare -A MCA_SCRIPT_VARS=()

# _mca_script_subst <text>
# The text with $NAME and ${NAME} replaced by what the script assigned to them,
# left in MCA_SUBST.
#
# Fails as soon as something turns up that only a running shell could work out
# - a positional parameter, a name the script never set, a default value. That
# is the point: an unresolvable path has to come out as no path at all, never
# as a wrong one.
MCA_SUBST=''

_mca_script_subst() {
	local text="$1" out='' rest name

	while [[ $text == *'$'* ]]; do
		out+="${text%%\$*}"
		rest="${text#*\$}"

		if [[ $rest == '{'* ]]; then
			[[ $rest == *'}'* ]] || return 1
			name="${rest%%\}*}"; name="${name#\{}"
			rest="${rest#*\}}"
		else
			name="${rest%%[!A-Za-z0-9_]*}"
			rest="${rest:${#name}}"
		fi

		[[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
		[[ -n ${MCA_SCRIPT_VARS[$name]+set} ]] || return 1

		out+="${MCA_SCRIPT_VARS[$name]}"
		text="$rest"
	done

	MCA_SUBST="$out$text"
	return 0
}

# _mca_script_target <script>
# The program a wrapper script hands over to, so a chain like
# heroic -> electron43 -> /usr/lib/electron43/electron can be followed.
#
# The assignments above the exec line are followed as well, because that is the
# shape the Chromium wrappers outside Arch have: Debian, Ubuntu, Fedora and
# openSUSE all set the directory and the program name into variables at the top
# of the script and end on `exec -a "$APPNAME" "$LIBDIR/$APPNAME"`. Without
# resolving those there is nothing to follow, and the answer would have to come
# from the hint scan - a weaker kind of evidence than finding the binary and
# its markers.
_mca_script_target() {
	local script="$1" line tok name val skip=0
	local -a tokens
	local re_assign='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=([^[:space:];|&()`]*)[[:space:]]*$'

	MCA_SCRIPT_VARS=()

	while IFS= read -r line; do
		if [[ $line =~ $re_assign ]]; then
			name="${BASH_REMATCH[2]}"
			val="${BASH_REMATCH[3]}"

			# One pair of quotes around the whole value is ordinary and means
			# nothing here. Single quotes also mean the value is literal, so
			# there is nothing left to expand.
			if [[ $val == \'*\' ]]; then
				MCA_SCRIPT_VARS[$name]="${val:1:${#val}-2}"
				continue
			fi
			[[ $val == \"*\" ]] && val="${val:1:${#val}-2}"

			if _mca_script_subst "$val"; then
				MCA_SCRIPT_VARS[$name]="$MCA_SUBST"
			else
				# Not resolvable, so anything built from it must not be either.
				unset "MCA_SCRIPT_VARS[$name]"
			fi
			continue
		fi

		[[ $line =~ ^[[:space:]]*exec[[:space:]]+(.*)$ ]] || continue
		read -r -a tokens <<< "${BASH_REMATCH[1]}"
		skip=0
		for tok in "${tokens[@]}"; do
			(( skip )) && { skip=0; continue; }
			case "$tok" in
				env) continue ;;
				# `exec -a NAME PROG` renames the process. NAME is not a
				# program, and it is usually the wrapper's own name, so
				# following it would lead straight back here.
				-a|--argv0) skip=1; continue ;;
				-*) continue ;;
			esac
			[[ $tok == *=* && $tok != /* ]] && continue

			tok="${tok%\"}"; tok="${tok#\"}"
			tok="${tok%\'}"; tok="${tok#\'}"

			# Anything still carrying a shell variable is resolved from the
			# assignments above, or not at all; the hint scan answers for the
			# wrappers that build their command line some other way.
			if [[ $tok == *'$'* ]]; then
				_mca_script_subst "$tok" || return 1
				tok="$MCA_SUBST"
			fi
			[[ -n $tok ]] || return 1

			if [[ $tok == /* ]]; then
				printf '%s\n' "$tok"
			else
				command -v "$tok" 2>/dev/null
			fi
			return $?
		done
	done < "$script"
	return 1
}

# mca_flags_candidates <program>
# The flag files a launcher reads, in the order it reads them, taken from the
# launcher itself rather than assumed from the distribution. Where the wrappers
# follow that convention - Arch's Electron and Chromium packages do, and take
# extra arguments from $XDG_CONFIG_HOME/<name>-flags.conf - it is a far better
# place to inject than a desktop entry: it survives package updates and it
# applies to a launch from the terminal too. Where they do not, this finds
# nothing and the caller falls back to the desktop entry.
mca_flags_candidates() {
	local prog="$1" depth="${2:-0}" target inherited
	(( depth > 3 )) && return 0
	[[ -r $prog ]] || return 0
	head -c2 -- "$prog" 2>/dev/null | grep -q '#!' || return 0

	grep -oE '[A-Za-z0-9_.+-]+-flags\.conf' -- "$prog" 2>/dev/null

	# A wrapper that only execs another wrapper (heroic -> electron43) inherits
	# that one's flag files, plus the specific name it builds from a variable
	# at runtime and therefore never writes down - which is why that one is
	# derived from the target's own name rather than found.
	#
	# It is derived only once the target has shown that it reads a flag file at
	# all. Every launcher that can be followed is not a launcher that reads
	# one: the Chromium wrappers outside Arch do not, and neither does an
	# ordinary program that simply execs its own binary. Naming a file for
	# those would put the flag somewhere nothing ever looks and skip the
	# desktop entry that would have worked.
	if target="$(_mca_script_target "$prog")" && [[ -n $target ]]; then
		inherited="$(mca_flags_candidates "$target" $(( depth + 1 )))"
		if [[ -n $inherited ]]; then
			printf '%s-flags.conf\n' "${target##*/}"
			printf '%s\n' "$inherited"
		fi
	fi
}

# ---------------------------------------------------------------------------
# Looking inside an AppImage
# ---------------------------------------------------------------------------
#
# An AppImage is the AppImage runtime - an ordinary ELF executable - with a
# squashfs image appended to it. The payload is compressed, so nothing the
# application ships is on disk where the marker check could find it, and for a
# long time that made every AppImage a "cannot tell".
#
# It does not have to be. squashfs keeps the names of everything it holds in
# one table of its own, the table is a few kilobytes, and the names are the
# whole of what this question needs. So that table is read and inflated here -
# rather than unpacking a hundred megabytes, and rather than running the image
# to ask it, which is the one thing a scan started by a path unit must never
# do.
#
# Everything below fails closed. The moment a field is not where it should be,
# or the compressor is one there is no tool for, the answer goes back to
# "cannot tell" and the application is left to the applications screen.

# _mca_bytes <file> <offset> <count>
# Count bytes from an offset, as numbers, in MCA_BYTES. od rather than a shell
# read because a variable cannot hold a NUL byte and these headers are full of
# them - and a whole header at a time rather than a field at a time, because
# the first question below is asked about every program on the system and one
# od per field would be four forks per program.
MCA_BYTES=()

_mca_bytes() {
	local file="$1" off="$2" count="$3"

	MCA_BYTES=()

	# read stops on end of input rather than on the delimiter it was given, so
	# it reports failure for input that is perfectly complete. The count is
	# the check.
	read -r -d '' -a MCA_BYTES \
		< <(od -An -tu1 -j"$off" -N"$count" -v -- "$file" 2>/dev/null)

	(( ${#MCA_BYTES[@]} == count ))
}

# _mca_slice <file> <offset> <length>
# Length bytes from an offset, on stdout.
_mca_slice() {
	dd if="$1" bs=65536 iflag=skip_bytes,count_bytes \
		skip="$2" count="$3" status=none 2>/dev/null
}

# _mca_word <index>
# One 64-bit little-endian field out of MCA_BYTES, in MCA_WORD. Assigns rather
# than prints for the same reason _mca_bytes reads a whole header at a time:
# printing means a command substitution, and that is a fork per field.
#
# Fails for the all-ones value squashfs writes down for a table that is not in
# the image, which is a case the callers below have to tell from a real offset
# and bash arithmetic - signed, 64-bit - cannot represent.
MCA_WORD=0

_mca_word() {
	local at="$1"

	(( ${#MCA_BYTES[@]} >= at + 8 )) || return 1
	(( MCA_BYTES[at+7] == 255 && MCA_BYTES[at+6] == 255 )) && return 1

	MCA_WORD=$(( (MCA_BYTES[at] | MCA_BYTES[at+1] << 8 \
		| MCA_BYTES[at+2] << 16 | MCA_BYTES[at+3] << 24) \
		| ((MCA_BYTES[at+4] | MCA_BYTES[at+5] << 8 \
		| MCA_BYTES[at+6] << 16 | MCA_BYTES[at+7] << 24) << 32) ))
	return 0
}

# _mca_appimage_offset <file>
# Where the appended image starts, in MCA_APPIMAGE_AT: directly after the ELF,
# which is where its section header table ends. This is how the runtime works
# it out for --appimage-offset, and it is exact.
#
# Searching for the squashfs magic instead would not be: the runtime carries a
# copy of it in its own code. Neither is the AppImage magic at byte 8 of the
# ELF header a way in - it is there to be zeroed, and a build pipeline that
# does not want its image picked up by a desktop integration daemon does
# exactly that. So the offset is computed for any ELF at all and the caller
# finds out whether there is an image at it.
MCA_APPIMAGE_AT=0

_mca_appimage_offset() {
	local shoff shentsize shnum

	MCA_APPIMAGE_AT=0
	_mca_bytes "$1" 0 64 || return 1

	# \x7fELF, and then the class byte: 2 for the 64-bit header, 1 for the
	# 32-bit one, which puts every field after it somewhere else.
	(( MCA_BYTES[0] == 127 && MCA_BYTES[1] == 69 \
		&& MCA_BYTES[2] == 76 && MCA_BYTES[3] == 70 )) || return 1

	if (( MCA_BYTES[4] == 2 )); then
		_mca_word 40 || return 1
		shoff="$MCA_WORD"
		shentsize=$(( MCA_BYTES[58] | MCA_BYTES[59] << 8 ))
		shnum=$(( MCA_BYTES[60] | MCA_BYTES[61] << 8 ))
	elif (( MCA_BYTES[4] == 1 )); then
		shoff=$(( MCA_BYTES[32] | MCA_BYTES[33] << 8 \
			| MCA_BYTES[34] << 16 | MCA_BYTES[35] << 24 ))
		shentsize=$(( MCA_BYTES[46] | MCA_BYTES[47] << 8 ))
		shnum=$(( MCA_BYTES[48] | MCA_BYTES[49] << 8 ))
	else
		return 1
	fi

	(( shoff > 0 && shentsize > 0 && shnum > 0 )) || return 1
	MCA_APPIMAGE_AT=$(( shoff + shentsize * shnum ))
	return 0
}

# _mca_inflate <compressor> <file> <offset> <length>
# One squashfs metadata block, decompressed onto stdout.
#
# lzo and lz4 are missing because squashfs stores them as bare blocks and
# neither lzop nor the lz4 tool will read one without the framing their own
# file format puts around it. An image compressed with either comes out as
# "cannot tell", which is where it started.
_mca_inflate() {
	local comp="$1" file="$2" off="$3" len="$4"

	case "$comp" in
		1)
			# squashfs stores a zlib stream and gzip only reads its own
			# container, but underneath both are the same deflate data with a
			# different wrapper around it - so the wrapper is swapped: zlib's
			# two header bytes are dropped and a minimal gzip header put in
			# front. gzip then writes every byte of the block and complains
			# about the trailer it did not get, which is why its status is
			# thrown away here and the check is on the output instead.
			(( len > 2 )) || return 1
			{
				printf '\037\213\010\000\000\000\000\000\000\003'
				_mca_slice "$file" $(( off + 2 )) $(( len - 2 ))
			} | { gzip -dc 2>/dev/null || true; }
			;;
		2)
			mca_have xz || return 1
			_mca_slice "$file" "$off" "$len" \
				| { xz -dc --format=lzma 2>/dev/null || true; }
			;;
		4)
			mca_have xz || return 1
			_mca_slice "$file" "$off" "$len" | { xz -dc 2>/dev/null || true; }
			;;
		6)
			mca_have zstd || return 1
			_mca_slice "$file" "$off" "$len" | { zstd -dc 2>/dev/null || true; }
			;;
		*)  return 1 ;;
	esac
}

# _mca_squashfs_names <file> <offset>
# The directory table of the image at that offset, inflated onto stdout. It is
# not parsed: the names sit in it as plain text between the records that
# describe them, and a name is all the caller is looking for.
#
# Fails unless the walk lands exactly on the end of the table. That is the
# integrity check - the block sizes adding up to the table's own length is
# what says the fields were read from a real superblock and that the output is
# the whole of the names rather than some of them - and it is why the caller
# has to collect this before trusting it, never pipe it.
_mca_squashfs_names() {
	local file="$1" base="$2"
	local comp dir_start end field header size pos

	_mca_bytes "$file" "$base" 96 || return 1
	comp=$(( MCA_BYTES[20] | MCA_BYTES[21] << 8 ))

	_mca_word 72 || return 1
	dir_start="$MCA_WORD"
	(( dir_start > 0 )) || return 1

	# Where the names stop: the first table squashfs writes after them. Which
	# one that is depends on the image - there is no fragment table when
	# nothing was packed into a fragment, and no export table unless it was
	# asked for - so they are tried in the order they are written and the
	# first one that is actually there wins. bytes_used closes the list for an
	# image that has none of them.
	end=0
	for field in 80 88 48 40; do
		_mca_word "$field" || continue
		(( MCA_WORD > dir_start )) || continue
		end="$MCA_WORD"
		break
	done
	(( end > dir_start )) || return 1

	# Names for a hundred thousand files would still fit in a fraction of
	# this. A table that claims more than it is a table that was misread.
	(( end - dir_start > 8388608 )) && return 1

	pos=$(( base + dir_start ))
	end=$(( base + end ))

	while (( pos < end )); do
		_mca_bytes "$file" "$pos" 2 || return 1
		header=$(( MCA_BYTES[0] | MCA_BYTES[1] << 8 ))
		size=$(( header & 0x7fff ))
		(( size > 0 && pos + 2 + size <= end )) || return 1

		# The top bit says the block was stored as it is, which squashfs does
		# for the ones compression made no smaller.
		if (( header & 0x8000 )); then
			_mca_slice "$file" $(( pos + 2 )) "$size" || return 1
		else
			_mca_inflate "$comp" "$file" $(( pos + 2 )) "$size" || return 1
		fi

		pos=$(( pos + 2 + size ))
	done

	(( pos == end ))
}

# _mca_appimage_verdict <file>
# What the image appended to this file contains, left in MCA_APPIMAGE:
#   yes      - Chromium, CEF or Electron
#   no       - the names of everything inside were read and none of them is
#   unknown  - there is an image, but its contents could not be read
#   none     - not an AppImage; there is nothing appended to this ELF
MCA_APPIMAGE=none

_mca_appimage_verdict() {
	local file="$1" base names m
	local -a args=()

	MCA_APPIMAGE=none

	_mca_appimage_offset "$file" || return 0
	base="$MCA_APPIMAGE_AT"

	# hsqs, the squashfs magic. Nothing there means nothing was appended, so
	# this is an ordinary executable and not an AppImage at all.
	_mca_bytes "$file" "$base" 4 || return 0
	(( MCA_BYTES[0] == 104 && MCA_BYTES[1] == 115 \
		&& MCA_BYTES[2] == 113 && MCA_BYTES[3] == 115 )) || return 0

	# From here on there is an image, so the worst this can end on is "cannot
	# tell" - never "no", which would be an answer about contents that were
	# never read.
	MCA_APPIMAGE=unknown

	names="$(mktemp "${TMPDIR:-/tmp}/mca-names.XXXXXX")" || return 0

	# Nothing at all in the table means every block failed to inflate - a
	# compressor whose tool is not installed - which is a "cannot tell" too.
	if _mca_squashfs_names "$file" "$base" > "$names" 2>/dev/null \
		&& [[ -s $names ]]
	then
		for m in "${MCA_MARKERS_STRICT[@]}"; do args+=(-e "$m"); done
		if grep -qaF "${args[@]}" -- "$names"; then
			MCA_APPIMAGE=yes
		else
			MCA_APPIMAGE=no
		fi
	fi

	rm -f -- "$names"
	return 0
}

# mca_detect_verdict <program>
# What running this program starts, left in MCA_VERDICT:
#   yes      - Chromium, CEF or Electron
#   no       - something else
#   unknown  - an image whose payload could not be read, so neither answer has
#              been earned and the applications screen offers it as a choice
#
# Assigns rather than returns three states through an exit code, and is the one
# place the memo and the on-disk cache are consulted.
MCA_VERDICT=''

mca_detect_verdict() {
	local prog="$1" real stamp cached

	MCA_VERDICT=no
	[[ -n $prog && -e $prog ]] || return 0

	# Memoized under the path as given, so the same launcher named twice in a
	# scan costs nothing at all the second time.
	if [[ -n ${MCA_DETECT_MEMO[$prog]+set} ]]; then
		MCA_VERDICT="${MCA_DETECT_MEMO[$prog]}"
		return 0
	fi

	_mca_cache_load

	if [[ -n ${MCA_STAT[$prog]+set} ]]; then
		stamp="${MCA_STAT[$prog]}"
	else
		stamp="$(stat -Lc '%s:%Y' -- "$prog" 2>/dev/null)" || stamp=''
	fi

	if [[ -n $stamp && -n ${MCA_DETECT_CACHE[$prog]+set} ]]; then
		cached="${MCA_DETECT_CACHE[$prog]}"
		if [[ "${cached%%$'\t'*}" == "$stamp" ]]; then
			MCA_VERDICT="${cached#*$'\t'}"
			MCA_DETECT_MEMO[$prog]="$MCA_VERDICT"
			return 0
		fi
	fi

	real="$(readlink -f -- "$prog" 2>/dev/null)" || real="$prog"

	MCA_DETECT_UNSURE=0
	if _mca_detect_uncached "$real"; then
		MCA_VERDICT=yes
	elif (( MCA_DETECT_UNSURE )); then
		MCA_VERDICT=unknown
	else
		MCA_VERDICT=no
	fi

	MCA_DETECT_MEMO[$prog]="$MCA_VERDICT"
	if [[ -n $stamp ]]; then
		MCA_DETECT_CACHE["$prog"]="$stamp"$'\t'"$MCA_VERDICT"
		MCA_CACHE_DIRTY=1
	fi
	return 0
}

# mca_is_chromium <program>
# Succeeds when the program is a Chromium, CEF or Electron process. "Cannot
# tell" is not that, so it fails here - anything that has to treat the two
# differently asks mca_detect_verdict instead.
mca_is_chromium() {
	mca_detect_verdict "$1"
	[[ $MCA_VERDICT == yes ]]
}

# Set by _mca_detect_uncached when it reaches the end without finding anything
# and the reason is that something could not be read, rather than that there
# was nothing there. Only mca_detect_verdict reads it, straight after the call.
MCA_DETECT_UNSURE=0

_mca_detect_uncached() {
	local real="$1" depth="${2:-0}" dir target

	(( depth > 3 )) && return 1
	[[ -r $real ]] || return 1

	if head -c2 -- "$real" 2>/dev/null | grep -q '#!'; then
		# A launcher script. Following where it hands over is the reliable
		# answer; the hint scan catches the ones that build the command line
		# out of variables (vesktop, discord and most vendor wrappers).
		if target="$(_mca_script_target "$real")" && [[ -n $target ]]; then
			_mca_detect_uncached "$(readlink -f -- "$target" 2>/dev/null || printf '%s' "$target")" \
				$(( depth + 1 )) && return 0
		fi
		grep -qE "$MCA_SCRIPT_HINTS" -- "$real" 2>/dev/null && return 0
		return 1
	fi

	# A binary. Everything Chromium ships is unpacked next to it, either in the
	# same directory or - for /opt/thing/bin/Thing layouts - one level up.
	dir="$(dirname -- "$real")"
	_mca_has_markers "$dir" && return 0
	[[ ${dir##*/} == bin ]] && _mca_has_markers "${dir%/*}" && return 0

	# An AppImage keeps all of that inside a filesystem appended to itself, so
	# there is nothing next to the binary to find - but the names of everything
	# in there can be read, and that settles it either way.
	_mca_appimage_verdict "$real"
	case "$MCA_APPIMAGE" in
		yes) return 0 ;;
		no)  return 1 ;;
	esac

	# Last resort: Chromium's own argument table is in the binary. -m1 stops at
	# the first hit, so this reads far less than the file size suggests.
	grep -qaFm1 -- 'enable-blink-features' "$real" 2>/dev/null && return 0
	grep -qaFm1 -- 'CHROME_VERSION_EXTRA' "$real" 2>/dev/null && return 0

	# What is left is an image that could not be read - an unsupported
	# compressor - or the older AppImage layout, which is an ISO9660 filesystem
	# and has no name table of this shape at all. Either way the answer is not
	# "no", it is "nobody looked".
	if [[ $MCA_APPIMAGE == unknown || $real == *.AppImage || $real == *.appimage ]]; then
		MCA_DETECT_UNSURE=1
	fi

	return 1
}

# ---------------------------------------------------------------------------
# The scan
# ---------------------------------------------------------------------------
# Results land in parallel arrays rather than being printed, so the caller can
# use them for both patching and the applications screen without scanning twice.

MCA_IDS=()        # desktop file id, without the .desktop suffix
MCA_FILES=()      # the desktop entry that is in effect for that id
MCA_NAMES=()      # display name
MCA_PROGS=()      # resolved program, or a Flatpak app id or a snap name
MCA_KINDS=()      # app | browser | steam | unknown | no
MCA_PACKAGING=()  # native | flatpak | snap

# A scan reads every desktop entry on the system, so the menu does it once and
# then redraws from what it found. Applying rescans on its own, so nothing else
# has to remember to invalidate this.
MCA_SCANNED=0

mca_scan_once() {
	(( MCA_SCANNED )) && return 0
	mca_scan
}

mca_scan() {
	local dir file id name exec_line prog kind packaging i
	local -A seen=()
	local -a c_ids=() c_files=() c_names=() c_progs=() c_browser=() c_stat=()

	MCA_IDS=(); MCA_FILES=(); MCA_NAMES=(); MCA_PROGS=(); MCA_KINDS=()
	MCA_PACKAGING=()

	# Pass one: read the entries and work out what each of them starts. No
	# detection yet - that needs a stat per program, and those are collected so
	# they can be asked for all at once.
	while IFS= read -r dir; do
		[[ -d $dir ]] || continue
		for file in "$dir"/*.desktop; do
			[[ -f $file ]] || continue

			id="${file##*/}"; id="${id%.desktop}"
			[[ -n ${seen[$id]+set} ]] && continue
			seen[$id]=1

			_mca_desktop_read "$file"

			# One of our own generated entries. It describes the same
			# application as the system one it shadows, so it is skipped and
			# the id left free for the original further down the search path.
			[[ -n $DE_OURS ]] && { unset "seen[$id]"; continue; }

			[[ $DE_TYPE == Application ]] || continue
			[[ $DE_HIDDEN == true ]] && continue

			exec_line="$DE_EXEC"
			[[ -n $exec_line ]] || continue

			name="$DE_NAME"
			[[ -n $name ]] || name="$id"

			mca_exec_program "$exec_line" || continue
			prog="$MCA_PROG"

			if [[ ${prog##*/} == flatpak ]]; then
				mca_exec_flatpak_id "$exec_line" || continue
				prog="flatpak:$MCA_PROG"
			elif mca_snap_name "$prog"; then
				prog="snap:$MCA_PROG"
			fi

			# The shortcuts Steam writes for single games are not
			# applications of their own - a game is whatever engine it was
			# built with, and none of those reads a Chromium argument - and
			# starting the client through one needs nothing on its command
			# line either.
			mca_exec_is_steam_link "$exec_line" "$prog" && continue

			c_ids+=("$id"); c_files+=("$file"); c_names+=("$name")
			c_progs+=("$prog")
			if mca_desktop_is_browser; then c_browser+=(1); else c_browser+=(0); fi
			[[ $prog == /* ]] && c_stat+=("$prog")
		done
	done < <(mca_desktop_dirs)

	MCA_STAT=()
	_mca_stat_batch "${c_stat[@]}"

	# Pass two: decide what each one is. What it does - an application or a
	# browser - and how it was packaged are two separate questions: a Chromium
	# installed as a snap is still a browser, and somebody who has turned
	# browsers off means that one too.
	for i in "${!c_ids[@]}"; do
		prog="${c_progs[i]}"
		kind=no
		packaging=native

		if [[ $prog == flatpak:* ]]; then
			packaging=flatpak
			if mca_prog_is_steam "$prog"; then
				kind=steam
			elif mca_flatpak_is_chromium "${prog#flatpak:}"; then
				(( c_browser[i] )) && kind=browser || kind=app
			fi
			prog="${prog#flatpak:}"
		elif [[ $prog == snap:* ]]; then
			prog="${prog#snap:}"
			packaging=snap
			if [[ $prog == steam ]]; then
				kind=steam
			elif mca_snap_is_chromium "$prog"; then
				(( c_browser[i] )) && kind=browser || kind=app
			fi
		elif mca_prog_is_steam "$prog"; then
			# Steam is Chromium inside, but nothing about it can be changed
			# from a command line argument; it has its own module.
			kind=steam
		else
			mca_detect_verdict "$prog"
			case "$MCA_VERDICT" in
				yes)     (( c_browser[i] )) && kind=browser || kind=app ;;
				unknown) kind=unknown ;;
			esac
		fi

		[[ $kind == no ]] && continue

		MCA_IDS+=("${c_ids[i]}")
		MCA_FILES+=("${c_files[i]}")
		MCA_NAMES+=("${c_names[i]}")
		MCA_PROGS+=("$prog")
		MCA_KINDS+=("$kind")
		MCA_PACKAGING+=("$packaging")
	done

	mca_cache_flush
	MCA_SCANNED=1
}

# mca_has_flags_file <program>
# Whether the program's launcher reads a flag file. Memoized: the status block
# asks this for every application it lists, and answering it means reading the
# launcher script.
declare -A MCA_FLAGS_MEMO=()

mca_has_flags_file() {
	local prog="$1"

	if [[ -z ${MCA_FLAGS_MEMO[$prog]+set} ]]; then
		if [[ -n "$(mca_flags_candidates "$prog")" ]]; then
			MCA_FLAGS_MEMO[$prog]=yes
		else
			MCA_FLAGS_MEMO[$prog]=no
		fi
	fi

	[[ ${MCA_FLAGS_MEMO[$prog]} == yes ]]
}

# A browser is anything that offers itself for http. That is the property that
# matters here: those are the applications where middle click currently pastes
# a URL, so a user may well want them left alone.
#
# Reads the keys _mca_desktop_read left behind, so it only makes sense straight
# after that call.
mca_desktop_is_browser() {
	[[ $DE_CATEGORIES == *WebBrowser* ]] && return 0
	[[ $DE_MIME == *x-scheme-handler/http* ]] && return 0
	return 1
}

# mca_snap_name <program>
# The snap an executable belongs to, left in MCA_PROG - assigned rather than
# printed for the same reason mca_exec_program is: the scan asks this about
# every desktop entry on the system, and a command substitution per entry is a
# fork per entry.
#
# /snap/bin/<name> is the shim snapd puts in PATH and is a symlink to snapd
# itself, so following it lands on /usr/bin/snap and says nothing whatever
# about the application. The name is the only thing that carries information,
# and it is what leads to the mounted tree below.
mca_snap_name() {
	local prog="$1" rest d

	for d in "${MCA_SNAP_DIRS[@]}"; do
		if [[ $prog == "$d/bin/"* ]]; then
			rest="${prog#"$d/bin/"}"
			# A snap that ships several programs names them <snap>.<app>.
			MCA_PROG="${rest%%.*}"
			return 0
		fi
		if [[ $prog == "$d/"* ]]; then
			rest="${prog#"$d/"}"
			MCA_PROG="${rest%%/*}"
			return 0
		fi
	done
	return 1
}

# mca_snap_is_chromium <snap name>
# A snap keeps everything it ships inside its own mounted revision, so the
# marker check works the same way there as anywhere else once that tree has
# been located. "current" is the symlink snapd keeps pointing at the revision
# that will actually be started.
mca_snap_is_chromium() {
	local name="$1" d root

	if [[ -n ${MCA_DETECT_MEMO[snap:$name]+set} ]]; then
		[[ ${MCA_DETECT_MEMO[snap:$name]} == yes ]]
		return $?
	fi

	for d in "${MCA_SNAP_DIRS[@]}"; do
		root="$d/$name/current"
		if _mca_find_markers "$root" 5; then
			MCA_DETECT_MEMO[snap:$name]=yes
			return 0
		fi
	done

	MCA_DETECT_MEMO[snap:$name]=no
	return 1
}

# mca_flatpak_is_chromium <app id>
# Flatpak keeps every application in its own tree, so the marker check works the
# same way once that tree has been located.
mca_flatpak_is_chromium() {
	local id="$1" loc
	mca_have flatpak || return 1

	if [[ -n ${MCA_DETECT_MEMO[flatpak:$id]+set} ]]; then
		[[ ${MCA_DETECT_MEMO[flatpak:$id]} == yes ]]
		return $?
	fi

	loc="$(flatpak info --show-location "$id" 2>/dev/null)"
	if [[ -n $loc ]] && _mca_find_markers "$loc/files" 4; then
		MCA_DETECT_MEMO[flatpak:$id]=yes
		return 0
	fi

	MCA_DETECT_MEMO[flatpak:$id]=no
	return 1
}

# mca_kind_wanted <kind> <id> [packaging]
# Whether the current settings say this entry should be patched. Skip beats
# everything, an explicit include beats detection, and detection beats nothing.
#
# Packaging is a gate in front of the category rather than a category of its
# own: a Flatpak or a snap sees none of the host's configuration and is worth
# switching off as a group, but it is still an application or a browser and
# whichever of those the user turned off applies to it too.
mca_kind_wanted() {
	local kind="$1" id="$2" packaging="${3:-native}"

	mca_config_list_has Skip "$id" && return 1
	mca_config_list_has Include "$id" && return 0

	case "$packaging" in
		flatpak) [[ $CFG_FLATPAK == yes ]] || return 1 ;;
		snap)    [[ $CFG_SNAP == yes ]] || return 1 ;;
	esac

	case "$kind" in
		app)     [[ $CFG_APPS == yes ]] ;;
		browser) [[ $CFG_BROWSERS == yes ]] ;;
		*)       return 1 ;;
	esac
}
