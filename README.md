# GL.iNet Utilities Script for OpenWrt Routers

```
   _____ _      _ _   _      _   
  / ____| |    (_) \ | |    | |  
 | |  __| | ___ _|  \| | ___| |_ 
 | | |_ | |/ _ \ | . ` |/ _ \ __|
 | |__| | |  __/ | |\  |  __/ |_ 
  \_____|_|\___|_|_| \_|\___|\__|

         GL.iNet Utilities Toolkit

```

> 🛠️ A growing collection of practical utilities for managing and tuning GL.iNet / OpenWrt routers via a single interactive script.

---

## Features

- 🧑‍💻 Interactive, menu-driven CLI designed for BusyBox environments
- 🧭 Consistent navigation with support for submenus, back, and exit
- 🔧 Router utilities commonly needed on GL.iNet devices
- 🪶 Lightweight shell script (POSIX `sh`, no bashisms)
- 📦 No external dependencies beyond standard OpenWrt tools
- 🛡️ Safe prompts and confirmations for potentially destructive actions
- 🔄 Designed to be easily extended with additional utilities
- 🧪 Tested on multiple GL.iNet routers running OpenWrt-based firmware
- 🆓 Licensed under GPLv3

---

## 🚀 Installation

1. SSH into your router:

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

## 🧭 Usage

When launched, the script presents an interactive menu system.  
Options may vary as new utilities are added, but generally include:

- System and service management helpers
- Feature enable/disable utilities
- Diagnostics and status checks
- Cleanup and maintenance actions

Navigation is intentionally simple and predictable:

- **Number keys** → perform actions  
- **`b`** → go back one menu  
- **`m`** → return to main menu  
- **`q`** → quit the script  
- **`?` / `h`** → help (where available)

---

## 🧠 Design Philosophy

This script is built with OpenWrt realities in mind:

- Works over **SSH, serial consoles, and limited terminals**
- ASCII-safe output (no reliance on Unicode or emojis for input)
- Defensive coding to avoid bricking or misconfiguring devices
- Emphasis on clarity over cleverness

If you’ve ever SSH’d into a router at 2am, this script is for you.

---

## 🧹 Updating

To update to the latest version, simply re-download the script:

```
wget -O glinet_utils.sh https://raw.githubusercontent.com/phantasm22/GL-iNet_utils/main/glinet_utils.sh
chmod +x glinet_utils.sh
```

---

## 🧑 Author

**phantasm22**

Contributions, suggestions, and pull requests are welcome.  
If you have a utility you run on every GL.iNet router you touch, it probably belongs here.

---

## 📜 License

This project is licensed under the **GNU GPL v3.0 License**.  
See the [LICENSE](https://www.gnu.org/licenses/gpl-3.0.en.html) file for details.
