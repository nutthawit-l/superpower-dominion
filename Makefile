IMAGE_NAME = superpower-dominion
CONTAINER_NAME = superpower-dominion
PORT = 5173

build:
	distrobox assemble create

clean:
	distrobox assemble rm

rebuild: clean build

enter:
	distrobox enter $(CONTAINER_NAME)

enter-v:
	distrobox enter -v $(CONTAINER_NAME)

# The following commands must be executed within a Distrobox container

define VSCODE_SOURCE
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
endef
export VSCODE_SOURCE

install-vscode:
	sudo apt-get install -y wget gpg && \
	wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg && \
	sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg && \
	rm -f microsoft.gpg
	@echo "$$VSCODE_SOURCE" | sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null
	sudo apt install -y apt-transport-https && sudo apt update && sudo apt install -y code

install-claude:
	curl -fsSL https://claude.ai/install.sh | bash

install-go:
	[ ! -f "${HOME}/go.tar.gz" ] && curl -o "${HOME}/go.tar.gz" https://dl.google.com/go/go1.26.1.linux-amd64.tar.gz; sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "${HOME}/go.tar.gz"