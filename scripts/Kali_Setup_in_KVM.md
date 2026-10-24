# Kali Linux Setup Guide for KVM

> Why KVM? KVM (Kernel-based Virtual Machine) gives near-native performance, but clipboard, display integration, and shared folders need explicit setup.

---

## Part 0: Host Prerequisites (Do This First)

Before creating the Kali VM, confirm your Linux host is ready:

1. CPU virtualization enabled in BIOS/UEFI (Intel VT-x or AMD-V).
2. KVM/libvirt stack installed (`qemu-kvm`, `libvirt-daemon-system`, `virt-manager`).
3. Virtiofs daemon installed on host (required on Fedora for shared folders):

   > 🖥️ **Run on: HOST machine (Fedora)**

   ```bash
   # On Fedora host:
   sudo dnf install -y virtiofsd
   ```
4. Your user is in `libvirt` and `kvm` groups. To add yourself if not already:

   > 🖥️ **Run on: HOST machine (Fedora/Linux)**

   ```bash
   sudo usermod -aG libvirt,kvm $USER
   newgrp libvirt   # apply without full logout (or log out/in)
   ```
5. `libvirtd` service is running.

Quick check commands on host:

> 🖥️ **Run on: HOST machine (Fedora/Linux)**

```bash
grep -cE '(vmx|svm)' /proc/cpuinfo
sudo systemctl status libvirtd --no-pager
groups
```

---
## Part 1: Initial VM Creation

### Step 1: Create the Virtual Machine

| Setting                 | Recommended Value | Notes                                                    |
| ----------------------- | ----------------- | -------------------------------------------------------- |
| Installation Method     | ISO image         | Download from [kali.org](https://www.kali.org/get-kali/) |
| OS Type                 | Debian 12/13      | Select the closest match available                       |
| RAM                     | 8192 MiB (8 GB)   | Minimum 4 GB; 8 GB recommended for smooth operation      |
| CPU Cores               | 8 cores           | Adjust based on your host CPU                            |
| Disk Space              | 60-96 GiB         | 60 GiB minimum; 96 GiB if running multiple tools         |

---

## Part 2: Network Setup (After VM is Created and Running)

### Network Overview

- **default** – a NAT network (`192.168.122.0/24`). Provides outbound Internet for the guest.
- **pentest‑lab** – an isolated lab network (`192.168.100.0/24`). Allows the guest to talk to the other vulnerable VMs.

These two NICs should be attached to the Kali VM (one to each network) to enable both Internet access and lab interaction.

> **Prerequisites:** The Kali VM must already exist and be **running** before executing the steps below (`--live` requires a running domain).

### Network Configuration Steps

1. **Attach the NAT interface** (default network) – this provides Internet:

   > 🖥️ **Run on: HOST machine (Fedora/Linux)**

   ```bash
   virsh -c qemu:///system attach-interface Kali-Linux network default \
        --model virtio --config --live
   ```

2. **Attach the isolated lab interface** (`pentest-lab`) – this allows communication with the other vulnerable VMs:

   > 🖥️ **Run on: HOST machine (Fedora/Linux)**

   ```bash
   virsh -c qemu:///system attach-interface Kali-Linux network pentest-lab \
        --model virtio --config --live
   ```
   *If you created the VM with `virt-manager`, you can also add the interfaces via the UI:*
   - Open the Kali VM → **Details** → **NIC** → **Add Hardware** → **Network source:** choose `default` for the first NIC and `pentest‑lab` for the second.
   - Set **Device model** to `virtio` and check **`--config`** (to persist) and **`--live`** (to apply immediately).

3. **Verify the interfaces inside Kali** after reboot:

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   ip a
   # You should see two interfaces, e.g.:
   # - ens3  (192.168.122.x) – NAT / Internet
   # - ens4  (192.168.100.x) – lab network
   ```

4. **Check routing** – the default route should point to the NAT interface:

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   ip route
   # Expect a line like: default via 192.168.122.1 dev ens3
   ```

5. **Test connectivity & DNS resolution**:

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   ping -c 3 8.8.8.8                # Outbound Internet IP
   ping -c 3 192.168.100.1          # Lab gateway / another VM
   getent hosts http.kali.org       # DNS resolution check
   ```

### Troubleshooting: DNS / Repository Resolution Failures
A common issue in Kali on KVM with two NICs is `Temporary failure resolving 'http.kali.org'` during `apt update`:

1. **Check DNS servers configured**:

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   cat /etc/resolv.conf
   ```
2. **If DNS resolution fails or `/etc/resolv.conf` is empty**:
   Add public DNS servers temporarily:

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf
   ```
3. **If default route is missing or pointing to the lab interface**:
   Check device status and connection profiles first:

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   nmcli device status
   nmcli connection show
   ```

   Configure explicit profiles for both interfaces so routes and metrics are predictable:
   - Identify which interface is on NAT (`192.168.122.x`, usually `eth0` or `ens3`) and which is on the lab network (`192.168.100.x`, e.g. `eth1`/`eth2`).
   - Create or configure explicit, dedicated connection profiles:

   ```bash
   # Configure the NAT connection for internet access:
   sudo nmcli connection add type ethernet ifname eth0 con-name "NAT-Internet" ipv4.route-metric 100 2>/dev/null || \
   sudo nmcli connection modify "NAT-Internet" connection.interface-name eth0 ipv4.route-metric 100
   sudo nmcli connection up "NAT-Internet"

   # Configure the lab network to NEVER become the default gateway:
   sudo nmcli connection add type ethernet ifname eth2 con-name "Lab-Network" ipv4.never-default true ipv4.route-metric 200 2>/dev/null || \
   sudo nmcli connection modify "Lab-Network" connection.interface-name eth2 ipv4.never-default true ipv4.route-metric 200
   sudo nmcli connection up "Lab-Network"
   ```

These steps ensure that the Kali VM has reliable internet access, DNS resolution, and lab‑network connectivity.

---

## Part 3: Post-Installation Configuration (KVM-Specific)

### Phase A: Enable Clipboard and Display Integration

Install guest agents to enable clipboard sharing and automatic resizing:

> 🐧 **Run inside: Kali VM (guest)**

```bash
sudo apt update && sudo apt install -y qemu-guest-agent spice-vdagent
sudo systemctl start qemu-guest-agent
# Note: qemu-guest-agent is a static unit managed by udev, so running 'systemctl enable'
# prints "The unit files have no installation config", which is normal and expected.
```

### Phase B: Set Up Shared Folder (Host <-> Guest)

Prefer `virtiofs` on modern KVM stacks (better performance and file locking). Keep `9p` as fallback.

#### Prerequisites on Host (Fedora):
1. Install `virtiofsd`:

   > 🖥️ **Run on: HOST machine (Fedora)**

   ```bash
   sudo dnf install -y virtiofsd
   ```
2. Enable Shared Memory in `virt-manager`:
   - Open VM Details → **Memory** → Check **"Enable shared memory"** *(virtiofs will not mount without this!)*.
3. Configure SELinux permissions on the host folder:

   > 🖥️ **Run on: HOST machine (Fedora)**

   ```bash
   # Dedicated shared folder on host:
   mkdir -p "$HOME/Desktop/shared_folder"
   sudo chcon -R -t svirt_image_t "$HOME/Desktop/shared_folder"
   ```

#### In virt-manager:
1. Add Hardware → **Filesystem**:
   - **Driver:** `virtiofs`
   - **Source path:** `/home/smylo/Desktop/shared_folder`
   - **Target path:** `kali_share`

#### Inside Kali Guest:
1. Create mount point:

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   mkdir -p "$HOME/Desktop/SharedFolder"
   ```
2. Add ONE of these `fstab` entries (virtiofs first, 9p fallback):

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   # Preferred: virtiofs
   echo "kali_share $HOME/Desktop/SharedFolder virtiofs defaults,_netdev,nofail 0 0" | sudo tee -a /etc/fstab

   # Fallback: 9p
   echo "kali_share $HOME/Desktop/SharedFolder 9p trans=virtio,version=9p2000.L,rw,_netdev,nofail 0 0" | sudo tee -a /etc/fstab
   ```
3. Test mount:

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   sudo mount "$HOME/Desktop/SharedFolder"
   ```

### Phase C: Enable 3D Acceleration and OpenGL

> **Prerequisite:** Shut down the Kali VM before making display/video hardware changes.

1. **Find your host render nodes**:

   > 🖥️ **Run on: HOST machine (Fedora/Linux)**

   ```bash
   ls -l /dev/dri/renderD*
   ```
   > 💡 *Dual GPU laptops: Always pick the integrated GPU (usually AMD/Intel, e.g. `/dev/dri/renderD128`) rather than discrete NVIDIA (`renderD129`). Virgl runs on open-source Mesa drivers; AMD/Intel provides rock-solid stability and zero battery waste.*

2. **In `virt-manager`**:
   - Under **Display Spice**:
     - Check **OpenGL**.
     - Set **Render node** to your iGPU (e.g., `/dev/dri/renderD128`).
     - Set **Listen type** to **None** (OpenGL does not support remote listening sockets).
   - Under **Video Virtio**:
     - Check **3D acceleration**.
   - Click **Apply** on both and start the VM.

3. **Verify acceleration inside Kali**:

   > 🐧 **Run inside: Kali VM (guest)**

   ```bash
   glxinfo -B | grep -E "OpenGL renderer|OpenGL vendor"
   # Expect: OpenGL renderer string: virgl (...)
   # If it shows 'llvmpipe', software rendering is active instead of 3D acceleration.
   ```

---

## Part 4: Universal Kali Setup Script

Save this as `setup.sh` (or `kali-setup.sh`). Run it as your normal user — it calls `sudo` internally where needed.

> **Before running:** Take a snapshot on the Fedora host. 
> 💡 *Note: Because Virgl 3D acceleration is enabled, live RAM snapshots cannot be migrated while running. Shut down the VM first to take a clean internal qcow2 snapshot:*

> 🖥️ **Run on: HOST machine (Fedora/Linux)**

> ```bash
> virsh -c qemu:///system shutdown Kali
> # Check state until it outputs 'shut off':
> virsh -c qemu:///system domstate Kali
>
> # Create the snapshot:
> virsh -c qemu:///system snapshot-create-as Kali pre-setup --atomic
>
> # Verify snapshot was created:
> virsh -c qemu:///system snapshot-list Kali
>
> # Start the VM:
> virsh -c qemu:///system start Kali
> ```

> 🐧 **Run inside: Kali VM (guest)** — execute the setup script below

```bash
#!/usr/bin/env bash
# ==============================================================================
# KALI SETUP SCRIPT (UNIVERSAL: KVM OR NORMAL)
# Safe, idempotent, mode-aware.
# Run as normal user — script calls sudo internally.
# ==============================================================================

# No set -e. Each step uses explicit || on_error so the summary always prints
# and a single failure never silently aborts the rest of the run.
set -uo pipefail

# --- CONFIGURATION FLAGS ---
INSTALL_BASIC_TOOLS=true
INSTALL_SECURITY_TOOLS=true
INSTALL_NODE_NVM=true
INSTALL_SHELL_CONFIG=true

# --- SHARED FOLDER CONFIG ---
SHARE_TAG="kali_share"
SHARE_MOUNT_POINT="$HOME/Desktop/SharedFolder"

# --- NVM VERSION (check https://github.com/nvm-sh/nvm/releases for latest) ---
NVM_VERSION="v0.40.1"

# --- COLORS / STATE ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
STEP_TOTAL=0; STEP_PASS=0; STEP_SKIP=0; STEP_FAIL=0
CURRENT_STEP=""
STEP_STATUS="pass"
SUDO_KEEPALIVE_PID=""

log_info()  { echo -e "${GREEN}[OK]${NC} [$(date '+%H:%M:%S')] $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} [$(date '+%H:%M:%S')] $1"; }
log_error() { echo -e "${RED}[ERR]${NC} [$(date '+%H:%M:%S')] $1"; }

retry() {
    local n=1 max=3 delay=5
    while true; do
        "$@" && return 0
        if (( n >= max )); then return 1; fi
        log_warn "Attempt $n/$max failed. Retrying in ${delay}s..."
        sleep "$delay"
        (( n++ ))
    done
}

start_step() {
    STEP_TOTAL=$(( STEP_TOTAL + 1 ))
    CURRENT_STEP="$1"
    STEP_STATUS="pass"
    echo -e "\n${BLUE}>>> [STEP $STEP_TOTAL] $CURRENT_STEP${NC}"
}

pass_step()  {
    if [[ "$STEP_STATUS" == "pass" ]]; then
        STEP_PASS=$(( STEP_PASS + 1 ))
    fi
}

skip_step()  { STEP_SKIP=$(( STEP_SKIP + 1 )); log_warn "Skipped: $CURRENT_STEP"; }

on_error()   {
    if [[ "$STEP_STATUS" != "fail" ]]; then
        STEP_FAIL=$(( STEP_FAIL + 1 ))
        STEP_STATUS="fail"
    fi
    log_error "Failed: $CURRENT_STEP"
}

ensure_line_in_file() {
    local line="$1" file="$2"
    grep -Fqx "$line" "$file" 2>/dev/null || echo "$line" | sudo tee -a "$file" > /dev/null
}

cleanup() {
    # Kill the entire keepalive process group to avoid orphan sleep processes.
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill -- "-$SUDO_KEEPALIVE_PID" 2>/dev/null || kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- LOGGING ---
# Log to $HOME (user-writable). /var/log requires root and tee runs as user.
LOG_FILE="$HOME/kali-setup.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
log_info "Logging to $LOG_FILE"

# Warm up sudo, then keep the token alive in a background process group.
sudo -v
(while true; do sudo -n true; sleep 55; done) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

# --- MODE SELECTION ---
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE} Kali Setup - Choose Installation Mode ${NC}"
echo -e "${BLUE}=============================================${NC}"
echo "  1) KVM guest setup"
echo "  2) Normal setup (hardware/laptop/VPS)"
while true; do
    read -rp "Select mode [1/2]: " SETUP_CHOICE
    case "$SETUP_CHOICE" in
        1) SETUP_MODE="kvm";    break ;;
        2) SETUP_MODE="normal"; break ;;
        *) log_warn "Invalid choice. Please enter 1 or 2." ;;
    esac
done
log_info "Using setup mode: $SETUP_MODE"

# --- PRE-FLIGHT NETWORK & DNS CHECK ---
check_network() {
    log_info "Verifying internet and DNS connectivity..."
    if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        log_error "No outbound IP connectivity detected! Check your NAT network adapter."
        return 1
    fi
    # BUG-FIX: use || so the fallback fires if EITHER host fails DNS resolution,
    # not only when both simultaneously fail (the original && was too lenient).
    if ! getent hosts http.kali.org >/dev/null 2>&1 || ! getent hosts github.com >/dev/null 2>&1; then
        log_warn "DNS resolution failed for http.kali.org and/or github.com."
        log_warn "Attempting persistent DNS fix via NetworkManager (survives reconnects)..."
        # Persistent fix: NM respects ipv4.dns and won't clobber resolv.conf on reconnect.
        ACTIVE_CON=$(nmcli -t -f NAME con show --active 2>/dev/null | grep -v 'lo' | head -1)
        if [[ -n "$ACTIVE_CON" ]]; then
            sudo nmcli con mod "$ACTIVE_CON" ipv4.dns "1.1.1.1 8.8.8.8" ipv4.ignore-auto-dns yes 2>/dev/null                 && sudo nmcli con up "$ACTIVE_CON" 2>/dev/null                 && log_info "Persistent DNS set on '$ACTIVE_CON' via nmcli."                 || log_warn "nmcli persistent fix failed — falling back to direct resolv.conf write."
        fi
        # Fallback: direct write (temporary; NM may overwrite on next reconnect)
        if ! getent hosts http.kali.org >/dev/null 2>&1; then
            log_warn "Writing fallback nameservers directly to /etc/resolv.conf (temporary)."
            echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
        fi
        if ! getent hosts http.kali.org >/dev/null 2>&1; then
            log_error "DNS resolution is still failing. Check NetworkManager route metrics before proceeding."
            return 1
        fi
        log_info "DNS resolution restored via fallback nameservers."
    fi
    log_info "Network and DNS connectivity confirmed."
    return 0
}

check_network || log_warn "Pre-flight network check failed. Attempting setup anyway, but online steps may fail."

# --- SHARED ALIASES ---
# bat: aliased as 'bcat' — aliasing 'cat' breaks pipes and adds decorations.
# fd: kali ships fdfind; alias keeps muscle memory for 'fd'.
# zoxide: initialised via eval below, not via the z omz plugin (they conflict).
ALIASES_MARKER="# --- kali-setup custom aliases ---"
SHARED_ALIASES="${ALIASES_MARKER}
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias lt='eza --tree --icons --level=2'
alias bcat='batcat --paging=never'
alias fd='fdfind'
alias help='tldr'
alias ports='ss -tulpn'
# zoxide (replaces cd with smarter directory jumping)
eval \"$(zoxide init zsh)\""

# ==============================================================================
# STEP 1 — System Update
# ==============================================================================
start_step "System Update"
if retry sudo apt update; then
    # full-upgrade handles held-back packages; important on Kali rolling.
    retry sudo apt full-upgrade -y || on_error
else
    on_error
fi
pass_step

# ==============================================================================
# STEP 2 — Base Tools
# ==============================================================================
start_step "Base Tools"
if [[ "$INSTALL_BASIC_TOOLS" == true ]]; then
    # Package name notes:
    #   bat      → binary lands as 'batcat'; pkg is 'bat' on newer Kali
    #   eza      → available in Kali 2024+; fallback chain below
    #   fd-find  → binary is 'fdfind' on Debian/Kali
    APT_PKGS=(
        zsh git curl vim tree jq
        fzf htop
        tmux                  # critical: keeps sessions alive if SPICE/console drops mid-scan
        python3-pip python3-venv python3-dev pipx
        build-essential cmake pkg-config python3-unicorn
        zoxide
        fonts-powerline
        fd-find
        # tools you already use / partially know
        tcpdump wireshark ffuf nikto whatweb
        # remote access & lab pivoting
        openssh-server        # makes Kali reachable from other lab VMs via SSH
        sshpass               # non-interactive SSH with password (lab pivoting practice)
    )
    for pkg in "${APT_PKGS[@]}"; do
        sudo apt install -y "$pkg" 2>/dev/null || log_warn "Package '$pkg' not found — skipping."
    done

    # bat: prefer 'bat', fall back to 'bat-musl'
    if ! sudo apt install -y bat 2>/dev/null; then
        sudo apt install -y bat-musl 2>/dev/null || log_warn "bat not available via apt."
    fi
    # Confirm which binary name landed
    if command -v batcat > /dev/null 2>&1; then
        log_info "bat binary: batcat"
    elif command -v bat > /dev/null 2>&1; then
        log_info "bat binary: bat — update bcat alias if needed"
    else
        log_warn "bat not found after install attempt."
    fi

    # eza: apt → exa → GitHub release (no-root download, manual move)
    if ! sudo apt install -y eza 2>/dev/null; then
        if ! sudo apt install -y exa 2>/dev/null; then
            log_warn "eza/exa not in apt — fetching from GitHub (no checksum; verify manually)."
            EZA_TMP=$(mktemp -d)
            EZA_URL=$(curl -fsSL https://api.github.com/repos/eza-community/eza/releases/latest \
                | grep -o '"browser_download_url": *"[^"]*eza_x86_64-unknown-linux-musl\.tar\.gz"' \
                | grep -o 'https://[^"]*' | head -1)
            if [[ -n "$EZA_URL" ]]; then
                curl -fsSL "$EZA_URL" -o "$EZA_TMP/eza.tar.gz"
                tar -xzf "$EZA_TMP/eza.tar.gz" -C "$EZA_TMP"
                sudo mv "$EZA_TMP/eza" /usr/local/bin/eza
                rm -rf "$EZA_TMP"
                log_info "eza installed from GitHub. Manually verify: sha256sum /usr/local/bin/eza"
            else
                log_warn "Could not resolve eza download URL from GitHub API."
            fi
        fi
    fi

    # mesa-utils for glxinfo (KVM 3D check later)
    sudo apt install -y mesa-utils 2>/dev/null \
        || sudo apt install -y mesa-utils-extra 2>/dev/null \
        || log_warn "mesa-utils not available."

    # tldr
    if ! sudo apt install -y tldr 2>/dev/null; then
        log_warn "apt tldr failed — trying pipx..."
        pipx install tldr 2>/dev/null || log_warn "tldr pipx install also failed."
    fi

    pass_step
else
    skip_step
fi

# ==============================================================================
# STEP 3 — Platform Specifics
# ==============================================================================
start_step "Platform Specifics (Mode: $SETUP_MODE)"
if [[ "$SETUP_MODE" == "kvm" ]]; then

    log_info "Installing SPICE guest agents..."
    # spice-vdagent only helps if VM display is SPICE (not VNC).
    # Check virt-manager: Display → type. If VNC, skip spice-vdagent.
    sudo apt install -y qemu-guest-agent spice-vdagent || log_warn "Guest agent install failed."
    sudo systemctl enable --now qemu-guest-agent || log_warn "qemu-guest-agent enable failed."

    log_info "Enabling SSH server (makes Kali reachable from other lab VMs on pentest-lab network)..."
    sudo systemctl enable --now ssh || log_warn "SSH server enable failed — start manually: sudo systemctl start ssh"

    log_info "Checking virgl 3D acceleration..."
    # llvmpipe = software rendering = NOT accelerated. Only virgl is the real thing.
    if command -v glxinfo > /dev/null 2>&1; then
        if glxinfo 2>/dev/null | grep -qi 'virgl'; then
            log_info "virgl confirmed — hardware-accelerated 3D active."
        else
            log_warn "virgl not detected. Check virt-manager: Video → Model=virtio, 3D accel ON; Display → OpenGL ON."
        fi
    else
        log_warn "glxinfo not found — skipping renderer check."
    fi

    log_info "Configuring shared folder mount..."
    mkdir -p "$SHARE_MOUNT_POINT"

    # Ensure virtiofs module is loaded before checking /proc/filesystems.
    sudo modprobe virtiofs 2>/dev/null || true

    if grep -qw virtiofs /proc/filesystems; then
        # x-gvfs-hide: prevents file managers creating phantom sidebar icons
        FSTAB_LINE="$SHARE_TAG $SHARE_MOUNT_POINT virtiofs defaults,x-gvfs-hide,nofail 0 0"
        log_info "Using virtiofs for shared folder."
    else
        FSTAB_LINE="$SHARE_TAG $SHARE_MOUNT_POINT 9p trans=virtio,version=9p2000.L,rw,_netdev,nofail 0 0"
        log_warn "virtiofs unavailable after modprobe — using 9p fallback (slower, worse permissions)."
    fi

    ensure_line_in_file "$FSTAB_LINE" /etc/fstab
    sudo mount "$SHARE_MOUNT_POINT" 2>/dev/null \
        || log_warn "Mount failed. Check: virt-manager filesystem target='$SHARE_TAG', driver=virtiofs, shared memory enabled."

else
    log_info "Skipping KVM-specific agents and shared folder setup."
fi
pass_step

# ==============================================================================
# STEP 4 — Kali Security Tools
# ==============================================================================
start_step "Kali Security Tools"
if [[ "$INSTALL_SECURITY_TOOLS" == true ]]; then
    # Note: if you installed from a full Kali ISO, most of these are already present.
    SEC_PKGS=(
        seclists wordlists
        nmap metasploit-framework
        gobuster sqlmap
        # password cracking — essential for offline lab scenarios
        hashcat john hydra crunch medusa
        # web app testing — DVWA, Juice Shop, etc.
        burpsuite
        # AD / Windows lab enumeration
        bloodhound neo4j
        # network poisoning / credential capture
        responder
        # already know these but ensure they're present
        wireshark tcpdump ffuf nikto whatweb
    )
    for pkg in "${SEC_PKGS[@]}"; do
        sudo apt install -y "$pkg" 2>/dev/null || log_warn "Package '$pkg' not found — skipping."
    done

    # rockyou.txt: decompress if still gzipped, then verify the txt is present.
    if [[ -f /usr/share/wordlists/rockyou.txt.gz ]]; then
        sudo gunzip -f /usr/share/wordlists/rockyou.txt.gz || log_warn "gunzip rockyou.txt.gz failed."
    fi
    if [[ -f /usr/share/wordlists/rockyou.txt ]]; then
        log_info "rockyou.txt ready at /usr/share/wordlists/rockyou.txt."
    else
        log_warn "rockyou.txt not found after gunzip — check the 'wordlists' package."
    fi

    # evil-winrm: Ruby gem; needed for WinRM shell into Windows lab VMs.
    # ruby-full is a large dep — warn on failure, don't block the step.
    if ! command -v evil-winrm > /dev/null 2>&1; then
        log_info "Attempting evil-winrm install via gem (requires ruby-full)..."
        sudo apt install -y ruby-full 2>/dev/null && sudo gem install evil-winrm 2>/dev/null             || log_warn "evil-winrm install failed — install manually: sudo gem install evil-winrm"
    else
        log_info "evil-winrm already present — skipping."
    fi

    pass_step
else
    skip_step
fi

# ==============================================================================
# STEP 5 — Node via NVM
# ==============================================================================
start_step "Node via NVM"
if [[ "$INSTALL_NODE_NVM" == true ]]; then
    # TRUST WARNING: curl|bash with no checksum. Pinned to $NVM_VERSION.
    # Verify current release at https://github.com/nvm-sh/nvm/releases before running.
    if curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash; then
        export NVM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvm"
        [ -s "$NVM_DIR/nvm.sh" ] || export NVM_DIR="${HOME}/.nvm"
        # shellcheck disable=SC1091
        [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
        if command -v nvm > /dev/null 2>&1; then
            nvm install --lts || on_error
        else
            on_error
        fi
    else
        on_error
    fi
    pass_step
else
    skip_step
fi

# ==============================================================================
# STEP 6 — Zsh + Oh My Zsh
# ==============================================================================
start_step "Zsh + Oh My Zsh"
if [[ "$INSTALL_SHELL_CONFIG" == true ]]; then

    # TRUST WARNING: curl|bash from ohmyzsh master (unpinned). Review before running.
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            "" --unattended || on_error
    fi

    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] \
        || git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
               "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] \
        || git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
               "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    [[ -d "$ZSH_CUSTOM/plugins/zsh-history-substring-search" ]] \
        || git clone --depth=1 https://github.com/zsh-users/zsh-history-substring-search \
               "$ZSH_CUSTOM/plugins/zsh-history-substring-search"
    [[ -d "$ZSH_CUSTOM/plugins/zsh-completions" ]] \
        || git clone --depth=1 https://github.com/zsh-users/zsh-completions \
               "$ZSH_CUSTOM/plugins/zsh-completions"

    # Only write plugins line if it hasn't already been customised by this script.
    # Avoids nuking plugins you add manually later on reruns.
    PLUGINS_LINE='plugins=(git sudo fzf extract dirhistory copypath copyfile history command-not-found zsh-autosuggestions zsh-completions zsh-history-substring-search zsh-syntax-highlighting)'
    if ! grep -Fq "kali-setup" "$HOME/.zshrc" 2>/dev/null; then
        # First run: overwrite the default plugins= line.
        sed -i 's|^plugins=.*|# kali-setup managed — edit here only\n'"$PLUGINS_LINE"'|' "$HOME/.zshrc"
    fi
    # Note: 'z' omz plugin removed — conflicts with zoxide.
    # zoxide is initialised via eval in SHARED_ALIASES below.

    # Append aliases block only once (keyed on marker string).
    if ! grep -Fq "$ALIASES_MARKER" "$HOME/.zshrc" 2>/dev/null; then
        printf '\n%s\n' "$SHARED_ALIASES" >> "$HOME/.zshrc"
    fi

    # Actually switch the default shell to zsh so the config applies on next login.
    ZSH_BIN=$(command -v zsh)
    if [[ "$SHELL" != "$ZSH_BIN" ]]; then
        log_info "Changing default shell to zsh..."
        sudo chsh -s "$ZSH_BIN" "$USER" || log_warn "chsh failed — run manually: chsh -s $ZSH_BIN"
    fi

    pass_step
else
    skip_step
fi

# ==============================================================================
# STEP 7 — Python Tools
# ==============================================================================
start_step "Python Tools"
pipx ensurepath || true

# impacket: already shipped by Kali as python3-impacket + /usr/bin/impacket-*.
# Installing via pipx creates duplicate binaries on PATH — skip it.
# BUG-FIX: was log_warn — changed to on_error so step correctly fails if impacket is missing.
sudo apt install -y python3-impacket 2>/dev/null \
    || on_error

# netexec: not on PyPI as a stable package; install from git.
# BUG-FIX: was log_warn — changed to on_error; nxc is a core lab tool.
if ! command -v netexec > /dev/null 2>&1 && ! command -v nxc > /dev/null 2>&1; then
    pipx install "git+https://github.com/Pennyw0rth/NetExec" \
        || on_error
else
    log_info "netexec/nxc already present — skipping."
fi

# volatility3: optional forensics tool — log_warn is intentional (lab may not need it).
pipx install volatility3 2>/dev/null || log_warn "volatility3 install failed or already present."

# pwntools: you use it as a library to import in scripts, not as a standalone binary.
# pipx isolates it so 'import pwn' won't work in your own scripts.
# Use a dedicated venv instead:
if [[ ! -d "$HOME/venvs/pentest" ]]; then
    python3 -m venv --system-site-packages "$HOME/venvs/pentest" || on_error
    "$HOME/venvs/pentest/bin/pip" install --upgrade pip pwntools \
        || on_error
    log_info "pentest venv at ~/venvs/pentest — activate with: source ~/venvs/pentest/bin/activate"
else
    log_info "~/venvs/pentest already exists — skipping pwntools install."
fi

[[ "$STEP_STATUS" == "pass" ]] && pass_step || true

# ==============================================================================
# SUMMARY
# ==============================================================================

# Auto-run tldr update now that network is confirmed working (avoids manual step).
log_info "Updating tldr page cache..."
tldr --update 2>/dev/null || log_warn "tldr --update failed — run manually after reboot."

echo
log_info "Setup finished. Passed: $STEP_PASS | Skipped: $STEP_SKIP | Failed: $STEP_FAIL"
log_info "Log: $LOG_FILE"
log_info "Mode: $SETUP_MODE"
echo
log_info "Next steps:"
log_info "  1. Reboot the VM."
log_info "  2. Open a new terminal — it should now be zsh."
log_info "  3. Activate the pentest venv when using pwntools: source ~/venvs/pentest/bin/activate"
if [[ "$SETUP_MODE" == "kvm" ]]; then
log_info "  4. If shared folder is empty: on the Fedora host run:"
log_info "       sudo chcon -R -t svirt_image_t /path/to/SharedFolder"
log_info "     and confirm 'Enable shared memory' is checked in virt-manager Memory settings."
log_info "  5. BloodHound: start neo4j first — sudo neo4j console, then launch bloodhound."
log_info "  6. SSH into this VM from other lab VMs: ssh kali@\$(hostname -I | awk '{print \$1}')"
fi
echo
log_info "RECOMMENDED: Take a post-setup snapshot now (clean baseline with all tools installed):"
log_info "  [On Fedora host] virsh -c qemu:///system shutdown Kali"
log_info "  [On Fedora host] virsh -c qemu:///system domstate Kali    # wait until shut off"
log_info "  [On Fedora host] virsh -c qemu:///system snapshot-create-as Kali post-setup --atomic"
log_info "  [On Fedora host] virsh -c qemu:///system snapshot-list Kali"
log_info "  [On Fedora host] virsh -c qemu:///system start Kali" 
```

### Notes

1. **No `set -e`** — each step uses `|| on_error` explicitly so the summary always prints.
2. **Per-step pass/fail tracking** — steps only increment `Passed` if all required commands succeeded, avoiding misleading 100% pass counts when errors occur.
3. **Pre-flight Network & DNS Check** — automatically detects and falls back to public DNS if NetworkManager doesn't populate nameservers, preventing batch `apt` failures.
4. **Log file is `~/kali-setup.log`** — user-writable; `/var/log` requires root and breaks with `tee`.
5. **`bcat` not `cat`** — `alias cat=batcat` breaks pipes silently; use `bcat` and keep `cat` clean.
6. **`zoxide` replaces the `z` omz plugin** — having both conflicts; `eval "$(zoxide init zsh)"` handles it.
7. **`impacket` via apt, not pipx** — Kali ships it; pipx would create duplicate conflicting binaries.
8. **`pwntools` in a venv** — it's a library you import; pipx isolation breaks `import pwn` in your scripts.
9. **`netexec` from git** — not stable on PyPI; use the official git source.
10. **`chsh` is called** — shell actually switches to zsh so config applies on next login.
11. **`sudo modprobe virtiofs`** — forces the module before checking `/proc/filesystems` to avoid false 9p fallback.
12. **`glxinfo` only checks `virgl`** — `llvmpipe` in the output means software rendering, not acceleration.
13. **nvm version is a variable** (`NVM_VERSION`) — update it at the top; check current at github.com/nvm-sh/nvm/releases.
14. **`tmux` is in APT_PKGS** — if your SPICE/VNC console drops during a long `apt` or scan, tmux keeps the session alive; reconnect and `tmux attach`.
15. **`hashcat` / `john`** — GPU acceleration in hashcat requires passing a host GPU to the VM; for CPU-only cracking inside KVM both work fine.
16. **`bloodhound` + `neo4j`** — start neo4j first with `sudo neo4j console` (wait for "Started"), then launch `bloodhound`. Default credentials: `neo4j` / `neo4j` (change on first login).
17. **`responder`** — always run in KVM `pentest-lab` network only; never on a network you don't own. Start with: `sudo responder -I ens4 -dPv`.
18. **`evil-winrm`** — connects to Windows VMs on port 5985/5986; usage: `evil-winrm -i <target-IP> -u Administrator -p <password>`.
19. **SSH server enabled on Kali** — find the Kali IP with `hostname -I`; connect from other lab VMs via `ssh kali@<ip>`. Useful for copying files and running tools from a host terminal.
20. **DNS check fixed** (`||` not `&&`) — the original check only triggered fallback when *both* DNS hosts failed; with `||` it fires if *either* fails, preventing silent `apt` failures.

### Important: Fedora/SELinux Host & Virtiofs Requirements

If virtiofs shared folder fails to mount or appears empty inside the guest:

1. **Install `virtiofsd` on the Fedora host**:

   > 🖥️ **Run on: HOST machine (Fedora)**

   ```bash
   sudo dnf install -y virtiofsd
   ```
2. **Enable shared memory in virt-manager**:
   Open VM → **Details** → **Memory** → Check **"Enable shared memory"** *(Required! Without this, the virtiofs daemon cannot attach to the VM's RAM)*.
3. **Fix SELinux security context on the host folder**:

   > 🖥️ **Run on: HOST machine (Fedora)**

   ```bash
   sudo chcon -R -t svirt_image_t /path/to/SharedFolder
   ```
