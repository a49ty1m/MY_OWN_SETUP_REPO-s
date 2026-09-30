# OWASP Broken Web Applications (BWA) Setup Guide for KVM (Virt-Manager)

The OWASP Broken Web Applications Project (OWASP BWA) is a virtual machine containing dozens of web applications with known vulnerabilities. It is based on a 32-bit Linux distribution.

---

## ⚠️ Security Warning
> [!CAUTION]
> OWASP BWA is packed with vulnerable web servers.
> * **Never** configure its network interface to **Bridged** mode.
> * Always attach it to your private isolated network (e.g., `pentest-lab`) so it cannot communicate with the internet or your local home/office network.

---

## Part 1: VM Disk Conversion
OWASP BWA is distributed as split VMware VMDK files. You must convert these files to a single QCOW2 image for use in KVM:

1. Extract the 7z archive:
   ```bash
   mkdir -p ~/Desktop/vulnerable_lab/owaspbwa
   7z x ~/Desktop/OWASP_Broken_Web_Apps_VM_1.2.7z -o/home/smilo/Desktop/vulnerable_lab/owaspbwa/
   ```
2. Convert the main VMDK (which references the split parts) into a unified QCOW2 disk:
   ```bash
   qemu-img convert -f vmdk -O qcow2 "/home/smilo/Desktop/vulnerable_lab/owaspbwa/OWASP Broken Web Apps-cl1.vmdk" ~/Desktop/vulnerable_lab/owaspbwa/OWASP_Broken_Web_Apps.qcow2
   ```

---

## Part 2: VM Creation Settings in Virt-Manager

When creating the virtual machine in Virtual Machine Manager:

| Setting | Value | Notes |
| :--- | :--- | :--- |
| **Method** | **Import existing disk image** | Do not select ISO installation. |
| **Storage Path** | Select `OWASP_Broken_Web_Apps.qcow2` | The file converted in Part 1. |
| **OS Type** | **Generic Linux** (or Ubuntu 10.04 / Debian Squeeze if listed) | Prevents Virt-Manager from applying unsupported modern defaults. |
| **Memory (RAM)** | **1024 MiB** to **2048 MiB** | 1 GB is minimal; 2 GB is recommended for all web apps to run smoothly. |
| **CPUs** | **1** or **2** | 1 CPU is fine, 2 CPUs will make web request handling faster. |
| **Network** | **pentest-lab** (Isolated Network) | Select the isolated network shared with your Kali VM. |

---

## Part 3: Hardware Tweaks (Before Booting)

> [!IMPORTANT]
> Since OWASP BWA uses an older Linux kernel, configuring legacy virtual hardware is recommended to prevent boot or driver issues:

1. On the final step of the VM Creation wizard, check **"Customize configuration before install"**.
2. **Disk Bus Type:**
   * Go to **VirtIO Disk 1** on the left menu.
   * Change **Disk bus** from `VirtIO` to `IDE` (or `SATA`).
   * Click **Apply**.
3. **Network Device Model:**
   * Go to **NIC** on the left menu.
   * Change **Device model** from `virtio` to `e1000`.
   * Click **Apply**.
4. Click **Begin Installation** (top left) to boot the VM.

---

## Part 4: Access and Default Credentials

Once the system boots, you will see a console login screen showing the IP address of the machine.

### Operating System Login (Console)
* **Username:** `root`
* **Password:** `owaspbwa`

### Web Applications Interface
To access the vulnerable web applications:
1. Turn on your Kali Linux VM.
2. Open a web browser in Kali Linux.
3. Enter the IP address of the OWASP BWA virtual machine in the URL bar (e.g., `http://192.168.100.150`).
4. You will see a landing page containing links to all the vulnerable web applications (such as Mutillidae, DVWA, WebGoat, etc.).
5. Common default web application credentials:
   * **DVWA:** `admin` / `password`
   * **WebGoat:** `guest` / `guest` or `webgoat` / `webgoat`
   * **Other applications:** Generally listed on the main landing page or in the [owaspbwa-release-notes.txt](file:///home/smilo/Desktop/vulnerable_lab/owaspbwa/owaspbwa-release-notes.txt) file.
