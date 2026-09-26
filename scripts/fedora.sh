#!/usr/bin/env bash

# Fail on errors, unset variables, and failed pipeline components.
set -Eeuo pipefail
umask 022

echo "=== System Setup & Catppuccin GRUB Theme Installer for Fedora ==="

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
INSTALL_STEAM_DISCORD=true
INSTALL_OBSIDIAN=true
INSTALL_KVM=true
INSTALL_GRUB_THEME=true
INSTALL_DESKTOP_THEMES=true
INSTALL_ANYDESK=true

FEATURE_FLAGS="INSTALL_MULTIMEDIA INSTALL_NVIDIA INSTALL_ZSH INSTALL_FRESH INSTALL_BRAVE INSTALL_VSCODE INSTALL_GHOSTTY INSTALL_BTOP INSTALL_CLI_UTILS INSTALL_VLC INSTALL_STEAM_DISCORD INSTALL_OBSIDIAN INSTALL_KVM INSTALL_GRUB_THEME INSTALL_DESKTOP_THEMES INSTALL_ANYDESK"

show_menu() {
  local choice name
  while true; do
    clear
    echo "==============================================="
    echo "        Fedora Workstation Setup Options       "
    echo "==============================================="
    printf " 1) [%-3s] Multimedia codecs       9) [%-3s] CLI utilities\n" "$([[ $INSTALL_MULTIMEDIA == true ]] && echo ON || echo OFF)" "$([[ $INSTALL_CLI_UTILS == true ]] && echo ON || echo OFF)"
    printf " 2) [%-3s] Nvidia drivers         10) [%-3s] VLC\n" "$([[ $INSTALL_NVIDIA == true ]] && echo ON || echo OFF)" "$([[ $INSTALL_VLC == true ]] && echo ON || echo OFF)"
    printf " 3) [%-3s] Zsh and plugins        11) [%-3s] Steam and Discord\n" "$([[ $INSTALL_ZSH == true ]] && echo ON || echo OFF)" "$([[ $INSTALL_STEAM_DISCORD == true ]] && echo ON || echo OFF)"
    printf " 4) [%-3s] Fresh shell manager    12) [%-3s] Obsidian\n" "$([[ $INSTALL_FRESH == true ]] && echo ON || echo OFF)" "$([[ $INSTALL_OBSIDIAN == true ]] && echo ON || echo OFF)"
    printf " 5) [%-3s] Brave browsers         13) [%-3s] KVM and shared folder\n" "$([[ $INSTALL_BRAVE == true ]] && echo ON || echo OFF)" "$([[ $INSTALL_KVM == true ]] && echo ON || echo OFF)"
    printf " 6) [%-3s] VS Code                14) [%-3s] GRUB theme\n" "$([[ $INSTALL_VSCODE == true ]] && echo ON || echo OFF)" "$([[ $INSTALL_GRUB_THEME == true ]] && echo ON || echo OFF)"
    printf " 7) [%-3s] Ghostty                15) [%-3s] Desktop themes\n" "$([[ $INSTALL_GHOSTTY == true ]] && echo ON || echo OFF)" "$([[ $INSTALL_DESKTOP_THEMES == true ]] && echo ON || echo OFF)"
    printf " 8) [%-3s] btop                  16) [%-3s] AnyDesk\n" "$([[ $INSTALL_BTOP == true ]] && echo ON || echo OFF)" "$([[ $INSTALL_ANYDESK == true ]] && echo ON || echo OFF)"
    echo
    echo " r) Run setup   a) All on   n) All off   q) Quit"
    read -rp "Choose: " choice
    case "$choice" in
      [1-9]|1[0-6])
        case "$choice" in
          1) name=INSTALL_MULTIMEDIA ;; 2) name=INSTALL_NVIDIA ;; 3) name=INSTALL_ZSH ;;
          4) name=INSTALL_FRESH ;; 5) name=INSTALL_BRAVE ;; 6) name=INSTALL_VSCODE ;;
          7) name=INSTALL_GHOSTTY ;; 8) name=INSTALL_BTOP ;; 9) name=INSTALL_CLI_UTILS ;;
          10) name=INSTALL_VLC ;; 11) name=INSTALL_STEAM_DISCORD ;; 12) name=INSTALL_OBSIDIAN ;;
          13) name=INSTALL_KVM ;; 14) name=INSTALL_GRUB_THEME ;; 15) name=INSTALL_DESKTOP_THEMES ;;
          16) name=INSTALL_ANYDESK ;;
        esac
        if [ "${!name}" = true ]; then printf -v "$name" false; else printf -v "$name" true; fi
        ;;
      a|A) for name in $FEATURE_FLAGS; do printf -v "$name" true; done ;;
      n|N) for name in $FEATURE_FLAGS; do printf -v "$name" false; done ;;
      r|R) return 0 ;;
      q|Q) CANCELLED=1; exit 0 ;;
    esac
  done
}

LOG_FILE="/var/log/fedora-workstation-setup.log"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fedora-setup.XXXXXX")
chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$TMP_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

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

if [ -t 0 ] && [ -t 1 ]; then
  show_menu
fi

echo "Target User: $TARGET_USER"
echo "Target Home: $TARGET_HOME"
echo "============================================="

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
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Multimedia codecs"
fi

echo "RPM Fusion repositories enabled and multimedia codecs installed."
echo "============================================="

# ----------------------------------------------------------------------
# 2. Install Nvidia Drivers & 32-bit Libraries (Crucial for Steam)
# ----------------------------------------------------------------------
start_step "Install Nvidia drivers and 32-bit libraries"
if [ "$INSTALL_NVIDIA" = true ]; then
# Enable the nvidia driver repo (DNF5 syntax)
dnf config-manager setopt rpmfusion-nonfree-nvidia-driver.enabled=1 || log_warn "Could not enable the RPM Fusion Nvidia repository."
dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs.i686 egl-wayland || log_warn "Nvidia packages could not be installed; check hardware and repository setup."
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Nvidia drivers"
fi
echo "Nvidia drivers and Steam graphics libraries installation complete."
echo "============================================="

# ----------------------------------------------------------------------
# 3. Install Zsh and Extensions
# ----------------------------------------------------------------------
start_step "Install and configure Zsh"
if [ "$INSTALL_ZSH" = true ]; then
dnf install -y zsh git curl

# Install Oh My Zsh if not already present
OMZ_DIR="$TARGET_HOME/.oh-my-zsh"
if [ ! -d "$OMZ_DIR" ]; then
  echo "Installing Oh My Zsh for $TARGET_USER..."
  curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
    | sudo -u "$TARGET_USER" env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -s -- --unattended
else
  echo "Oh My Zsh is already installed for $TARGET_USER."
fi

# Install plugins (autosuggestions & syntax-highlighting)
PLUGINS_DIR="$OMZ_DIR/custom/plugins"
mkdir -p "$PLUGINS_DIR"
chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$PLUGINS_DIR"

SUGGESTIONS_DIR="$PLUGINS_DIR/zsh-autosuggestions"
if [ ! -d "$SUGGESTIONS_DIR" ]; then
  echo "Installing zsh-autosuggestions..."
  sudo -u "$TARGET_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "$SUGGESTIONS_DIR"
fi

HIGHLIGHT_DIR="$PLUGINS_DIR/zsh-syntax-highlighting"
if [ ! -d "$HIGHLIGHT_DIR" ]; then
  echo "Installing zsh-syntax-highlighting..."
  sudo -u "$TARGET_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$HIGHLIGHT_DIR"
fi

# Enable plugins in .zshrc
ZSHRC="$TARGET_HOME/.zshrc"
if [ -f "$ZSHRC" ]; then
  echo "Configuring plugins in $ZSHRC..."
  if grep -q '^plugins=(git)' "$ZSHRC"; then
    sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
    echo "Added plugins to $ZSHRC."
  elif ! grep -q 'zsh-autosuggestions' "$ZSHRC"; then
    sed -i 's/plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
    echo "Appended plugins to custom list in $ZSHRC."
  else
    echo "Plugins already configured in $ZSHRC."
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
if [ ! -d "$TARGET_HOME/.fresh" ]; then
  curl -fsSL https://get.freshshell.com \
    | sudo -u "$TARGET_USER" bash -s || log_warn "Fresh installation failed; continuing without it."
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

# DNF returns 100 when updates are available; that is not an error here.
dnf check-update || [ "$?" -eq 100 ]
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
# 8a. Install General CLI Utilities
# ----------------------------------------------------------------------
start_step "Install general CLI utilities"
if [ "$INSTALL_CLI_UTILS" = true ]; then
dnf install -y tldr ncdu calibre gh gcc-c++ fzf duf eza zoxide mycli git-lfs
echo "CLI utilities installed successfully."
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "CLI utilities"
fi

# ----------------------------------------------------------------------
# 9. Install VLC
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
# 10. Install Steam and Discord
# ----------------------------------------------------------------------
start_step "Install Steam and Discord"
if [ "$INSTALL_STEAM_DISCORD" = true ]; then
dnf install -y steam discord
echo "Steam and Discord installed successfully."

# Note on Steam WebHelper blank screen issues on Wayland / hybrid graphics
echo "TIP: If Steam launches with a black or empty screen, run:"
echo "     steam -cef-disable-gpu"
echo "     Or delete the browser cache by running: rm -rf ~/.local/share/Steam/config/htmlcache/*"
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Steam and Discord"
fi

# ----------------------------------------------------------------------
# 11. Install Obsidian (AppImage)
# ----------------------------------------------------------------------
start_step "Install Obsidian AppImage"
if [ "$INSTALL_OBSIDIAN" = true ]; then
dnf install -y fuse wget curl

# Create installation directory
mkdir -p /opt/obsidian/

# Fetch latest AppImage URL from GitHub API
LATEST_URL=$(curl -s https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
  | grep "browser_download_url.*AppImage" \
  | tail -n 1 \
  | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
  echo "Could not determine the latest Obsidian AppImage download URL." >&2
  exit 1
fi

echo "Downloading Obsidian AppImage from: $LATEST_URL"
wget -O /opt/obsidian/Obsidian.AppImage "$LATEST_URL"
chmod +x /opt/obsidian/Obsidian.AppImage

# Create a symlink to /usr/local/bin/obsidian
ln -sf /opt/obsidian/Obsidian.AppImage /usr/local/bin/obsidian

# Download Obsidian logo for desktop entry
echo "Downloading Obsidian logo..."
mkdir -p /usr/share/icons/hicolor/512x512/apps/
wget -O /usr/share/icons/hicolor/512x512/apps/obsidian.png https://obsidian.md/images/logo.png || log_warn "Could not download the Obsidian icon."

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
echo "============================================="
STEP_PASS=$((STEP_PASS + 1))
else
  skip_step "Obsidian"
fi

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

VM_NAME="Kali-Linux"

# Check if the VM exists
if ! virsh -c qemu:///system dominfo "$VM_NAME" &>/dev/null; then
  log_warn "VM '$VM_NAME' not found. Skipping shared folder attachment."
  echo "  Create the VM first, then re-run this script."
  echo "============================================="
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
        sed -i '/<\/currentMemory>/a \  <memoryBacking>\n    <source type="memfd"/>\n    <access mode="shared"/>\n  </memoryBacking>' "$TMPXML"
        virsh -c qemu:///system define "$TMPXML"
      }
    else
      TMPXML="$TMP_DIR/vm-memory.xml"
      virsh -c qemu:///system dumpxml "$VM_NAME" > "$TMPXML"
      sed -i '/<\/currentMemory>/a \  <memoryBacking>\n    <source type="memfd"/>\n    <access mode="shared"/>\n  </memoryBacking>' "$TMPXML"
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
sudo -u "$TARGET_USER" mkdir -p "$GTK_THEME_DIR"
GTK_REPO_DIR="$TMP_DIR/Catppuccin-GTK-Theme"
sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme.git "$GTK_REPO_DIR"
# Run the installer as TARGET_USER in batch mode
sudo -u "$TARGET_USER" env BATCH_MODE=true bash "$GTK_REPO_DIR/themes/install.sh" -a mauve -m dark || log_warn "Catppuccin GTK theme installation failed."

# 15d. Cursor compatibility symlink
echo "Creating cursor compatibility symlink..."
if [ ! -e "$TARGET_HOME/.icons" ]; then
  sudo -u "$TARGET_USER" ln -s "$TARGET_HOME/.local/share/icons" "$TARGET_HOME/.icons"
fi

# 15e. Ghostty Theme
echo "Configuring Catppuccin theme for Ghostty..."
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
