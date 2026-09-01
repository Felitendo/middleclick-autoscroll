# middleclick-autoscroll

Middle-click autoscroll for Linux. Hold the middle mouse button, move the
mouse, the page scrolls — like on Windows. Works with browsers, Electron apps,
Flatpaks, snaps, Steam, and anything else that runs on Chromium under the hood.

No app list to maintain. The program looks at what's actually installed, figures
out what's Chromium-based, and handles it.

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

Then run `middleclick-autoscroll enable`. That's it — nothing else to configure.

Updates come through your package manager like anything else. Without a package,
build [from source](#building-from-source) or grab a `.deb`/`.rpm` from the
[releases page](https://github.com/Felitendo/middleclick-autoscroll/releases).

Run `middleclick-autoscroll disable` before removing the package — it undoes
everything.

## How it works

Blink (the engine in Chromium, Electron, and CEF) already has autoscroll, but
it's off on Linux because middle click does primary-selection paste there. One
flag turns it on:

```
--enable-blink-features=MiddleClickAutoscroll
```

Doing that for one app is a five-minute job. Doing it for *all* of them — across
flag files, desktop entries, Flatpaks, snaps, autostart entries, Steam — so it
survives upgrades, is not. That's what this does.

New apps are picked up within a second by a systemd path unit that watches the
relevant directories. Without systemd, `middleclick-autoscroll apply` does the
same thing manually.

## Steam

Steam's web UI supports autoscroll but has no way to pass extra arguments to its
helper, so the program patches the script that starts it. Steam checks its own
files at every start and repairs whatever looks changed, so the patch is written
to look unchanged: the bytes the argument costs come back out of the script's
comments and the timestamp is restored, leaving a file exactly as long and as old
as Steam left it. It survives however you start Steam — the menu, a desktop
shortcut, a game launcher, a terminal.

As a fallback, for the case where that isn't possible, `-noverifyfiles` goes on
everything that starts Steam: its launcher, its autostart entry, and the
shortcuts it writes for single games. That one means Steam won't auto-repair
damaged files on its own — you can turn it off separately in the settings.

## Commands

| Command | |
|---|---|
| `middleclick-autoscroll` | Interactive menu |
| `… enable` | Turn on, apply, start watching |
| `… disable` | Undo everything |
| `… apply` | Apply to new apps |
| `… apply --rebuild` | Redo from scratch |
| `… status` | What's covered |
| `… list` | All apps and how they're handled |

See `man middleclick-autoscroll` for more.

## Building from source

```bash
make
sudo make install
```

Optionally needs `msgfmt` (gettext) for translations and `scdoc` for the man
page. Supports `PREFIX` and `DESTDIR`. `make check` runs syntax checks and
shellcheck.

See [packaging/README.md](packaging/README.md) for release builds and repo
signing.

## License

GPL-3.0-or-later.
