# middleclick-autoscroll

Middle-click autoscroll is a CLI for Linux that enables autoscroll in every application that supports it.
Works with browsers, Electron apps like Discord and Spotify, Steam, and anything else that runs on Chromium under the hood.

There is no app list. My tool just looks at what uses chromium under the hood and applies the necessary steps to get it working.

## How to install

**Arch**

```bash
paru -S middleclick-autoscroll
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

Then run `middleclick-autoscroll`. This will open the configuration CLI.

Remember to run `middleclick-autoscroll disable` before removing the package
so it undoes everything.

## How it works

Blink (the engine in Chromium, Electron, and CEF) already has autoscroll, but
it's off on Linux because middle click does primary-selection paste there. This
flag turns it on:

--enable-blink-features=MiddleClickAutoscroll

But doing that for every app is kinda bothersome and it also might break with updates.
That's why I created this small tool to automate that.

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

Or just use `man middleclick-autoscroll` for a simple to navigate TUI.

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
