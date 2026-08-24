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

## Trying the release path first

```bash
gh workflow run release.yml -f dry_run=true
```

Builds both packages, builds both repositories with a key generated on the
spot, checks the three signatures it wrote, and then installs the packages back
out of the repositories — apt on the runner, dnf in a Fedora container. Nothing
is pushed and no release is made. This is worth running after any change to the
packaging, because the alternative is finding out from a tag.

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

Without the secret the workflow still builds both packages and attaches them to
the release; it says so in the log and leaves the repositories alone.

## Pointing Pages at it, once — and in this order

The `gh-pages` branch does not exist until a release has put something on it,
and a branch that does not exist cannot be picked in the Pages settings. So:

1. Set the secret, above.
2. Tag a release. The workflow creates the branch and fills it.
3. *Then* set **Pages** to deploy from a branch and pick `gh-pages` at the
   root.

Doing it the other way round is a wall, and leaving Pages pointed at `main`
serves the source tree at the address the install instructions name — the key
and the indexes are 404 and nothing installs.

## What users end up with

The public key is published as `KEY.gpg` beside the repositories, and the
landing page carries the setup lines for each distribution. After that, a new
version arrives with `apt upgrade`, `dnf upgrade` or `zypper up` like anything
else.
