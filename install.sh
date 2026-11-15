#! /usr/bin/env bash

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run as root!' >&2
    exit 1
fi

if ! [ -x "$(command -v dkms)" ]; then
    echo 'This script requires DKMS!' >&2
    exit 1
fi

if [ -f /usr/local/bin/xow ]; then
    echo 'Please uninstall xow!' >&2
    exit 1
fi

if [ -n "${SUDO_USER:-}" ]; then
    # Run as normal user to prevent "unsafe repository" error
    version=$(sudo -u "$SUDO_USER" git describe --tags 2> /dev/null || echo unknown)
else
    version=unknown
fi

# remove "v" prefix
version=${version##v}

source="/usr/src/xone-$version"
log="/var/lib/dkms/xone/$version/build/make.log"

if [ -n "$(dkms status xone)" ]; then
    echo -e 'Driver is already installed, uninstalling...\n'
    ./uninstall.sh --no-firmware
fi

echo "Installing xone $version..."
cp -r . "$source"
find "$source" -type f \( -name dkms.conf -o -name '*.c' \) -exec sed -i "s/#VERSION#/$version/" {} +

# The MAKE line in dkms.conf is required for kernels built using clang.
# Add it if the kernel is built using gcc - i.e. "clang" is in the kernel
# version string.
if [ -n "$(cat /proc/version | grep clang)" ]; then
    echo 'MAKE[0]="make V=1 LLVM=1 -C ${kernel_source_dir}'\
        'M=${dkms_tree}/${PACKAGE_NAME}/${PACKAGE_VERSION}/build"'\
        >> "$source/dkms.conf"
fi

if [ "${1:-}" == --debug ]; then
    echo 'ccflags-y += -DDEBUG' >> "$source/Kbuild"
fi

if dkms install -m xone -v "$version" --force; then
    # The modprobe config should be placed in /usr/local/lib/modprobe.d for kmod 29+
    rm -f /etc/modprobe.d/xone-blacklist.conf
    install -D -m 644 install/modprobe.conf /etc/modprobe.d/xone.conf
    install -D -m 644 install/udev.rules /etc/udev/rules.d/50-xone.rules

    if [ -x "$(command -v udevadm)" ]; then
        udevadm control --reload-rules
        udevadm trigger --subsystem-match=usb --attr-match=bInterfaceClass=ff \
            --attr-match=bInterfaceSubClass=47 --attr-match=bInterfaceProtocol=d0 || true
    fi

    # Avoid conflicts between mt76x2u and xone
    if lsmod | grep -q '^mt76x2u'; then
        modprobe -r mt76x2u
    fi
else
    if [ -r "$log" ]; then
        cat "$log" >&2
    fi

    exit 1
fi

echo -e "\nxone installation finished\n"
