# middleclick-autoscroll

middleclick-autoscroll (what a great name, wow) is a CLI for Linux that enables autoscroll in every application that supports it.
Works with browsers, Electron apps like Discord and Spotify, Steam, and anything else that runs on Chromium under the hood.

This tool looks at which of your apps run chromium under the hood and applies the necessary steps to get autoscrolling working. One install, one command and everything _✨just works✨_

## How to install

**Arch (for the cachyos enjoyers)**

```bash
yay -S middleclick-autoscroll
```

**Fedora (for the mentally stable)**

```bash
sudo curl -fsSL -o /etc/yum.repos.d/middleclick-autoscroll.repo \
  https://felitendo.github.io/middleclick-autoscroll/middleclick-autoscroll.repo
sudo dnf install middleclick-autoscroll
```

**Debian (for the elderly)**

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://felitendo.github.io/middleclick-autoscroll/KEY.gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/middleclick-autoscroll.gpg
echo "deb [signed-by=/etc/apt/keyrings/middleclick-autoscroll.gpg] https://felitendo.github.io/middleclick-autoscroll/deb ./" \
  | sudo tee /etc/apt/sources.list.d/middleclick-autoscroll.list
sudo apt update && sudo apt install middleclick-autoscroll
```

**openSUSE (idek who would use that)**

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

Normally you just need to press `[1]` and the magic is done.
Pressing `[3]` lets you see every app that was found and toggle each individually. 

```
  Applications

  ▸ Steam                              on (Steam)
    Chromium                           on (launcher)
    Discord                            on (flag file)
    Obsidian                           on (launcher)
    Spotify                            on (launcher)
    Slack                              off
    Cursor                             cannot tell

  Up/Down select - Space turns one on or off - q goes back
```

`[4]` for more settings.

## How it works

Blink (the engine in Chromium, Electron, and CEF) already has autoscroll, but
it's off on Linux by default because middle click normally pastes the clipboard (??).
This flag turns it on:

--enable-blink-features=MiddleClickAutoscroll

But doing that for every app is kinda bothersome and it also might break with updates.
That's why I created this small tool to automate that.

Browsers get the same thing but this time without "blink":

--enable-features=MiddleClickAutoscroll

But both do the same ¯\_(ツ)_/¯

New apps are picked up by a systemd path unit that watches the
relevant directories. If you hate systemd; `middleclick-autoscroll apply` does the
same thing manually.

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
