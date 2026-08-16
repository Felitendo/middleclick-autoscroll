# middleclick-autoscroll

Middle-click autoscroll — hold the middle mouse button, move the pointer, the
page scrolls — for every Chromium-based application on the system. Discord,
Vesktop, Equibop, VS Code, Obsidian, Signal, Spotify, Steam, Chromium-based
browsers, and whatever gets installed next week.

```bash
paru -S middleclick-autoscroll
middleclick-autoscroll enable
```

That is the whole setup. Nothing else has to be configured, and no file has to
be edited.

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

- Some applications read a flag file, some don't.
- Some ship their own copy of Electron, some use the system one.
- Flatpaks see none of the host's configuration.
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
  [2] Apply now
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
Flatpaks, autostart entries, Steam, Spotify, whether to watch for new
applications, and a field for extra Chromium arguments if you want any.

There is a configuration file behind all of this. You are never asked to open
it.

## Where the argument actually goes

Two routes, picked per application.

| | |
|---|---|
| **Flag file** | Arch's Electron and Chromium wrappers read extra arguments from `~/.config/<name>-flags.conf`. This is the good one: it is the supported way to pass arguments, it survives package upgrades untouched, and it applies to a launch from a terminal as much as one from the menu. |
| **Desktop entry** | For applications that ship their own binary with no wrapper, and for Flatpaks, a copy of the entry with the argument appended goes into `~/.local/share/applications`, where it shadows the system one. |

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

Steam checksums that script at every start and restores it when it differs, so
its launcher entry also gets `-noverifyfiles`. **The trade-off is real**: with
verification off, Steam no longer repairs a damaged installation by itself. That
is why Steam is a switch of its own rather than part of the general handling —
turn it off in the settings and Steam is left completely alone.

The script comes back on every client update. The watcher notices and puts the
patch back.

Starting Steam from a terminal without `-noverifyfiles` undoes it for that one
session; the next start from the menu has it again.

## Applications installed later

A systemd user path unit watches every directory a launcher can appear in —
`/usr/share/applications`, the Flatpak exports, `~/.local/share/applications`,
`~/.config/autostart` — plus Steam's helper script. Anything new is handled
within a second of being installed, whether it came from pacman, the AUR,
Flatpak or an AppImage manager. There is no hook to install per package manager.

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
| `… status` | what is covered |
| `… list` | every application that was found and how it is handled |

See `man middleclick-autoscroll` for the details.

## Requirements

Arch or an Arch derivative (CachyOS, EndeavourOS, Manjaro), bash, systemd for
the watcher. Nothing outside your home directory is ever written to, and running
it as root is refused.

## Building from source

```bash
make
sudo make install
```

`make check` runs `bash -n` and, if installed, `shellcheck` over every script.

## License

GPL-3.0-or-later.
