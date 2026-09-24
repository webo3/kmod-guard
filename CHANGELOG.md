# Changelog

## 0.1.0 (unreleased)

First version.

- `kmod-guard generate` writes `/etc/modprobe.d/kmod-guard.conf`, blocking every module that is not loaded, not allowed and not a dependency of either.
- Keep-set: loaded modules, a sticky set of every module seen loaded, allow entries (name, glob, `path:` prefix), and their dependencies through `modules.dep`, `softdep` and aliases for every installed kernel.
- Blocked loads are logged to syslog with the trigger (`autoload`, `udev`, `explicit`) and caller.
- Guards: first-run uptime wait, refusal to block a loaded module, allow file ownership check, atomic writes.
- `allow`, `deny`, `disable`, `enable`, `status`, `version` commands.
- Deny lists: `/etc/kmod-guard/deny.d/*.conf` blocks a module even when an allow entry, the learned set or a dependency would keep it. Loaded modules are still never blocked; their deny applies once unloaded.
- `kmod-guard deny <module>` writes `deny.d/local.conf`. It refuses a loaded module (exit 75, unload it with `rmmod` first), and names that aren't modules of the running kernel or are built in.
- `generate --managed-deny` previews a managed deny list; the summary gains `denied`, `denied_list` and `deny_loaded_list`.
- `kmod-guard allow` warns when a deny entry still blocks the module.
- initramfs-tools and dracut hooks, daily systemd timer, example allow lists.
