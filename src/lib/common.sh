# shellcheck shell=bash
#
# Paths, translations, output helpers and the change ledger.
#
# Everything here runs unprivileged. This tool only ever writes inside the
# user's own home - flag files, desktop entries, Steam's own scripts - so there
# is no system state to guard and nothing that needs root.

MCA_VERSION="@VERSION@"
MCA_NAME="middleclick-autoscroll"
MCA_PRETTY="Middle-Click Autoscroll"

# The whole point of the package. Blink implements Windows-style autoscroll
# behind a runtime flag that Chromium does not turn on for Linux, because
# middle click is taken by primary-selection paste there.
MCA_FLAG="--enable-blink-features=MiddleClickAutoscroll"

# The Blink feature name on its own, for merging into an --enable-blink-features
# list that an app (or the user) already carries.
MCA_FEATURE="MiddleClickAutoscroll"

MCA_LIBDIR="${MCA_LIBDIR:-@LIBDIR@}"
MCA_LOCALEDIR="${MCA_LOCALEDIR:-@LOCALEDIR@}"

MCA_XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
MCA_XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
MCA_XDG_STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
MCA_XDG_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

MCA_CONFDIR="${MCA_CONFDIR:-${MCA_XDG_CONFIG}/${MCA_NAME}}"
MCA_CONFIG="${MCA_CONFIG:-${MCA_CONFDIR}/config}"
MCA_STATEDIR="${MCA_STATEDIR:-${MCA_XDG_STATE}/${MCA_NAME}}"
MCA_CACHEDIR="${MCA_CACHEDIR:-${MCA_XDG_CACHE}/${MCA_NAME}}"

# Where generated desktop entries go. A file here shadows the one with the same
# name in /usr/share/applications, which is how an application gets extra
# command line arguments without touching anything pacman owns.
MCA_APPDIR="${MCA_XDG_DATA}/applications"

# Copies of every file that is edited in place rather than shadowed.
MCA_BACKUPDIR="${MCA_STATEDIR}/backup"

# One line per change, so `revert` can undo exactly what was done and nothing
# else. See mca_ledger_add.
MCA_LEDGER="${MCA_STATEDIR}/ledger"

# ---------------------------------------------------------------------------
# Translations
# ---------------------------------------------------------------------------

export TEXTDOMAIN="middleclick-autoscroll"
export TEXTDOMAINDIR="${MCA_LOCALEDIR}"

mca_ui_locale() {
	local l="${MCA_UI_LOCALE:-}"

	if [[ -z $l ]]; then
		l="${LC_ALL:-}"
		[[ -z $l ]] && l="${LC_MESSAGES:-}"
		[[ -z $l ]] && l="${LANG:-}"
	fi

	if [[ -z $l && -r /etc/locale.conf ]]; then
		l="$(sed -n 's/^LANG=//p' /etc/locale.conf | tr -d '"' | head -n1)"
	fi

	printf '%s\n' "${l:-C}"
}

# Every gettext lookup is a fork and the settings screen redraws a screenful of
# labels per keypress, so results are memoized.
declare -A MCA_MSG_CACHE=()

MCA_MSG_RESULT=''

# mca_msg_into <locale> <msgid>
# Plain lookup with the result in MCA_MSG_RESULT and no printf formatting, for
# callers that would otherwise pay a fork per label per frame.
mca_msg_into() {
	local locale="$1" msgid="$2" cachekey
	cachekey="${locale}"$'\x1f'"${msgid}"

	if [[ -n ${MCA_MSG_CACHE[$cachekey]+set} ]]; then
		MCA_MSG_RESULT="${MCA_MSG_CACHE[$cachekey]}"
		return 0
	fi

	MCA_MSG_RESULT="$(LC_ALL="$locale" LANGUAGE="${locale%%.*}" gettext -- "$msgid" 2>/dev/null)"
	[[ -n $MCA_MSG_RESULT ]] || MCA_MSG_RESULT="$msgid"
	MCA_MSG_CACHE[$cachekey]="$MCA_MSG_RESULT"
	return 0
}

# mca_msg_in <locale> <msgid> [printf args...]
mca_msg_in() {
	local locale="$1" msgid="$2" translated cachekey
	shift 2

	cachekey="${locale}"$'\x1f'"${msgid}"
	if [[ -n ${MCA_MSG_CACHE[$cachekey]+set} ]]; then
		translated="${MCA_MSG_CACHE[$cachekey]}"
	else
		translated="$(LC_ALL="$locale" LANGUAGE="${locale%%.*}" gettext -- "$msgid" 2>/dev/null)"
		[[ -n $translated ]] || translated="$msgid"
		MCA_MSG_CACHE[$cachekey]="$translated"
	fi

	# With no arguments the message is plain text, not a format string. Feeding
	# it to printf anyway would turn a literal percent sign in a translation
	# into an invalid conversion.
	if (( $# == 0 )); then
		printf '%s' "$translated"
		return
	fi

	# shellcheck disable=SC2059  # the format string is the translated message
	printf -- "$translated" "$@"
}

# mca_msg <msgid> [printf args...]
mca_msg() { mca_msg_in "$(mca_ui_locale)" "$@"; }

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# Decided once, while stdout is still whatever the process was started with:
# testing -t 1 at the point of use is wrong for anything called through $(...),
# which sees a pipe and would conclude nobody is watching.
MCA_INTERACTIVE=''
[[ -t 1 ]] && MCA_INTERACTIVE=1

if [[ -n $MCA_INTERACTIVE && -z ${NO_COLOR:-} ]]; then
	MCA_C_RESET=$'\033[0m'
	MCA_C_BOLD=$'\033[1m'
	MCA_C_DIM=$'\033[2m'
	MCA_C_BLUE=$'\033[38;2;23;147;209m'
	MCA_C_GREEN=$'\033[32m'
	MCA_C_YELLOW=$'\033[33m'
	MCA_C_RED=$'\033[31m'
else
	MCA_C_RESET='' MCA_C_BOLD='' MCA_C_DIM='' MCA_C_BLUE=''
	MCA_C_GREEN='' MCA_C_YELLOW='' MCA_C_RED=''
fi

# Set by mca_bad and mca_note. The menu redraws straight after an action, which
# would wipe the screen; this marks that something was printed the user still
# has to read. A plain success needs no acknowledgement - the status block at
# the top of the menu already shows the new state.
MCA_UI_NEEDS_ACK=''

# --quiet silences progress chatter; errors still go to stderr. Used by the
# systemd unit, which has no terminal and logs to the journal anyway.
MCA_QUIET=''

mca_say()  { [[ -n $MCA_QUIET ]] || printf '%s\n' "$*"; }
mca_head() { printf '\n%s%s%s\n\n' "$MCA_C_BOLD$MCA_C_BLUE" "$*" "$MCA_C_RESET"; }
mca_ok()   { [[ -n $MCA_QUIET ]] || printf '%s✔%s %s\n' "$MCA_C_GREEN" "$MCA_C_RESET" "$*"; }
mca_bad()  { MCA_UI_NEEDS_ACK=1; printf '%s✘%s %s\n' "$MCA_C_RED" "$MCA_C_RESET" "$*" >&2; }
mca_note() { MCA_UI_NEEDS_ACK=1; [[ -n $MCA_QUIET ]] || printf '%s•%s %s\n' "$MCA_C_DIM" "$MCA_C_RESET" "$*"; }

mca_have() { command -v "$1" > /dev/null 2>&1; }

# Human-readable "x minutes ago" for a unix timestamp. Empty input yields the
# translated "never".
mca_time_ago() {
	local ts="$1" now delta

	[[ $ts =~ ^[0-9]+$ ]] || { mca_msg "never"; printf '\n'; return; }

	now="$(date +%s)"
	delta=$(( now - ts ))
	(( delta < 0 )) && delta=0

	if   (( delta < 60 ));    then mca_msg "just now"
	elif (( delta < 3600 ));  then mca_msg "%d minutes ago" "$(( delta / 60 ))"
	elif (( delta < 86400 )); then mca_msg "%d hours ago" "$(( delta / 3600 ))"
	else                           mca_msg "%d days ago" "$(( delta / 86400 ))"
	fi
	printf '\n'
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

mca_state_read() {
	local key="$1" default="${2:-}"
	if [[ -r "$MCA_STATEDIR/$key" ]]; then
		cat "$MCA_STATEDIR/$key"
	else
		printf '%s\n' "$default"
	fi
}

mca_state_write() {
	local key="$1"
	shift
	mkdir -p "$MCA_STATEDIR" 2>/dev/null || return 1
	printf '%s\n' "$*" > "$MCA_STATEDIR/$key"
}

# ---------------------------------------------------------------------------
# The change ledger
# ---------------------------------------------------------------------------
# Reverting by pattern - "delete every desktop entry that mentions the flag" -
# would also delete entries the user wrote by hand. So every change is recorded
# instead, and `revert` replays the ledger backwards.
#
# Format, tab separated:
#   <kind> <path> <detail>
#
#   shadow  <generated desktop entry>   <source entry it was generated from>
#   inplace <edited file>               <basename of its backup copy>
#   flags   <flag file>                 created | appended | merged
#
# `inplace` and `flags` differ in how they are undone: a backup is restored
# wholesale, a flag file only loses the one line that was added to it.

mca_ledger_add() {
	local kind="$1" path="$2" detail="${3:-}"
	mkdir -p "$MCA_STATEDIR" 2>/dev/null || return 1

	# Never record the same path twice: applying repeatedly is normal (the path
	# unit fires on every desktop file that appears) and the ledger has to stay
	# a set, not a log.
	mca_ledger_forget "$path"
	printf '%s\t%s\t%s\n' "$kind" "$path" "$detail" >> "$MCA_LEDGER"
}

mca_ledger_forget() {
	local path="$1" tmp
	[[ -f $MCA_LEDGER ]] || return 0

	tmp="$(mktemp "${MCA_LEDGER}.XXXXXX")" || return 1
	awk -F'\t' -v p="$path" '$2 != p' "$MCA_LEDGER" > "$tmp" 2>/dev/null \
		&& mv -f "$tmp" "$MCA_LEDGER" || rm -f "$tmp"
	return 0
}


# mca_backup_name <file>
# The name a backup copy of that file is stored under. Derived from the path
# rather than remembered, so a caller can ask whether a file has been backed up
# before without reading the ledger.
mca_backup_name() {
	printf '%s' "$1" | sed 's|/|%|g'
}

# mca_backup <file>
# Copies a file aside before it is edited in place, and prints the name the
# copy was stored under. Existing backups are never overwritten: the first copy
# is the pristine one, and a second apply must not replace it with an already
# patched version.
mca_backup() {
	local file="$1" name
	name="$(mca_backup_name "$file")"

	mkdir -p "$MCA_BACKUPDIR" 2>/dev/null || return 1
	if [[ ! -e "$MCA_BACKUPDIR/$name" ]]; then
		cp -p -- "$file" "$MCA_BACKUPDIR/$name" 2>/dev/null || return 1
	fi
	printf '%s\n' "$name"
}

# mca_write_if_changed <path> <content>
# Writing a file that is already correct would touch its mtime, and the systemd
# path unit watches these directories: an unconditional write would retrigger
# the service, which would write again, forever.
mca_write_if_changed() {
	local path="$1" content="$2" current=''

	[[ -r $path ]] && current="$(< "$path")"

	# $(< file) drops trailing newlines and callers pass content that ends in
	# one, so both sides are trimmed before comparing. Getting this wrong makes
	# every file look changed on every run, which is exactly the feedback loop
	# this function exists to prevent.
	[[ "${current%"${current##*[!$'\n']}"}" == "${content%"${content##*[!$'\n']}"}" ]] && return 1

	mkdir -p "$(dirname "$path")" 2>/dev/null || return 2
	printf '%s' "$content" > "$path" || return 2
	return 0
}
