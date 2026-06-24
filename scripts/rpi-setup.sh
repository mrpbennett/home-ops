#!/usr/bin/env bash
set -euo pipefail

sudo apt-get install -y \
  git curl wget unzip build-essential

echo "==> Installing Docker"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg |
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update
sudo apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

echo "==> Adding $USER to docker group"
sudo usermod -aG docker "$USER"

echo "==> Enabling Docker on boot"
sudo systemctl enable --now docker

echo "==> Installing Homebrew"
NONINTERACTIVE=1 /bin/bash -c \
  "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add brew to current session and shell rc
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
eval "$("$BREW_PREFIX/bin/brew" shellenv)"

# Persist to .bashrc and .zshrc if present
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ]; then
    grep -qxF 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' "$rc" ||
      echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >>"$rc"
  fi
done

# ─────────────────────────────────────────────
#  Neovim (latest stable via brew)
# ─────────────────────────────────────────────
echo "==> Installing Neovim"
brew install neovim

# ─────────────────────────────────────────────
#  LazyVim
# ─────────────────────────────────────────────
echo "==> Backing up any existing Neovim config"
[ -d "$HOME/.config/nvim" ] && mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak.$(date +%s)"
[ -d "$HOME/.local/share/nvim" ] && mv "$HOME/.local/share/nvim" "$HOME/.local/share/nvim.bak.$(date +%s)"
[ -d "$HOME/.cache/nvim" ] && mv "$HOME/.cache/nvim" "$HOME/.cache/nvim.bak.$(date +%s)"

echo "==> Cloning LazyVim starter"
git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
rm -rf "$HOME/.config/nvim/.git"

## Installing EZA
brew install eza

# Eza aliases
grep -qF 'alias ls=' ~/.bashrc || cat >>~/.bashrc <<'EOF'

# eza
alias ls='eza -lh --group-directories-first --icons=auto'
alias lsa='ls -a'
alias lt='eza --tree --level=2 --long --icons --git'
alias lta='lt -a'
EOF

# Installing Yazi
brew install yazi
