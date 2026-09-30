# Metasploitable 2 Setup Guide for KVM (Virt-Manager)

Metasploitable 2 is an intentionally vulnerable Ubuntu 8.04 Linux virtual machine designed for security testing. Because of its age, it requires specific configuration details to boot properly in modern KVM environments.

---

## ⚠️ Security Warning
> [!CAUTION]
> Metasploitable 2 is highly vulnerable. 
> * **Never** configure its network interface to **Bridged** mode.
> * Always attach it to your private isolated network (e.g., `pentest-lab`) so it cannot communicate with the internet or your local home/office network.

---

## Part 1: VM Disk Conversion
Metasploitable 2 is distributed as a VMware VMDK disk. For optimal compatibility and performance in KVM:

1. Extract the zip archive:
   ```bash
   unzip ~/Desktop/metasploitable-linux-2.0.0.zip -d ~/Desktop/vulnerable_lab/metasploitable/
   ```
2. Convert the VMDK to QCOW2 format:
   ```bash
   qemu-img convert -f vmdk -O qcow2 ~/Desktop/vulnerable_lab/metasploitable/Metasploitable2-Linux/Metasploitable.vmdk ~/Desktop/vulnerable_lab/metasploitable/Metasploitable.qcow2
   ```

---

## Part 2: VM Creation Settings in Virt-Manager

When creating the virtual machine in Virtual Machine Manager:

| Setting | Value | Notes |
| :--- | :--- | :--- |
| **Method** | **Import existing disk image** | Do not select ISO installation. |
| **Storage Path** | Select `Metasploitable.qcow2` | The file converted in Part 1. |
| **OS Type** | **Generic Linux** (or Ubuntu 8.04 / Debian Lenny if listed) | Prevents virt-manager from applying unsupported modern defaults. |
| **Memory (RAM)** | **512 MiB** to **1024 MiB** | 512 MB is plenty; do not allocate more than 1 GB. |
| **CPUs** | **1** | Metasploitable 2 does not benefit from multiple CPU cores. |
| **Network** | **pentest-lab** (Isolated Network) | Select the isolated network shared with your Kali VM. |

---

## Part 3: Critical Hardware Tweaks (Before Booting)

> [!IMPORTANT]
> Because Metasploitable 2 uses an old Linux kernel (v2.6.24), it **does not support VirtIO** drivers out of the box. You must configure legacy virtual hardware:

1. On the final step of the VM Creation wizard, check **"Customize configuration before install"**.
2. **Disk Bus Type:**
   * Go to **VirtIO Disk 1** on the left menu.
   * Change **Disk bus** from `VirtIO` to `IDE` (or `SATA`).
   * Click **Apply**.
3. **Network Device Model:**
   * Go to **NIC** on the left menu.
   * Change **Device model** from `virtio` to `e1000` (or `rtl8139`).
   * Click **Apply**.
4. Click **Begin Installation** (top left) to boot the VM.

---

## Part 4: Access and Default Credentials

Once the system boots, you will be presented with a command-line login prompt.

* **Default Username:** `msfadmin`
* **Default Password:** `msfadmin`

### Verifying Connection to Kali
To find the IP address of your Metasploitable 2 VM, log in and run:
```bash
ip addr show
# or
ifconfig
```
To test connectivity from Kali Linux, open a terminal in Kali and ping the target:
```bash
ping <Metasploitable_IP>
```
