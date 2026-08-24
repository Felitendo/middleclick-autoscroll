# Packaging and releases

The Makefile installs everything; these only wrap what it produced. That is
deliberate — a packaging script that lists the files again is a second
description of the layout, and two descriptions drift.

| | |
|---|---|
| `deb/control`, `deb/copyright` | metadata for the Debian binary package |
| `rpm/middleclick-autoscroll.spec` | the RPM spec |
| `build-deb.sh`, `build-rpm.sh` | build one package into `dist/` |
| `check-version.sh` | refuses a tag that disagrees with the Makefile |
| `publish-repos.sh` | regenerates the APT and RPM repositories |
| `pages/` | the landing page and the `.repo` file served from GitHub Pages |

Neither package carries a maintainer script. The units are enabled per user by
the program itself, and there is nothing to do as root at install time.

## Building one by hand

```bash
packaging/build-deb.sh      # needs dpkg-dev, gettext, scdoc
packaging/build-rpm.sh      # needs rpm-build, gettext, scdoc, systemd-rpm-macros
```

Both take the version from `make version` unless one is passed as the first
argument.

## Making a release

1. Bump `VERSION` in the Makefile.
2. Commit, then `git tag vX.Y.Z && git push --tags`.

The `release` workflow builds both packages in a Debian and a Fedora container,
refuses the tag if it disagrees with the Makefile, attaches the packages to a
GitHub release, and adds them to the APT and RPM repositories on the `gh-pages`
branch. Nothing else has to be done by hand.

## Setting up the signing, once

The repositories are signed, so this needs a key. Make one that exists for
nothing else — not a personal key — and give it no passphrase: it lives as an
encrypted repository secret, and `rpmsign` cannot be handed a passphrase
unattended.

```bash
gpg --batch --passphrase '' --quick-generate-key \
    'middleclick-autoscroll repository <felitendoyt@gmail.com>' rsa4096 sign never

gpg --armor --export-secret-keys 'middleclick-autoscroll repository' \
    | gh secret set GPG_PRIVATE_KEY
```

Then, in the repository settings, set **Pages** to deploy from a branch and
pick `gh-pages` at the root. The branch is created by the first release that
runs with the key in place.

Without the secret the workflow still builds both packages and attaches them to
the release; it says so in the log and leaves the repositories alone.

## What users end up with

The public key is published as `KEY.gpg` beside the repositories, and the
landing page carries the setup lines for each distribution. After that, a new
version arrives with `apt upgrade`, `dnf upgrade` or `zypper up` like anything
else.
