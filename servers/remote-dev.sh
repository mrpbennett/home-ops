#!/bin/bash
set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() {
  echo -e "${RED}[ERROR]${NC} $1"
  exit 1
}

# ── config ────────────────────────────────────────────────────────────────────
DEV_USER="${1:-$USER}"
HOSTNAME_NEW="${2:-pi-dev}"
LAZYVIM_REPO="https://github.com/mrpbennett/lazyvim-config"
NVIM_CONFIG_DIR="/home/$DEV_USER/.config/nvim"

# ── checks ────────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run this script with sudo: sudo $0"
id "$DEV_USER" &>/dev/null || error "User '$DEV_USER' does not exist"

info "Setting up dev server for user: $DEV_USER"

# ── system ────────────────────────────────────────────────────────────────────
info "Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq

info "Installing base tools..."
apt-get install -y -qq \
  curl wget git \
  build-essential ca-certificates \
  gnupg lsb-release \
  ripgrep fd-find unzip

# ── hostname ──────────────────────────────────────────────────────────────────
info "Setting hostname to '$HOSTNAME_NEW'..."
hostnamectl set-hostname "$HOSTNAME_NEW"
sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME_NEW/" /etc/hosts

# ── SSH ───────────────────────────────────────────────────────────────────────
info "Enabling SSH..."
systemctl enable ssh
systemctl start ssh

info "Configuring SSH server keep-alive..."
cat >>/etc/ssh/sshd_config <<'EOF'

# Keep connections alive
ClientAliveInterval 60
ClientAliveCountMax 3
EOF
systemctl restart ssh

# ── Docker ────────────────────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
  warn "Docker already installed, skipping..."
else
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi

info "Adding $DEV_USER to docker group..."
usermod -aG docker "$DEV_USER"

info "Installing Docker Compose plugin..."
apt-get install -y -qq docker-compose-plugin

info "Enabling Docker service..."
systemctl enable docker
systemctl start docker

# ── mise + runtimes ───────────────────────────────────────────────────────────
info "Installing mise for $DEV_USER..."
sudo -u "$DEV_USER" bash -c '
  curl -fsSL https://mise.run | sh

  MISE="$HOME/.local/bin/mise"

  # Add mise to shell
  echo "eval \"\$($MISE activate bash)\"" >> ~/.bashrc

  # Install runtimes
  echo "Installing runtimes via mise..."
  $MISE use --global neovim@latest
  $MISE use --global python@latest
  $MISE use --global go@latest
  $MISE use --global node@lts
  $MISE use --global java@temurin-21
  $MISE use --global yazi@latest
  $MISE use --global lazygit@latest
  $MISE use --global lazydocker@latest
  $MISE use --global tmux@latest

  # Trust the global config
  $MISE trust ~/.config/mise/config.toml 2>/dev/null || true
'

# ── LazyVim config ────────────────────────────────────────────────────────────
info "Setting up LazyVim config for $DEV_USER..."

# Back up existing nvim config and state if present
USER_HOME="/home/$DEV_USER"

for dir in \
  "$USER_HOME/.config/nvim" \
  "$USER_HOME/.local/share/nvim" \
  "$USER_HOME/.local/state/nvim" \
  "$USER_HOME/.cache/nvim"; do
  if [ -d "$dir" ]; then
    warn "Backing up $dir → ${dir}.bak"
    mv "$dir" "${dir}.bak"
  fi
done

sudo -u "$DEV_USER" bash -c "
  mkdir -p /home/$DEV_USER/.config
  git clone $LAZYVIM_REPO $NVIM_CONFIG_DIR
"

info "LazyVim config cloned to $NVIM_CONFIG_DIR"

# ── tmux config + TPM ────────────────────────────────────────────────────────
info "Writing tmux config for $DEV_USER..."
sudo -u "$DEV_USER" bash -c "
  mkdir -p /home/$DEV_USER/.config/tmux

  cat > /home/$DEV_USER/.config/tmux/tmux.conf <<'TMUXEOF'
# =============================================================================
# General Settings
# =============================================================================
# Unbind default prefix (Ctrl+b)
unbind C-b
# Set Ctrl+s as new leader key
set -g prefix C-s
bind C-s send-prefix
# mouse support and terminal settings
set -g mouse on
set -g default-terminal \"tmux-256color\"
set -g set-clipboard on          # use system clipboard
set -g status-position top       # macOS / darwin style
set -g detach-on-destroy off     # don't exit from tmux when closing a session
setw -g mode-keys vi
# Enable Yazi Image Previewer
set -g allow-passthrough on
set -ga update-environment TERM
set -ga update-environment TERM_PROGRAM
# Reload config
unbind r
bind R source-file \"\$HOME/.config/tmux/tmux.conf\" \; display-message \"tmux.conf reloaded ☺️\"
# =============================================================================
# Window, Pane & Session Management
# =============================================================================
# Pane navigation using hjkl
bind-key h select-pane -L
bind-key j select-pane -D
bind-key k select-pane -U
bind-key l select-pane -R
bind -r -T prefix H resize-pane -L 20
bind -r -T prefix J resize-pane -D 20
bind -r -T prefix K resize-pane -U 7
bind -r -T prefix L resize-pane -R 7
bind x kill-pane
bind r command-prompt -I \"#W\" \"rename-window '%%'\"
# Pop a floating pane: Opens a large centered popup with your default shell
bind f display-popup -w 80% -h 80% -E \$SHELL
# LazyVim Window splits
bind | split-window -h -c \"#{pane_current_path}\"    # split window right
bind - split-window -v -c \"#{pane_current_path}\"    # split window down
unbind c
bind t new-window -c \"#{pane_current_path}\"         # new tab with <leader> t
# Window and pane numbering
set-window-option -g pane-base-index 1
set -g base-index 1                                 # Start windows at 1, not 0
setw -g pane-base-index 1                           # Start panes at 1, not 0
set -g renumber-windows on                          # renumber all windows when any window is closed
set -g automatic-rename off
set -g allow-rename off
bind s command-prompt -p \"Session name:\" \"new-session -s '%%'\"
bind S command-prompt -p \"Rename Session:\" \"rename-session '%%'\"
bind o choose-session                               # zellij session keybind
bind q kill-session
# =============================================================================
# List of plugins
# =============================================================================
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'catppuccin/tmux#v2.1.3'
set -g @plugin 'tmux-plugins/tmux-yank'
# =============================================================================
# Catppuccin theme options
# =============================================================================
set -g @catppuccin_flavor \"mocha\"
set -g @catppuccin_window_status_style \"basic\"
set -g @catppuccin_window_current_text \" #{window_name}\"
set -g @catppuccin_window_text \" #{window_name}\"
set -g @catppuccin_window_current_number_color \"#{?window_zoomed_flag,#{@thm_yellow},#{@thm_mauve}}\"
set -g @catppuccin_window_number_color \"#{?window_zoomed_flag,#{@thm_yellow},#{@thm_overlay_2}}\"
# ============================================================================
# STATUS LINE CONFIGURATION
# ============================================================================
set -g status-right-length 100
set -g status-left-length 100
set -g status-left \"#{E:@catppuccin_status_session}\"
set -g status-right \"#{E:@catppuccin_status_application}\"
# Initialize TMUX plugin manager
run '~/.tmux/plugins/tpm/tpm'
TMUXEOF

  # Install TPM
  git clone https://github.com/tmux-plugins/tpm /home/$DEV_USER/.tmux/plugins/tpm
"

info "TPM installed — plugins will auto-install on first tmux launch"

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
info "✅ Setup complete! Summary of what was installed:"
echo "   • Docker (+ Compose plugin)"
echo "   • mise with: neovim, python, go, node (LTS), java (temurin-21), yazi, lazygit, lazydocker, tmux, zellij"
echo "   • LazyVim config → $NVIM_CONFIG_DIR"
echo "   • tmux, ripgrep, fd, and base build tools"
echo ""
info "Next steps:"
echo "  1. Log out and back in to activate Docker group + mise in PATH"
echo "  2. Run 'nvim' — LazyVim will auto-install plugins on first launch"
echo "  3. Connect from VS Code: Remote-SSH → ${DEV_USER}@${HOSTNAME_NEW}.local"
echo "  4. Verify Docker: docker ps"
