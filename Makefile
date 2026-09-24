# kmod-guard installs to fixed paths: the generated install lines call
# /usr/local/sbin/kmod-guard. DESTDIR is for packaging.

SBIN     = $(DESTDIR)/usr/local/sbin
CONF     = $(DESTDIR)/etc/kmod-guard
STATE    = $(DESTDIR)/var/lib/kmod-guard
UNITS    = $(DESTDIR)/etc/systemd/system
ITOOLS   = $(DESTDIR)/etc/initramfs-tools/hooks
DRACUT   = $(DESTDIR)/usr/lib/dracut/modules.d

.PHONY: install uninstall test lint

install:
	install -D -m 0755 kmod-guard $(SBIN)/kmod-guard
	install -d -m 0755 $(CONF)/allow.d $(STATE)
	test -e $(CONF)/allow.d/00-managed.conf || \
		install -m 0644 examples/allow.d/00-managed.conf $(CONF)/allow.d/00-managed.conf
	if [ -d $(ITOOLS) ]; then install -m 0755 hooks/initramfs-tools-hook $(ITOOLS)/zz-kmod-guard; fi
	if [ -d $(DRACUT) ]; then install -D -m 0755 hooks/dracut-module-setup.sh $(DRACUT)/99kmod-guard/module-setup.sh; fi
	install -D -m 0644 systemd/kmod-guard.service $(UNITS)/kmod-guard.service
	install -D -m 0644 systemd/kmod-guard.timer $(UNITS)/kmod-guard.timer
	@echo
	@echo "Installed. Review /etc/kmod-guard/allow.d/, then:"
	@echo "  kmod-guard generate --dry-run"
	@echo "  kmod-guard generate"
	@echo "  systemctl daemon-reload && systemctl enable --now kmod-guard.timer"

# The blocklist goes first: its install lines call the script
uninstall:
	rm -f $(DESTDIR)/etc/modprobe.d/kmod-guard.conf
	-systemctl disable --now kmod-guard.timer 2>/dev/null
	rm -f $(UNITS)/kmod-guard.service $(UNITS)/kmod-guard.timer
	rm -f $(ITOOLS)/zz-kmod-guard
	rm -f $(DRACUT)/99kmod-guard/module-setup.sh
	-rmdir $(DRACUT)/99kmod-guard 2>/dev/null
	rm -f $(SBIN)/kmod-guard
	@echo "Kept /etc/kmod-guard and /var/lib/kmod-guard."

test:
	sh tests/run.sh

lint:
	shellcheck -s sh kmod-guard hooks/initramfs-tools-hook tests/run.sh
	shellcheck -s bash hooks/dracut-module-setup.sh
