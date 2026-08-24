# shellcheck shell=bash
#
# Reading and writing ~/.config/middleclick-autoscroll/config.
#
# The file exists so the tool has somewhere to remember what it was told; it is
# not meant to be edited. Every option it holds is reachable from the interface,
# which is why there is no commented template shipped anywhere and no reference
# to the path in the interface itself.
#
# It is parsed rather than sourced. One "Key=Value" per line, '#' comments.

MCA_CONFIG_CACHE=''
MCA_CONFIG_CACHED=0

_mca_config_slurp() {
	(( MCA_CONFIG_CACHED )) && return 0
	MCA_CONFIG_CACHE=''
	[[ -r $MCA_CONFIG ]] && MCA_CONFIG_CACHE="$(< "$MCA_CONFIG")"
	MCA_CONFIG_CACHED=1
	return 0
}

# _mca_config_lookup <Key> [default]
# Result in MCA_CONFIG_VALUE. Assigning rather than printing matters on the
# settings screen, which reads every key on every frame: a command substitution
# there is a fork, and forks are the whole cost of a redraw.
MCA_CONFIG_VALUE=''

_mca_config_lookup() {
	local key="$1" default="${2:-}" val='' line

	MCA_CONFIG_VALUE="$default"
	[[ -r $MCA_CONFIG ]] || return 0
	_mca_config_slurp

	while IFS= read -r line; do
		[[ $line == *"$key"* ]] || continue
		[[ $line =~ ^[[:space:]]*"$key"[[:space:]]*=(.*)$ ]] || continue
		val="${BASH_REMATCH[1]}"
	done <<< "$MCA_CONFIG_CACHE"

	val="${val%%#*}"
	val="${val#"${val%%[![:space:]]*}"}"
	val="${val%"${val##*[![:space:]]}"}"
	val="${val%\"}"
	val="${val#\"}"

	[[ -n $val ]] && MCA_CONFIG_VALUE="$val"
	return 0
}

# mca_config_get <Key> [default]
mca_config_get() {
	_mca_config_lookup "$@"
	printf '%s\n' "$MCA_CONFIG_VALUE"
}

# mca_config_bool <Key> <default: yes|no>
mca_config_bool() {
	local val
	val="$(mca_config_get "$1" "$2")"
	case "${val,,}" in
		yes|y|true|1|on|enabled) return 0 ;;
		*) return 1 ;;
	esac
}

# mca_config_set <Key> <Value>
mca_config_set() {
	local key="$1" value="$2" tmp

	if [[ ! -e $MCA_CONFIG ]]; then
		mkdir -p "$(dirname "$MCA_CONFIG")" || return 1
		{
			printf '# %s\n' "$MCA_PRETTY"
			printf '#\n'
			printf '# Written by `%s`. Nothing here needs editing by hand -\n' "$MCA_NAME"
			printf '# every option is reachable from `%s` itself.\n' "$MCA_NAME"
		} > "$MCA_CONFIG" || return 1
	fi
	[[ -w $MCA_CONFIG ]] || return 1

	tmp="$(mktemp "${MCA_CONFIG}.XXXXXX")" || return 1
	chmod --reference="$MCA_CONFIG" "$tmp" 2>/dev/null || chmod 0644 "$tmp"

	if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=" "$MCA_CONFIG"; then
		awk -v key="$key" -v value="$value" '
			!done && $0 ~ "^[[:space:]]*#?[[:space:]]*" key "[[:space:]]*=" {
				print key "=" value; done = 1; next
			}
			# drop any further occurrences so the file cannot grow duplicates
			$0 ~ "^[[:space:]]*" key "[[:space:]]*=" { next }
			{ print }
		' "$MCA_CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
	else
		cat "$MCA_CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
		printf '%s=%s\n' "$key" "$value" >> "$tmp"
	fi

	mv -f "$tmp" "$MCA_CONFIG"
	MCA_CONFIG_CACHED=0
}

# mca_config_list_has <Key> <item>
# The per-application overrides are stored as space separated lists.
mca_config_list_has() {
	local list item="$2" entry
	list="$(mca_config_get "$1" '')"
	for entry in $list; do
		[[ $entry == "$item" ]] && return 0
	done
	return 1
}

# mca_config_list_add <Key> <item> / mca_config_list_del <Key> <item>
mca_config_list_add() {
	local key="$1" item="$2" list
	mca_config_list_has "$key" "$item" && return 0
	list="$(mca_config_get "$key" '')"
	mca_config_set "$key" "${list:+$list }$item"
}

mca_config_list_del() {
	local key="$1" item="$2" list entry out=''
	list="$(mca_config_get "$key" '')"
	for entry in $list; do
		[[ $entry == "$item" ]] && continue
		out="${out:+$out }$entry"
	done
	mca_config_set "$key" "$out"
}

# ---------------------------------------------------------------------------
# Resolved settings
# ---------------------------------------------------------------------------

mca_config_load() {
	CFG_ENABLED=no;    mca_config_bool Enabled          no  && CFG_ENABLED=yes
	CFG_APPS=no;       mca_config_bool PatchApps        yes && CFG_APPS=yes
	CFG_BROWSERS=no;   mca_config_bool PatchBrowsers    yes && CFG_BROWSERS=yes
	CFG_FLATPAK=no;    mca_config_bool PatchFlatpak     yes && CFG_FLATPAK=yes
	CFG_SNAP=no;       mca_config_bool PatchSnap        yes && CFG_SNAP=yes
	CFG_AUTOSTART=no;  mca_config_bool PatchAutostart   yes && CFG_AUTOSTART=yes
	CFG_STEAM=no;      mca_config_bool PatchSteam       yes && CFG_STEAM=yes
	CFG_SPOTIFY=no;    mca_config_bool PatchSpotify     yes && CFG_SPOTIFY=yes
	CFG_WATCH=no;      mca_config_bool WatchNewApps     yes && CFG_WATCH=yes

	CFG_EXTRA_FLAGS="$(mca_config_get ExtraFlags '')"

	# Applications the user turned on or off by hand on the applications
	# screen, by desktop file id. Include wins over detection, Skip wins over
	# everything.
	CFG_INCLUDE="$(mca_config_get Include '')"
	CFG_SKIP="$(mca_config_get Skip '')"
}

# The full argument string that gets injected. Kept in one place so the flag
# file writer and the desktop entry writer cannot drift apart.
mca_flags() {
	printf '%s' "$MCA_FLAG"
	[[ -n ${CFG_EXTRA_FLAGS:-} ]] && printf ' %s' "$CFG_EXTRA_FLAGS"
	printf '\n'
}
