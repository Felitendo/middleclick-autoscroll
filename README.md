# middleclick-autoscroll

Middle-click autoscroll is a CLI for Linux that enables autoscroll in every application that supports it.
Works with browsers, Electron apps like Discord and Spotify, Steam, and anything else that runs on Chromium under the hood.

There is no app list. My tool just looks at what uses chromium under the hood and applies the necessary steps to get it working.

## How to install

**Arch**

```bash
yay -S middleclick-autoscroll
```

**Fedora**

```bash
sudo curl -fsSL -o /etc/yum.repos.d/middleclick-autoscroll.repo \
  https://felitendo.github.io/middleclick-autoscroll/middleclick-autoscroll.repo
sudo dnf install middleclick-autoscroll
```

**Debian**

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://felitendo.github.io/middleclick-autoscroll/KEY.gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/middleclick-autoscroll.gpg
echo "deb [signed-by=/etc/apt/keyrings/middleclick-autoscroll.gpg] https://felitendo.github.io/middleclick-autoscroll/deb ./" \
  | sudo tee /etc/apt/sources.list.d/middleclick-autoscroll.list
sudo apt update && sudo apt install middleclick-autoscroll
```

**openSUSE**

```bash
sudo rpm --import https://felitendo.github.io/middleclick-autoscroll/KEY.gpg
sudo zypper addrepo --gpgcheck --refresh \
  https://felitendo.github.io/middleclick-autoscroll/rpm middleclick-autoscroll
sudo zypper install middleclick-autoscroll
```

## How to use

Just run `middleclick-autoscroll`. This will open the configuration TUI that looks like this:

```
  Middle-Click Autoscroll

  Autoscroll                     ON

  Applications covered           11 of 13
  Not identified                 1 - see the applications list
  Steam                          ON
  New applications               ON
  Last applied                   2 minutes ago

  Applications pick this up the next time they are started.

  [1] Turn autoscroll on or off
  [2] Re-apply everything
  [3] Applications
  [4] Settings
  [q] Quit

  >
```

`[1]` is all you need for the normal case. `[3]` lists every app that was found
and what is being done with it, so you can leave a single one out or switch on
an AppImage that couldn't be identified:

```
  Applications

  ▸ Steam                              on (Steam)
    Chromium                           on (launcher)
    Discord                            on (flag file)
    Obsidian                           on (launcher)
    Spotify                            on (launcher)
    Slack                              off
    Cursor                             cannot tell

  Anything not identified is left alone until it is turned on here.
  Up/Down select - Space turns one on or off - q goes back
```

`[4]` has the same switches per category - browsers, Electron and CEF apps,
Flatpaks, snaps, autostart entries, Steam, Spotify - plus a field for extra
Chromium arguments.

## How it works

Blink (the engine in Chromium, Electron, and CEF) already has autoscroll, but
it's off on Linux because middle click does primary-selection paste there. This
flag turns it on:

--enable-blink-features=MiddleClickAutoscroll

But doing that for every app is kinda bothersome and it also might break with updates.
That's why I created this small tool to automate that.

Browsers get the same thing asked for differently:

--enable-features=MiddleClickAutoscroll

Both mean the same feature - Blink generates a matching feature name for each of
its runtime flags - but the first one is on Chromium's list of flags worth
warning about, so a browser started with it shows a yellow "unsupported
command-line flag" bar over every page. The second one is not on that list, so
there's no bar. It only works from Chromium 124 on, which is why apps that
embed something older (Steam's CEF, older Electron) keep the first one - they
have no such bar to begin with. Helium, which carries the feature under its own
name, is asked for `HeliumMiddleClickAutoscroll` alongside it.

New apps are picked up by a systemd path unit that watches the
relevant directories. Without systemd, `middleclick-autoscroll apply` does the
same thing manually.

## Steam

Steam's web UI supports autoscroll but has no way to pass extra arguments to its
helper, so the program patches the script that starts it. Steam checks its own
files at every start and repairs whatever looks changed, so the patch is written
to look unchanged.

As a fallback, for the case where that isn't possible, `-noverifyfiles` goes on
everything that starts Steam: its launcher, its autostart entry, and the
shortcuts it writes for single games. That one means Steam won't auto-repair
damaged files on its own just so you're aware of that.

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
