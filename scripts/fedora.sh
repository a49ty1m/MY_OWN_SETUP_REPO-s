#!/usr/bin/env bash

# Fail on errors, unset variables, and failed pipeline components.
set -Eeuo pipefail
umask 022

# Ensure the script is run with sudo/root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo:"
  echo "sudo bash \$0"
  exit 1
fi

# Determine the non-root target user and their home directory
if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = root ]; then
  echo "Run this script with sudo from the account you want to configure: sudo bash $0" >&2
  exit 1
fi
TARGET_USER="$SUDO_USER"
USER_ENTRY=$(getent passwd "$TARGET_USER") || {
  echo "Could not find the invoking account '$TARGET_USER'." >&2
  exit 1
}
TARGET_HOME=$(cut -d: -f6 <<< "$USER_ENTRY")
if [ -z "$TARGET_HOME" ] || [ "$TARGET_HOME" = /root ]; then
  echo "Refusing to configure an invalid home directory for '$TARGET_USER'." >&2
  exit 1
fi

if ! grep -qi '^ID=.*fedora' /etc/os-release; then
  echo "This script supports Fedora only." >&2
  exit 1
fi

CURRENT_STEP="Pre-flight checks"
STEP_TOTAL=0
STEP_PASS=0
STEP_SKIP=0
WARNINGS=0
CANCELLED=0

# Optional setup sections (the system update always runs).
INSTALL_MULTIMEDIA=true
INSTALL_NVIDIA=true
INSTALL_ZSH=true
INSTALL_FRESH=true
INSTALL_BRAVE=true
INSTALL_VSCODE=true
INSTALL_GHOSTTY=true
INSTALL_BTOP=true
INSTALL_CLI_UTILS=true
INSTALL_VLC=true
INSTALL_DISCORD=true
INSTALL_OBSIDIAN=true
INSTALL_KVM=true
INSTALL_GRUB_THEME=true
INSTALL_DESKTOP_THEMES=true
INSTALL_ANYDESK=true

# ── Per-step configuration ────────────────────────────────────────────────────
# Name of the KVM guest to attach the virtiofs shared folder to (Step 13a).
KVM_GUEST_NAME="Kali-Linux"

FEATURE_FLAGS="INSTALL_MULTIMEDIA INSTALL_NVIDIA INSTALL_ZSH INSTALL_FRESH INSTALL_BRAVE INSTALL_VSCODE INSTALL_GHOSTTY INSTALL_BTOP INSTALL_CLI_UTILS INSTALL_VLC INSTALL_DISCORD INSTALL_OBSIDIAN INSTALL_KVM INSTALL_GRUB_THEME INSTALL_DESKTOP_THEMES INSTALL_ANYDESK"

show_menu() {
  local choice name
  # Use /dev/tty for interactive I/O so it works even when stdout is redirected
  exec 3>/dev/tty 4</dev/tty
  while true; do
    clear >&3
    printf "===============================================\n" >&3
    printf "        Fedora Workstation Setup Options       \n" >&3
    printf "===============================================\n" >&3
    printf " 1) [%-3s] Multimedia codecs       9) [%-3s] CLI utilities\n"    \
      "$([[ $INSTALL_MULTIMEDIA == true ]] && echo ON || echo OFF)"          \
      "$([[ $INSTALL_CLI_UTILS  == true ]] && echo ON || echo OFF)"  >&3
    printf " 2) [%-3s] Nvidia drivers         10) [%-3s] VLC\n"              \
      "$([[ $INSTALL_NVIDIA  == true ]] && echo ON || echo OFF)"             \
      "$([[ $INSTALL_VLC     == true ]] && echo ON || echo OFF)"     >&3
    printf " 3) [%-3s] Zsh and plugins        11) [%-3s] Discord\n"          \
      "$([[ $INSTALL_ZSH     == true ]] && echo ON || echo OFF)"             \
      "$([[ $INSTALL_DISCORD == true ]] && echo ON || echo OFF)"     >&3
    printf " 4) [%-3s] Fresh shell manager    12) [%-3s] Obsidian\n"         \
      "$([[ $INSTALL_FRESH    == true ]] && echo ON || echo OFF)"            \
      "$([[ $INSTALL_OBSIDIAN == true ]] && echo ON || echo OFF)"    >&3
    printf " 5) [%-3s] Brave browsers         13) [%-3s] KVM and shared folder\n" \
      "$([[ $INSTALL_BRAVE == true ]] && echo ON || echo OFF)"               \
      "$([[ $INSTALL_KVM   == true ]] && echo ON || echo OFF)"       >&3
    printf " 6) [%-3s] VS Code                14) [%-3s] GRUB theme\n"       \
      "$([[ $INSTALL_VSCODE     == true ]] && echo ON || echo OFF)"          \
      "$([[ $INSTALL_GRUB_THEME == true ]] && echo ON || echo OFF)"  >&3
    printf " 7) [%-3s] Ghostty                15) [%-3s] Desktop themes\n"   \
      "$([[ $INSTALL_GHOSTTY        == true ]] && echo ON || echo OFF)"      \
      "$([[ $INSTALL_DESKTOP_THEMES == true ]] && echo ON || echo OFF)" >&3
    printf " 8) [%-3s] btop                  16) [%-3s] AnyDesk\n"           \
      "$([[ $INSTALL_BTOP    == true ]] && echo ON || echo OFF)"             \
      "$([[ $INSTALL_ANYDESK == true ]] && echo ON || echo OFF)"     >&3
    printf "\n" >&3
    printf " r) Run setup   a) All on   n) All off   q) Quit\n" >&3
    printf "===============================================\n" >&3
    read -rp "Choose [1-16/r/a/n/q]: " choice <&4
    case "$choice" in
      [1-9]|1[0-6])
        case "$choice" in
          1)  name=INSTALL_MULTIMEDIA ;;  2)  name=INSTALL_NVIDIA ;;
          3)  name=INSTALL_ZSH ;;         4)  name=INSTALL_FRESH ;;
          5)  name=INSTALL_BRAVE ;;       6)  name=INSTALL_VSCODE ;;
          7)  name=INSTALL_GHOSTTY ;;     8)  name=INSTALL_BTOP ;;
          9)  name=INSTALL_CLI_UTILS ;;   10) name=INSTALL_VLC ;;
          11) name=INSTALL_DISCORD ;;     12) name=INSTALL_OBSIDIAN ;;
          13) name=INSTALL_KVM ;;         14) name=INSTALL_GRUB_THEME ;;
          15) name=INSTALL_DESKTOP_THEMES ;; 16) name=INSTALL_ANYDESK ;;
        esac
        if [ "${!name}" = true ]; then printf -v "$name" false; else printf -v "$name" true; fi
        ;;
      a|A) for name in $FEATURE_FLAGS; do printf -v "$name" true;  done ;;
      n|N) for name in $FEATURE_FLAGS; do printf -v "$name" false; done ;;
      r|R) exec 3>&- 4<&-; return 0 ;;
      q|Q) exec 3>&- 4<&-; CANCELLED=1; exit 0 ;;
      *)   printf "  Invalid choice '%s' — use a number, r, a, n, or q.\n" "$choice" >&3 ;;
    esac
  done
}

# Show the interactive menu BEFORE redirecting stdout/stderr to the log file,
# so that the menu is always visible on the terminal regardless of redirection.
if [ -t 0 ] && [ -t 1 ]; then
  show_menu
fi

LOG_FILE="/var/log/fedora-workstation-setup.log"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fedora-setup.XXXXXX")
chmod 700 "$TMP_DIR"   # Keep root-owned; user-writable dirs risk symlink attacks
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== System Setup & Catppuccin GRUB Theme Installer for Fedora ==="
echo "Target User: $TARGET_USER"
echo "Target Home: $TARGET_HOME"
echo "============================================="

start_step() {
  CURRENT_STEP="$1"
  STEP_TOTAL=$((STEP_TOTAL + 1))
  echo
  echo ">>> [STEP $STEP_TOTAL] $CURRENT_STEP"
}

log_warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "WARNING: $*" >&2
}
skip_step() {
  STEP_SKIP=$((STEP_SKIP + 1))
  echo "[SKIP] $1"
}

open_in_new_tab() {
  local title="${1:-Tool Setup}"
  local command_to_run="$2"

  echo "  [→] Spawning interactive setup for '$title' in a new terminal tab..."

  local uid
  uid=$(id -u "$TARGET_USER")
  local runtime_dir="/run/user/$uid"

  # If not in a graphical session, inform the user and skip opening GUI tab
  if [ ! -d "$runtime_dir" ] || { [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; }; then
    echo "  [INFO] No active GUI session detected. Run manually when ready: $command_to_run"
    return 0
  fi

  # Create a wrapper script that runs the command and keeps the tab open when finished
  local wrapper
  wrapper=$(mktemp /tmp/setup-tab-XXXXXX.sh)
  cat <<EOF > "$wrapper"
#!/usr/bin/env bash
printf "\033[1;36m======================================================================\033[0m\n"
printf "\033[1;33m       $title - Post-Installation Setup\033[0m\n"
printf "\033[1;36m======================================================================\033[0m\n\n"
$command_to_run
printf "\n\033[1;32m[✔] Setup finished.\033[0m Press \033[1;37mEnter\033[0m to close this tab..."
read -r
rm -f "\$0"
EOF
  chmod +x "$wrapper"
  chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$wrapper"

  local env_args=(
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    DISPLAY="${DISPLAY:-:0}"
    XDG_RUNTIME_DIR="$runtime_dir"
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
  )

  if command -v ghostty &>/dev/null; then
    sudo -u "$TARGET_USER" env "${env_args[@]}" ghostty -e "$wrapper" &
  elif command -v konsole &>/dev/null; then
    sudo -u "$TARGET_USER" env "${env_args[@]}" konsole --new-tab -e "$wrapper" &
  elif command -v ptyxis &>/dev/null; then
    sudo -u "$TARGET_USER" env "${env_args[@]}" ptyxis --new-window -- "$wrapper" &
  elif command -v gnome-terminal &>/dev/null; then
    sudo -u "$TARGET_USER" env "${env_args[@]}" gnome-terminal --tab -- "$wrapper" &
  else
    echo "  [INFO] Run manually: $command_to_run"
  fi
}
on_error() {
  local status=$? line=${1:-unknown}
  trap - ERR
  echo "ERROR: '$CURRENT_STEP' failed at line $line (exit $status). See $LOG_FILE." >&2
  exit "$status"
}
finish() {
  local status=$?
  trap - EXIT
  rm -rf -- "$TMP_DIR"
  echo
  echo "--- SETUP SUMMARY ---"
  echo "Steps started: $STEP_TOTAL | Completed: $STEP_PASS | Skipped: $STEP_SKIP | Warnings: $WARNINGS"
  if [ "$CANCELLED" -eq 1 ]; then
    echo "Status: CANCELLED"
  elif [ "$status" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "Status: SUCCESS"
  elif [ "$status" -eq 0 ]; then
    echo "Status: COMPLETED WITH WARNINGS"
  else
    echo "Status: FAILED (exit $status)"
  fi
}
trap 'on_error "$LINENO"' ERR
trap finish EXIT

# ----------------------------------------------------------------------
# 0. Ensure system is fully up-to-date before installing anything
# ----------------------------------------------------------------------
start_step "Update system packages"

# Upgrade all packages to the latest versions.
# The -y flag auto-confirms; this runs early so subsequent steps use the
# newest library versions.
#
# Note: on Fedora this may pull in newer kernel, glibc, etc.;
# a reboot may be required.
dnf upgrade -y --refresh
STEP_PASS=$((STEP_PASS + 1))

echo "============================================="

# ----------------------------------------------------------------------
# 1. Enable RPM Fusion Repositories & Install Multimedia Codecs
# ----------------------------------------------------------------------
start_step "Enable RPM Fusion and install multimedia codecs"
if [ "$INSTALL_MULTIMEDIA" = true ]; then
dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
  || log_warn "RPM Fusion repository installation failed; multimedia setup may fail."

# Enable Fedora Cisco openh264 repo (DNF5 syntax)
dnf config-manager setopt fedora-cisco-openh264.enabled=1 || log_warn "Could not enable the Cisco OpenH264 repository."

# Swap to full FFmpeg (required for H.264/H.265 decoders)
dnf swap -y ffmpeg-free ffmpeg --allowerasing || log_warn "Could not replace ffmpeg-free with the full FFmpeg package."

# Install multimedia complements & GStreamer plugins
dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin || log_warn "Multimedia group installation failed."

# Install OpenH264 support
dnf install -y gstreamer1-plugin-openh264 mozilla-openh264 || log_warn "OpenH264 packages could not be installed."

# Update multimedia packages
dnf upgrade -y @multimedia || log_warn "Multimedia package update failed."
echo "RPM Fusion repositories enabled and multimedia codecs installed."
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Multimedia codecs"
fi
echo "============================================="

# ----------------------------------------------------------------------
# 2. Install Nvidia Drivers & 32-bit Libraries
# ----------------------------------------------------------------------
start_step "Install Nvidia drivers and 32-bit libraries"
if [ "$INSTALL_NVIDIA" = true ]; then
# Enable the nvidia driver repo (DNF5 syntax)
dnf config-manager setopt rpmfusion-nonfree-nvidia-driver.enabled=1 || log_warn "Could not enable the RPM Fusion Nvidia repository."
dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs.i686 egl-wayland || log_warn "Nvidia packages could not be installed; check hardware and repository setup."
echo "Nvidia drivers installation complete."
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Nvidia drivers"
fi
echo "============================================="

# ----------------------------------------------------------------------
# 3. Install Zsh and Extensions
# ----------------------------------------------------------------------
start_step "Install and configure Zsh"
if [ "$INSTALL_ZSH" = true ]; then
dnf install -y zsh git curl fzf eza zoxide fontconfig perl

# Install Nerd Fonts (MesloLGS NF for icons support in prompt & eza)
echo "Installing MesloLGS NF Nerd Fonts for $TARGET_USER..."
FONTS_DIR="$TARGET_HOME/.local/share/fonts"
sudo -u "$TARGET_USER" mkdir -p "$FONTS_DIR"
MESLO_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
for font_file in "MesloLGS NF Regular.ttf" "MesloLGS NF Bold.ttf" "MesloLGS NF Italic.ttf" "MesloLGS NF Bold Italic.ttf"; do
  if [ ! -f "$FONTS_DIR/$font_file" ]; then
    echo "Downloading font: $font_file..."
    curl -fsSL -o "$FONTS_DIR/$font_file" "$MESLO_URL/${font_file// /%20}" || log_warn "Could not download $font_file"
    chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$FONTS_DIR/$font_file" 2>/dev/null || true
  fi
done
fc-cache -f "$FONTS_DIR"                                         # system cache (root)
sudo -u "$TARGET_USER" fc-cache -f "$FONTS_DIR" || log_warn "Could not refresh user font cache."

# Install Oh My Zsh if not already present
OMZ_DIR="$TARGET_HOME/.oh-my-zsh"
if [ ! -d "$OMZ_DIR" ]; then
  echo "Installing Oh My Zsh for $TARGET_USER..."
  curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
    | sudo -u "$TARGET_USER" env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -s -- --unattended
else
  echo "Oh My Zsh is already installed for $TARGET_USER."
fi

# Install Powerlevel10k theme
THEMES_DIR="$OMZ_DIR/custom/themes"
mkdir -p "$THEMES_DIR"
chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$THEMES_DIR"

P10K_DIR="$THEMES_DIR/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
  echo "Installing Powerlevel10k theme..."
  sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

# Install plugins (autosuggestions, syntax-highlighting, fzf-tab, zsh-completions)
PLUGINS_DIR="$OMZ_DIR/custom/plugins"
mkdir -p "$PLUGINS_DIR"
chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$PLUGINS_DIR"

SUGGESTIONS_DIR="$PLUGINS_DIR/zsh-autosuggestions"
if [ ! -d "$SUGGESTIONS_DIR" ]; then
  echo "Installing zsh-autosuggestions..."
  sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$SUGGESTIONS_DIR"
fi

HIGHLIGHT_DIR="$PLUGINS_DIR/zsh-syntax-highlighting"
if [ ! -d "$HIGHLIGHT_DIR" ]; then
  echo "Installing zsh-syntax-highlighting..."
  sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$HIGHLIGHT_DIR"
fi

FZF_TAB_DIR="$PLUGINS_DIR/fzf-tab"
if [ ! -d "$FZF_TAB_DIR" ]; then
  echo "Installing fzf-tab..."
  sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/Aloxaf/fzf-tab "$FZF_TAB_DIR"
fi

COMPLETIONS_DIR="$PLUGINS_DIR/zsh-completions"
if [ ! -d "$COMPLETIONS_DIR" ]; then
  echo "Installing zsh-completions..."
  sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/zsh-users/zsh-completions "$COMPLETIONS_DIR"
fi

# Configure custom icons, eza aliases, zoxide and fzf-tab previews
ICONS_ZSH="$OMZ_DIR/custom/icons-and-tools.zsh"
cat <<'EOF' > "$ICONS_ZSH"
# Icons & Modern CLI Aliases (eza)
if command -v eza &>/dev/null; then
  alias ls='eza --icons=auto'
  alias l='eza -lh --icons=auto'
  alias ll='eza -lha --icons=auto --git'
  alias la='eza -a --icons=auto'
  alias lt='eza --tree --level=2 --icons=auto'
fi

# Zoxide (smart cd directory jumper)
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi

# fzf-tab configuration: colors, previews & icons
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --color=always --icons $realpath'
zstyle ':fzf-tab:*' switch-group '<' '>'
EOF
chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$ICONS_ZSH"

# Configure .zshrc (create if missing — OMZ may not have run yet on re-runs)
ZSHRC="$TARGET_HOME/.zshrc"
[ -f "$ZSHRC" ] || sudo -u "$TARGET_USER" touch "$ZSHRC"

echo "Configuring $ZSHRC..."

# Powerlevel10k instant prompt at the top
if ! grep -q "p10k-instant-prompt" "$ZSHRC"; then
  TMP_ZSHRC=$(mktemp)
  # Write p10k header first
  cat <<'EOF' > "$TMP_ZSHRC"
# Enable Powerlevel10k instant prompt (disabled to allow fastfetch on startup)
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#   source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# fi

EOF
  cat "$ZSHRC" >> "$TMP_ZSHRC"
  # Use install(1) so the file is atomically placed with correct ownership
  install -m 644 -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" "$TMP_ZSHRC" "$ZSHRC"
  rm -f "$TMP_ZSHRC"
fi

# Set ZSH_THEME to powerlevel10k
if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC"
fi

# Update plugins list
perl -0777 -i -pe 's/plugins=\([^)]*\)/plugins=(\n  git\n  sudo\n  extract\n  colored-man-pages\n  zsh-completions\n  fzf-tab\n  zsh-autosuggestions\n  zsh-syntax-highlighting\n)/s' "$ZSHRC"

# Source p10k.zsh at bottom if not already present
if ! grep -q 'p10k.zsh' "$ZSHRC"; then
  cat <<'EOF' >> "$ZSHRC"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
fi

chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$ZSHRC"
echo "Updated $ZSHRC with Powerlevel10k, plugins, and instant prompt."

# Configure Ghostty font if Ghostty config exists
GHOSTTY_CONF="$TARGET_HOME/.config/ghostty/config"
if [ -f "$GHOSTTY_CONF" ]; then
  if ! grep -q "^font-family =" "$GHOSTTY_CONF"; then
    echo 'font-family = "MesloLGS NF"' >> "$GHOSTTY_CONF"
    echo 'font-size = 12' >> "$GHOSTTY_CONF"
    chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$GHOSTTY_CONF"
  fi
fi

# Change default shell to Zsh
CURRENT_SHELL=$(getent passwd "$TARGET_USER" | cut -d: -f7)
if [ "$CURRENT_SHELL" != "$(which zsh)" ]; then
  echo "Changing default shell to Zsh for $TARGET_USER..."
  chsh -s "$(which zsh)" "$TARGET_USER"
else
  echo "Default shell is already Zsh."
fi

# Launch Powerlevel10k interactive configuration wizard in a new tab
open_in_new_tab "Powerlevel10k Prompt Wizard" "zsh -ic 'p10k configure'"

echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Zsh and plugins"
fi

# ----------------------------------------------------------------------
# 4. Install Fresh Shell Configuration Manager
# ----------------------------------------------------------------------
start_step "Install Fresh shell configuration manager"
if [ "$INSTALL_FRESH" = true ]; then
# Ensure Perl module File::Find is installed (required by Fresh)
dnf install -y perl-File-Find
if [ ! -d "$TARGET_HOME/.fresh" ]; then
  # Download to a temp file rather than piping curl directly to bash (S2)
  FRESH_INSTALLER="$TMP_DIR/fresh-install.sh"
  if curl -fsSL -o "$FRESH_INSTALLER" https://get.freshshell.com && [ -s "$FRESH_INSTALLER" ]; then
    chmod +x "$FRESH_INSTALLER"
    sudo -u "$TARGET_USER" bash "$FRESH_INSTALLER" || log_warn "Fresh installation failed; continuing without it."
  else
    log_warn "Could not download Fresh installer; skipping."
  fi
  rm -f "$FRESH_INSTALLER"
else
  echo "Fresh is already installed."
fi
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Fresh shell manager"
fi

# ----------------------------------------------------------------------
# 5. Install Brave & Brave Nightly Browsers
# ----------------------------------------------------------------------
start_step "Install Brave browsers"
if [ "$INSTALL_BRAVE" = true ]; then

# Ensure dnf-plugins-core is available
dnf install -y dnf-plugins-core

# Back up existing Brave repo files before replacing them.
for repo_file in /etc/yum.repos.d/brave-browser.repo /etc/yum.repos.d/brave-browser-nightly.repo; do
  if [ -e "$repo_file" ]; then
    cp -a "$repo_file" "$repo_file.backup.$(date +%Y%m%d%H%M%S%N)"
  fi
done

# Write correct Brave Browser repo file (with $basearch in the URL)
cat <<'EOF' > /etc/yum.repos.d/brave-browser.repo
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF

# Write correct Brave Browser Nightly repo file
cat <<'EOF' > /etc/yum.repos.d/brave-browser-nightly.repo
[brave-browser-nightly]
name=Brave Browser Nightly
baseurl=https://brave-browser-rpm-nightly.s3.brave.com/$basearch
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-nightly.s3.brave.com/brave-core-nightly.asc
EOF

# Import GPG keys
rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
rpm --import https://brave-browser-rpm-nightly.s3.brave.com/brave-core-nightly.asc

dnf install -y brave-browser brave-browser-nightly || {
  log_warn "Brave Nightly may not be available; trying stable only."
  dnf install -y brave-browser
}
echo "Brave browsers installed successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Brave browsers"
fi

# ----------------------------------------------------------------------
# 6. Install VS Code (via Microsoft RPM Repository)
# ----------------------------------------------------------------------
start_step "Install VS Code"
if [ "$INSTALL_VSCODE" = true ]; then
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat <<'EOF' > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

dnf install -y code
echo "VS Code installed successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "VS Code"
fi

# ----------------------------------------------------------------------
# 7. Install Ghostty Terminal Emulator
# ----------------------------------------------------------------------
start_step "Install Ghostty"
if [ "$INSTALL_GHOSTTY" = true ]; then
dnf copr enable -y scottames/ghostty || log_warn "Could not enable the Ghostty COPR repository."
dnf install -y ghostty
echo "Ghostty installed successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Ghostty"
fi

# ----------------------------------------------------------------------
# 8. Install btop (Resource Monitor)
# ----------------------------------------------------------------------
start_step "Install btop"
if [ "$INSTALL_BTOP" = true ]; then
dnf install -y btop
echo "btop installed successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "btop"
fi

# ----------------------------------------------------------------------
# 9. Install General CLI Utilities
# ----------------------------------------------------------------------
start_step "Install general CLI utilities and Fastfetch"
if [ "$INSTALL_CLI_UTILS" = true ]; then
dnf install -y tldr ncdu calibre gh gcc-c++ fzf duf eza zoxide mycli git-lfs fastfetch

# ── Configure Fastfetch Custom Preset ─────────────────────────────────────────
echo "Configuring Fastfetch custom preset and adaptive layout..."
FASTFETCH_CONF_DIR="$TARGET_HOME/.config/fastfetch"
sudo -u "$TARGET_USER" mkdir -p "$FASTFETCH_CONF_DIR"

cat <<\EOF > "$FASTFETCH_CONF_DIR/config.jsonc"
// Based on #1576
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "padding": {
            "right": 1
        }
    },
    "display": {
        "color": {
            "keys": "blue"
        },
        "separator": "",
        // Constants are reusable strings referenced by {$1}, {$2}, etc.
        // These contain ANSI escape codes for cursor positioning
        "constants": [
            "────────────────────────────────────────", // {$1} - horizontal line for inner borders
            "\u001b[41D",                                     // {$2} - move cursor left 47 columns
            "\u001b[41C",                                     // {$3} - move cursor right 47 columns
            "\u001b[40C",                                     // {$4} - move cursor right 46 columns
            "════════════════════════════════════════"  // {$5} - horizontal line for outer borders
        ],
        "brightColor": false
    },
    "modules": [
        {
            "type": "version",
            "key": "╔═══════════════╦═{$5}╗\u001b[35D",
            "format": "\u001b[1m{#keys} {1} - {2} "
        },
        {
            "type": "os",
            // Key format breakdown for OS module:
            // "║  {icon}  \u001b[s{sysname}\u001b[u\u001b[10C│{$3}║{$2}"
            //
            // ║                    - Left border of key block
            //   {icon}             - OS icon (defined internally by fastfetch)
            //   \u001b[s           - ANSI escape: save cursor position (ESC[s)
            // {sysname}            - Format variable: system name (e.g., "Linux", "Darwin")
            // \u001b[u             - ANSI escape: restore cursor to saved position (ESC[u)
            //                        Necessary because the length of `{sysname}` differs between different platforms
            // \u001b[10C           - ANSI escape: move cursor right 10 columns (ESC[10C)
            // │                    - Right border of key block (always 10 columns from left border)
            // {$3}                 - Reference to constants[2]: move cursor right 47 columns
            // ║                    - Right border of value block
            // {$2}                 - Reference to constants[1]: move cursor left 47 columns
            //
            // This creates a fixed-width layout where the key block is exactly 10 columns wide,
            // regardless of the actual content length. The cursor manipulation ensures proper
            // alignment for the table-like structure.
            "key": "║  {icon}  \u001b[s{sysname}\u001b[u\u001b[10C║{$3}║{$2}"
        },
        {
            "type": "locale",
            "key": "║  {icon}  Locale    ║{$3}║{$2}"
        },

        // Hardware section with cyan color theme
        {
            "type": "custom",
            "key": "║{#cyan}┌──────────────┬{$1}┐{#keys}║\u001b[31D",
            "format": "{#bright_cyan} Hardware "
        },
        {
            "type": "chassis",
            // Similar structure but with cyan color formatting:
            // │{#cyan}│             - Left border with cyan color
            //  {icon}               - Chassis icon
            //  Chassis             - Fixed label text
            // │{$4}│{#keys}║{$2}    - Positioning and borders for value area
            "key": "║{#cyan}│ {icon}  Chassis   │{$4}│{#keys}║{$2}"
        },
        {
            "type": "memory",
            "key": "║{#cyan}│ {icon}  RAM       │{$4}│{#keys}║{$2}"
        },
        {
            "type": "swap",
            "key": "║{#cyan}│ {icon}  SWAP      │{$4}│{#keys}║{$2}"
        },
        {
            "type": "cpu",
            "key": "║{#cyan}│ {icon}  CPU       │{$4}│{#keys}║{$2}",
            "showPeCoreCount": true
        },
        {
            "type": "gpu",
            "key": "║{#cyan}│ {icon}  GPU       │{$4}│{#keys}║{$2}"
        },
        {
            "type": "disk",
            "key": "║{#cyan}│ {icon}  Disk      │{$4}│{#keys}║{$2}",
            "format": "{size-used} \/ {size-total} ({size-percentage}) - {filesystem}",
        },
        {
            "type": "battery",
            "key": "║{#cyan}│ {icon}  Battery   │{$4}│{#keys}║{$2}"
        },
        {
            "type": "custom",
            "key": "║{#cyan}└──────────────┴{$1}┘{#keys}║",
            "format": ""
        },

        // Desktop section with green color theme
        {
            "type": "custom",
            "key": "║{#green}┌──────────────┬{$1}┐{#keys}║\u001b[31D",
            "format": "{#bright_green} Desktop "
        },
        {
            "type": "de",
            "key": "║{#green}│ {icon}  Desktop   │{$4}│{#keys}║{$2}"
        },
        {
            "type": "display",
            "key": "║{#green}│ {icon}  Display   │{$4}│{#keys}║{$2}",
            "compactType": "original-with-refresh-rate"
        },
        {
            "type": "gpu",
            "key": "║{#green}│ {icon}  G-Driver  │{$4}│{#keys}║{$2}",
            "format": "{driver}"
        },
        {
            "type": "custom",
            "key": "║{#green}└──────────────┴{$1}┘{#keys}║",
            "format": ""
        },

        // Terminal section with yellow color theme
        {
            "type": "custom",
            "key": "║{#yellow}┌──────────────┬{$1}┐{#keys}║\u001b[31D",
            "format": "{#bright_yellow} Terminal "
        },
        {
            "type": "shell",
            "key": "║{#yellow}│ {icon}  Shell     │{$4}│{#keys}║{$2}"
        },
        {
            "type": "terminal",
            "key": "║{#yellow}│ {icon}  Terminal  │{$4}│{#keys}║{$2}"
        },
        {
            "type": "packages",
            "key": "║{#yellow}│ {icon}  Packages  │{$4}│{#keys}║{$2}"
        },
        {
            "type": "custom",
            "key": "║{#yellow}└──────────────┴{$1}┘{#keys}║",
            "format": ""
        },

        // Development section with red color theme
        {
            "type": "custom",
            "key": "║{#red}┌──────────────┬{$1}┐{#keys}║\u001b[33D",
            "format": "{#bright_red} Development "
        },
        {
            "type": "command",
            "keyIcon": "",                                   // Custom icon override
            "key": "║{#red}│ {icon}  Rust      │{$4}│{#keys}║{$2}",
            "text": "rustc --version",
            "format": "rustc {~6,13}"                         // Print 6th to 13th characters (version number)
        },
        {
            "type": "command",
            "condition": {
                "!system": "Windows"                          // Posix version
            },
            "keyIcon": "",
            "key": "║{#red}│ {icon}  Clang     │{$4}│{#keys}║{$2}",
            "text": "clang --version | sed -n 's/.*version \\([0-9][0-9.]*\\).*/\\1/p'",
            "format": "clang {}"
        },
        {
            "type": "command",
            "condition": {
                "system": "Windows"                           // Windows version
            },
            "keyIcon": "",
            "key": "║{#red}│ {icon}  Clang     │{$4}│{#keys}║{$2}",
            "text": "clang --version | findstr version",      // Finds the line with "version"
            "format": "clang {~-6}"                           // Prints the last 6 characters (version number)
        },
        {
            "type": "command",
            "keyIcon": "",
            "key": "║{#red}│ {icon}  NodeJS    │{$4}│{#keys}║{$2}",
            "text": "node --version",
            "format": "node {~1}"                             // {~1} removes first character (v)
        },
        {
            "type": "command",
            "keyIcon": "",
            "key": "║{#red}│ {icon}  Go        │{$4}│{#keys}║{$2}",
            "text": "go version | cut -d' ' -f3",
            "format": "go {~2}"                               // {~2} removes first 2 characters (go)
        },
        {
            "type": "command",
            "keyIcon": "",
            "key": "║{#red}│ {icon}  Zig       │{$4}│{#keys}║{$2}",
            "text": "zig version",
            "format": "zig {}"
        },
        {
            "type": "editor",
            "key": "║{#red}│ {icon}  Editor    │{$4}│{#keys}║{$2}"
        },
        {
            "type": "command",
            "keyIcon": "󰊢",
            "key": "║{#red}│ {icon}  Git       │{$4}│{#keys}║{$2}",
            "text": "git version",
            "format": "git {~12}"
        },
        {
            "type": "font",
            "key": "║{#red}│ {icon}  Interface │{$4}│{#keys}║{$2}"
        },
        {
            "type": "custom",
            "key": "║{#red}└──────────────┴{$1}┘{#keys}║",
            "format": ""
        },

        // Network section with magenta color theme
        {"type": "custom", "key": "║{#magenta}┌──────────────┬{$1}┐{#keys}║\u001b[31D", "format": "{#bright_magenta} Network "},
        {"type": "users", "myselfOnly": true, "keyIcon": "", "key": "║{#magenta}│ {icon}  User      │{$4}│{#keys}║{$2}", "format": "{name}"},
        {"type": "command", "shell": "/bin/bash", "keyIcon": "󰩟", "key": "║{#magenta}│ {icon}  Priv IPv4 │{$4}│{#keys}║{$2}", "text": "r=$(ip -4 route get 1.1.1.1 2>/dev/null); if [[ $r =~ src[[:space:]]+([0-9.]+) ]]; then ip=${BASH_REMATCH[1]}; gw=$(ip -4 route show default 2>/dev/null | awk '/default/ {print $3; exit}'); [[ -n $gw ]] && echo \"$ip, $gw\" || echo \"$ip\"; else echo \"192.168.0.0, default gateway\"; fi"},
        {"type": "command", "shell": "/bin/bash", "keyIcon": "󰖟", "key": "║{#magenta}│ {icon}  Pub IPv4  │{$4}│{#keys}║{$2}", "text": "c=/tmp/ff_pub_ip; if [[ -f $c && -s $c ]]; then cat $c; [[ $(($(date +%s) - $(stat -c %Y $c 2>/dev/null || echo 0))) -gt 600 ]] && (p=$(curl -s -m 2 https://api.ipify.org 2>/dev/null || curl -s -m 2 http://ipinfo.io/ip 2>/dev/null); [[ -n $p ]] && echo $p > $c) & else p=$(curl -s -m 1.5 https://api.ipify.org 2>/dev/null || curl -s -m 1.5 http://ipinfo.io/ip 2>/dev/null); if [[ -n $p && $p =~ ^[0-9.]+$ ]]; then echo $p > $c; echo $p; else echo \"localhost 127.0.0.1\"; fi; fi"},
        {"type": "command", "shell": "/bin/bash", "keyIcon": "󰩠", "key": "║{#magenta}│ {icon}  IPv6      │{$4}│{#keys}║{$2}", "text": "ip6=$(ip -6 addr show scope global 2>/dev/null | awk '/inet6 / {print $2; exit}' | cut -d/ -f1); [[ -n $ip6 ]] && echo \"$ip6\" || echo \"::1\""},
        {"type": "custom", "key": "║{#magenta}└──────────────┴{$1}┘{#keys}║", "format": ""},
        {"type": "custom", "key": "╚═════════════════{$5}╝", "format": ""},
        "break",                                             // Add a blank line
        "colors"                                             // Display color palette
    ]
}

/*
Key Format Structure Explanation:

The key format uses a combination of:
1. Unicode box drawing characters (│ ┌ ┐ └ ┘ ┬ ┴) for borders
2. ANSI escape codes for cursor positioning (\u001b[...)
3. Format variables ({icon}, {sysname}, etc.)
4. Constant references ({$1}, {$2}, etc.)
5. Color formatting ({#color})

ANSI Escape Codes Used:
- \u001b[s      - Save cursor position (ESC[s)
- \u001b[u      - Restore cursor position (ESC[u)
- \u001b[nC     - Move cursor right n columns (ESC[nC)
- \u001b[nD     - Move cursor left n columns (ESC[nD)

This creates a table-like layout with fixed column widths and proper alignment,
regardless of the actual content length in each field.

For more ANSI escape code reference, see:
https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797#cursor-controls
*/
EOF
chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$FASTFETCH_CONF_DIR"

# ── Configure Adaptive Fastfetch & Window Resize Hook in .zshrc ───────────────
ZSHRC="$TARGET_HOME/.zshrc"
if [ -f "$ZSHRC" ] && ! grep -q "_run_adaptive_fastfetch" "$ZSHRC"; then
  cat <<\EOF >> "$ZSHRC"

# Adaptive fastfetch with dynamic window resize hook
if [[ -o interactive ]]; then
  typeset -gi _ff_is_wide=0
  typeset -gi _ff_allow_resize=1

  _run_adaptive_fastfetch() {
    local cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
    if (( cols >= 100 )); then
      _ff_is_wide=1
      fastfetch
    else
      _ff_is_wide=0
      fastfetch --logo-position top
    fi
  }

  # Initial startup display
  _run_adaptive_fastfetch

  # Dynamically re-render if window is resized between max and min
  TRAPWINCH() {
    if [[ $_ff_allow_resize -eq 1 ]]; then
      local cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
      local now_wide=0
      (( cols >= 100 )) && now_wide=1
      if [[ $now_wide -ne $_ff_is_wide ]]; then
        clear
        _run_adaptive_fastfetch
        zle && zle reset-prompt 2>/dev/null
      fi
    fi
  }

  # Once user executes any command, disable resize re-rendering so work is never interrupted
  _disable_ff_resize() {
    _ff_allow_resize=0
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _disable_ff_resize

  # Quick shortcut to clear and show adaptive fastfetch anytime
  alias ff="clear && _run_adaptive_fastfetch"
fi
EOF
  chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$ZSHRC"
fi

# Ensure Powerlevel10k instant prompt is off so it does not suppress fastfetch
P10K_FILE="$TARGET_HOME/.p10k.zsh"
if [ -f "$P10K_FILE" ]; then
  sed -i "s/^  typeset -g POWERLEVEL9K_INSTANT_PROMPT=.*/  typeset -g POWERLEVEL9K_INSTANT_PROMPT=off/" "$P10K_FILE"
fi

# Launch interactive post-setup in new tabs for tools that require configuration
if command -v gh &>/dev/null; then
  open_in_new_tab "GitHub CLI Login" "gh auth login"
fi
open_in_new_tab "Fastfetch Layout Preview" "fastfetch; echo ''; echo 'Tip: Your adaptive layout is active. Type ff to refresh!'"

echo "CLI utilities & Fastfetch installed and configured successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "CLI utilities"
fi

# ----------------------------------------------------------------------
# 10. Install VLC
# ----------------------------------------------------------------------
start_step "Install VLC"
if [ "$INSTALL_VLC" = true ]; then
dnf install -y vlc
echo "VLC installed successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "VLC"
fi

# ----------------------------------------------------------------------
# 11. Install Discord
# ----------------------------------------------------------------------
start_step "Install Discord"
if [ "$INSTALL_DISCORD" = true ]; then
dnf install -y discord
echo "Discord installed successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Discord"
fi

# ----------------------------------------------------------------------
# 12. Install Obsidian (AppImage)
# ----------------------------------------------------------------------
start_step "Install Obsidian AppImage"
if [ "$INSTALL_OBSIDIAN" = true ]; then
dnf install -y fuse wget curl

# Create installation directory
mkdir -p /opt/obsidian/

# Fetch the latest x86_64 AppImage URL from GitHub API.
# /releases/latest sometimes points to a mobile-only release (APK/dmg),
# so we scan the last 10 releases to find the first x86_64 AppImage.
LATEST_URL=$(curl -s "https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=10" \
  | grep '"browser_download_url"' \
  | grep '\.AppImage"' \
  | grep -iv 'arm' \
  | head -n 1 \
  | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
  log_warn "Could not find an x86_64 Obsidian AppImage in the last 10 releases. Skipping Obsidian install."
else
  # R3: derive the version tag from the URL; skip re-download if already current
  LATEST_VER=$(basename "$(dirname "$LATEST_URL")")
  INSTALLED_VER=""
  [ -f /opt/obsidian/version.txt ] && INSTALLED_VER=$(cat /opt/obsidian/version.txt)

  if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
    echo "Obsidian $LATEST_VER is already installed; skipping download."
  else
    echo "Downloading Obsidian $LATEST_VER AppImage from: $LATEST_URL"
    wget -O /opt/obsidian/Obsidian.AppImage "$LATEST_URL"
    chmod +x /opt/obsidian/Obsidian.AppImage
    echo "$LATEST_VER" > /opt/obsidian/version.txt
  fi

  # Create a symlink to /usr/local/bin/obsidian
  ln -sf /opt/obsidian/Obsidian.AppImage /usr/local/bin/obsidian

  # S3: extract icon as TARGET_USER — running AppImage as root executes arbitrary code with root privileges
  echo "Setting up Obsidian logo..."
  mkdir -p /usr/share/icons/hicolor/512x512/apps/
  (
    ICON_TMP=$(mktemp -d)
    chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$ICON_TMP"
    if sudo -u "$TARGET_USER" sh -c \
        "cd '$ICON_TMP' && /opt/obsidian/Obsidian.AppImage --appimage-extract 'usr/share/icons/hicolor/512x512/apps/obsidian.png'" &>/dev/null \
        && [ -f "$ICON_TMP/squashfs-root/usr/share/icons/hicolor/512x512/apps/obsidian.png" ]; then
      cp "$ICON_TMP/squashfs-root/usr/share/icons/hicolor/512x512/apps/obsidian.png" \
         /usr/share/icons/hicolor/512x512/apps/obsidian.png
    else
      wget -qO /usr/share/icons/hicolor/512x512/apps/obsidian.png \
        "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/obsidian.png" \
        || log_warn "Could not download the Obsidian icon."
    fi
    rm -rf "$ICON_TMP"
  )

  # Create Desktop Entry
  echo "Creating desktop entry for Obsidian..."
  cat <<EOF > /usr/share/applications/obsidian.desktop
[Desktop Entry]
Name=Obsidian
Comment=Obsidian knowledge base
Exec=/opt/obsidian/Obsidian.AppImage %u
Icon=obsidian
Terminal=false
Type=Application
Categories=Office;Utility;
MimeType=x-scheme-handler/obsidian;
StartupWMClass=Obsidian
EOF

  echo "Obsidian AppImage installed successfully."
fi  # end LATEST_URL check

echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Obsidian"
fi  # end INSTALL_OBSIDIAN

# ----------------------------------------------------------------------
# 13. Install and Configure Virtualization (KVM/QEMU/Libvirt)
# ----------------------------------------------------------------------
start_step "Install virtualization stack"
if [ "$INSTALL_KVM" = true ]; then
# Install the virtualization group
dnf install -y @virtualization

# Enable and start the libvirtd daemon
echo "Enabling and starting libvirtd service..."
systemctl enable --now libvirtd

# Add the target user to the libvirt group
echo "Adding $TARGET_USER to the libvirt group..."
usermod -a -G libvirt "$TARGET_USER"
echo "Virtualization stack installed successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))

# ----------------------------------------------------------------------
# 13a. Create a host-side shared folder for KVM guests (virtiofs)
# ----------------------------------------------------------------------
start_step "Configure the KVM shared folder"

# Create the folder on the host
SHARE_DIR="${TARGET_HOME}/SharedFolder"
mkdir -p "$SHARE_DIR"
chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$SHARE_DIR"
echo "  → Host folder created at: $SHARE_DIR"

# Install virtiofsd (host-side daemon required for virtio-fs)
dnf install -y virtiofsd

# KVM_GUEST_NAME is set at the top of the script
VM_NAME="$KVM_GUEST_NAME"

# Check if the VM exists
if ! virsh -c qemu:///system dominfo "$VM_NAME" &>/dev/null; then
  echo "  [INFO] VM '$VM_NAME' not found yet. Skipping shared folder attachment."
  echo "  Create the VM first (see Kali_Setup_in_KVM.md), then re-run this step."
else
  # Never stop or force-stop a running guest automatically.
  VM_STATE=$(virsh -c qemu:///system domstate "$VM_NAME" | head -1)
  if [ "$VM_STATE" != "shut off" ]; then
    log_warn "VM '$VM_NAME' is $VM_STATE. Skipping its virtiofs changes; shut it down and rerun this step manually."
  else

  # ── 1. Add <memoryBacking> for shared memory (required by virtiofs) ──
  # Check if memoryBacking is already configured
  if ! virsh -c qemu:///system dumpxml "$VM_NAME" | grep -q "<memoryBacking>"; then
    echo "  → Adding shared memory backing to VM (required for virtiofs)..."
    # Use virt-xml if available, otherwise patch the XML manually
    if command -v virt-xml &>/dev/null; then
      virt-xml "$VM_NAME" --edit --memorybacking source.type=memfd,access.mode=shared 2>/dev/null || {
        # Fallback: manual XML edit
        TMPXML="$TMP_DIR/vm-memory.xml"
        virsh -c qemu:///system dumpxml "$VM_NAME" > "$TMPXML"
        # Insert memoryBacking after the closing </vcpu> or </currentMemory> tag
        sed -i '/<\/currentMemory>/a \  <memoryBacking>\n    <source type="memfd"\/>\n    <access mode="shared"\/>\n  <\/memoryBacking>' "$TMPXML"
        virsh -c qemu:///system define "$TMPXML"
      }
    else
      TMPXML="$TMP_DIR/vm-memory.xml"
      virsh -c qemu:///system dumpxml "$VM_NAME" > "$TMPXML"
      sed -i '/<\/currentMemory>/a \  <memoryBacking>\n    <source type="memfd"\/>\n    <access mode="shared"\/>\n  <\/memoryBacking>' "$TMPXML"
      virsh -c qemu:///system define "$TMPXML"
    fi
    echo "  → Shared memory backing added."
  else
    echo "  → Shared memory backing already configured."
  fi

  # ── 2. Add <filesystem> device for the shared folder ──
  if ! virsh -c qemu:///system dumpxml "$VM_NAME" | grep -q "kali_share"; then
    echo "  → Adding shared folder device to VM..."
    FSXML="$TMP_DIR/virtiofs-device.xml"
    cat > "$FSXML" <<'XMLEOF'
<filesystem type="mount" accessmode="passthrough">
  <driver type="virtiofs"/>
  <source dir="SHARE_DIR_PLACEHOLDER"/>
  <target dir="kali_share"/>
</filesystem>
XMLEOF
    # Replace placeholder with actual path
    sed -i "s|SHARE_DIR_PLACEHOLDER|$SHARE_DIR|" "$FSXML"
    virsh -c qemu:///system attach-device "$VM_NAME" "$FSXML" --config
    echo "  → Shared folder device added to VM config."
  else
    echo "  → Shared folder device already configured."
  fi

  echo ""
  echo "  ┌─────────────────────────────────────────────────────────┐"
  echo "  │  Shared folder device configured.                      │"
  echo "  │                                                        │"
  echo "  │  Host folder:  $SHARE_DIR"
  echo "  │  VM device:    kali_share (virtiofs)                   │"
  echo "  │                                                        │"
  echo "  │  ⚠  You still need to MOUNT it inside the Kali VM:    │"
  echo "  │                                                        │"
  echo "  │  1. Open a terminal inside Kali and run:               │"
  echo "  │     sudo mkdir -p ~/Desktop/SharedFolder               │"
  echo "  │     sudo mount -t virtiofs kali_share \\                │"
  echo "  │          ~/Desktop/SharedFolder                        │"
  echo "  │                                                        │"
  echo "  │  2. To auto-mount on every boot, add to /etc/fstab:   │"
  echo "  │     kali_share /home/kali/Desktop/SharedFolder \\       │"
  echo "  │          virtiofs defaults 0 0                         │"
  echo "  │                                                        │"
  echo "  └─────────────────────────────────────────────────────────┘"
  fi
  echo ""
fi
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "KVM, libvirt, and shared folder"
fi

# ----------------------------------------------------------------------
# 14. Configure Catppuccin GRUB Theme & Custom Wallpaper
# ----------------------------------------------------------------------
start_step "Configure the Catppuccin GRUB theme"
if [ "$INSTALL_GRUB_THEME" = true ]; then

REPO_DIR="$TARGET_HOME/.cache/catppuccin-grub"
REPO_URL="https://github.com/catppuccin/grub.git"

if [ -d "$REPO_DIR/.git" ]; then
  echo "Using existing repository directory: $REPO_DIR"
else
  echo "Cloning Catppuccin GRUB repository..."
  install -d -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" "$(dirname "$REPO_DIR")"
  sudo -u "$TARGET_USER" git clone "$REPO_URL" "$REPO_DIR"
fi

mkdir -p /usr/share/grub/themes/

echo "Copying Catppuccin GRUB themes..."
cp -r "$REPO_DIR"/src/catppuccin-*-grub-theme /usr/share/grub/themes/

# Apply custom wallpaper if available
if [ -f "$TARGET_HOME/288.jpg" ]; then
  echo "Custom wallpaper $TARGET_HOME/288.jpg found. Applying to GRUB themes..."
  dnf install -y ImageMagick # Ensure magick is available
  for theme_dir in /usr/share/grub/themes/catppuccin-*-grub-theme; do
    if [ -d "$theme_dir" ]; then
      magick "$TARGET_HOME/288.jpg" "$theme_dir/background.png"
    fi
  done
  echo "Custom wallpaper applied."

  # Apply custom lock screen wallpaper to KDE Plasma
  if command -v kwriteconfig6 &> /dev/null; then
    echo "Applying lock screen wallpaper to KDE Plasma..."
    sudo -u "$TARGET_USER" kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --key wallpaperplugin "org.kde.image"
    sudo -u "$TARGET_USER" kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$TARGET_HOME/288.jpg"
  fi
fi

echo "Configuring /etc/default/grub..."
cp -a /etc/default/grub "/etc/default/grub.backup.$(date +%Y%m%d%H%M%S%N)"
if grep -q '^GRUB_TERMINAL_OUTPUT="console"' /etc/default/grub; then
  sed -i 's/^GRUB_TERMINAL_OUTPUT="console"/#GRUB_TERMINAL_OUTPUT="console"/' /etc/default/grub
  echo "Commented out GRUB_TERMINAL_OUTPUT=\"console\""
fi

THEME_PATH="/usr/share/grub/themes/catppuccin-mocha-grub-theme/theme.txt"
if grep -q '^GRUB_THEME=' /etc/default/grub; then
  sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" /etc/default/grub
  echo "Updated existing GRUB_THEME setting to Mocha flavor."
else
  echo "GRUB_THEME=\"$THEME_PATH\"" >> /etc/default/grub
  echo "Added GRUB_THEME setting for Mocha flavor."
fi

echo "Regenerating GRUB configuration..."
grub2-mkconfig -o /boot/grub2/grub.cfg
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "GRUB theme"
fi

# ----------------------------------------------------------------------
# 15. Configure Catppuccin KDE Theme, GTK Theme, Konsole Theme, and Ghostty Theme
# ----------------------------------------------------------------------
start_step "Install Catppuccin desktop themes"
if [ "$INSTALL_DESKTOP_THEMES" = true ]; then

# Install compile dependencies
dnf install -y sassc unzip wget tar

# 15a. KDE Theme
echo "Installing Catppuccin KDE theme..."
KDE_REPO_DIR="$TMP_DIR/catppuccin-kde"
sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/catppuccin/kde "$KDE_REPO_DIR"
# Strip broken Pling KNS dependency (Aurorae is already installed locally by install.sh)
sudo -u "$TARGET_USER" sed -i '/X-KPackage-Dependencies/d' "$KDE_REPO_DIR"/generated/look-and-feel/*/*/metadata.desktop
sudo -u "$TARGET_USER" sed -i '/kns:\/\/aurorae\.knsrc/d' "$KDE_REPO_DIR"/generated/look-and-feel/*/*/metadata.json
sudo -u "$TARGET_USER" bash -c "cd '$KDE_REPO_DIR' && chmod +x install.sh && ./install.sh 1 4 1 auto" || log_warn "Catppuccin KDE theme installation failed."

# 15b. Konsole Color Schemes
echo "Installing Catppuccin Konsole color schemes..."
KONSOLE_DIR="$TARGET_HOME/.local/share/konsole"
sudo -u "$TARGET_USER" mkdir -p "$KONSOLE_DIR"
KONSOLE_REPO_DIR="$TMP_DIR/catppuccin-konsole"
sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/catppuccin/konsole "$KONSOLE_REPO_DIR"
sudo -u "$TARGET_USER" cp "$KONSOLE_REPO_DIR"/themes/*.colorscheme "$KONSOLE_DIR/"

# 15c. GTK Theme
echo "Installing Catppuccin GTK theme..."
GTK_THEME_DIR="$TARGET_HOME/.themes"
LOCAL_GTK_THEME_DIR="$TARGET_HOME/.local/share/themes"
sudo -u "$TARGET_USER" mkdir -p "$GTK_THEME_DIR" "$LOCAL_GTK_THEME_DIR"
GTK_REPO_DIR="$TMP_DIR/Catppuccin-GTK-Theme"
sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme.git "$GTK_REPO_DIR"
# Run the installer as TARGET_USER in batch mode
sudo -u "$TARGET_USER" env BATCH_MODE=true bash "$GTK_REPO_DIR/themes/install.sh" -a mauve -m dark || log_warn "Catppuccin GTK theme installation failed."
sudo -u "$TARGET_USER" cp -r "$GTK_THEME_DIR"/Catppuccin-Mauve-Dark* "$LOCAL_GTK_THEME_DIR"/ 2>/dev/null || true

# 15d. Cursor compatibility symlink
echo "Creating cursor compatibility symlink..."
if [ ! -e "$TARGET_HOME/.icons" ]; then
  sudo -u "$TARGET_USER" ln -s "$TARGET_HOME/.local/share/icons" "$TARGET_HOME/.icons"
fi

# 15e. Ghostty Theme & Font
echo "Configuring Catppuccin theme and font for Ghostty..."
GHOSTTY_CONFIG_DIR="$TARGET_HOME/.config/ghostty"
sudo -u "$TARGET_USER" mkdir -p "$GHOSTTY_CONFIG_DIR"
GHOSTTY_CONFIG_FILE="$GHOSTTY_CONFIG_DIR/config"
if [ ! -f "$GHOSTTY_CONFIG_FILE" ]; then
  sudo -u "$TARGET_USER" touch "$GHOSTTY_CONFIG_FILE"
fi
if ! grep -q "^theme =" "$GHOSTTY_CONFIG_FILE"; then
  sudo -u "$TARGET_USER" sh -c "echo 'theme = Catppuccin Mocha' >> '$GHOSTTY_CONFIG_FILE'"
else
  sudo -u "$TARGET_USER" sed -i 's/^theme =.*/theme = Catppuccin Mocha/' "$GHOSTTY_CONFIG_FILE"
fi
if ! grep -q "^font-family =" "$GHOSTTY_CONFIG_FILE"; then
  sudo -u "$TARGET_USER" sh -c "echo 'font-family = \"MesloLGS NF\"' >> '$GHOSTTY_CONFIG_FILE'"
  sudo -u "$TARGET_USER" sh -c "echo 'font-size = 12' >> '$GHOSTTY_CONFIG_FILE'"
fi

echo "Catppuccin KDE, GTK, Konsole, and Ghostty themes installed/configured."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Desktop themes"
fi

# ----------------------------------------------------------------------
# 16. Install AnyDesk
# ----------------------------------------------------------------------
start_step "Install AnyDesk"
if [ "$INSTALL_ANYDESK" = true ]; then
if [ -e /etc/yum.repos.d/AnyDesk-Fedora.repo ]; then
  cp -a /etc/yum.repos.d/AnyDesk-Fedora.repo "/etc/yum.repos.d/AnyDesk-Fedora.repo.backup.$(date +%Y%m%d%H%M%S%N)"
fi
cat << 'EOF' > /etc/yum.repos.d/AnyDesk-Fedora.repo
[anydesk]
name=AnyDesk Fedora - stable
baseurl=http://rpm.anydesk.com/fedora/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
EOF

dnf install -y anydesk
echo "AnyDesk installed successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "AnyDesk"
fi

if [ "$WARNINGS" -eq 0 ]; then
  echo "Setup completed successfully!"
else
  echo "Setup finished with $WARNINGS warning(s); review the log before treating it as complete."
fi
echo "Note: To install the graphical Antigravity IDE, download the RPM directly from: https://antigravity.google/download"
echo "Please reboot your system for Nvidia drivers and other changes to take full effect."
echo "============================================="
