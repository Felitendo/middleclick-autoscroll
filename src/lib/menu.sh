# shellcheck shell=bash
#
# The interactive front end.
#
# This is the whole configuration interface. There is a file behind it, but no
# part of the program ever asks anyone to open it: one switch on the front
# screen, a settings list for the categories, and a list of the applications
# themselves for the cases where the automatic answer is not the wanted one.

# Terminal mode.
#
# bash flips the terminal into non-canonical mode for each `read -sn1` and back
# out again in between. That gap matters: in canonical mode DEL is the ERASE
# character, so the line discipline eats it instead of delivering it, and a
# backspace typed while the interface was between reads simply vanishes.
# Holding non-canonical mode for the whole interface removes the gap.
MCA_TERM_SAVED=''

mca_ui_term_raw() {
	mca_have stty || return 0
	[[ -t 0 ]] || return 0
	[[ -n $MCA_TERM_SAVED ]] && return 0

	MCA_TERM_SAVED="$(stty -g 2>/dev/null)" || { MCA_TERM_SAVED=''; return 0; }
	stty -icanon -echo min 1 time 0 2>/dev/null || true
}

mca_ui_term_restore() {
	[[ -n $MCA_TERM_SAVED ]] || return 0
	stty "$MCA_TERM_SAVED" 2>/dev/null || true
	MCA_TERM_SAVED=''
}

# Runs an action with the terminal handed back to normal line mode, so anything
# it prints - or prompts for - behaves the way a program expects.
mca_ui_cooked() {
	mca_ui_term_restore
	"$@"
	local rc=$?
	mca_ui_term_raw
	return $rc
}

# mca_read_key
# One keypress, resolved to a symbolic name. Arrow keys arrive as ESC [ A, so
# the tail of the sequence is consumed here rather than being mistaken for
# three separate presses.
mca_read_key() {
	local k rest

	IFS= read -rsn1 k || return 1

	case "$k" in
		$'\e')
			if IFS= read -rsn2 -t 0.05 rest; then
				case "$rest" in
					'[A') printf 'up\n' ;;
					'[B') printf 'down\n' ;;
					'[C') printf 'right\n' ;;
					'[D') printf 'left\n' ;;
					*)    printf 'escape\n' ;;
				esac
			else
				printf 'escape\n'
			fi
			;;
		''|$'\r')      printf 'enter\n' ;;
		$'\x7f'|$'\b') printf 'backspace\n' ;;
		' ')           printf 'space\n' ;;
		*)             printf '%s\n' "$k" ;;
	esac
}

# mca_ui_read_line <initial>
# A minimal line editor built on mca_read_key, with the result in
# MCA_LINE_RESULT. This exists instead of bash's own `read -r` because mixing
# line mode into a single-key interface breaks it: after one cooked-mode read
# the following `read -sn1` stops receiving keystrokes entirely.
MCA_LINE_RESULT=''

mca_ui_read_line() {
	local buf="${1:-}" key

	MCA_LINE_RESULT=''
	printf '%s' "$buf"

	while true; do
		key="$(mca_read_key)" || { printf '\n'; return 1; }

		case "$key" in
			enter)
				printf '\n'
				MCA_LINE_RESULT="$buf"
				return 0
				;;
			escape)
				printf '\n'
				return 1
				;;
			backspace)
				if [[ -n $buf ]]; then
					buf="${buf%?}"
					printf '\b \b'
				fi
				;;
			space)
				buf+=' '
				printf ' '
				;;
			up|down|left|right) ;;
			*)
				[[ ${#key} -eq 1 ]] || continue
				buf+="$key"
				printf '%s' "$key"
				;;
		esac
	done
}

mca_pause() {
	printf '\n  %s' "$(mca_msg "Press any key to continue...")"
	read -rsn1 _ || true
	printf '\n'
}

# _mca_row <label> <value>
# printf's %-28s pads by bytes, so a label containing "ü" comes out one column
# short. ${#s} counts characters in a UTF-8 locale, so the padding is computed
# here instead - and applied inline, because command substitution would eat the
# trailing spaces again.
_mca_row() {
	local label="$1" value="$2" pad
	pad=$(( 30 - ${#label} ))
	(( pad < 0 )) && pad=0
	printf '  %s%*s %s\n' "$label" "$pad" '' "$value"
}

_mca_onoff() {
	if [[ $1 == yes ]]; then
		printf '%s%s%s' "$MCA_C_GREEN" "$(mca_msg "ON")" "$MCA_C_RESET"
	else
		printf '%s%s%s' "$MCA_C_DIM" "$(mca_msg "OFF")" "$MCA_C_RESET"
	fi
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

# mca_ui_status
# Shared by the `status` subcommand and the menu header. Scans, so the numbers
# describe what is on disk right now rather than what was true at the last run.
mca_ui_status() {
	local last covered

	mca_scan_once
	mca_count_routes

	last="$(mca_state_read last_apply '')"

	_mca_row "$(mca_msg "Autoscroll")" "$(_mca_onoff "$CFG_ENABLED")"
	printf '\n'

	if [[ $CFG_ENABLED == yes ]]; then
		covered="$MCA_N_ON"
	else
		covered=0
	fi

	_mca_row "$(mca_msg "Applications covered")" \
		"$(mca_msg "%d of %d" "$covered" "$(( MCA_N_ON + MCA_N_OFF + MCA_N_UNKNOWN ))")"

	if (( MCA_N_UNKNOWN )); then
		_mca_row "$(mca_msg "Not identified")" \
			"${MCA_C_DIM}$(mca_msg "%d - see the applications list" "$MCA_N_UNKNOWN")${MCA_C_RESET}"
	fi

	if mca_steam_installed; then
		if mca_steam_patched; then
			_mca_row "$(mca_msg "Steam")" "$(_mca_onoff yes)"
		elif [[ $CFG_STEAM == yes && $CFG_ENABLED == yes ]] && mca_steam_waiting; then
			_mca_row "$(mca_msg "Steam")" \
				"${MCA_C_DIM}$(mca_msg "waiting until Steam is closed")${MCA_C_RESET}"
		elif [[ $CFG_STEAM == yes && $CFG_ENABLED == yes ]]; then
			_mca_row "$(mca_msg "Steam")" \
				"${MCA_C_YELLOW}$(mca_msg "not patched yet")${MCA_C_RESET}"
		else
			_mca_row "$(mca_msg "Steam")" "$(_mca_onoff no)"
		fi
	fi

	if mca_watch_available; then
		if mca_watch_enabled; then
			_mca_row "$(mca_msg "New applications")" "$(_mca_onoff yes)"
		else
			_mca_row "$(mca_msg "New applications")" "$(_mca_onoff no)"
		fi
	fi

	_mca_row "$(mca_msg "Last applied")" "$(mca_time_ago "$last")"

	if [[ $CFG_ENABLED == yes ]]; then
		printf '\n  %s%s%s\n' "$MCA_C_DIM" \
			"$(mca_msg "Applications pick this up the next time they are started.")" \
			"$MCA_C_RESET"
	fi
}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
# Format: Key|type|default|label-msgid
# type is bool or text.
MCA_SETTINGS=(
	"PatchApps|bool|yes|Electron and CEF applications"
	"PatchBrowsers|bool|yes|Chromium-based browsers"
	"PatchFlatpak|bool|yes|Flatpak applications"
	"PatchSnap|bool|yes|Snap applications"
	"PatchAutostart|bool|yes|Programs that start themselves at login"
	"PatchSteam|bool|yes|Steam"
	"PatchSpotify|bool|yes|Spotify"
	"WatchNewApps|bool|yes|Apply to newly installed applications"
	"ExtraFlags|text||Additional Chromium arguments"
)

_mca_is_true() {
	case "${1,,}" in
		yes|y|true|1|on|enabled) return 0 ;;
		*) return 1 ;;
	esac
}

MCA_SETTING_SHOWN=''
MCA_LBL_ON=''
MCA_LBL_OFF=''
MCA_LBL_NONE=''

_mca_setting_display() {
	local type="$1" value="$2"

	case "$type" in
		bool)
			if _mca_is_true "$value"; then
				MCA_SETTING_SHOWN="${MCA_C_GREEN}${MCA_LBL_ON}${MCA_C_RESET}"
			else
				MCA_SETTING_SHOWN="${MCA_C_DIM}${MCA_LBL_OFF}${MCA_C_RESET}"
			fi
			;;
		text)
			if [[ -n $value ]]; then
				MCA_SETTING_SHOWN="$value"
			else
				MCA_SETTING_SHOWN="${MCA_C_DIM}${MCA_LBL_NONE}${MCA_C_RESET}"
			fi
			;;
		*) MCA_SETTING_SHOWN="$value" ;;
	esac
}

# mca_ui_settings
# A cursor list rather than a numbered menu. The frame is assembled in memory
# and written once, and everything constant is resolved before the loop:
# drawing the naive way costs a command substitution per label per frame, which
# is slow enough that arrow keys feel like the console is reloading.
#
# Returns 0 when something was changed, so the caller knows to re-apply.
mca_ui_settings() {
	local count=${#MCA_SETTINGS[@]}
	local -a names=() types=() defaults=() labels=() values=()
	local spec name type default label locale i key frame row pad dirty=1 cursor=0
	local touched=0

	locale="$(mca_ui_locale)"
	mca_msg_into "$locale" "ON";     MCA_LBL_ON="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "OFF";    MCA_LBL_OFF="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "(none)"; MCA_LBL_NONE="$MCA_MSG_RESULT"

	for spec in "${MCA_SETTINGS[@]}"; do
		IFS='|' read -r name type default label <<< "$spec"
		names+=("$name"); types+=("$type"); defaults+=("$default")
		mca_msg_into "$locale" "$label"
		labels+=("$MCA_MSG_RESULT")
	done

	local title hint
	mca_msg_into "$locale" "Settings"; title="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "Up/Down select - Space or Right changes - q goes back"
	hint="$MCA_MSG_RESULT"

	local clearseq
	clearseq="$(clear 2>/dev/null)" || clearseq=$'\033[H\033[2J'

	while true; do
		if (( dirty )); then
			for i in "${!names[@]}"; do
				_mca_config_lookup "${names[i]}" "${defaults[i]}"
				values[i]="$MCA_CONFIG_VALUE"
			done
			dirty=0
		fi

		frame="$clearseq"$'\n'"${MCA_C_BOLD}${MCA_C_BLUE}  ${title}${MCA_C_RESET}"$'\n\n'

		local marker selected="${MCA_C_BLUE}▸${MCA_C_RESET} "
		for i in "${!names[@]}"; do
			_mca_setting_display "${types[i]}" "${values[i]}"
			pad=$(( 46 - ${#labels[i]} ))
			(( pad < 0 )) && pad=0
			if (( i == cursor )); then marker="$selected"; else marker='  '; fi
			printf -v row '  %s%s%*s %s' \
				"$marker" "${labels[i]}" "$pad" '' "$MCA_SETTING_SHOWN"
			frame+="$row"$'\n'
		done

		frame+=$'\n'"  ${MCA_C_DIM}${hint}${MCA_C_RESET}"$'\n'
		printf '%s' "$frame"

		key="$(mca_read_key)" || return "$(( ! touched ))"

		type="${types[cursor]}"
		name="${names[cursor]}"

		case "$key" in
			up|k)   cursor=$(( (cursor - 1 + count) % count )) ;;
			down|j) cursor=$(( (cursor + 1) % count )) ;;
			space|enter|right|l|left|h)
				if [[ $type == text ]]; then
					[[ $key == left || $key == h ]] && continue
					mca_ui_edit_text "$name" "${values[cursor]}" && touched=1
				else
					if _mca_is_true "${values[cursor]}"; then
						mca_config_set "$name" no
					else
						mca_config_set "$name" yes
					fi || { mca_bad "$(mca_msg "Could not save the setting.")"; mca_pause; }
					touched=1
				fi
				dirty=1
				;;
			q|Q|escape) return "$(( ! touched ))" ;;
			*) ;;
		esac
	done
}

# mca_ui_edit_text <key> <current>
mca_ui_edit_text() {
	local name="$1" current="$2"

	printf '\n  %s\n' "$(mca_msg "Arguments separated by spaces, empty for none:")"
	printf '  > '

	if mca_ui_read_line "$current"; then
		mca_config_set "$name" "$MCA_LINE_RESULT" \
			|| { mca_bad "$(mca_msg "Could not save the setting.")"; mca_pause; }
		return 0
	fi
	return 1
}

# ---------------------------------------------------------------------------
# Applications
# ---------------------------------------------------------------------------

# mca_ui_apps
# Every application that was found, what will happen to it, and a key to
# change that. This is where an AppImage that could not be identified gets
# turned on, and where a single application gets left out without having to
# switch off its whole category.
#
# Returns 0 when something was changed.
mca_ui_apps() {
	local count key frame row pad i cursor=0 dirty=1 touched=0 locale
	local -a labels=() states=()

	locale="$(mca_ui_locale)"

	local title hint legend warn
	mca_msg_into "$locale" "Applications"; title="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "Up/Down select - Space turns one on or off - q goes back"
	hint="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "Anything not identified is left alone until it is turned on here."
	legend="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "Autoscroll is off - this is what would be covered."
	warn="$MCA_MSG_RESULT"

	# The per-row labels are resolved once, here. Looking them up inside the
	# drawing loop is a fork per row per keypress, and that is enough to make
	# the arrow keys feel like the screen is reloading.
	local l_off l_cannot l_on l_steam l_flagfile l_launcher
	mca_msg_into "$locale" "off";         l_off="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "cannot tell"; l_cannot="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "on";          l_on="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "Steam";       l_steam="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "flag file";   l_flagfile="$MCA_MSG_RESULT"
	mca_msg_into "$locale" "launcher";    l_launcher="$MCA_MSG_RESULT"

	local s_off="${MCA_C_DIM}${l_off}${MCA_C_RESET}"
	local s_cannot="${MCA_C_DIM}${l_cannot}${MCA_C_RESET}"
	local s_on="${MCA_C_GREEN}${l_on}${MCA_C_RESET}"
	local s_steam="${s_on} ${MCA_C_DIM}(${l_steam})${MCA_C_RESET}"
	local s_flags="${s_on} ${MCA_C_DIM}(${l_flagfile})${MCA_C_RESET}"
	local s_desktop="${s_on} ${MCA_C_DIM}(${l_launcher})${MCA_C_RESET}"

	local clearseq
	clearseq="$(clear 2>/dev/null)" || clearseq=$'\033[H\033[2J'

	printf '%s\n  %s\n' "$clearseq" "$(mca_msg "Looking at the installed applications...")"
	mca_config_load
	mca_scan_once
	count=${#MCA_IDS[@]}

	if (( count == 0 )); then
		printf '\n  %s\n' "$(mca_msg "No Chromium-based applications found.")"
		mca_pause
		return 1
	fi

	while true; do
		if (( dirty )); then
			mca_config_load
			mca_count_routes
			labels=(); states=()
			for i in "${!MCA_IDS[@]}"; do
				labels+=("${MCA_NAMES[i]}")
				states+=("${MCA_ROUTES[i]}")
			done
			dirty=0
		fi

		frame="$clearseq"$'\n'"${MCA_C_BOLD}${MCA_C_BLUE}  ${title}${MCA_C_RESET}"$'\n\n'

		local marker selected="${MCA_C_BLUE}▸${MCA_C_RESET} " shown
		for i in "${!labels[@]}"; do
			case "${states[i]}" in
				off)     shown="$s_off" ;;
				unknown) shown="$s_cannot" ;;
				steam)   shown="$s_steam" ;;
				flags)   shown="$s_flags" ;;
				*)       shown="$s_desktop" ;;
			esac
			pad=$(( 34 - ${#labels[i]} ))
			(( pad < 0 )) && pad=0
			if (( i == cursor )); then marker="$selected"; else marker='  '; fi
			printf -v row '  %s%s%*s %s' "$marker" "${labels[i]}" "$pad" '' "$shown"
			frame+="$row"$'\n'
		done

		frame+=$'\n'
		# Without this the list reads as a list of what is switched on, which
		# it is not while the whole thing is off.
		if [[ $CFG_ENABLED != yes ]]; then
			frame+="  ${MCA_C_YELLOW}${warn}${MCA_C_RESET}"$'\n'
		fi
		frame+="  ${MCA_C_DIM}${legend}${MCA_C_RESET}"$'\n'
		frame+="  ${MCA_C_DIM}${hint}${MCA_C_RESET}"$'\n'
		printf '%s' "$frame"

		key="$(mca_read_key)" || return "$(( ! touched ))"

		case "$key" in
			up|k)   cursor=$(( (cursor - 1 + count) % count )) ;;
			down|j) cursor=$(( (cursor + 1) % count )) ;;
			space|enter|right|left|l|h)
				case "${states[cursor]}" in
					off|unknown)
						mca_config_list_del Skip "${MCA_IDS[cursor]}"
						mca_config_list_add Include "${MCA_IDS[cursor]}"
						;;
					*)
						mca_config_list_del Include "${MCA_IDS[cursor]}"
						mca_config_list_add Skip "${MCA_IDS[cursor]}"
						;;
				esac
				touched=1
				dirty=1
				;;
			q|Q|escape) return "$(( ! touched ))" ;;
			*) ;;
		esac
	done
}

# ---------------------------------------------------------------------------
# The menu
# ---------------------------------------------------------------------------

mca_ui_menu() {
	local choice

	mca_ui_term_raw
	trap 'mca_ui_term_restore' EXIT INT TERM

	while true; do
		mca_config_load

		clear 2>/dev/null || true
		mca_head "  $MCA_PRETTY"
		mca_ui_status
		printf '\n'
		printf '  [1] %s\n' "$(mca_msg "Turn autoscroll on or off")"
		printf '  [2] %s\n' "$(mca_msg "Re-apply everything")"
		printf '  [3] %s\n' "$(mca_msg "Applications")"
		printf '  [4] %s\n' "$(mca_msg "Settings")"
		printf '  [q] %s\n' "$(mca_msg "Quit")"
		printf '\n  > '

		choice="$(mca_read_key)" || {
			printf '\n'; mca_ui_term_restore; trap - EXIT INT TERM; return 0
		}
		case "$choice" in
			enter|space|up|down|left|right|escape) choice='' ;;
		esac
		printf '%s\n' "$choice"

		case "$choice" in
			1)
				MCA_UI_NEEDS_ACK=''
				if [[ $CFG_ENABLED == yes ]]; then
					mca_ui_cooked mca_do_disable
				else
					mca_ui_cooked mca_do_enable
				fi
				[[ -n $MCA_UI_NEEDS_ACK ]] && mca_pause
				;;
			# Not a plain apply: with the watcher running there is never
			# anything left for one to do, and a menu entry that answers
			# "already done" every time is not an action. This is the repair -
			# everything is taken back and written again from scratch, which is
			# what fixes an application that drifted, a flag file somebody
			# edited, or Steam after it restored its own script.
			2)
				mca_ui_cooked mca_do_apply --rebuild
				mca_pause
				;;
			3)
				if mca_ui_apps; then
					[[ $CFG_ENABLED == yes ]] && mca_ui_cooked mca_do_apply --rebuild
				fi
				;;
			4)
				if mca_ui_settings; then
					[[ $CFG_ENABLED == yes ]] && mca_ui_cooked mca_do_apply --rebuild
				fi
				;;
			q|Q) mca_ui_term_restore; trap - EXIT INT TERM; return 0 ;;
			# Anything else - Enter, arrow keys, stray characters - just
			# redraws. Escape is deliberately not a quit key, so a mistyped
			# arrow key cannot close the menu.
			*) ;;
		esac
	done
}
