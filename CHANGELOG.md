# Changelog

## 0.1.0 (unreleased)

First version.

- `kmod-guard generate` writes `/etc/modprobe.d/kmod-guard.conf`, blocking every module that is not loaded, not allowed and not a dependency of either.
- Keep-set: loaded modules, a sticky set of every module seen loaded, allow entries (name, glob, `path:` prefix), and their dependencies through `modules.dep`, `softdep` and aliases for every installed kernel.
- Blocked loads are logged to syslog with the trigger (`autoload`, `udev`, `explicit`) and caller.
- Guards: first-run uptime wait, refusal to block a loaded module, allow file ownership check, atomic writes.
- `allow`, `disable`, `enable`, `status`, `version` commands.
- initramfs-tools and dracut hooks, daily systemd timer, example allow lists.
