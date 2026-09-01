# shellcheck shell=bash
#
# Deciding what happens to each application, and doing it.
#
# The routing lives in mca_route and is used twice: once by mca_apply to patch
# and once by the applications screen to show what would happen. Keeping it in
# one function is what makes that screen trustworthy - it is not a description
# of the behaviour, it is the behaviour.

MCA_CHANGES=0
MCA_ROUTES=()

# mca_route <kind> <id> <program> [packaging]
# What happens to one application, left in MCA_ROUTE:
#   flags    - the launcher reads a flag file; write it there
#   desktop  - no flag file; shadow or edit the desktop entry
#   steam    - Steam's own two-part treatment
#   unknown  - cannot tell what engine this is (an AppImage), so nothing is done
#   off      - detected, but switched off
#
# Assigns rather than prints so the memo inside mca_has_flags_file survives:
# from inside a command substitution it would be filled in a subshell and
# thrown away, which is the whole point of having it.
MCA_ROUTE=''

mca_route() {
	local kind="$1" id="$2" prog="$3" packaging="${4:-native}"

	if [[ $kind == steam ]]; then
		if mca_config_list_has Skip "$id" || [[ $CFG_STEAM != yes ]]; then
			MCA_ROUTE=off
		else
			MCA_ROUTE=steam
		fi
		return
	fi

	if ! mca_kind_wanted "$kind" "$id" "$packaging"; then
		[[ $kind == unknown ]] && MCA_ROUTE=unknown || MCA_ROUTE=off
		return
	fi

	# A Flatpak or a snap carries its own copy of everything and sees none of
	# the host's wrappers, so the desktop entry is the only way in.
	if [[ $packaging != native ]]; then
		MCA_ROUTE=desktop
		return
	fi

	if mca_has_flags_file "$prog"; then
		MCA_ROUTE=flags
	else
		MCA_ROUTE=desktop
	fi
}

# mca_apply
# Brings everything into line with the current settings. Safe to run as often
# as it likes to be - it writes only what differs, which is what keeps the
# watcher from chasing its own changes.
mca_apply() {
	local i id file prog kind packaging route steam_done=0

	MCA_CHANGES=0
	MCA_ROUTES=()
	MCA_N_ON=0; MCA_N_OFF=0; MCA_N_UNKNOWN=0

	mca_config_load
	mca_scan

	for i in "${!MCA_IDS[@]}"; do
		id="${MCA_IDS[i]}"
		file="${MCA_FILES[i]}"
		prog="${MCA_PROGS[i]}"
		kind="${MCA_KINDS[i]}"
		packaging="${MCA_PACKAGING[i]}"

		mca_route "$kind" "$id" "$prog" "$packaging"
		route="$MCA_ROUTE"
		MCA_ROUTES[i]="$route"

		case "$route" in
			unknown) MCA_N_UNKNOWN=$(( MCA_N_UNKNOWN + 1 )) ;;
			off)     MCA_N_OFF=$(( MCA_N_OFF + 1 )) ;;
			*)       MCA_N_ON=$(( MCA_N_ON + 1 )) ;;
		esac

		case "$route" in
			flags)
				mca_flags_apply "$prog" || mca_desktop_apply "$id" "$file"
				;;
			desktop)
				mca_desktop_apply "$id" "$file"
				;;
			steam)
				mca_steam_desktop_apply "$id" "$file" "$packaging"
				if (( ! steam_done )); then
					mca_steam_apply
					steam_done=1
				fi
				;;
		esac
	done

	# Steam is worth patching even when its desktop entry is missing - a user
	# who starts it from a script or a game launcher still gets the interface.
	if [[ $CFG_STEAM == yes ]] && (( ! steam_done )) && mca_steam_installed; then
		mca_steam_apply
	fi

	# The shortcuts Steam writes for single games. They are not applications
	# and are not offered as ones, but starting a game with Steam closed is a
	# Steam start like any other: without the switch the client finds the
	# patched helper script, puts its own back, and the interface loses
	# autoscroll for the rest of the session.
	if [[ $CFG_STEAM == yes ]]; then
		for i in "${!MCA_STEAM_LINKS[@]}"; do
			mca_steam_desktop_apply "${MCA_STEAM_LINKS[i]}" \
				"${MCA_STEAM_LINK_FILES[i]}" "${MCA_STEAM_LINK_PACK[i]}"
		done
	fi

	# Steam's autostart entry carries Steam's own switch and follows the Steam
	# setting, not this one - leaving it out while Steam is patched is what puts
	# the client in an update loop - so both are checked inside.
	if [[ $CFG_AUTOSTART == yes || $CFG_STEAM == yes ]]; then
		mca_autostart_apply
	fi

	# Shortcuts on the desktop itself. Nothing above has seen them - the XDG
	# search path does not go there - and a game started from one starts Steam
	# without its switch, which is the difference between autoscroll working
	# and autoscroll working most of the time. Each entry is gated on its own,
	# so there is nothing to check out here.
	mca_shortcuts_apply

	[[ $CFG_SPOTIFY == yes ]] && mca_spotify_apply

	mca_prune_orphans

	if (( MCA_CHANGES )) && mca_have update-desktop-database; then
		update-desktop-database "$MCA_APPDIR" 2>/dev/null || true
	fi

	mca_state_write last_apply "$(date +%s)"
	return 0
}

# mca_revert
# Undoes every recorded change and forgets them.
mca_revert() {
	MCA_CHANGES=0
	mca_revert_all

	if (( MCA_CHANGES )) && mca_have update-desktop-database; then
		update-desktop-database "$MCA_APPDIR" 2>/dev/null || true
	fi

	return 0
}

# ---------------------------------------------------------------------------
# The watcher
# ---------------------------------------------------------------------------
# A systemd user path unit watching every directory a desktop entry can appear
# in. That covers a package from whatever the distribution's package manager
# is, a Flatpak, a snap, an AppImage registered by hand and a Steam client
# update, without a hook per package manager.

MCA_UNIT_PATH="middleclick-autoscroll.path"
MCA_UNIT_SERVICE="middleclick-autoscroll.service"

# The desktop folder is watched like every other directory an entry can turn up
# in, but its name is translated and the unit that ships with the package
# cannot know it. So that one path is written here, into a drop-in, from the
# name this system actually uses.
MCA_UNIT_DROPIN="${MCA_XDG_CONFIG}/systemd/user/${MCA_UNIT_PATH}.d"

mca_watch_available() {
	mca_have systemctl && [[ -n ${XDG_RUNTIME_DIR:-} || -S "/run/user/$(id -u)/bus" ]]
}

mca_watch_enabled() {
	mca_watch_available || return 1
	systemctl --user is-enabled --quiet "$MCA_UNIT_PATH" 2>/dev/null
}

# _mca_watch_dropin_write
# Returns 0 when the drop-in changed and systemd has to be told, 1 when it was
# already right - the same contract as mca_write_if_changed, and for the same
# reason: the watcher runs after every desktop entry that appears anywhere on
# the system, and a daemon-reload each time would be absurd.
_mca_watch_dropin_write() {
	local dir file="$MCA_UNIT_DROPIN/desktop.conf" content

	dir="$(mca_desktop_folder)"
	[[ -d $dir ]] || { _mca_watch_dropin_remove; return $?; }

	# A per cent sign starts a specifier in a unit file and has to be doubled
	# to mean itself. Rare in a folder name, fatal when it happens.
	content="[Path]"$'\n'"PathModified=${dir//%/%%}"$'\n'

	mca_write_if_changed "$file" "$content"
}

_mca_watch_dropin_remove() {
	[[ -e "$MCA_UNIT_DROPIN/desktop.conf" ]] || return 1
	rm -f -- "$MCA_UNIT_DROPIN/desktop.conf"
	rmdir "$MCA_UNIT_DROPIN" 2>/dev/null || true
	return 0
}

mca_watch_enable() {
	mca_watch_available || return 1
	_mca_watch_dropin_write
	systemctl --user daemon-reload > /dev/null 2>&1 || true
	systemctl --user enable --now "$MCA_UNIT_PATH" > /dev/null 2>&1 || return 1
	systemctl --user enable "$MCA_UNIT_SERVICE" > /dev/null 2>&1 || true
	return 0
}

# mca_watch_refresh
# Keeps a running watcher in step with a desktop folder that has been renamed,
# which is what a change of session language does to it.
mca_watch_refresh() {
	mca_watch_available || return 0
	_mca_watch_dropin_write || return 0
	systemctl --user daemon-reload > /dev/null 2>&1 || true
	systemctl --user restart "$MCA_UNIT_PATH" > /dev/null 2>&1 || true
	return 0
}

mca_watch_disable() {
	mca_watch_available || return 0
	systemctl --user disable --now "$MCA_UNIT_PATH" > /dev/null 2>&1 || true
	systemctl --user disable "$MCA_UNIT_SERVICE" > /dev/null 2>&1 || true
	_mca_watch_dropin_remove && systemctl --user daemon-reload > /dev/null 2>&1
	return 0
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

# mca_count_routes
# Fills MCA_N_ON / MCA_N_OFF / MCA_N_UNKNOWN from a scan, without writing
# anything. Used by the status block and the menu header.
MCA_N_ON=0
MCA_N_OFF=0
MCA_N_UNKNOWN=0

mca_count_routes() {
	local i route

	MCA_N_ON=0; MCA_N_OFF=0; MCA_N_UNKNOWN=0
	MCA_ROUTES=()

	for i in "${!MCA_IDS[@]}"; do
		mca_route "${MCA_KINDS[i]}" "${MCA_IDS[i]}" "${MCA_PROGS[i]}" \
			"${MCA_PACKAGING[i]}"
		route="$MCA_ROUTE"
		MCA_ROUTES[i]="$route"
		case "$route" in
			unknown) MCA_N_UNKNOWN=$(( MCA_N_UNKNOWN + 1 )) ;;
			off)     MCA_N_OFF=$(( MCA_N_OFF + 1 )) ;;
			*)       MCA_N_ON=$(( MCA_N_ON + 1 )) ;;
		esac
	done
}

# mca_route_label <route>
mca_route_label() {
	case "$1" in
		flags)   mca_msg "flag file" ;;
		desktop) mca_msg "launcher" ;;
		steam)   mca_msg "Steam" ;;
		unknown) mca_msg "cannot tell" ;;
		*)       mca_msg "off" ;;
	esac
	printf '\n'
}
