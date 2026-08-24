# middleclick-autoscroll

Middle-click autoscroll — hold the middle mouse button, move the pointer, the
page scrolls — in every application on the system that can do it, and in
anything installed later.

There is no list of supported applications to check against and none to keep up
to date. Every launcher on the system is examined, the ones running on Chromium
underneath are identified by what they ship rather than by their name, and each
of them is handled.

## Installing

**Arch, CachyOS, EndeavourOS, Manjaro**

```bash
paru -S middleclick-autoscroll
```

**Debian, Ubuntu, Linux Mint, Pop!_OS**

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://felitendo.github.io/middleclick-autoscroll/KEY.gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/middleclick-autoscroll.gpg
echo "deb [signed-by=/etc/apt/keyrings/middleclick-autoscroll.gpg] https://felitendo.github.io/middleclick-autoscroll/deb ./" \
  | sudo tee /etc/apt/sources.list.d/middleclick-autoscroll.list
sudo apt update && sudo apt install middleclick-autoscroll
```

**Fedora, RHEL, CentOS Stream**

```bash
sudo curl -fsSL -o /etc/yum.repos.d/middleclick-autoscroll.repo \
  https://felitendo.github.io/middleclick-autoscroll/middleclick-autoscroll.repo
sudo dnf install middleclick-autoscroll
```

**openSUSE**

```bash
sudo rpm --import https://felitendo.github.io/middleclick-autoscroll/KEY.gpg
sudo zypper addrepo --gpgcheck --refresh \
  https://felitendo.github.io/middleclick-autoscroll/rpm middleclick-autoscroll
sudo zypper install middleclick-autoscroll
```

Then `middleclick-autoscroll enable`, once. That is the whole setup: nothing
else has to be configured, and no file has to be edited.

Every package is signed, and a new version arrives with `apt upgrade`,
`dnf upgrade` or `zypper up` like anything else. Anywhere without a package,
build it — [from source](#building-from-source) — or take the `.deb` or the
`.rpm` off the
[releases page](https://github.com/Felitendo/middleclick-autoscroll/releases).

Run `middleclick-autoscroll disable` before removing the package: it puts back
everything that was changed.

## Why this needs a program at all

Blink — the engine inside Chromium, Electron and CEF — has had Windows-style
autoscroll for years. On Linux it is switched off, because middle click is
already taken by primary-selection paste. One command line argument turns it
back on:

```
--enable-blink-features=MiddleClickAutoscroll
```

Getting that argument into one application is a five-minute job. Getting it into
all of them, in a way that survives the next package upgrade, is not:

- Some applications read a flag file, some don't - and which do depends on the
  distribution as much as on the application.
- Some ship their own copy of Electron, some use the system one.
- Flatpaks and snaps see none of the host's configuration.
- An application that starts itself at login uses a different entry than the one
  in the menu, and Discord launched at login used to behave differently from
  Discord launched by hand.
- Steam takes no arguments for its interface at all, and puts back any file you
  change.
- Every upgrade can undo the lot.

## The interface

`middleclick-autoscroll` on its own:

```
  Middle-Click Autoscroll

  Autoscroll                     ON

  Applications covered           14 of 15
  Not identified                 1 - see the applications list
  Steam                          ON
  New applications               ON
  Last applied                   3 minutes ago

  Applications pick this up the next time they are started.

  [1] Turn autoscroll on or off
  [2] Re-apply everything
  [3] Applications
  [4] Settings
  [q] Quit
```

**[3] Applications** lists everything that was found, how each one is handled,
and lets a single application be switched off — or an unrecognised one switched
on — with the space bar:

```
  Applications

  ▸ Vesktop                            on (flag file)
    Discord                            on (flag file)
    Code - OSS                         on (flag file)
    Obsidian                           on (flag file)
    Signal                             on (flag file)
    Spotify                            on (launcher)
    Steam                              on (Steam)
    Cursor                             cannot tell
```

**[4] Settings** has the categories — Electron and CEF applications, browsers,
Flatpaks, snaps, autostart entries, Steam, Spotify, whether to watch for new
applications, and a field for extra Chromium arguments if you want any.

There is a configuration file behind all of this. You are never asked to open
it.

## Where the argument actually goes

Two routes, picked per application.

| | |
|---|---|
| **Flag file** | Where the launcher reads extra arguments from `~/.config/<name>-flags.conf`. This is the good one: it is the supported way to pass arguments, it survives package upgrades untouched, and it applies to a launch from a terminal as much as one from the menu. Arch's Electron and Chromium packages all work this way, and a number of individual vendors' launchers do everywhere else. |
| **Desktop entry** | For applications that ship their own binary with no wrapper, and for everything inside a Flatpak or a snap, a copy of the entry with the argument appended goes into `~/.local/share/applications`, where it shadows the system one. |

Which of the two an application ends up on is decided by reading its launcher,
never by knowing which distribution this is. Nothing here has a list of
distributions in it any more than it has a list of applications.

Entries that already live in `~/.local/share/applications` — AppImages, web app
shortcuts — are edited in place and the original is kept. So are the entries in
`~/.config/autostart`, so an application that starts itself at login gets the
same treatment as one started from the menu.

An `--enable-blink-features` that is already there is **extended**, never
repeated. Chromium keeps only the last occurrence of that option, so a second
one would silently switch off whatever the first one enabled.

## Steam

Steam's interface is CEF and supports the feature perfectly well, but Steam
builds the command line for its web helper itself and offers no way to add to
it. The only place an argument fits is the script that starts the helper, inside
Steam's own installation:

```
~/.local/share/Steam/ubuntu12_64/steamwebhelper_sniper_wrap.sh
```

Steam compares the installed files against its manifest at every start — by
size, not by content — and restores whatever differs, so its launcher entry gets
`-noverifyfiles`. So does its entry in `~/.config/autostart`, which Steam writes
as soon as it is set to run at login: that one bypasses the menu entry entirely,
and without the switch a Steam started at login finds the patched script,
restores it, gets patched again, and never gets past its update dialog.

The shortcuts Steam writes for single games get the switch as well. A game is
not an application this program has anything to offer — none of them is a
Chromium process and none appears in the applications list — but starting one
with Steam closed is a Steam start like any other, and leaving the switch out
there costs the interface its autoscroll for the rest of the session.

**The trade-off is real**: with verification off, Steam no longer repairs a
damaged installation by itself. That is why Steam is a switch of its own rather
than part of the general handling — turn it off in the settings and Steam is
left completely alone.

The script comes back on every client update. The watcher notices and puts the
patch back.

Starting Steam some other way — from a terminal, from a script — leaves the
switch out and Steam puts its own copy back for that session. The patch returns
at the next apply with Steam closed; it is deliberately not repeated while the
client is running, because the two would only undo each other and the helper is
started once, at the start.

## Applications installed later

A systemd user path unit watches every directory a launcher can appear in —
`/usr/share/applications`, the Flatpak exports, snapd's export directory, the
NixOS and Guix profiles, `~/.local/share/applications`, `~/.config/autostart` —
plus Steam's helper script. Anything new is handled within a second of being
installed, whether it came from pacman, apt, dnf, zypper, the AUR, Flatpak,
snapd or an AppImage manager. There is no hook to install per package manager,
which is the only reason one program can cover all of them.

Without systemd nothing breaks; new applications are picked up the next time
`middleclick-autoscroll apply` runs instead of on their own.

## What it will not guess

An AppImage keeps its payload in a compressed filesystem, so there is no way to
tell from the outside whether Chromium is in there. Those show up as **cannot
tell** and are left alone until you switch them on from the applications screen.

Detection is deliberately conservative everywhere else too. A wrong "yes" would
append an unknown argument to something that is not Chromium, and plenty of
programs treat an unrecognised argument as a file name to open.

## Undoing it

```bash
middleclick-autoscroll disable
```

Every change is recorded in a ledger as it is made, and `disable` replays it
backwards: generated entries are deleted, edited files are restored from their
backups, flag files that only ever contained our line are removed, and a flag
file that was merged into loses exactly the one feature that was added to it.
Files that were not touched by this program are not touched by it now either.

Run this before uninstalling the package.

## Commands

| | |
|---|---|
| `middleclick-autoscroll` | the menu above |
| `… enable` | turn it on, apply, start watching |
| `… disable` | turn it off and put everything back |
| `… apply` | apply to anything new (this is what the watcher calls) |
| `… apply --rebuild` | take everything back and apply it again, to repair a mess |
| `… status` | what is covered |
| `… list` | every application that was found and how it is handled |

See `man middleclick-autoscroll` for the details.

## Distributions

Any of them. Nothing here is keyed to a distribution name — what differs is
which of the two routes above an application ends up on, and that is read off
its launcher.

On Arch and its derivatives most Electron and Chromium packages ship a wrapper
that reads a flag file, so most applications take that route. On Debian,
Ubuntu, Fedora and openSUSE the equivalent file lives under `/etc` and belongs
to the system rather than to you, so there is no flag file to write and those
applications go through their launcher entry instead. Both work. The flag file
is only the nicer of the two, because it applies to a launch from a terminal as
well.

Snaps are handled the way Flatpaks are: what a snap ships lives in its own
mounted tree, `/snap/bin/<name>` is a shim into snapd and says nothing about
what is behind it, and the launcher entry is the only way in. Each has a switch
of its own in the settings.

Steam is found wherever the installation actually is — `~/.local/share/Steam`
for Valve's own package and Arch's, `~/.steam/debian-installation` for
Debian's, and inside the private tree for the Flatpak and the snap.

## Requirements

Bash 4.2 or newer, GNU coreutils, and systemd for the watcher — that is all,
and it is what a desktop Linux install already has. Nothing outside your home
directory is ever written to, and running it as root is refused.

## Building from source

```bash
make
sudo make install
```

`make` needs `msgfmt` (gettext) for the translations and `scdoc` for the man
page; both are optional and skipped with a note when missing. `make install`
puts the systemd user units where systemd itself says they go, and honours the
usual `PREFIX` and `DESTDIR`:

```bash
make PREFIX=/usr/local
sudo make PREFIX=/usr/local install
```

`make check` runs `bash -n` and, if installed, `shellcheck` over every script.

The `.deb` and the `.rpm` are built from the same `make install`, by
`packaging/build-deb.sh` and `packaging/build-rpm.sh`. See
[packaging/README.md](packaging/README.md) for how a release is made and how
the repositories are signed.

## License

GPL-3.0-or-later.
