# Linux Setup Scripts

This repository contains automated setup scripts for configuring fresh Linux installations with commonly used development tools and applications.

## 📁 Repository Structure

```
.
├── scripts/
│   ├── arch_setup.sh              # Arch Linux setup script
│   ├── ubuntu_setup_snap.sh       # Ubuntu setup with Snap (recommended)
│   └── ubuntu_setup_flatpak.sh    # Ubuntu setup with Flatpak (alternative)
├── docs/
│   └── (documentation files)
└── README.md                      # This file
```

## 🚀 Quick Start

### Arch Linux

```bash
chmod +x scripts/arch_setup.sh
./scripts/arch_setup.sh
```

### Ubuntu (with Snap)

```bash
chmod +x scripts/ubuntu_setup_snap.sh
./scripts/ubuntu_setup_snap.sh
```

### Ubuntu (with Flatpak)

```bash
chmod +x scripts/ubuntu_setup_flatpak.sh
./scripts/ubuntu_setup_flatpak.sh
```

## 📦 What Gets Installed

### Common Tools (All Scripts)

- **System Utilities**: tldr, ncdu, git, curl, vim, nano
- **Applications**: VLC media player, GParted, Calibre, Discord
- **Development**: Python 3, pip, Visual Studio Code
- **Browsers**: Brave Browser (stable & nightly)
- **Productivity**: Notion, Notion Calendar

### Arch-Specific

- **Package Managers**: yay (AUR helper)
- **Development**: base-devel (build tools)

### Ubuntu-Specific

**Snap Version** (ubuntu_setup_snap.sh):
- Uses Snap for application management
- Includes step tracking and resume capability
- Comprehensive logging to `~/ubuntu-setup.log`

**Flatpak Version** (ubuntu_setup_flatpak.sh):
- Uses Flatpak for application management
- More sandboxed applications
- Integrates with Flathub repository

## ⚙️ Configuration

All scripts automatically configure Git with the following settings:

```bash
git config --global core.editor "code --wait"
git config --global user.name "a49ty1m"
git config --global user.email "a4920251m@gmail.com"
```

**Note**: If you're not a49ty1m, modify these values in the scripts before running!

## 🔄 Features

### Ubuntu Snap Version Features

- ✅ **Step Tracking**: Resume from where you left off if interrupted
- ✅ **Logging**: All output saved to `~/ubuntu-setup.log`
- ✅ **Error Handling**: Automatic error detection and reporting
- ✅ **Idempotent**: Safe to run multiple times

### All Scripts Include

- System updates and upgrades
- Package installation
- Development environment setup
- Browser configuration assistance (WhatsApp Web, Brave Sync, GitHub)

## 📝 Post-Installation

After running any script, you should:

1. **Sync Brave Browser**: The script opens Brave Sync settings automatically
2. **Connect WhatsApp**: WhatsApp Web will open in the browser
3. **Login to GitHub**: GitHub login page opens for authentication
4. **Restart Your System**: Some changes may require a restart

## 🛠️ Customization

To customize the scripts for your needs:

1. Edit the package lists in the respective script
2. Modify Git configuration values
3. Add or remove applications as needed
4. Adjust browser startup pages

## 📋 Requirements

### Arch Linux
- Fresh or existing Arch Linux installation
- Internet connection
- Sudo privileges

### Ubuntu
- Ubuntu 20.04 or later (recommended)
- Internet connection
- Sudo privileges

## 🐛 Troubleshooting

### Ubuntu Snap Version

- **Check logs**: `cat ~/ubuntu-setup.log`
- **Reset progress**: `rm ~/.ubuntu-setup-step` to start fresh
- **Snap issues**: Ensure snapd is running: `sudo systemctl status snapd`

### Arch Linux

- **AUR issues**: Ensure base-devel is installed
- **Package conflicts**: Run `pacman -Syu` manually first

### General

- **Permission denied**: Ensure scripts are executable (`chmod +x`)
- **Network errors**: Check internet connection
- **Application not found**: Verify package manager updates

## 📄 License

Feel free to use, modify, and distribute these scripts for personal or educational purposes.

## 👤 Author

**a49ty1m**
- Email: a4920251m@gmail.com
- GitHub: [@a49ty1m](https://github.com/a49ty1m)

## 🤝 Contributing

Feel free to fork this repository and customize the scripts for your needs. Pull requests for improvements are welcome!
