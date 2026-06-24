#!/usr/bin/env bash
set -euo pipefail

[ "$(uname -m)" = "aarch64" ] || { echo "arm64 only"; exit 1; }

sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y git curl unzip ripgrep fd-find make gcc
# ponytail: fd-find installs as fdfind on Debian; LazyVim expects fd
sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd

# Neovim
curl -L https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.tar.gz \
  | sudo tar -xz -C /usr/local --strip-components=1

# LazyVim starter config
[ -d ~/.config/nvim ] && mv ~/.config/nvim ~/.config/nvim.bak
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git

# Eza
curl -L https://github.com/eza-community/eza/releases/latest/download/eza_aarch64-unknown-linux-musl.tar.gz \
  | sudo tar -xz -C /usr/local/bin

# Yazi + ya shell wrapper
curl -L -o /tmp/yazi.zip \
  https://github.com/sxyazi/yazi/releases/latest/download/yazi-aarch64-unknown-linux-gnu.zip
sudo unzip -jo /tmp/yazi.zip "*/yazi" "*/ya" -d /usr/local/bin/
rm /tmp/yazi.zip

# Eza aliases
grep -qF 'alias ls=' ~/.bashrc || cat >> ~/.bashrc << 'EOF'

# eza
alias ls='eza'
alias ll='eza -l'
alias la='eza -la'
alias lt='eza --tree'
EOF

echo "Done. Run: nvim  (LazyVim will self-install on first open)"
