# middleclick-autoscroll - build and install
#
# Everything here is plain shell; "building" only means compiling the gettext
# catalogs and rendering the man page. Both targets degrade to a no-op when
# msgfmt/scdoc are missing, so the tree stays usable for development without
# the build dependencies installed.

# Overridable so a packager can pass the version it is actually building
# (`make VERSION=$pkgver`). The literal below is the fallback for builds
# straight from a checkout, and is what a release tag has to carry.
VERSION      ?= 1.0.3

PREFIX       ?= /usr
DESTDIR      ?=
BINDIR       ?= $(PREFIX)/bin
DATADIR      ?= $(PREFIX)/share
LIBDIR       ?= $(DATADIR)/middleclick-autoscroll/lib
LOCALEDIR    ?= $(DATADIR)/locale
MANDIR       ?= $(DATADIR)/man

# Where systemd looks for user units. For a normal install into /usr this is
# asked of systemd itself, because the answer is not the same everywhere - a
# distribution that still keeps /lib separate from /usr/lib says so here - and
# only guessed at when there is no systemd installed to ask.
#
# A build with a prefix of its own keeps the units under that prefix instead.
# systemd searches $(PREFIX)/lib/systemd/user as well, and a file outside the
# prefix it was asked for is not this build's to place.
ifeq ($(PREFIX),/usr)
USERUNITDIR  ?= $(shell pkg-config --variable=systemduserunitdir systemd 2>/dev/null || echo /usr/lib/systemd/user)
else
USERUNITDIR  ?= $(PREFIX)/lib/systemd/user
endif

LINGUAS      := de
MOFILES      := $(patsubst %,po/%.mo,$(LINGUAS))
MANPAGE      := doc/middleclick-autoscroll.1

LIBS         := $(wildcard src/lib/*.sh)

MSGFMT       := $(shell command -v msgfmt 2>/dev/null)
SCDOC        := $(shell command -v scdoc 2>/dev/null)

.PHONY: all build install uninstall check clean

all: build

build: $(MOFILES) $(MANPAGE)

po/%.mo: po/%.po
ifdef MSGFMT
	$(MSGFMT) --check --output-file=$@ $<
else
	@echo "msgfmt not found - skipping $@"
endif

$(MANPAGE): doc/middleclick-autoscroll.1.scd
ifdef SCDOC
	$(SCDOC) < $< > $@
else
	@echo "scdoc not found - skipping $@"
endif

# Syntax-check every shell file, and run shellcheck when it is available.
check:
	@set -e; for f in src/middleclick-autoscroll $(LIBS); do \
		bash -n "$$f" && echo "ok  $$f"; \
	done
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x -e SC1090,SC1091 src/middleclick-autoscroll $(LIBS); \
		echo "ok  shellcheck"; \
	else \
		echo "shellcheck not found - skipped"; \
	fi
	@if command -v desktop-file-validate >/dev/null 2>&1; then \
		echo "ok  desktop-file-validate (nothing to check)"; \
	fi

install: build
	# executable
	install -Dm755 src/middleclick-autoscroll \
		"$(DESTDIR)$(BINDIR)/middleclick-autoscroll"

	# shell libraries
	install -d "$(DESTDIR)$(LIBDIR)"
	install -Dm644 -t "$(DESTDIR)$(LIBDIR)" $(LIBS)

	# the version and the resolved paths are baked in at install time
	sed -i -e 's|@VERSION@|$(VERSION)|g' \
	       -e 's|@LIBDIR@|$(LIBDIR)|g' \
	       -e 's|@LOCALEDIR@|$(LOCALEDIR)|g' \
	       "$(DESTDIR)$(BINDIR)/middleclick-autoscroll" \
	       "$(DESTDIR)$(LIBDIR)"/*.sh

	# user units: the watcher, and the one-shot it starts
	install -Dm644 res/systemd/middleclick-autoscroll.service \
		"$(DESTDIR)$(USERUNITDIR)/middleclick-autoscroll.service"
	install -Dm644 res/systemd/middleclick-autoscroll.path \
		"$(DESTDIR)$(USERUNITDIR)/middleclick-autoscroll.path"
	sed -i -e 's|@BINDIR@|$(BINDIR)|g' \
		"$(DESTDIR)$(USERUNITDIR)/middleclick-autoscroll.service"

	# translations
	@for l in $(LINGUAS); do \
		if [ -f "po/$$l.mo" ]; then \
			install -Dm644 "po/$$l.mo" \
				"$(DESTDIR)$(LOCALEDIR)/$$l/LC_MESSAGES/middleclick-autoscroll.mo"; \
		fi; \
	done

	# documentation
	@if [ -f $(MANPAGE) ]; then \
		install -Dm644 $(MANPAGE) "$(DESTDIR)$(MANDIR)/man1/middleclick-autoscroll.1"; \
	fi
	install -Dm644 README.md \
		"$(DESTDIR)$(DATADIR)/doc/middleclick-autoscroll/README.md"

uninstall:
	rm -f  "$(DESTDIR)$(BINDIR)/middleclick-autoscroll"
	rm -rf "$(DESTDIR)$(DATADIR)/middleclick-autoscroll"
	rm -f  "$(DESTDIR)$(USERUNITDIR)/middleclick-autoscroll.service"
	rm -f  "$(DESTDIR)$(USERUNITDIR)/middleclick-autoscroll.path"
	rm -f  "$(DESTDIR)$(MANDIR)/man1/middleclick-autoscroll.1"
	rm -rf "$(DESTDIR)$(DATADIR)/doc/middleclick-autoscroll"

clean:
	rm -f po/*.mo $(MANPAGE)
