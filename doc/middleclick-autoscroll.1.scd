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

A browser is given *--enable-features=MiddleClickAutoscroll* instead. It asks
for the same feature - Blink generates a feature of that name for each of its
runtime flags - but it is not on the list of flags Chromium warns about, so the
browser does not put a bar reading "You are using an unsupported command-line
flag" above every page. That spelling only works from Chromium 124 onwards,
which is why everything else keeps the first one: an application that embeds an
older Chromium, such as Steam's CEF, has no such bar to show anyway. Helium
knows the feature under a name of its own and is asked for
*HeliumMiddleClickAutoscroll* as well; a name a browser does not know is
ignored. It works on any distribution:
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
	applies to a launch from a terminal as much as one from the menu. A
	feature list that is already in the file is extended rather than
	duplicated - Chromium keeps only the last occurrence of such an option, so
	a second one would switch the first one off.

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

Shortcuts on the desktop itself are patched in place too. Nothing in the XDG
search path looks at that folder, so a shortcut that lives only there would
otherwise be invisible - and Steam puts one there for every game somebody asks
for a shortcut to. The folder's name is translated, and the name in use is read
from _~/.config/user-dirs.dirs_ rather than guessed; the watcher is told about
it in a drop-in written when autoscroll is turned on.

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
size and timestamp rather than by content - and restores whatever differs. So
the patch is written to look untouched: the bytes the argument costs are taken
back out of the script's own comments and the timestamp is put back afterwards,
leaving a file exactly as long and exactly as old as Steam left it. A client
that checks its files finds nothing to repair, and the argument survives
however Steam was started - from the menu, from a game shortcut, from a
launcher like Heroic or Lutris, from a terminal.

That is what has to work, because there is no way to make every possible way of
starting Steam carry an argument. *-noverifyfiles* is the second line rather
than the first: it covers the case where the script has no comments left to pay
for the argument and the patch has to grow the file. It goes on Steam's
launcher entry, on its entry in _~/.config/autostart_, which Steam writes as
soon as it is set to run at login, and on the shortcuts Steam writes for single
games, on the desktop and in the menu alike. A game is not an application this
program has anything to offer and none of them is listed under *Applications*,
but starting one is a Steam start like any other. The trade-off of the switch
is that Steam no longer repairs a damaged installation on its own; that is why
Steam is a switch of its own in the settings.

A patch that does change the size is still held back while the client is
running: Steam puts its own copy back, the two would only undo each other, and
the helper is started once, at the start, so patching again would not help that
session anyway. It goes in at the next apply with Steam closed. A patch that
keeps the size has nothing to wait for and goes in either way.

A client update brings a new version of the script. The watcher notices and
patches it again, and the copy kept for undoing is replaced with the new
version at the same time, so undoing puts back the script Steam last shipped
rather than the one from before the update.

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
