# Built with `packaging/build-rpm.sh`, which passes the version in rather than
# editing this file: the Makefile is where the version is written down, and two
# places that have to agree are one place too many.
%global upstream_version %{?_version}%{!?_version:1.0.3}

Name:           middleclick-autoscroll
Version:        %{upstream_version}
Release:        1%{?dist}
Summary:        Middle-click autoscroll for Chromium-based applications

License:        GPL-3.0-or-later
URL:            https://github.com/Felitendo/middleclick-autoscroll
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  make
BuildRequires:  gettext
BuildRequires:  scdoc
# For %{_userunitdir}, which is where the watcher's user units belong.
BuildRequires:  systemd-rpm-macros

Requires:       bash >= 4.2
Requires:       coreutils
Requires:       findutils
Requires:       grep
Requires:       sed
Requires:       gawk

# The interface falls back to English without gettext and picks up new
# applications at the next `apply` without systemd, so neither is required.
Recommends:     /usr/bin/gettext
Recommends:     systemd
Recommends:     desktop-file-utils

%description
Blink - the engine inside Chromium, Electron and CEF - has had Windows-style
autoscroll for years: hold the middle mouse button, move the pointer, the page
scrolls. On Linux it is switched off, because middle click is already taken by
primary-selection paste.

This turns it back on for every application on the system that can do it, and
for anything installed later. There is no list of supported applications to keep
up to date: every launcher is examined, the ones running on Chromium underneath
are identified by what they ship rather than by their name, and the argument goes
wherever that particular application will actually read it.

Nothing outside the user's home directory is ever written to. Run
"middleclick-autoscroll disable" before removing this package, so that everything
it changed is put back.

%prep
%autosetup -n %{name}-%{version}

%build
%make_build VERSION=%{upstream_version}

%install
%make_install PREFIX=%{_prefix} VERSION=%{upstream_version} \
	USERUNITDIR=%{_userunitdir}

%find_lang %{name}

%files -f %{name}.lang
%license LICENSE
%doc %{_datadir}/doc/%{name}/README.md
%{_bindir}/%{name}
%{_datadir}/%{name}/
%{_userunitdir}/%{name}.path
%{_userunitdir}/%{name}.service
%{_mandir}/man1/%{name}.1*

%changelog
