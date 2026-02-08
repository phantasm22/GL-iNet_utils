# GL.iNet Utilities Script for OpenWrt Routers

```
   _____ _          _ _   _      _   
  / ____| |        (_) \\ | |    | |  
 | |  __| |  ______ _|  \\| | ___| |_ 
 | | |_ | | |______| | . \` |/ _ \\ __|
 | |__| | |____    | | |\\  |  __/ |_ 
 \\_____|______|   |_|_| \\_|\\___|\\__|

         GL.iNet Utilities Toolkit

```

> 🛠️ A growing collection of practical utilities for managing and tuning GL.iNet routers via a single interactive script.

---

## Features

- 🖥️ **Hardware Information** – Detailed system, CPU, memory, storage, crypto acceleration, network & wireless info (paged navigation)
- ⚙️ **AdGuardHome Management** – Enable/disable UI auto-updates, install/remove custom blocklists & allowlists
- 💾 **Zram Swap** – Install, enable, disable or uninstall compressed RAM swap (great for low-RAM models)
- 📊 **Benchmarks** – CPU stress test (stress-ng), OpenSSL speed, disk I/O read/write performance
- 📋 **UCI Config Viewer** – View wireless SSIDs/passwords, network, VPN, system, GoodCloud settings safely
- 🔄 **Self-updating** – Checks GitHub for new versions and offers easy upgrade
- 🆓 Licensed under **GPL-3.0**

Tested on various GL.iNet models (BE3600, MT3000, etc.) running recent firmware.

---

## 🚀 Installation

1. SSH into your GL.iNet router:

```
ssh root@192.168.8.1
```

2. Download the script:

```
wget -O glinet_utils.sh https://raw.githubusercontent.com/phantasm22/GL-iNet_utils/main/glinet_utils.sh
chmod +x glinet_utils.sh
```

3. Run the script:

```
./glinet_utils.sh
```

---

## 📸 Screenshots / Usage

When launched, the script presents an interactive menu system.  
Options may vary as new utilities are added, but generally include:

```
1️⃣ Show Hardware Information
2️⃣ Manage AdGuardHome
3️⃣ Manage AdGuardHome Lists
4️⃣ Manage Zram Swap
5️⃣ System Benchmarks (CPU & Disk)
6️⃣ View System Configuration (UCI)
7️⃣ Check for Update
8️⃣ Exit
```

Most sections include built-in help text and confirmation prompts for safety.

---


## 🔧 Requirements

- GL.iNet router running OpenWrt-based firmware (most models supported)
- SSH access (root login enabled)
- Internet connection for updates, package installs & benchmarks
- Optional: `opkg` packages (lscpu, stress, etc.) are installed automatically when needed
  
---

## ⚙️ Updating the Script

The toolkit includes a built-in update checker (option 7 or automatic on start).

To force an update manually:

```bash
wget -O glinet_utils.sh https://raw.githubusercontent.com/phantasm22/GL-iNet_utils/main/glinet_utils.sh
chmod +x glinet_utils.sh
./glinet_utils.sh
```

---

## 🗑️ Uninstall / Cleanup

Simply delete the script file:

```bash
rm glinet_utils.sh
```
No other files are installed by default. If you installed packages via the script (zram-swap, stress, etc.), remove them manually if desired:
```
opkg remove zram-swap stress
```

---

## ❤️ Credits & Author

Created by **phantasm22**  
https://github.com/phantasm22  

Inspired by the need for a simple, powerful toolkit tailored for GL.iNet routers. 
If you have a utility you run on every GL.iNet router you touch, it probably belongs here.

Contributions, bug reports & feature suggestions welcome!

Star ⭐ the repo if you find it useful!


---

## 📜 License

This project is licensed under the **GNU GPL v3.0 License**.  
See the [LICENSE](https://www.gnu.org/licenses/gpl-3.0.en.html) file for details.
