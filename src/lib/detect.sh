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
	/usr/local/lib /opt
)

# Strings in a launcher script that mean it starts a Chromium or Electron
# process, for the wrappers whose command line is assembled out of variables and
# cannot be followed from the outside.
#
# Only strings that no other kind of program has a reason to contain. The word
# "chromium" on its own is not one of them: /usr/bin/xdg-open lists every
# browser it knows how to start, and that is not a browser.
#
# The flag file convention is an Arch packaging habit and says nothing about the
# engine either, so it is not in here.
MCA_SCRIPT_HINTS='ELECTRON_|app\.asar|chrome-sandbox|libcef|enable-blink-features|ozone-platform-hint'

# ---------------------------------------------------------------------------
# Desktop entries
# ---------------------------------------------------------------------------

# The directories a desktop entry can come from, most specific first - which is
# also XDG lookup order, so the first file found for an id is the one that is
# actually used.
mca_desktop_dirs() {
	local dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" d
	printf '%s\n' "$MCA_APPDIR"
	while IFS= read -r -d: d; do
		[[ -n $d ]] && printf '%s/applications\n' "${d%/}"
	done <<< "${dirs}:"
}

# mca_desktop_get <file> <key>
# A single value from the [Desktop Entry] group. Desktop Action groups repeat
# the same keys, and reading past the first group would pick up the wrong one.
mca_desktop_get() {
	local file="$1" key="$2"
	awk -v key="$key" '
		/^[[:space:]]*\[/ { inentry = ($0 ~ /^[[:space:]]*\[Desktop Entry\][[:space:]]*$/); next }
		inentry && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
	' "$file" 2>/dev/null
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

	for m in "${MCA_MARKERS[@]}"; do
		[[ -e "$dir/$m" ]] && return 0
	done
	[[ -e "$dir/resources/app.asar" || -e "$dir/app.asar" ]] && return 0
	return 1
}

# _mca_script_target <script>
# The program a wrapper script hands over to, so a chain like
# heroic -> electron43 -> /usr/lib/electron43/electron can be followed.
_mca_script_target() {
	local script="$1" line tok
	local -a tokens

	while IFS= read -r line; do
		[[ $line =~ ^[[:space:]]*exec[[:space:]]+(.*)$ ]] || continue
		read -r -a tokens <<< "${BASH_REMATCH[1]}"
		for tok in "${tokens[@]}"; do
			[[ $tok == env ]] && continue
			[[ $tok == *=* && $tok != /* ]] && continue
			[[ $tok == -* ]] && continue
			# Anything still carrying a shell variable cannot be resolved from
			# the outside; the hint scan has to answer for those.
			[[ $tok == *'$'* ]] && return 1
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
# The flag files a launcher reads, in the order it reads them. Arch's Electron
# and Chromium wrappers all take extra arguments from
# $XDG_CONFIG_HOME/<name>-flags.conf, which is a far better place to inject than
# a desktop entry: it survives package updates and it applies to a launch from
# the terminal too.
mca_flags_candidates() {
	local prog="$1" depth="${2:-0}" target
	(( depth > 3 )) && return 0
	[[ -r $prog ]] || return 0
	head -c2 -- "$prog" 2>/dev/null | grep -q '#!' || return 0

	grep -oE '[A-Za-z0-9_.+-]+-flags\.conf' -- "$prog" 2>/dev/null

	# A wrapper that only execs another wrapper (heroic -> electron43) inherits
	# that one's flag files, plus the specific name it builds from a variable.
	if target="$(_mca_script_target "$prog")" && [[ -n $target ]]; then
		printf '%s-flags.conf\n' "${target##*/}"
		mca_flags_candidates "$target" $(( depth + 1 ))
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
MCA_PROGS=()      # resolved program, or a flatpak app id
MCA_KINDS=()      # app | browser | flatpak | steam | unknown | no

# A scan reads every desktop entry on the system, so the menu does it once and
# then redraws from what it found. Anything that changes the answer - applying,
# reverting - invalidates it explicitly.
MCA_SCANNED=0

mca_scan_once() {
	(( MCA_SCANNED )) && return 0
	mca_scan
}

mca_scan_invalidate() { MCA_SCANNED=0; }

mca_scan() {
	local dir file id name exec_line prog kind i
	local -A seen=()
	local -a c_ids=() c_files=() c_names=() c_progs=() c_browser=() c_stat=()

	MCA_IDS=(); MCA_FILES=(); MCA_NAMES=(); MCA_PROGS=(); MCA_KINDS=()

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
			fi

			c_ids+=("$id"); c_files+=("$file"); c_names+=("$name")
			c_progs+=("$prog")
			if mca_desktop_is_browser; then c_browser+=(1); else c_browser+=(0); fi
			[[ $prog == /* ]] && c_stat+=("$prog")
		done
	done < <(mca_desktop_dirs)

	MCA_STAT=()
	_mca_stat_batch "${c_stat[@]}"

	# Pass two: decide what each one is.
	for i in "${!c_ids[@]}"; do
		prog="${c_progs[i]}"
		kind=no

		if [[ $prog == flatpak:* ]]; then
			prog="${prog#flatpak:}"
			mca_flatpak_is_chromium "$prog" && kind=flatpak
		elif [[ ${prog##*/} == steam || ${prog##*/} == steam-runtime ]]; then
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

# mca_kind_wanted <kind> <id>
# Whether the current settings say this entry should be patched. Skip beats
# everything, an explicit include beats detection, and detection beats nothing.
mca_kind_wanted() {
	local kind="$1" id="$2"

	mca_config_list_has Skip "$id" && return 1
	mca_config_list_has Include "$id" && return 0

	case "$kind" in
		app)     [[ $CFG_APPS == yes ]] ;;
		browser) [[ $CFG_BROWSERS == yes ]] ;;
		flatpak) [[ $CFG_FLATPAK == yes && $CFG_APPS == yes ]] ;;
		*)       return 1 ;;
	esac
}
