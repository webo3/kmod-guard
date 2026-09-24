#!/bin/sh
# Fixture tests for kmod-guard: two fake kernels, a fake /proc/modules and
# allow files in a temp dir. Nothing outside it is read or written.
#
#   sh tests/run.sh             # with /bin/sh
#   SH=dash sh tests/run.sh     # with another shell

set -u
here=$(cd "$(dirname "$0")" && pwd)
KG="${SH:-sh} $here/../kmod-guard"
R=$(mktemp -d "${TMPDIR:-/tmp}/kmod-guard-test.XXXXXX")
trap 'rm -rf "$R"' EXIT
mkdir -p "$R/lib/6.1.0-new" "$R/lib/6.0.0-old" "$R/etc/allow.d" "$R/state" "$R/modprobe.d"

export KMOD_GUARD_CONF_DIR="$R/etc" KMOD_GUARD_STATE_DIR="$R/state" \
    KMOD_GUARD_OUTPUT="$R/modprobe.d/kmod-guard.conf" \
    KMOD_GUARD_MODULES_ROOT="$R/lib" KMOD_GUARD_PROC_MODULES="$R/proc_modules"
OUT=$KMOD_GUARD_OUTPUT

fail=0
check() {
    if eval "$2"; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        fail=1
    fi
}
blocked() { grep -q "^install $1 " "$OUT"; }
loaded() { printf '%s 1 0 - Live 0x0\n' "$@" >"$R/proc_modules"; }

# 6.1.0-new: xfs gained a libcrc32c dependency, libcrc32c has an alias softdep
cat >"$R/lib/6.1.0-new/modules.dep" <<'EOF'
kernel/fs/xfs/xfs.ko.xz: kernel/lib/libcrc32c.ko.xz
kernel/lib/libcrc32c.ko.xz:
kernel/crypto/crc32c_generic.ko.xz:
kernel/fs/nfs/nfs.ko.xz: kernel/net/sunrpc/sunrpc.ko.xz kernel/fs/lockd/lockd.ko.xz kernel/fs/nfs_common/grace.ko.xz kernel/fs/netfs/netfs.ko.xz
kernel/fs/nfs/nfsv4.ko.xz: kernel/fs/nfs/nfs.ko.xz
kernel/net/sunrpc/sunrpc.ko.xz:
kernel/fs/lockd/lockd.ko.xz: kernel/net/sunrpc/sunrpc.ko.xz kernel/fs/nfs_common/grace.ko.xz
kernel/fs/nfs_common/grace.ko.xz:
kernel/fs/netfs/netfs.ko.xz:
kernel/net/sctp/sctp.ko.xz: kernel/lib/libcrc32c.ko.xz
kernel/drivers/edac/amd64_edac.ko.xz: kernel/drivers/edac/edac_mce_amd.ko.xz
kernel/drivers/edac/edac_mce_amd.ko.xz:
kernel/drivers/cpufreq/powernow-k8.ko.xz:
kernel/net/netfilter/nf_conntrack_netlink.ko.xz: kernel/net/netfilter/nf_conntrack.ko.xz kernel/net/netfilter/nfnetlink.ko.xz
kernel/net/netfilter/nf_conntrack.ko.xz: kernel/net/ipv6/netfilter/nf_defrag_ipv6.ko.xz
kernel/net/ipv6/netfilter/nf_defrag_ipv6.ko.xz:
kernel/net/netfilter/nfnetlink.ko.xz:
kernel/net/netfilter/xt_recent.ko.xz: kernel/net/netfilter/x_tables.ko.xz
kernel/net/netfilter/x_tables.ko.xz:
kernel/net/tipc/tipc.ko.xz: kernel/net/ipv4/udp_tunnel.ko.xz
kernel/net/ipv4/udp_tunnel.ko.xz:
kernel/drivers/net/wireguard/wireguard.ko.xz: kernel/lib/crypto/libcurve25519-generic.ko.xz kernel/net/ipv4/udp_tunnel.ko.xz
kernel/lib/crypto/libcurve25519-generic.ko.xz:
kernel/crypto/algif_skcipher.ko.xz: kernel/crypto/af_alg.ko.xz
kernel/crypto/af_alg.ko.xz:
kernel/drivers/tty/n_gsm.ko.xz:
kernel/fs/ext4/ext4.ko.zst: kernel/fs/jbd2/jbd2.ko.zst kernel/fs/mbcache.ko.zst
kernel/fs/jbd2/jbd2.ko.zst:
kernel/fs/mbcache.ko.zst:
kernel/sound/core/snd.ko.xz:
updates/dkms/snapapi26.ko:
EOF
echo 'softdep libcrc32c pre: crc32c' >"$R/lib/6.1.0-new/modules.softdep"
printf 'alias crc32c crc32c_generic\nalias crypto-crc32c crc32c_generic\nalias net-pf-132 sctp\n' \
    >"$R/lib/6.1.0-new/modules.alias"

cat >"$R/lib/6.0.0-old/modules.dep" <<'EOF'
kernel/fs/xfs/xfs.ko.xz:
kernel/lib/libcrc32c.ko.xz:
kernel/crypto/crc32c_generic.ko.xz:
kernel/net/sctp/sctp.ko.xz:
kernel/fs/ext4/ext4.ko.xz: kernel/fs/jbd2/jbd2.ko.xz
kernel/fs/jbd2/jbd2.ko.xz:
kernel/drivers/edac/amd64_edac.ko.xz:
kernel/drivers/tty/n_gsm.ko.xz:
kernel/fs/nfs/nfs.ko.xz: kernel/net/sunrpc/sunrpc.ko.xz
kernel/net/sunrpc/sunrpc.ko.xz:
kernel/sound/core/snd.ko.xz:
EOF

cat >"$R/etc/allow.d/00-managed.conf" <<'EOF'
# managed
path:kernel/drivers/edac/  path:kernel/drivers/cpufreq/ path:updates/
nf_* nfnetlink* x_tables xt_*   # netfilter
EOF
chmod 644 "$R/etc/allow.d/00-managed.conf"
loaded xfs ext4 jbd2

echo "--- first run on the old kernel"
echo 'FIRST_RUN_MIN_UPTIME=999999999' >"$R/etc/kmod-guard.conf"
out=$(KMOD_GUARD_KVER=6.0.0-old $KG generate 2>&1)
check "first run waits for uptime" "echo \"\$out\" | grep -qx result=skipped && [ ! -e '$OUT' ]"
rm -f "$R/etc/kmod-guard.conf"
KMOD_GUARD_KVER=6.0.0-old $KG generate --force >/dev/null 2>&1
check "loaded xfs kept" "! blocked xfs"
check "sctp blocked" "blocked sctp"
check "n_gsm blocked" "blocked n_gsm"
check "path:kernel/drivers/edac/ allowed" "! blocked amd64_edac"
check "libcrc32c kept (dependency of xfs in the other kernel)" "! blocked libcrc32c"
check "crc32c_generic kept (softdep alias)" "! blocked crc32c_generic"
check "learned set written" "grep -qx xfs '$R/state/learned'"

echo "--- running kernel 6.1.0-new"
KMOD_GUARD_KVER=6.1.0-new $KG generate >/dev/null 2>&1
check "dash in file name normalised, cpufreq path allowed" "! blocked powernow_k8"
check "glob nf_* keeps nf_conntrack_netlink" "! blocked nf_conntrack_netlink"
check "glob xt_* keeps xt_recent" "! blocked xt_recent"
check "path:updates/ keeps DKMS module" "! blocked snapapi26"
check "nfs blocked" "blocked nfs"
check "af_alg blocked" "blocked af_alg"
check "wireguard blocked" "blocked wireguard"
check "install line format" "grep -qx 'install sctp /usr/local/sbin/kmod-guard blocked sctp' '$OUT'"
out=$(KMOD_GUARD_KVER=6.1.0-new $KG generate 2>&1)
check "second run unchanged" "echo \"\$out\" | grep -qx result=unchanged"

echo "--- dependency closure"
echo 'nfs wireguard' >"$R/etc/allow.d/local.conf"
chmod 644 "$R/etc/allow.d/local.conf"
KMOD_GUARD_KVER=6.1.0-new $KG generate >/dev/null 2>&1
for m in nfs sunrpc lockd grace netfs wireguard libcurve25519_generic udp_tunnel; do
    check "closure keeps $m" "! blocked $m"
done
check "nfsv4 still blocked (not a dependency of nfs)" "blocked nfsv4"
check "tipc still blocked" "blocked tipc"

echo "--- learned set is sticky"
loaded xfs sctp
KMOD_GUARD_KVER=6.1.0-new $KG generate >/dev/null 2>&1
loaded xfs
KMOD_GUARD_KVER=6.1.0-new $KG generate >/dev/null 2>&1
check "sctp stays allowed after unload" "! blocked sctp"

echo "--- dry-run, --managed, --probe"
before=$(cksum <"$OUT")
out=$(KMOD_GUARD_KVER=6.1.0-new $KG generate --dry-run --managed 'nf_*' --probe 'amd64-edac tipc xfs' 2>&1)
check "probe reports only blocked modules" "echo \"\$out\" | grep -qx 'probe_blocked=amd64_edac tipc'"
out=$(KMOD_GUARD_KVER=6.1.0-new $KG generate --dry-run --probe '' 2>&1)
check "empty probe still prints the key" "echo \"\$out\" | grep -qx 'probe_blocked='"
check "dry-run writes nothing" "[ \"\$(cksum <'$OUT')\" = \"$before\" ]"
out=$(KMOD_GUARD_KVER=6.1.0-new $KG generate --dry-run --managed "$(cat "$here"/../examples/allow.d/*.conf)" 2>&1)
check "example allow files parse" "echo \"\$out\" | grep -qx result=dry-run"

echo "--- guards"
chmod 666 "$R/etc/allow.d/local.conf"
KMOD_GUARD_KVER=6.1.0-new $KG generate >/dev/null 2>&1
check "world-writable allow file refused (77)" "[ $? -eq 77 ]"
chmod 644 "$R/etc/allow.d/local.conf"
cp "$R/etc/allow.d/local.conf" "$R/local.bak"
echo 'bad;name' >>"$R/etc/allow.d/local.conf"
KMOD_GUARD_KVER=6.1.0-new $KG generate >/dev/null 2>&1
check "invalid entry refused (65)" "[ $? -eq 65 ]"
cat "$R/local.bak" >"$R/etc/allow.d/local.conf"
KMOD_GUARD_KVER=9.9.9 $KG generate >/dev/null 2>&1
check "missing modules.dep refused (66)" "[ $? -eq 66 ]"

echo "--- disable / enable / allow"
$KG disable >/dev/null 2>&1
check "disable removes the blocklist" "[ ! -e '$OUT' ]"
out=$(KMOD_GUARD_KVER=6.1.0-new $KG generate 2>&1)
check "generate honours disabled" "echo \"\$out\" | grep -qx result=disabled && [ ! -e '$OUT' ]"
KMOD_GUARD_KVER=6.1.0-new $KG enable >/dev/null 2>&1
check "enable regenerates" "[ -s '$OUT' ]"
KMOD_GUARD_KVER=6.1.0-new $KG allow tipc >/dev/null 2>&1
check "allow tipc unblocks it" "! blocked tipc"
check "allow rejects globs" "! KMOD_GUARD_KVER=6.1.0-new $KG allow 'x*' >/dev/null 2>&1"
check "version" "$KG version | grep -q '^kmod-guard [0-9]'"

if [ -r /proc/self/status ]; then
    echo "--- blocked handler (Linux)"
    $KG blocked testmod >/dev/null 2>&1
    check "blocked exits 0 by default" "[ $? -eq 0 ]"
    echo 'BLOCK_EXIT=1' >"$R/etc/kmod-guard.conf"
    $KG blocked testmod >/dev/null 2>&1
    check "blocked exits BLOCK_EXIT" "[ $? -eq 1 ]"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASSED"
else
    echo "SOME FAILED"
    exit 1
fi
