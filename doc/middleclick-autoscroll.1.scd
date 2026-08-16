middleclick-autoscroll(1)

# NAME

middleclick-autoscroll - middle-click autoscroll in every application that supports it

# SYNOPSIS

*middleclick-autoscroll* [_command_]

# DESCRIPTION

Blink, the engine inside Chromium, Electron and CEF, implements Windows-style
autoscroll: hold the middle mouse button and the page scrolls with the pointer.
On Linux it is switched off, because middle click is taken by primary-selection
paste. It can be turned back on with *--enable-blink-features=MiddleClickAutoscroll*
on the command line.

*middleclick-autoscroll* finds every Chromium-based application on the system
and puts that argument somewhere the application will actually read it, then
keeps doing so for anything installed later.

Run without a command it shows an interactive menu. Everything it can be told
is reachable from there; the configuration file behind it does not need to be
edited by hand.

Nothing outside the user's home directory is written to, and running it as root
is refused.

# COMMANDS

*enable*
	Turn autoscroll on, apply it to everything installed, and start watching
	for new applications.

*disable*
	Turn it off and put every file that was changed back the way it was.

*apply*
	Apply to anything that has appeared since the last run. This is what the
	watcher calls; running it by hand is only needed when the watcher is off.

*status*
	How many applications are covered, whether Steam is patched, and when the
	last run was.

*list*
	Every Chromium-based application that was found, and how each one is
	handled.

*-h*, *--help*
	Show a summary of the commands.

*-V*, *--version*
	Show the version.

# HOW THE ARGUMENT GETS IN

Two ways, chosen per application.

*Flag file*
	Arch's Electron and Chromium wrappers read extra arguments from
	_$XDG_CONFIG_HOME/<name>-flags.conf_. This is the preferred route: it is
	the supported way to pass arguments, it survives package upgrades, and it
	applies to a launch from a terminal as much as one from the menu. An
	*--enable-blink-features* line that is already in the file is extended
	rather than duplicated - Chromium keeps only the last occurrence of that
	option, so a second one would switch the first one off.

*Desktop entry*
	For applications that ship their own binary with no wrapper, and for
	Flatpaks, a copy of the desktop entry with the argument appended is written
	to _~/.local/share/applications_, where it shadows the system one. Entries
	that already live there - AppImages, web app shortcuts - are edited in
	place, with the original kept.

	A generated entry is marked *X-MCA-Generated* and an entry edited in place
	*X-MCA-Patched*. The two are never confused: the first is deleted when
	undoing, the second is restored from its backup. An entry with neither
	marker belongs to somebody else and is left alone.

Programs that start themselves at login write their own entry into
_~/.config/autostart_ pointing straight at their binary, bypassing the menu
entry entirely. Those are patched in place as well.

# STEAM

Steam's interface is CEF and supports the feature, but Steam builds the command
line for its web helper itself. The only way in is the script that starts the
helper, inside Steam's own installation:

	~/.local/share/Steam/ubuntu12_64/steamwebhelper_sniper_wrap.sh

Steam checksums that script at every start and restores it when it differs, so
its launcher entry also gets *-noverifyfiles*. The trade-off is that Steam no
longer repairs a damaged installation on its own; that is why Steam is a switch
of its own in the settings.

Starting Steam from a terminal without *-noverifyfiles* undoes the patch for
that session. The watcher notices and puts it back, so the next start has it
again.

# SPOTIFY

The official client is CEF rather than Electron. Installed through
*spotify-launcher*, it is started by a program that builds its own command line
and has a configuration file with a slot for extra arguments; that slot is
where the flag goes. Installed as a plain package, it is an ordinary desktop
entry and needs nothing special.

# WHAT CANNOT BE DETECTED

An AppImage keeps its payload in a compressed filesystem, so there is no way to
tell from the outside whether it contains Chromium. Those are listed as *cannot
tell* and left alone until they are switched on from the applications screen.

# FILES

_~/.config/middleclick-autoscroll/config_
	Written by the program. Every option in it is reachable from the menu.

_~/.local/state/middleclick-autoscroll/ledger_
	One line per change, so *disable* can undo exactly what was done and
	nothing else.

_~/.local/state/middleclick-autoscroll/backup/_
	Copies of the files that are edited in place rather than shadowed.

_~/.cache/middleclick-autoscroll/detect_
	Which programs were found to be Chromium, keyed by size and modification
	time. Safe to delete.

# ENVIRONMENT

*NO_COLOR*
	Disables colour.

# SEE ALSO

*systemctl*(1), *flatpak*(1)

# AUTHORS

Felitendo. Source and issue tracker at
https://github.com/Felitendo/middleclick-autoscroll
