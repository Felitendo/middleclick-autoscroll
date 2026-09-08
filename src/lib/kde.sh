# shellcheck shell=bash
#
# KDE's middle-click paste.
#
# Inside a Chromium application the flag settles this on its own: with
# autoscroll on, Blink stops pasting the primary selection on middle click,
# because the button is doing something else now. Everywhere else on the
# desktop middle click goes on pasting, which is the behaviour this whole
# program exists to get away from - so the desktop's own switch for it is
# turned off too.
#
# KWin has such a switch, and only for a Wayland session, where the paste is a
# protocol the compositor either offers or does not:
#
#   ~/.config/kwinrc, [Wayland], EnablePrimarySelection=false
#
# On X11 there is nothing to switch. The primary selection is part of X itself
# and every toolkit reaches for it on its own; no one place can say no.
#
# KWin reads the key once, while it starts, so what is written here is true
# from the next login on rather than straight away.

MCA_KWINRC="${MCA_XDG_CONFIG}/kwinrc"
MCA_KWIN_GROUP="Wayland"
MCA_KWIN_KEY="EnablePrimarySelection"

# The kconfig command line tools, whichever generation this session has. They
# are what System Settings writes kwinrc with, and worth the fork: the file has
# a cascade behind it - /etc/xdg, the kdedefaults directory - and entries a
# distribution can mark immutable, and an edit that reaches past all that with
# sed writes something KDE goes on to ignore.
MCA_KDE_TOOL=''
MCA_KDE_TOOL_LOOKED=0

_mca_kde_tool() {
	local gen

	if (( ! MCA_KDE_TOOL_LOOKED )); then
		MCA_KDE_TOOL_LOOKED=1
		for gen in 6 5; do
			if mca_have "kreadconfig$gen" && mca_have "kwriteconfig$gen"; then
				MCA_KDE_TOOL="$gen"
				break
			fi
		done
	fi

	[[ -n $MCA_KDE_TOOL ]] || return 1
	printf '%s\n' "$MCA_KDE_TOOL"
}

# mca_kde_session
# Whether this is a KWin Wayland session.
mca_kde_session() {
	local desktop="${XDG_CURRENT_DESKTOP:-}"

	# The watcher is a systemd service, and one started before the session
	# imported its environment sees none of these variables. A running
	# kwin_wayland answers both halves of the question at once, and is what
	# such a run ends up going by.
	if [[ -z $desktop && -z ${KDE_FULL_SESSION:-} ]]; then
		mca_have pgrep || return 1
		pgrep -u "$(id -u)" -x kwin_wayland > /dev/null 2>&1
		return
	fi

	# XDG_CURRENT_DESKTOP is the one every desktop sets, and the one to go by
	# wherever it is set; KDE_FULL_SESSION is what answers when it is not.
	[[ -z $desktop || ${desktop^^} == *KDE* ]] || return 1

	[[ ${XDG_SESSION_TYPE:-} == wayland || -n ${WAYLAND_DISPLAY:-} ]]
}

mca_kde_available() {
	mca_kde_session && _mca_kde_tool > /dev/null
}

# mca_kde_read [file]
# What the key says now, lowercased, empty when it is not set at all.
mca_kde_read() {
	local file="${1:-$MCA_KWINRC}" gen val
	gen="$(_mca_kde_tool)" || return 1

	# kreadconfig creates the file it is pointed at, and the status screen -
	# which asks on every redraw - has no business writing anything. A file
	# that is not there has no value in it to read anyway.
	[[ -f $file ]] || return 0

	val="$("kreadconfig$gen" --file "$file" --group "$MCA_KWIN_GROUP" \
		--key "$MCA_KWIN_KEY" 2>/dev/null)"
	printf '%s\n' "${val,,}"
}

# mca_kde_write [file] <value>
# An empty value takes the key back out rather than writing nothing into it -
# a key that is missing and a key that says nothing are not the same thing to
# KDE, and only the first one is what an untouched kwinrc looks like.
mca_kde_write() {
	local file="$1" value="$2" gen
	gen="$(_mca_kde_tool)" || return 1

	if [[ -z $value ]]; then
		"kwriteconfig$gen" --file "$file" --group "$MCA_KWIN_GROUP" \
			--key "$MCA_KWIN_KEY" --delete 2>/dev/null
	else
		"kwriteconfig$gen" --file "$file" --group "$MCA_KWIN_GROUP" \
			--key "$MCA_KWIN_KEY" "$value" 2>/dev/null
	fi
}

# mca_kde_paste_apply
# Turns the paste off, and remembers what the key said before so that undoing
# puts that back rather than a guess.
#
# A key that already says false without the ledger knowing about it was set by
# the user or by the distribution. That one is left alone and nothing is
# recorded, so `disable` cannot switch a paste back on that this program never
# switched off.
mca_kde_paste_apply() {
	local current previous changed=0

	mca_kde_available || return 1
	current="$(mca_kde_read)" || return 1

	if mca_ledger_has "$MCA_KWINRC"; then
		# Ours already. What goes back is the value recorded the first time
		# round, not what reading the file now would say - that is false, and
		# false is what is being undone.
		previous="$(mca_ledger_detail "$MCA_KWINRC")" || previous=unset
	elif [[ $current == false ]]; then
		return 0
	else
		previous="${current:-unset}"
	fi

	if [[ $current != false ]]; then
		mca_kde_write "$MCA_KWINRC" false || return 1
		MCA_CHANGES=$(( MCA_CHANGES + 1 ))
		changed=1
	fi

	mca_ledger_add kwin "$MCA_KWINRC" "$previous"

	(( changed )) && mca_note "$(mca_msg "Middle click stops pasting at the next login.")"
	return 0
}

# mca_kde_paste_revert <file> <previous value>
mca_kde_paste_revert() {
	local file="$1" previous="$2"

	_mca_kde_tool > /dev/null || return 1
	[[ -f $file ]] || return 1

	# Only what is still recognisably ours. A key somebody has since put a
	# value of their own into is theirs now.
	[[ "$(mca_kde_read "$file")" == false ]] || return 1

	[[ $previous == unset ]] && previous=''
	mca_kde_write "$file" "$previous" || return 1

	# Nothing was in the file but the key, which means there was no file before
	# this program wrote one. An empty kwinrc says nothing that its absence
	# does not say better.
	[[ -s $file ]] || rm -f -- "$file"
	return 0
}
