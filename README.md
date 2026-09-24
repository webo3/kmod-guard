# kmod-guard

Block on-demand loading of Linux kernel modules a host doesn't use.

Many kernel privilege-escalation bugs live in modules that an unprivileged user can get the kernel to load on demand: an unusual socket family (`sctp`, `tipc`, `vsock`), a traffic-control action, a netfilter expression from inside a user namespace, a filesystem through `mount(2)`, an AF_ALG crypto algorithm, a tty line discipline (`n_gsm`). The usual fix is one `install <module> /bin/false` line per CVE, after the fact. kmod-guard does it for every module at once: anything not in use and not allowed gets an `install` line in `/etc/modprobe.d/kmod-guard.conf`.

- No reboot and nothing is unloaded. Removing the file reverts it instantly.
- Loaded modules are never blocked.
- Hardware drivers stay loadable (by default). The list targets what unprivileged syscalls can reach.
- A single POSIX shell script with no dependencies beyond coreutils, diffutils, awk and kmod.

## How it works

```
keep  = modules loaded now                      (/proc/modules)
      + every module ever seen loaded on this host (/var/lib/kmod-guard/learned)
      + allow entries                          (/etc/kmod-guard/allow.d/*.conf)
      + their dependencies                     (modules.dep, softdep, aliases) in every installed kernel
block = modules of the running kernel - keep
```

Each blocked module gets `install <module> /usr/local/sbin/kmod-guard blocked <module>`. When something tries to load it, modprobe runs that command instead. It logs the attempt to syslog and the module stays unloaded.

The keep-set only grows, so running `generate` again (by hand, from a timer or from configuration management) can only block modules that are new to the running kernel.

## Install

```sh
git clone https://github.com/webo3/kmod-guard.git
cd kmod-guard
sudo make install
```

This installs the script to `/usr/local/sbin/kmod-guard`. That path is fixed because the generated install lines call it. It also installs:
- the default allow list in `/etc/kmod-guard/allow.d/00-managed.conf`, if that file doesn't exist yet;
- the initramfs hook for initramfs-tools or dracut;
- a systemd service and timer, which are not enabled.

Then:

```sh
sudo kmod-guard generate --dry-run     # see what would be blocked
sudo kmod-guard generate
sudo systemctl daemon-reload
sudo systemctl enable --now kmod-guard.timer
```

Run the first `generate` once the host has been up long enough for its services to load their modules. It refuses during the first 30 minutes of uptime unless you pass `--force`.

## Allow lists

`/etc/kmod-guard/allow.d/*.conf` files must be owned by root and not be group- or world-writable. Entries are whitespace-separated, and `#` starts a comment:

| Entry | Matches |
| --- | --- |
| `xfs` | the module `xfs` (`-` and `_` are equivalent) |
| `nft_*`, `ip_set*` | a glob on the module name (`*`, `?`) |
| `path:kernel/drivers/edac/` | every module whose path under `/lib/modules/<kver>/` starts with this |

You don't need to list dependencies: allowing `nfs` also keeps `sunrpc`, `lockd`, `grace` and the rest.

- `00-managed.conf` is meant for configuration management.
- `local.conf` receives `kmod-guard allow` additions made on the host.
- Any other `*.conf` file is read as well.

[`examples/allow.d/00-managed.conf`](examples/allow.d/00-managed.conf) is the default list for servers. It allows:
- hardware and platform drivers by path: ACPI, storage, NICs, EDAC, cpufreq, hwmon, IPMI, virtio, Hyper-V, Xen, watchdogs, device-mapper;
- out-of-tree modules (`extra/`, `updates/`, `weak-updates/`);
- common filesystems;
- `ss` socket diagnostics;
- the netfilter toolkit (iptables, nftables, ipset), because firewalls and fail2ban-style tools load those the first time a rule uses them.

These stay blocked unless the host already uses them: uncommon socket families, tc schedulers, classifiers and actions, virtual network devices (vxlan, geneve, macsec, …), AF_ALG, network and legacy filesystems (cifs, nfs, ceph, 9p, hfs, …), tty line disciplines, RDMA, sound and media.

More examples: [Proxmox VE](examples/allow.d/proxmox-ve.conf), [Docker Swarm](examples/allow.d/docker-swarm.conf), [WireGuard](examples/allow.d/wireguard.conf).

## Usage

```
kmod-guard generate [--dry-run] [--force] [--quiet] [--managed "<entries>"] [--probe "<modules>"]
kmod-guard allow <module>...    allow on this host now (written to allow.d/local.conf)
kmod-guard disable              remove the blocklist; stays off until `kmod-guard enable`
kmod-guard enable
kmod-guard status               state, local allows, recent blocks
kmod-guard version
```

`generate` prints a `key=value` summary (counts, newly blocked and newly allowed modules), ending with `result=changed|unchanged|skipped|disabled`. With `--dry-run` it ends with `result=dry-run` and `would_change=yes|no` instead. Two options serve configuration management:
- `--managed` previews a new managed list without writing it.
- `--probe` answers "which of these modules would be blocked here?".

To load a blocked module once, as root: `modprobe --ignore-install <module>`.

## Logs

```
$ journalctl -t kmod-guard
kmod-guard: blocked module=sctp trigger=explicit parent=bash[4121] uid=0 loginuid=1000 cmd=-bash
kmod-guard: blocked module=tipc trigger=autoload parent=kthreadd[2] uid=0 loginuid=unset cmd=
```

`trigger` is one of:
- `explicit`: a process ran modprobe.
- `udev`: a device matched.
- `autoload`: the kernel requested the module itself, e.g. `socket(AF_TIPC, …)`. The request comes through a kernel thread, so the process that caused it can't be identified from the modprobe call.

`BLOCK_EXIT` in `/etc/kmod-guard/kmod-guard.conf` sets what a blocked load returns:
- `0` (the default): `modprobe` returns success without loading anything, so a service running `modprobe foo` in `ExecStartPre` keeps going.
- `1`: it fails loudly.

## Safety

- Loaded modules are never blocked. `generate` refuses to write a list that would block one (exit 70) or an empty list.
- The first run waits for `FIRST_RUN_MIN_UPTIME` (default 1800 s) so the snapshot isn't taken mid-boot.
- Dependencies are resolved for every installed kernel. A new kernel whose modules depend on something new still gets it.
- The initramfs hooks strip the blocklist from boot images, so a new kernel can always load its root-disk drivers.
- Writes are atomic, and an unchanged file isn't rewritten.

Exit codes: 64 usage, 65 invalid allow entry, 66 missing `modules.dep` or `/proc/modules`, 70 refused blocklist, 77 allow file with unsafe ownership or permissions.

## Limits

- Root can still load anything with `insmod` or `modprobe --ignore-install`. This limits what unprivileged users can pull into the kernel. It is not a root boundary; see `kernel.modules_disabled` for that.
- Code built into the kernel (`=y`) is not affected.
- Allowing netfilter and tc keeps what unprivileged user namespaces can reach through them. Restricting user namespaces (`kernel.unprivileged_userns_clone=0`, `user.max_user_namespaces`, or AppArmor on Ubuntu 24.04) complements this.

## Uninstall

```sh
sudo make uninstall      # keeps /etc/kmod-guard and /var/lib/kmod-guard
```

## Development

```sh
make test     # fixture tests: fake kernels and /proc/modules in a temp dir
make lint     # shellcheck
SH=dash sh tests/run.sh
```

CI runs the tests on Debian, Ubuntu, AlmaLinux 8, Rocky Linux 9 and Alpine to cover dash, bash, busybox, mawk and gawk.

## Credits

The idea comes from [modulejail](https://github.com/jnuyens/modulejail) by Jasper Nuyens. kmod-guard is a separate implementation that adds:
- dependency resolution;
- the sticky learned set;
- allow entries by glob and path.
