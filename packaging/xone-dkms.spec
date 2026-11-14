%global debug_package %{nil}

Name:           xone-dkms
Version:        %{?_version:%{_version}}%{!?_version:0.5.8}
Release:        %{?_release:%{_release}}%{!?_release:1}%{?dist}
Summary:        Linux kernel driver for Xbox One and Xbox Series X|S accessories (DKMS, xpad-coexistence)
License:        GPL-2.0-or-later
URL:            https://github.com/Locoxella/xone
Source0:        xone-%{version}.tar.gz
BuildArch:      noarch

Requires:       dkms
Requires:       kernel-devel
Requires:       gcc
Requires:       make
Requires:       udev

%description
DKMS kernel driver for Xbox One and Xbox Series X|S wired/wireless accessories
and GIP headsets, configured to coexist cleanly with the mainline xpad driver.

%prep
%setup -q -n xone-%{version}

%install
rm -rf %{buildroot}
install -d -m 0755 %{buildroot}/usr/src/xone-%{version}
cp -a auth bus driver transport dkms.conf Kbuild Makefile LICENSE \
    %{buildroot}/usr/src/xone-%{version}/

find %{buildroot}/usr/src/xone-%{version} -type f \( -name dkms.conf -o -name '*.c' \) \
    -exec sed -i "s/#VERSION#/%{version}/g" {} +

install -D -m 0644 install/modprobe.conf %{buildroot}%{_sysconfdir}/modprobe.d/xone.conf
install -D -m 0644 install/udev.rules %{buildroot}%{_sysconfdir}/udev/rules.d/50-xone.rules

%post
rm -f /etc/modprobe.d/xone-blacklist.conf
dkms add -m xone -v %{version} --rpm_safe_upgrade >/dev/null 2>&1 || :
dkms build -m xone -v %{version} >/dev/null 2>&1 || :
dkms install -m xone -v %{version} --force >/dev/null 2>&1 || :
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules >/dev/null 2>&1 || :
    udevadm trigger --subsystem-match=usb --attr-match=bInterfaceClass=ff \
        --attr-match=bInterfaceSubClass=47 --attr-match=bInterfaceProtocol=d0 >/dev/null 2>&1 || :
fi

%preun
dkms remove -m xone -v %{version} --all --rpm_safe_upgrade >/dev/null 2>&1 || :

%postun
if [ "$1" -eq 0 ] && command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules >/dev/null 2>&1 || :
fi

%files
%license LICENSE
/usr/src/xone-%{version}
%config(noreplace) %{_sysconfdir}/modprobe.d/xone.conf
%{_sysconfdir}/udev/rules.d/50-xone.rules
