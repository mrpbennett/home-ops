#!/bin/bash

# TO RUN: curl -fsSL https://raw.githubusercontent.com/mrpbennett/home-ops/main/servers/helix-install.sh | bash

# install helix if using homebrew within Linux Ubuntu
brew install helix

cat <<EOF >~/.config/helix/config.toml
theme = "boo_berry"

[editor]
line-number = "relative"
continue-comments = false
bufferline = "always"
color-modes = true


[editor.statusline]
left = ["mode", "spacer", "version-control", "spacer", "separator", "file-name", "file-modification-indicator"]
center = []
right = ["diagnostics", "selections", "position-percentage", "position", "file-encoding", "file-line-ending"]
separator = "·"
mode.normal = "NORMAL"
mode.insert = "INSERT"
mode.select = "SELECT"
diagnostics = ["warning", "error"]
workspace-diagnostics = ["warning", "error"]

[editor.lsp]
display-inlay-hints = true

[editor.cursor-shape]
insert = "bar"
normal = "block"
select = "underline"

[editor.file-picker]
hidden = false

[editor.auto-save]
focus-lost = true

[editor.indent-guides]
render = true
character = "-"
skip-levels = 1

[editor.inline-diagnostics]
cursor-line = "warning"
other-lines = "disable"

# KEY BINDINGS

# NORMAL MODE
[keys.normal.space]
e = [
  ':sh rm -f /tmp/unique-file',
  ':insert-output yazi "%{buffer_name}" --chooser-file=/tmp/unique-file',
  ':sh printf "\x1b[?1049h\x1b[?2004h" > /dev/tty',
  ':open %sh{cat /tmp/unique-file}',
  ':redraw',
]

# INSERT MODE
[keys.insert]
j = {j = "normal_mode"}
EOF

cat <<EOF >~/.config/helix/languages.toml
# Bash/Shell configuration
[[language]]
name = "bash"
scope = "source.bash"
file-types = ["sh", "bash"]
roots = []
comment-token = "#"
language-servers = ["bash-language-server"]
formatter = { command = "shfmt", args = ["-i", "2"] }
auto-format = true
EOF

# Install Yazi for better file navigation
sudo apt install ffmpeg 7zip jq poppler-utils fd-find ripgrep fzf zoxide imagemagick

# Install Yazi from source
sudo apt install build-essential make gcc curl
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env
git clone https://github.com/sxyazi/yazi.git /tmp/yazi
cd /tmp/yazi
cargo build --release --locked
sudo mv target/release/yazi target/release/ya /usr/local/bin/
cd ~
rm -rf /tmp/yazi
