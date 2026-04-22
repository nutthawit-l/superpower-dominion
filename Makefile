CONTAINER_NAME = superpower-dominion

build: link-ssh link-gitconfig
	distrobox assemble create

clean:
	distrobox assemble rm

rebuild: clean build

enter:
	distrobox enter $(CONTAINER_NAME)

enter-v:
	distrobox enter -v $(CONTAINER_NAME)

link-ssh:
	ln -svf ~/.ssh/ .

link-gitconfig:
	ln -svf ~/.gitconfig .

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

install-vscode-deb:
	sudo apt-get install -y wget gpg && \
	wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg && \
	sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg && \
	rm -f microsoft.gpg
	@echo "$$VSCODE_SOURCE" | sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null
	sudo apt install -y apt-transport-https && sudo apt update && sudo apt install -y code

install-vscode-rpm-repo:
	sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
	dnf check-update

install-vscode-rpm:
	sudo dnf install -y code

install-vscode:
	@if [ -f /etc/debian_version ]; then \
		echo "Detected Debian/Ubuntu – using apt method"; \
		$(MAKE) install-vscode-deb; \
	elif [ -f /etc/redhat-release ]; then \
		echo "Detected RHEL/Fedora – using dnf method"; \
		$(MAKE) install-vscode-rpm-repo; \
		$(MAKE) install-vscode-rpm; \
	else \
		echo "Unsupported OS – cannot install VSCode automatically"; \
		exit 1; \
	fi

install-gh:
	@if [ -f /etc/debian_version ]; then \
		echo "Detected Debian/Ubuntu – using apt method"; \
		$(MAKE) install-gh-deb; \
	elif [ -f /etc/fedora-release ] && grep -qi "fedora" /etc/fedora-release; then \
		echo "Detected Fedora – using dnf (official repo)"; \
		$(MAKE) install-gh-dnf5; \
	elif [ -f /etc/redhat-release ] && (grep -qi "red hat" /etc/redhat-release || grep -qi "centos" /etc/redhat-release); then \
		echo "Detected RHEL/CentOS – adding GitHub CLI repo first"; \
		$(MAKE) install-gh-dnf; \
	else \
		echo "Unsupported OS – cannot install GitHub CLI automatically"; \
		exit 1; \
	fi

install-gh-deb:
	(type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$$(mktemp) && wget -nv -O$$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $$out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y

install-gh-dnf:
	curl -fsSL -o - https://cli.github.com/packages/githubcli-archive-keyring.asc | gpg --show-keys
	sudo dnf install 'dnf-command(config-manager)'
	sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
	sudo dnf install gh --repo gh-cli

install-gh-dnf5:
	curl -fsSL -o - https://cli.github.com/packages/githubcli-archive-keyring.asc | gpg --show-keys
	sudo dnf install dnf5-plugins
	sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
	sudo dnf install gh --repo gh-cli

install-claude:
	curl -fsSL https://claude.ai/install.sh | bash

