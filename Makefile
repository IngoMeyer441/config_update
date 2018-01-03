PREFIX=/usr/local

default:
	@echo "Please run \`make install\` explicitly to install \`config_update.sh\`."
	@echo "You can override \`PREFIX\` to specify an installation prefix:"
	@echo
	@echo "    make PREFIX=/opt/config_update install"
	@echo
	@echo "which install to \`/opt/config_update/bin/\`."

install:
	cp "config_update.sh" "$(PREFIX)/bin/"

.PRECIOUS: %.o
.PHONY: default install
