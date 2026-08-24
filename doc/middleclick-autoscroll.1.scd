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
keeps doing so for anything installed later. It works on any distribution:
which of the routes below an application takes is read off its launcher, not
assumed from where the launcher came from.

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

*apply* [*--rebuild*]
	Apply to anything that has appeared since the last run. This is what the
	watcher calls; running it by hand is only needed when the watcher is off.

	Entries left behind by an application that has since been uninstalled are
	removed here too - the entry shadowing it lives in the user's home, where
	the package manager that removed the application cannot see it.

	With *--rebuild* everything is taken back first and written again from
	scratch. That is the repair: it does not care what looks correct already.

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
	Where the launcher reads extra arguments from
	_$XDG_CONFIG_HOME/<name>-flags.conf_. This is the preferred route: it is
	the supported way to pass arguments, it survives package upgrades, and it
	applies to a launch from a terminal as much as one from the menu. An
	*--enable-blink-features* line that is already in the file is extended
	rather than duplicated - Chromium keeps only the last occurrence of that
	option, so a second one would switch the first one off.

	Arch's Electron and Chromium packages all wrap their binaries this way, and
	so do a number of individual vendors' launchers elsewhere. Whether a given
	launcher does is read off the launcher itself, never assumed from the
	distribution: only one that really names such a file takes this route.

*Desktop entry*
	For applications that ship their own binary with no wrapper, and for
	everything inside a Flatpak or a snap, a copy of the desktop entry with the
	argument appended is written to _~/.local/share/applications_, where it
	shadows the system one. Entries that already live there - AppImages, web
	app shortcuts - are edited in place, with the original kept.

	This is the route everything takes on the distributions whose Chromium
	wrappers keep their equivalent file under _/etc_, where it is the system's
	to write and not the user's: Debian, Ubuntu, Fedora and openSUSE among
	them.

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

Where that installation is depends on how Steam was installed:
_~/.local/share/Steam_ for Valve's own package and Arch's,
_~/.steam/debian-installation_ for Debian's, and the private tree of the
sandbox for the Flatpak and the snap. All of them are looked at.

Steam compares the installed files against its manifest at every start - by
size, not by content - and restores whatever differs, so its launcher entry
gets *-noverifyfiles*. So does its entry in _~/.config/autostart_, which Steam
writes as soon as it is set to run at login: that entry bypasses the menu one
entirely, and without the switch a Steam started at login spends the session in
an update dialog. The trade-off is that Steam no longer repairs a damaged
installation on its own; that is why Steam is a switch of its own in the
settings.

The shortcuts Steam writes for single games carry the switch too. A game is not
an application this program has anything to offer and none of them is listed
under *Applications*, but starting one with Steam closed is a Steam start like
any other, and without the switch it costs the interface its autoscroll for the
rest of the session.

Starting Steam some other way - from a terminal, from a script - leaves the
switch out, and Steam puts its own copy of the script back for that session.
The patch returns at the next apply with Steam closed. It is deliberately not
repeated while the client is running: the two would only undo each other, and
the helper is started once, at the start, so it would not help that session
anyway.

# SPOTIFY

The official client is CEF rather than Electron. Installed through
*spotify-launcher*, it is started by a program that builds its own command line
and has a configuration file with a slot for extra arguments; that slot is
where the flag goes. Installed as a plain package, a Flatpak or a snap, it is
an ordinary desktop entry and needs nothing special.

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

# REQUIREMENTS

Bash 4.2 or newer and GNU coreutils. The watcher needs a systemd user session;
without one everything else works and applications installed later are picked
up at the next *apply* rather than on their own.

# SEE ALSO

*systemctl*(1), *flatpak*(1), *snap*(8)

# AUTHORS

Felitendo. Source and issue tracker at
https://github.com/Felitendo/middleclick-autoscroll
