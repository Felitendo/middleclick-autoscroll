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

	case "${prog##*/}" in
		steam|steam-runtime|steam-native|steam-jupiter) return 0 ;;
	esac
	[[ $prog == flatpak:com.valvesoftware.Steam || $prog == snap:steam ]]
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

_mca_cache_load() {
	local path stamp verdict

	(( MCA_CACHE_LOADED )) && return 0
	MCA_CACHE_LOADED=1

	[[ -r "$MCA_CACHEDIR/detect" ]] || return 0
	while IFS=$'\t' read -r path stamp verdict; do
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

# mca_is_chromium <program>
# Succeeds when the program is a Chromium, CEF or Electron process.
mca_is_chromium() {
	local prog="$1" verdict real stamp cached

	[[ -n $prog && -e $prog ]] || return 1

	# Memoized under the path as given, so the same launcher named twice in a
	# scan costs nothing at all the second time.
	if [[ -n ${MCA_DETECT_MEMO[$prog]+set} ]]; then
		[[ ${MCA_DETECT_MEMO[$prog]} == yes ]]
		return $?
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
			verdict="${cached#*$'\t'}"
			MCA_DETECT_MEMO[$prog]="$verdict"
			[[ $verdict == yes ]]
			return $?
		fi
	fi

	real="$(readlink -f -- "$prog" 2>/dev/null)" || real="$prog"

	verdict=no
	if _mca_detect_uncached "$real"; then verdict=yes; fi

	MCA_DETECT_MEMO[$prog]="$verdict"
	if [[ -n $stamp ]]; then
		MCA_DETECT_CACHE["$prog"]="$stamp"$'\t'"$verdict"
		MCA_CACHE_DIRTY=1
	fi
	[[ $verdict == yes ]]
}

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

	# Last resort: Chromium's own argument table is in the binary. -m1 stops at
	# the first hit, so this reads far less than the file size suggests.
	#
	# AppImages are the one thing this cannot see through - their payload is a
	# compressed filesystem - which is why they come out as unknown and are
	# left to the applications screen.
	grep -qaFm1 -- 'enable-blink-features' "$real" 2>/dev/null && return 0
	grep -qaFm1 -- 'CHROME_VERSION_EXTRA' "$real" 2>/dev/null && return 0

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

# The shortcuts Steam writes for single games. Not applications of their own - a
# game is whatever engine it was built with, and none of those reads a Chromium
# argument - so they are kept apart from the list rather than listed as
# something that got switched on. They do start Steam, which is why they are
# kept at all: the Steam module gives them Steam's own switch.
MCA_STEAM_LINKS=()       # desktop file id
MCA_STEAM_LINK_FILES=()  # the entry that is in effect for it
MCA_STEAM_LINK_PACK=()   # native | flatpak | snap, which decides where the
                         # switch goes on the command line

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
	MCA_STEAM_LINKS=(); MCA_STEAM_LINK_FILES=(); MCA_STEAM_LINK_PACK=()

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

			if mca_exec_is_steam_link "$exec_line" "$prog"; then
				MCA_STEAM_LINKS+=("$id")
				MCA_STEAM_LINK_FILES+=("$file")
				if [[ $prog == flatpak:* ]]; then
					MCA_STEAM_LINK_PACK+=(flatpak)
				elif [[ $prog == snap:* ]]; then
					MCA_STEAM_LINK_PACK+=(snap)
				else
					MCA_STEAM_LINK_PACK+=(native)
				fi
				continue
			fi

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
		elif mca_is_chromium "$prog"; then
			(( c_browser[i] )) && kind=browser || kind=app
		elif [[ $prog == *.AppImage || $prog == *.appimage ]]; then
			kind=unknown
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
		[[ -d $root ]] || continue
		if [[ -n "$(find "$root" -maxdepth 5 \
			\( -name 'chrome_crashpad_handler' -o -name 'app.asar' \
			   -o -name 'libcef.so' -o -name 'v8_context_snapshot.bin' \
			   -o -name 'chrome-sandbox' \) \
			-print -quit 2>/dev/null)" ]]
		then
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
	if [[ -n $loc && -d "$loc/files" ]] \
		&& [[ -n "$(find "$loc/files" -maxdepth 4 \
			\( -name 'chrome_crashpad_handler' -o -name 'app.asar' \
			   -o -name 'libcef.so' -o -name 'v8_context_snapshot.bin' \) \
			-print -quit 2>/dev/null)" ]]
	then
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
