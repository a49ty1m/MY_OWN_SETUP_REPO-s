#!/bin/bash
# ==============================================================================
# UBUNTU HOST SETUP SCRIPT (KVM HOST) - FINAL POLISHED VERSION
# Part of the "Twin Script" Framework (Host ↔ Guest)
# ==============================================================================
set -euo pipefail
umask 022

export DEBIAN_FRONTEND=noninteractive

# --- CONFIGURATION & FLAGS ---
USER_NAME="a49ty1m"
USER_EMAIL="a4920251m@gmail.com"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Feature flags
INSTALL_EZA=true
INSTALL_ZOXIDE=true
INSTALL_MARIADB=true
RUN_DB_HARDENING=false
INSTALL_BRAVE=true
INSTALL_SNAP_APPS=true
INSTALL_KVM_HOST=true
INSTALL_FRESH=true
INSTALL_THEME=true
INSTALL_NERD_FONT=true
INSTALL_NODE_NVM=true

# Nerd Font config
NERD_FONT_NAME="Hack"
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/Hack.zip"
NERD_FONT_TERMINAL_FACE="Hack Nerd Font Mono"
NERD_FONT_SIZE="12"

# --- LOGGING & FRAMEWORK ---
LOG_FILE="$HOME/.local/state/ubuntu-kvm-setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/ubuntu-kvm-setup.lock"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
STEP_TOTAL=0; STEP_PASS=0; STEP_SKIP=0; STEP_FAIL=0; SCRIPT_FAILED=0

log_info()  { echo -e "${GREEN}[✔]${NC} [$(date '+%H:%M:%S')] $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} [$(date '+%H:%M:%S')] $1"; }
log_error() { echo -e "${RED}[✘]${NC} [$(date '+%H:%M:%S')] $1"; }

retry() {
    local n=1 max=3 delay=5
    while true; do
        "$@" && return 0
        if (( n >= max )); then return 1; fi
        log_warn "Attempt $n/$max failed. Retrying in ${delay}s..."
        sleep $delay; (( n++ ))
    done
}

acquire_lock() {
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        log_error "Another setup instance is running (lock: $LOCK_DIR)."; exit 1
    fi
    echo "$$" > "$LOCK_DIR/pid"
}

release_lock() { rm -rf "$LOCK_DIR"; }

start_step() { STEP_TOTAL=$((STEP_TOTAL + 1)); CURRENT_STEP="$1"; echo -e "\n${BOLD}${BLUE}>>> [STEP $STEP_TOTAL] $CURRENT_STEP${NC}"; }
pass_step()  { STEP_PASS=$((STEP_PASS + 1)); }
skip_step()  { STEP_SKIP=$((STEP_SKIP + 1)); echo -e "${YELLOW}[SKIP]${NC} $CURRENT_STEP"; }
on_error()   { SCRIPT_FAILED=1; STEP_FAIL=$((STEP_FAIL + 1)); log_error "Failed: ${CURRENT_STEP:-unknown} (line $1)"; }

print_summary() {
    echo -e "\n${BOLD}--- SETUP SUMMARY ---${NC}"
    echo "Total: $STEP_TOTAL | Passed: $STEP_PASS | Skipped: $STEP_SKIP | Failed: $STEP_FAIL"
    [ "$SCRIPT_FAILED" -eq 0 ] && echo -e "${GREEN}Status: SUCCESS${NC}" || echo -e "${RED}Status: FAILED${NC}"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- SHARED ALIASES (Twin Symmetry) ---
SHARED_ALIASES='
# --- Custom Aliases ---
alias ls="eza --icons --group-directories-first"
alias ll="eza -la --icons --group-directories-first"
alias lt="eza --tree --icons --level=2"
alias cat="batcat --paging=never"
alias fd="fdfind"
alias help="tldr"
alias ports="ss -tulpn"
'

# --- MENU SYSTEM ---
show_menu() {
    local choice
    _flag() { [ "$1" = true ] && echo -e "${GREEN}[ON] ${NC}" || echo -e "${RED}[OFF]${NC}"; }
    while true; do
        clear
        echo -e "${BLUE}=============================================${NC}"
        echo -e "${BLUE}      Ubuntu Host Setup (KVM Framework)      ${NC}"
        echo -e "${BLUE}=============================================${NC}"
        printf "  1) %s eza (ls+)        6) %s Snap Apps\n" "$(_flag "$INSTALL_EZA")" "$(_flag "$INSTALL_SNAP_APPS")"
        printf "  2) %s zoxide (cd+)     7) %s KVM Host\n" "$(_flag "$INSTALL_ZOXIDE")" "$(_flag "$INSTALL_KVM_HOST")"
        printf "  3) %s MariaDB          8) %s Fresh Prompt\n" "$(_flag "$INSTALL_MARIADB")" "$(_flag "$INSTALL_FRESH")"
        printf "  4) %s Brave Browser    9) %s Catppuccin Theme\n" "$(_flag "$INSTALL_BRAVE")" "$(_flag "$INSTALL_THEME")"
        printf "  5) %s Node (NVM)      10) %s Nerd Font\n" "$(_flag "$INSTALL_NODE_NVM")" "$(_flag "$INSTALL_NERD_FONT")"
        echo
        echo -e "   ${GREEN}r)${NC} Run setup   ${GREEN}a)${NC} All ON   ${YELLOW}n)${NC} All OFF   ${RED}q)${NC} Quit"
        read -rp "  Choose: " choice
        case "$choice" in
            1) INSTALL_EZA=$([ "$INSTALL_EZA" = true ] && echo false || echo true) ;;
            2) INSTALL_ZOXIDE=$([ "$INSTALL_ZOXIDE" = true ] && echo false || echo true) ;;
            3) INSTALL_MARIADB=$([ "$INSTALL_MARIADB" = true ] && echo false || echo true) ;;
            4) INSTALL_BRAVE=$([ "$INSTALL_BRAVE" = true ] && echo false || echo true) ;;
            5) INSTALL_NODE_NVM=$([ "$INSTALL_NODE_NVM" = true ] && echo false || echo true) ;;
            6) INSTALL_SNAP_APPS=$([ "$INSTALL_SNAP_APPS" = true ] && echo false || echo true) ;;
            7) INSTALL_KVM_HOST=$([ "$INSTALL_KVM_HOST" = true ] && echo false || echo true) ;;
            8) INSTALL_FRESH=$([ "$INSTALL_FRESH" = true ] && echo false || echo true) ;;
            9) INSTALL_THEME=$([ "$INSTALL_THEME" = true ] && echo false || echo true) ;;
            10) INSTALL_NERD_FONT=$([ "$INSTALL_NERD_FONT" = true ] && echo false || echo true) ;;
            r|R) return 0 ;;
            a|A) INSTALL_EZA=true; INSTALL_ZOXIDE=true; INSTALL_MARIADB=true; INSTALL_BRAVE=true; INSTALL_NODE_NVM=true; INSTALL_SNAP_APPS=true; INSTALL_KVM_HOST=true; INSTALL_FRESH=true; INSTALL_THEME=true; INSTALL_NERD_FONT=true ;;
            n|N) INSTALL_EZA=false; INSTALL_ZOXIDE=false; INSTALL_MARIADB=false; INSTALL_BRAVE=false; INSTALL_NODE_NVM=false; INSTALL_SNAP_APPS=false; INSTALL_KVM_HOST=false; INSTALL_FRESH=false; INSTALL_THEME=false; INSTALL_NERD_FONT=false ;;
            q|Q) exit 0 ;;
        esac
    done
}

# --- EXECUTION ---
if [ -t 0 ]; then show_menu; fi
trap 'on_error $LINENO' ERR
acquire_lock

sudo -v
while true; do sudo -n true; sleep 55; done 2>/dev/null &
SUDO_PID=$!
trap 'kill $SUDO_PID 2>/dev/null; release_lock; print_summary' EXIT

start_step "Pre-flight checks"
[ "$EUID" -eq 0 ] && { log_error "Do not run as root."; exit 1; }
grep -qi "ubuntu" /etc/os-release || { log_error "Ubuntu only."; exit 1; }
pass_step

start_step "System update and core packages"
retry sudo apt-get update && retry sudo apt-get upgrade -y
retry sudo apt-get install -y zsh tldr ncdu git git-lfs curl vim nano vlc gparted calibre gh \
build-essential gcc g++ make fzf bat wget gpg gnome-tweaks btop duf unzip \
python3 python3-pip software-properties-common ca-certificates mesa-utils
pass_step

start_step "Fastfetch install"
if ! grep -Rqs "ppa.launchpadcontent.net/zhangsongcui3371/fastfetch/ubuntu" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch && retry sudo apt-get update
fi
retry sudo apt-get install -y fastfetch
pass_step

start_step "eza and zoxide installation"
if [ "$INSTALL_EZA" = true ] && ! command_exists eza; then
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --yes --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
    retry sudo apt-get update && retry sudo apt-get install -y eza
fi
if [ "$INSTALL_ZOXIDE" = true ] && ! command_exists zoxide; then
    retry bash -c 'curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh'
fi
pass_step

start_step "MariaDB setup"
if [ "$INSTALL_MARIADB" = true ]; then
    retry sudo apt-get install -y mariadb-server mariadb-client mycli
    sudo systemctl enable --now mariadb
    [ "$RUN_DB_HARDENING" = true ] && sudo mysql_secure_installation || log_warn "Skipping DB hardening."
    pass_step
else skip_step; fi

start_step "Brave and Snap apps"
if [ "$INSTALL_BRAVE" = true ]; then
    command_exists brave-browser || retry bash -c 'curl -fsSL https://dl.brave.com/install.sh | sh'
    command_exists brave-browser-nightly || retry bash -c 'curl -fsSL https://dl.brave.com/install.sh | CHANNEL=nightly sh'
fi
if [ "$INSTALL_SNAP_APPS" = true ]; then
    for app in discord telegram-desktop; do sudo snap install "$app" || true; done
fi
pass_step

start_step "Git and Python setup"
git config --global user.name "$USER_NAME"
git config --global user.email "$USER_EMAIL"
pass_step

start_step "KVM host and GPU/3D acceleration"
if [ "$INSTALL_KVM_HOST" = true ]; then
    retry sudo apt-get install -y qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients \
    virt-manager virtinst libosinfo-bin bridge-utils cpu-checker ovmf swtpm dnsmasq-base spice-client-gtk
    for grp in libvirt kvm render video; do
        if ! id -nG "$USER" | grep -qw "$grp"; then sudo usermod -aG "$grp" "$USER"; fi
    done
    id libvirt-qemu >/dev/null 2>&1 && sudo usermod -aG render,video libvirt-qemu
    CONF="/etc/apparmor.d/abstractions/libvirt-qemu"
    if [ -f "$CONF" ] && ! grep -q "/dev/dri/" "$CONF"; then
        sudo bash -c "printf '\n  # GPU 3D acceleration\n  /dev/dri/renderD* rw,\n  /dev/dri/ r,\n  /usr/share/libdrm/ r,\n  /usr/share/libdrm/** r,\n' >> $CONF"
        nvidia-smi >/dev/null 2>&1 && {
            sudo bash -c "printf '  /dev/nvidia* rw,\n  /usr/share/glvnd/egl_vendor.d/ r,\n  /usr/share/glvnd/egl_vendor.d/** r,\n  /usr/share/egl/egl_external_platform.d/ r,\n  /usr/share/egl/egl_external_platform.d/** r,\n  /usr/lib/x86_64-linux-gnu/libnvidia-egl* r,\n  /usr/lib/x86_64-linux-gnu/libEGL_nvidia* r,\n' >> $CONF"
            retry sudo apt-get install -y libnvidia-egl-gbm1 || true
        }
        sudo systemctl reload apparmor
    fi
    sudo systemctl enable --now libvirtd
    pass_step
else skip_step; fi

start_step "Node (NVM) installation"
if [ "$INSTALL_NODE_NVM" = true ]; then
    if [ ! -d "$HOME/.nvm" ] && [ ! -d "$HOME/.config/nvm" ]; then curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash; fi
    export NVM_DIR="$([ -d "$HOME/.config/nvm" ] && echo "$HOME/.config/nvm" || echo "$HOME/.nvm")"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install 20 --lts
    pass_step
else skip_step; fi

start_step "Oh My Zsh and Shell Prompt"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
sed -i 's|^plugins=.*|plugins=(git sudo fzf z extract dirhistory copypath copyfile history command-not-found zsh-autosuggestions zsh-completions zsh-history-substring-search zsh-syntax-highlighting)|' "$HOME/.zshrc"
grep -q "SHARED_ALIASES" "$HOME/.zshrc" || echo -e "\n# SHARED_ALIASES\n$SHARED_ALIASES" >> "$HOME/.zshrc"
if [ "$INSTALL_FRESH" = true ] && ! command_exists fresh; then
    retry bash -c 'curl -fsSL https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh | sh'
fi
pass_step

start_step "Catppuccin theme setup"
if [ "$INSTALL_THEME" = true ]; then
    mkdir -p "$HOME/.themes" "$HOME/.icons"
    tmp_theme="$(mktemp -d)"
    (
        cd "$tmp_theme" && git clone --depth 1 https://github.com/catppuccin/gtk.git
        cd gtk && python3 install.py mocha blue
    )
    if ! grep -Rqs "papirus" /etc/apt/sources.list.d 2>/dev/null; then
        sudo add-apt-repository -y ppa:papirus/papirus && retry sudo apt-get update
    fi
    retry sudo apt-get install -y papirus-icon-theme
    curl -fsSL https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders -o "$tmp_theme/p-folders"
    chmod +x "$tmp_theme/p-folders"
    (
        cd "$tmp_theme" && git clone --depth 1 https://github.com/catppuccin/papirus-folders.git
        cd papirus-folders && sudo cp -r src/* /usr/share/icons/Papirus
        "$tmp_theme/p-folders" -C cat-mocha-blue --theme Papirus-Dark
    )
    curl -fsSL https://github.com/catppuccin/cursors/releases/download/v2.0.0/catppuccin-mocha-blue-cursors.zip -o "$tmp_theme/cursor.zip"
    unzip -o "$tmp_theme/cursor.zip" -d "$HOME/.icons"
    if [ -n "${DISPLAY:-}" ] && command_exists gsettings; then
        gsettings set org.gnome.desktop.interface gtk-theme "catppuccin-mocha-blue-standard+default"
        gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
        gsettings set org.gnome.desktop.interface cursor-theme "catppuccin-mocha-blue-cursors"
    fi
    rm -rf "$tmp_theme"
    pass_step
else skip_step; fi

start_step "Nerd Font installation"
if [ "$INSTALL_NERD_FONT" = true ]; then
    f_dir="$HOME/.local/share/fonts/HackNerdFont"
    mkdir -p "$f_dir" && tmp_f="$(mktemp -d)"
    retry curl -fL "$NERD_FONT_URL" -o "$tmp_f/font.zip"
    unzip -o "$tmp_f/font.zip" -d "$tmp_f"
    find "$tmp_f" -type f \( -name "*.ttf" -o -name "*.otf" \) -exec mv -f {} "$f_dir/" \;
    fc-cache -fv && rm -rf "$tmp_f"
    if [ -n "${DISPLAY:-}" ] && command_exists gsettings; then
        gsettings set org.gnome.desktop.interface monospace-font-name "$NERD_FONT_TERMINAL_FACE $NERD_FONT_SIZE"
    fi
    pass_step
else skip_step; fi

start_step "Cleanup and Finalization"
sudo apt-get autoremove -y
if [ -n "${DISPLAY:-}" ] && command_exists brave-browser; then
    brave-browser https://code.visualstudio.com https://obsidian.md/download &
fi
log_info "Setup complete! Reboot recommended."
pass_step
