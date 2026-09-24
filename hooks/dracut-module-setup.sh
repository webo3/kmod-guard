#!/bin/bash
# kmod-guard: keep the module blocklist out of the initramfs. It is a
# policy for the running system and must not stop a new kernel from loading
# its root-disk drivers at boot.
check() { return 0; }
depends() { return 0; }
install() {
    # shellcheck disable=SC2154 # initdir is set by dracut
    rm -f "${initdir}/etc/modprobe.d/kmod-guard.conf"
}
