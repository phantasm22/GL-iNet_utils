# Changelog

All notable changes to the GL.iNet Utilities toolkit. Newest first. Versions
match the `# Version:` line in the script — `YYYY-MM-DD`, or `YYYY-MM-DD_HH:MM`
for multiple releases on the same day.

## 2026-11-10_13:01
### Bug Fixes
#### Firmware Update
- Stopping an update before the flash (Stop on the Admin Panel page, or Ctrl-C in the menu) left the
  downloaded image filling memory and its Update History entry at STARTED; the image is removed and the
  entry reads CANCELLED.

#### Admin Panel Page
- A job's log could point to menu option numbers the page doesn't have ("Detect or set it first
  (option 2)", "choose Optimize Tunnel (option 1)"); the page leaves the numbers out.
- Stopping a job could leave one more progress line under [stopped] ("Downloading the firmware 11% of
  35 MB"); the log ends where the job stopped.

## 2026-11-10
### What's New
#### Toolkit-wide
- Messages that send you to a menu item say what to do and add its option number: "install first
  (option 1)", "Manage Persistence (option 3) keeps them". An item on another screen is named by its
  path instead: "AdGuardHome Control Center → Recover Configuration". Help names items rather than
  numbering them.

### Bug Fixes
#### Firmware Update
- On a channel GL.iNet publishes no builds for (a Flint 3 on Beta), Update showed UNKNOWN (offline);
  it shows NONE (no beta builds) now, and Check for Updates points to Choose a Build.
- After an update, packages set to persist could fail to come back when the router missed one of GL.iNet's
  package feeds while starting up (zram-swap couldn't find kmod-zram on a Flint 3); the re-install now
  waits until every feed has been read.
- Older builds in Choose a Build (menu and Admin Panel page) show their real release tag: GL's older file
  names run the release number into the version's digits, so 4.3.26 showed as "release10326" instead of
  "release1" (Mudi, Spitz, Spitz AX, Puli, Puli AX, Cirrus).

#### Switch Position Indicator
- Help quoted option numbers that change with the indicator's state; it names the items now.

#### Admin Panel Page
- AdGuardHome messages in a job's log pointed to "item 1" of a menu the page doesn't have; they name
  the Control Center item now.
- A click could fail with "The router didn't answer - Load failed" when the browser reused a connection
  the router had just closed; the page now tries once more where that's safe (loading, reading, starting
  a job) and otherwise says the connection dropped.
- A progress line in a job's log could show a stale reading glued to the finished line ("Downloading the
  firmware 54% of 103 MB - Downloading the firmware"); progress now updates in place and the log keeps
  only the finished line.

## 2026-10-23
### Bug Fixes
#### Hardware Information
- Network Interfaces lists the LAN port on routers with a Qualcomm packet engine but no switch ports
  behind it (a Slate 7 showed only WAN), and no longer lists virtual interfaces such as bond0 as ports.

## 2026-10-22
### What's New
#### Toolkit-wide
- **Status notices**: anything that needs attention - a risk, something missing, something to do - is now
  one notice at the top of what it's about: under the screen title in the menus; at the top of its card,
  or above the cards, on the Admin Panel page (with a warning, error or info icon). Each opens with the
  name of the row it explains ("AdGuardHome Persistence is off: ..."). Status rows keep the value and a
  short fact in brackets; what a value means is in the screen's help, as a short glossary.
- Times of day show the router's timezone (2026-10-20 17:41 EDT).

#### Firmware Update
- Update and Checked are separate rows, as are Last Update and Attempted. Not Persisted shows how many
  items a firmware update will remove; menu item 3 Manage Persistence (on the page, the Packages tab)
  lists them and keeps them.

#### VPN MTU Optimizer
- A probed MTU shows when it was probed and against what (Probed and Target, under Basis).

#### Hardware Information
- Network Interfaces names a second WAN (GL's secondwan - the Flint 4's WAN/LAN1, or a LAN port switched
  to WAN) as WAN2, and lists an address line for each WAN; with more than one internet connection,
  "active" marks the one in use. A tethered phone or USB adapter gets its own Tethering line.

### Bug Fixes
#### Hardware Information
- Network Interfaces lists the WAN port on routers whose firmware has no GL port map (a Flint 2 on
  4.9.1-op25 or 4.8.3 showed LAN1-LAN5 and no WAN): only the CPU's internal link to the switch is left
  out now, and a USB network device is no longer listed as a port.

#### Toolkit Management
- Switch to Installed Version now takes this copy's settings with it - the startup-offer answers, the
  display mode and the keycap spacing - so the installed copy doesn't ask them again, and removing the
  local copy afterwards loses nothing. If they can't be copied, it says so and doesn't offer the removal.

#### Admin Panel Page
- Sub-rows are indented as in the menus (Version and Update under Channel, Probed and Target under Basis,
  State under the switch's function).
- The "not on this model" messages (fan, toggle switch, filter space limit, AdGuardHome) sit at the top
  of their card instead of above the tabs or at the bottom of the card.
- Firmware Update no longer leaves a stray line ("its config") at the bottom of its Status card.

#### Toolkit-wide
- Persistence reads a plain ENABLED / DISABLED on the fan and Bandwidth Limiter screens too, in the
  menus and on the Admin Panel page - the extra "(survives firmware upgrades)" notes are gone; the help
  explains it.
- System Configuration shows GoodCloud's Status as NOT SET when it isn't set up (the menu printed a
  warning instead).
- 0 on a yes/no question now cancels: it used to count as Yes on [Y/n] questions. Where No goes on to
  another step - wiping settings, enabling without a login, this session only - 0 stops and changes
  nothing.
- Messages, notices and help say what will happen ("a firmware update will restore ..."), not what
  would - "would" is kept for what doesn't happen (a skipped or refused step).
- In the Admin Panel's Web Terminal on ttyd 1.6.3, the warning, info and gear icons no longer touch the
  words after them.

## 2026-10-19
### What's New
#### Toolkit Management
- **Reset Toolkit Settings** (item 5) starts the toolkit's own settings over in every copy on the router,
  then restarts the toolkit so the startup questions are asked straight away and the display is detected
  again. What the toolkit set up on the router is left alone. Enable / Disable Admin Panel Page moves to
  item 6.
- **Switch to Installed Version**: run from another copy while the toolkit is installed, item 1 now
  switches to the installed copy (asking first when the two are different versions - the installed
  copy then offers its update as it starts). Uninstall is offered in the installed copy, the one it
  removes.
- **One toolkit on the router**: after installing as a system command, or switching to the installed
  copy, the toolkit offers to remove the copy it came from - the installed copy keeps its settings.
  Copies in /tmp or a git checkout are kept.

### Bug Fixes
#### Admin Panel Page
- Disabling the Admin Panel page (in Toolkit Management or on the page itself) said it "could not be
  removed completely" every time. The page was gone; the check after it took GL.iNet's own Admin Panel,
  which answers in its place, for the toolkit's page. It now looks for the toolkit's page itself.
- Disabled from the page, it now goes to the Admin Panel's home - the Router Toolkit menu goes too -
  instead of staying on a page that no longer exists.
- A page left open while it's disabled in a terminal now says it was turned off, with a link back to
  the Admin Panel, instead of failing on every click.
- After the page is turned off, Back from the Admin Panel's home no longer returns to the toolkit page
  that just went away.
- The sidebar entry for AdGuardHome reads "AGH Control Center", so it fits on one line like the
  others; the full name wrapped and crowded the entries around it. Its page keeps the full name.
- Allow/Blocklists and Packages: toggling a row no longer nudges the columns sideways. The Planned
  Action column now keeps the width of its longest wording from the start.
- Turning the page off - in Toolkit Management or on the page - counts as a "no" to the startup offer in
  every copy of the toolkit, so the next start doesn't offer it back (until the next update).

#### Toolkit Management
- The screen paused about 5 seconds before drawing the Admin Panel row while the page was on. The check
  for the page waited out its download timeout instead of reading the answer; it now takes a moment.

#### OpenSpeedTest Server
- Install now asks for the download source before installing anything. Cancelling there used to say
  nothing had changed while leaving NGINX, unzip and wget installed.

#### System Benchmarks
- The leaderboards' comparison column reads "vs this router" (it was "vs yours"), in the menus and on
  the Admin Panel page, and each menu table explains its marker: "> = this router". The help no longer
  claims Disk and Memory compare against a fixed Beryl 7 - every leaderboard compares against the router
  it runs on.

#### Toolkit-wide
- Declining a question now says "No change" everywhere (it said "Cancelled - nothing changed" in some
  places and "No change" in others), naming what stays where that matters ("No change - HW acceleration
  left on").
- Messages and the Admin Panel page's screen text no longer address the reader as "you" / "your" ("The SSH
  keys would then be lost", "check the internet connection"); menu paths in messages all use "→".

- Process, fan, temperature and AdGuardHome update checks no longer print a stray "can't open ..." line
  when a file vanishes mid-check (a process exiting during a scan, an update check that couldn't run).
- Toolkit Management's "Running from" no longer shows a stray "./" when the toolkit was started as
  ./glinet_utils.sh.
- Startup: the Admin Panel offer and the after-update firmware report each sit in their own block, one
  blank line apart from the update check and from each other, instead of directly under it.

## 2026-10-18
### What's New
#### Admin Panel Page
- **The toolkit lives in GL.iNet's Admin Panel.** A ROUTER TOOLKIT group in the left menu mirrors the
  main menu - Hardware Information, AdGuardHome Control Center, System Tweaks, System Benchmarks, Network
  and VPN Tools and System Configuration - each screen's sub-screens as tabs at the top, drawn the GL way
  (its cards, colours, light and dark themes, phone layout). Same words, states and checks as the menus:
  both read the same functions.
- Turn it on or off in Toolkit Management (Enable/Disable Admin Panel Page). A one-time offer at startup;
  "no" isn't asked again until the next update. It survives firmware updates when persistence is on.
- Hardware Information refreshes once a second, like the menu screen, with Reveal for the full IDs.
- Choices are made the web way, never typed into a terminal: on/off switches in place of pick lists
  (Allow/Blocklists, Packages, Features - with the menu's planned actions, Memory Impact and Storage
  projection updating as you toggle, and one Apply), check boxes and drop-downs in the confirm dialog
  (AdGuardHome backups, Direct UI Access logins, updates and channels, Package Repair), and rows picked
  in place (firmware builds). Everything a menu asks along the way is answered up front in that dialog.
- Long work - benchmarks, installs, the iPerf3 server, AdGuardHome's live log - runs in the background.
  Its Log stays minimized to one line with its state (RUNNING, DONE, NO CHANGE, FAILED) and opens
  when you want it, when it fails or when it needs you; the screen itself shows the result. A finished
  benchmark shows its results as tables - the leaderboards with bars and this router marked - and the
  Ookla speed test as Download / Upload / Latency / Packet Loss tiles.
- A benchmark's results say when it ran ("Last Run" with the date and time), and a finished job's Log
  line reads "<action> · finished <date> <time> <zone>" by the router's clock.
- System Configuration shows networks, DHCP pools (each with its subnet and the addresses it hands out),
  firewall zones and rules, VPN servers and clients, and cloud services as tables and status rows, like
  Wireless Networks and System Settings.
- Lists are acted on in place: tick the SSH keys or backups to delete (all / none in the header), tick
  one backup to restore, pick the network in the Bandwidth Limiter's table - its dialogs open with that
  network's current values, and buttons that don't apply to it stay disabled.
- Tabs that don't fit show arrows at the edges to scroll the rest into view.
- Refreshing the browser keeps you on the tab you were on; opening a screen from GL's menu still starts
  on its first tab.
- A tab you click is selected at once and waits under the spinner while it reads the router; clicking
  another meanwhile shows the last one you chose.
- Dialogs use GL's own controls: its drop-down (the toggle function lists every choice, VPN and Wi-Fi
  under headings, and opens on the current one) and its switch for every yes/no, in GL's colour; tick
  boxes are only for picking rows in a table, and a picked row takes GL's selection tint.
- A dialog that changes a setting opens on the current values and its button waits until something
  differs, like GL's own Apply - applying nothing no longer reloads the network or restarts Wi-Fi.
- Faster without cutting corners: each page request skips reading the whole toolkit just for its version
  (about a third quicker on MIPS routers), and a screen's Help comes in one request kept for the browser
  session - it's read again whenever the toolkit changes.
- Number fields pair GL's slider with a - / + box, as on GL's own Display settings: the slider gets
  you close, the box and - / + are exact. The Bandwidth Limiter's slider gives half its width to
  0-1,000 Mbps, where most limits are, and Set MTU Manually snaps to the Recommended MTU's tick.
- Help on every tab is the menu screen's own help. Help, release notes and the Change Log open in GL's
  own dialog style over the page, with headings and lists; so do the confirmations and their choices.
- Firmware Update on the page: the builds GL.iNet publishes for the router - pick one in the table, read
  its release notes, and Install Selected Build runs the toolkit's own update (memory check, checksum,
  signature and image test) with its choices - keep or erase settings, persist what's at risk, free
  memory - set in the dialog. The page waits through the reboot, reconnects, and shows the result.
- Remote LAN Access on the page: each tunnel's ends and its Outbound/Inbound reachability, measured live.
  Set the remote LAN's subnet or detect it; the levers (routing, inbound access, masquerade) run the
  menu's own steps, so a risky change still reverts by itself unless you press Yes within 30 seconds.
- Not on the page (terminal only): the toolkit's display settings.
- AdGuardHome's Status tab shows every status row the menu does - update, persistence, lists, storage and
  backups too - from the same list. Firmware Update has View Update History (each attempt, newest first,
  read live), and the Packages table sorts by Package or Size like the menu's [S] Sort.

#### AdGuardHome
- Direct UI Access says the same on both sides: Disable Direct Access, Set / Change Web UI Login, Remove
  Web UI Login (offered only while a login is set), and a "Web UI Login: SET / NOT SET" status (yellow
  while the dashboard is open to the LAN). The menu screen shows the Direct URL too.
- Storage lists each directory on one line - "4.4M used (56.5G free, 57.9G total)" - in the menu and on
  the page, with the Status screen's storage rows in the same order. "Used" is the directory itself (it
  was everything on its disk); free and total are its disk's, or the Filter Space Limit's when it's on.
- Status rows put the detail in brackets: "Filter storage: 4.2M used (56.5G free)". Backup & Recovery
  shows its backups on one line: "Backups: 2 (0.01M used, 56.5G free)".

#### Package & Persistence Manager
- Opens faster on firmware that uses apk (OpenWrt 25): every package's size comes from one apk call
  instead of one each - the same sizes, 12 s down to 8 s on an MT3000.

#### Firmware Update
- Choose a Build says what a build means from where you are: Update or Downgrade within your own channel,
  Install for a build in another channel (whether that's up or down depends on your point of view), and
  Reinstall for the installed build picked again. An older build in another channel still warns that
  settings made on newer firmware may not carry back. On the page, Planned Action follows your pick,
  as in the menu.
- On the page, builds are grouped by channel under headings, like the Allow/Blocklists sections, with
  yours marked. Keep Settings is GL's own switch - turned off, it says plainly that every setting is
  erased.
- The Update status says when GL.iNet's list was checked: "UP TO DATE (checked 2026-10-15 14:02)".
- When an update won't fit in memory, the services in the way (AdGuardHome, Tailscale, ...) are stopped
  without asking, each named with the memory stopping it frees. They start again with the reboot, or
  straight away if the update ends early - now including Ctrl-C and Stop on the page.
- On routers with zram swap (the Mango 2), an update now keeps 6 MB of memory spare. Tested on 60+ real
  flashes: with under 2 MB to spare about a third rebooted without installing, while stopping services
  before the download prevented every failure. Under 6 MB the meter says "tight" and services are stopped
  before the download; under 4 MB it won't fit. If you're connected through Tailscale (so it can't be
  stopped), a tight update asks first. Routers without swap keep the old limit.

#### OpenSpeedTest
- Diagnostics moved after Persistence in the menu (lifecycle actions, then Persistence, then extras), as
  on the page.

#### Remote LAN Access
- The menu's actions use the page's words in Title Case and GL.iNet's own name for masquerading:
  Enable / Disable IP Masquerading (the menu keeps its plain-English outcome alongside) and Detect or Set
  the Remote LAN.

#### Bandwidth Limiter
- The menu and the page offer the same actions for each network, from one shared list: a VLAN network can
  be brought up or down on the page too (it was menu-only), a switched-off network is brought up before
  limits are set, and Check Router Access is on the page.
- The Wi-Fi Bands grid says up front that applying restarts Wi-Fi - devices may disconnect briefly.
- On the page, Bring Interface Up / Down is one button for every network that can be switched, as in the
  menu: guest and iot get a switch per Wi-Fi band, a VLAN network one switch for the whole interface.
- lan is described as "wired + main Wi-Fi": the main SSIDs are bridged into it, so its limit covers both.
- Confirming the Wi-Fi Bands grid with nothing changed applies nothing (it restarted Wi-Fi for nothing).

#### System Configuration
- Wireless Networks labels GL.iNet's mesh interfaces (Role: Mesh backhaul / Mesh uplink) - they show a
  placeholder name such as "gl-mesh-bh-" and stay off until mesh is set up.
- DHCP Pools show each pool's subnet and the addresses it hands out (192.168.8.100 - 192.168.8.249)
  instead of "start=100 limit=150" - a VLAN or guest network has its own subnet, so the numbers alone
  said little.

### Bug Fixes
#### Admin Panel Page
- On iPad and iPhone a long dialog (Help, Update History, release notes) ran off the top and bottom of
  the screen behind Safari's bars, cutting off its title and Close; it now fits what you can see.
- A dialog opened with a tap no longer rings its button with a keyboard-focus outline (Safari did on the
  first open after a refresh). Enter still presses it; the ring returns once you use the keyboard.
- Tab and Shift+Tab stay inside an open dialog (they moved on to GL's page behind it).
- The tab row scrolls only sideways: on iPad a finger could drag the tabs up or down out of the row.

#### Toolkit-wide
- The startup install offer remembers "no" until the next update (it asked on every run).
- Recent Termius versions were taken for Windows Terminal (they now measure emoji like it) and showed ❶
  keycaps; they're recognised again and get the 1️⃣ keycaps they draw cleanly.

#### AdGuardHome
- Backup & Recovery's free space is the backup store's own disk (it showed AdGuardHome's working
  directory's, which differs when that directory is on another drive).

#### Remote LAN Access
- With IP Masquerading off, the outbound table pointed to option 2 to hide devices behind the tunnel;
  it's option 3 (IP Masquerading).

#### Zram Swap
- "Disk Size" is now "Swap Capacity" - zram swap lives in compressed RAM and uses no disk.

## 2026-10-05
### What's New
#### Benchmarks
- The Mango 2 (GL-MG1300) joins the VPN & Crypto, Disk I/O and Memory I/O leaderboards.
#### Firmware Update
- Choose a Build shows the installed build as **Installed** under Planned Action instead of tagging its
  version, so the Version column lines up and is only as wide as the longest build.
#### Toolkit Management
- Display Settings spells out "Windows Terminal" (it said "WT").
- Saving Auto in Display Settings clears the saved keycap spacing, so the next start in macOS Terminal
  asks again (once saved, it couldn't be unset). Cancelling the picker keeps this session's spacing.
- The Change Log reads like the rest of the toolkit: versions in cyan, What's New / Bug Fixes in lilac,
  each feature with its changes indented under it, and a page never ends on a heading. Long lines wrap
  between words instead of breaking mid-word.

### Bug Fixes
#### AdGuardHome
- **The firmware-update warning for AdGuardHome no longer goes stale.** Whether GL.iNet's own build can
  read config.yaml was remembered per session, but the check that the file had changed used a tool
  GL.iNet's firmware doesn't have, so after switching to Beta (which upgrades config.yaml) the
  Persistence row, Firmware Update's Not Persisted list and Reinstall AdGuardHome could all go on the
  old answer.
- The Filter Storage Space Limit help no longer shows raw `**` formatting.
- On a router whose firmware has no AdGuardHome, the Control Center opens and says so (NOT SUPPORTED)
  with Back, instead of an error on the main menu - and startup no longer stops to announce it. If its
  startup script is missing, it shows MISSING and offers Reset to Factory Settings to restore it.
  The Control Center help explains both.
#### Bandwidth Limiter
- The network list's divider spans the widest row (it was one column short).
#### Fan Control
- The fanless-hardware message follows the message style (no trailing period).
#### Firmware Update
- View Update History wraps long lines (package lists) between words, under their value.
#### Package and Persistence Manager
- The dividers span a row staged as "Enable Persistence (via reinstall)" (it ran past them).
#### SSH Key Management
- Manage / Delete Keys has one blank line under the title, like every other screen (there were two).
#### Switch Position Indicator
- "Set Toggle Button Function" is in Title Case like every other menu item.
#### System Configuration Viewer
- VPN Configuration shows a spinner while it reads, and no longer waits ~2 s on a Tailscale service
  that isn't running.
#### Toolkit Management
- The keycap spacing picker takes 1, 2 or 0 then Enter; a stray key or a bare Enter asks again instead
  of quietly picking Option 2. Its prompt has a blank line above it, like every other Choose prompt.
- The Change Log viewer has one blank line under the title (there were two).
#### VPN MTU Optimizer
- One blank line under the title, like every other screen (there were two).
- Its help describes Status as the screen shows it: CONNECTED / DISCONNECTED for a client, UP / DOWN
  for a server, with the last handshake or "no peer".
#### Toolkit-wide
- Help pages and paged views end with one blank line above [0] Back. Five help pages (Network and VPN
  Tools, VPN MTU Optimizer, Remote LAN Access, Direct UI Access, Package and Persistence Manager) and
  the VPN Configuration view had two.
- Two help pages (Bandwidth Limiter, Firmware Update) had a line wider than the window that wrapped
  mid-word; they're re-flowed.
- Temporary files from a session are removed when the toolkit exits, and ones left by a session that
  ended abnormally are cleared at the next start.

## 2026-10-03
### What's New
#### Firmware Update
- **Firmware Update (System Tweaks ▸ 8).** Update the router's firmware from GL.iNet's own
  download catalogue, with the same safety checks as GL.iNet's web interface plus several more.
  - **STATUS** shows the model, the firmware **Channel** (STABLE, BETA, NIGHTLY, RC, OPENWRT 25,
    OPENWRT 24) with its **Version** and **Update** state, **Not Persisted** (what an update would NOT
    keep, measured from the router's own keep list) and the **Last Update** result.
  - **Update to <build> / Check for Updates**, **Choose a Build**, **Manage Persistence** and **View
    Update History**. Choose a Build lists every build GL.iNet offers the router on one paged screen,
    grouped by channel: the installed build starts selected, [#] picks another (an older one is a
    downgrade), [R] shows its release notes, and picking the installed build again re-flashes it
    (Reinstall - for a damaged firmware partition; persisted packages are re-installed afterwards too).
  - **Keep settings is the default**; wiping lists everything that goes and asks a second time.
  - Before flashing it lists what may not survive the update: the toolkit itself, its features and settings
    (Web Terminal, fan, switch indicator, limits, OpenSpeedTest, an updated AdGuardHome, SSH keys,
    backups) and Package Manager packages not set to persist (including ones the current firmware came
    with - the next one may not) - then offers to persist them, opening the
    Package & Persistence Manager with exactly those staged. GL.iNet's own add-ons, and helpers the toolkit
    re-installs by itself, aren't listed.
  - **Update Memory meter.** The image and the kept files both sit in RAM during a flash, and running
    services count against it. The meter shows the fit (amber cells when it's close, "won't fit" in red)
    against a red line measured on real flashes (a Mango 2 with Tailscale running flashes fine close to
    the limit). What persists is measured for real (the same archive the flash packs), started in the
    background when Firmware Update opens and remembered until what persists changes - so it's usually
    ready before you need it. When it won't fit it
    offers to stop services such as Tailscale or AdGuardHome, which start again with the reboot - or
    straight away if the update doesn't happen; if it still won't fit, the update stops before downloading.
  - A dropped SSH or Web-UI Terminal session can no longer abort the flash at the hand-off, and an
    attempt that never flashed frees its image from memory.
  - Every step is checked before the next (memory, download, checksum, signature, image test). Then it
    shows what happens next, asks to flash and counts down 10 seconds (Enter starts now, any other key
    cancels). In the Web-UI Terminal it warns first and says whether the terminal comes back. It offers
    to keep the toolkit itself across the update.
  - **After the update**, the next start checks the router against what was true before: SSH keys,
    AdGuardHome, bandwidth limits, zram, the fan's static speed, re-installed packages, and each package
    that wasn't persisted (did it come back or not), and Web-UI tweaks. Each one reads OK, ISSUE (with
    where to fix it), PENDING (still coming back, checked again later) or REMOVED. If the persistence
    service missed the update, the next start runs it and says so. Every attempt, cancelled or failed
    ones too, is kept in View Update History.
- After a firmware update, a package that couldn't be re-installed says why (the new firmware's feed
  doesn't offer it, or it failed to install), and programs kept as files are checked to still run.

#### Package and Persistence Manager
- **Package & Persistence Manager: one place for what survives an update.** A new Features page
  lists the toolkit itself, the Web Terminal, fan settings, the switch indicator, bandwidth limits,
  OpenSpeedTest, an updated AdGuardHome, SSH keys and backups - each toggling the same setting as its own
  screen. A Persist line shows how much an update carries, and Storage shows the free space - both as they
  will be once you Confirm, the way the AdGuardHome meter shows a change live. A package persisted by
  re-installing says "(via reinstall)": only its settings are carried, so it barely moves Persist. The
  help now explains persistence correctly (it's about firmware updates, not reboots).
- **The Package & Persistence Manager is two pages** (Packages, then Features) so it fits a
  normal terminal: [N] Next / [P] Previous, and only the numbers on screen are accepted. [A] All and
  [Z] None (it was [N], which is now Next) act on the current page - All on Packages marks everything to
  install and persist in one key. [S] Sort works on both pages. Package sizes are measured once per
  session, so opening it again takes about 2 seconds instead of 7-8. The page line sits just above the
  prompt, with the actions above it, the same order as every other paged screen.
- **Persisting a package now means re-installing it, with its settings kept.** Keeping a program's file
  across a firmware update broke when the new firmware changed libraries (four of nine tools stopped
  running in testing), so every package the firmware's feed offers is re-installed after an update,
  built for that firmware, while its settings files are kept (e.g. Tailscale's login). Only the Ookla
  speedtest and speedtest-go, which no feed offers, are still kept as files. A service you had switched
  off stays off after the re-install. Existing setups are moved over automatically.
- **stress is one tool** in the Package Manager: its engine follows the kernel (the stress package below
  6.6, stress-ng from 6.6 - stress-ng can crash older kernels), shown as "stress (stress-ng)" when that's
  the engine. It's persisted by re-installing, so a firmware update that crosses 6.6 switches the engine.

#### OpenSpeedTest Server
- **OpenSpeedTest is kept whole across firmware updates**, and if a new firmware doesn't include nginx
  (which serves it) nginx is re-installed afterwards and OpenSpeedTest started again. Restarting
  OpenSpeedTest no longer fails with "port 8888 already in use".

#### AdGuardHome
- **AdGuardHome Lists Manager works while AdGuardHome is off.** A warning at the top says what happens:
  if it's SERVICE DOWN, Confirm applies the lists and starts it (and if it won't start with a heavy
  selection, points at memory as the likely cause); if it's DISABLED, Confirm asks whether to enable it,
  or just saves the lists for later. The Memory Impact meter stays; the "lists downloading" line no
  longer shows while nothing can download.

#### Toolkit-wide
- **Section headings are lilac** (they were a yellow-green that looked like the warning colour on some
  terminals), and headings inside a table are one word so they never read as a column label: the
  Lists Manager's "Your Other Lists" is now "Other". Display Settings says [P] Previous like every
  other pager.

### Bug Fixes
#### Persistence
- **Persisted packages now really come back after a firmware update.** Packages set to persist
  in the Package and Persistence Manager (zram, LibreSpeed, Tailscale…) relied on a one-shot hook that
  ran at the next reboot of any kind and then deleted itself. It was never kept by an update, and it ran
  before the network was up. Re-installing now belongs to the toolkit's persistence service: it's kept
  from the moment you persist a package, waits for the network after an update, re-installs what's
  missing, and reports each package on the next launch.
- The persistence service no longer depends on the toolkit file being executable, and reports a fan
  held at its static speed separately from the fan's Web-UI tweak.

#### Package and Persistence Manager
- **A package's Size includes what it pulls in.** A not-installed package now counts the dependencies
  it would install (Tailscale was shown as 3.4M on an MT1300; with tailscaled it's 9.6M), so the Storage
  line and the install's free-space check are honest about the space it needs.
- Removing a package from the re-install list now removes that exact name only.

#### Bandwidth Limiter
- **Bandwidth limits survive reboots.** On newer firmware the network comes up after the limiter
  started, and some firmware services clear interface queues later in boot, so limits could silently
  disappear. Limits are now re-applied whenever their interface comes up, and checked every minute (only
  missing ones are re-applied, and each repair is logged). Persisted limits also come back after a
  firmware update. Thanks again to mikeyjmatthews.

#### Fan Control
- **A static fan speed survives reboots.** Setting a static speed used to last only until the
  next boot. It's now stored and held at boot ("kept across reboots"), and Enable Dynamic Fan Control
  undoes it. GL's fan controller is now fully stopped before the speed is set (it used to overwrite the
  speed while shutting down), and with fan persistence on the speed also survives firmware updates. Fan
  persistence (for firmware updates) now accepts a static speed instead of asking you to
  set a value you already had. The screen spells out what persistence means: reboot-safe either way; this
  is about firmware upgrades.

#### AdGuardHome
- **Adding lists to a factory-fresh AdGuardHome config broke it.** GL.iNet's factory config.yaml
  lays out its lists differently from AdGuardHome's own files, and adding a list produced a file
  AdGuardHome refused to start with (the previous config was put back, so nothing was lost). The lists
  section is now brought to one layout before any change.

#### Toolkit-wide
- Long messages break between words onto an indented second line instead of wrapping mid-word, lists
  inside a message (the services an update would stop) line up under the first item, and release
  notes indent a wrapped bullet under its text.
- "Press any key" now takes any key on terminals without stty (it needed Enter).

## 2026-09-26_21:20
### What's New
#### AdGuardHome
- **AdGuardHome updates from the toolkit.** Updates & Channel now shows the installed Version and an
  Update line (UP TO DATE, or AVAILABLE with the newer version) under the Channel, on both Stable and
  Beta; the Control Center shows the same. A new option updates AdGuardHome to the newest build of its
  channel using AdGuardHome's own updater - config.yaml is backed up first, AdGuardHome restarts on the
  new version, and the result is checked - or checks again when there's no update. It checks free space
  first (allowing for flash that compresses, like the MT3000's), and if an update stops part-way the
  previous version is put back. "UI Updates" is now called **Updates via UI**, and the help explains
  what it and the channels actually do.
- **Switch AdGuardHome between the Stable and Beta channels** (Advanced Settings ▸ Updates &
  Channel). Beta installs AdGuard's pre-release build; config.yaml is backed up first, and switching
  back to Stable restores GL.iNet's build and that backup (Beta upgrades config.yaml to a format
  GL.iNet's build can't read). You're offered update persistence so a firmware update doesn't strand
  the Beta build.
- **Safer AdGuardHome channel switches, updates and restores.** Switching to Stable now installs
  AdGuard's current stable release and **keeps your config.yaml** (it used to put back an older backup
  and drop your changes); the new build is checked against config.yaml first, and nothing changes if it
  can't read it. If a new version won't start, the exact previous version and config are put back
  automatically. When a firmware update would leave AdGuardHome unable to start (GL.iNet's build can't
  read a newer config.yaml), the Persistence row turns yellow and you're offered persistence. Backups now
  record the version, channel and config schema they were taken on and show them in the restore list;
  a restore is checked first, and a backup taken on GL.iNet's build can bring that build back from
  /rom at no storage cost. If AdGuardHome is down because its build can't read config.yaml (e.g. after
  a firmware update), the Control Center offers **Reinstall AdGuardHome**.
- **The AdGuardHome service control is now a clean Enable/Disable toggle.** Item 1 of the Control
  Center used to be a compound "Restart / Stop AdGuardHome" that opened a second prompt — "⚠ Service
  is RUNNING / Disable, Restart, or Cancel? [D/R/0]" — which put a warning glyph on a perfectly
  healthy service and made you choose an action twice (a menu wearing a confirmation's clothes). It's
  now a single item whose label follows state: **Enable AdGuardHome** when stopped, **Disable
  AdGuardHome** when running. Enabling just acts; disabling asks once (it takes LAN DNS filtering
  down). The four destinations below it (Manage Lists, Advanced, Backup, Logs) keep fixed numbers.
- **AdGuardHome: item 1 now matches what's wrong.** It reads **Recover Configuration** when config.yaml
  is missing (restore a backup, or reset to factory defaults if there's none) and **Restart
  AdGuardHome** when the service is switched on but not running, instead of an Enable/Disable that
  couldn't fix either.
- **Restart moved to Logs & Maintenance**, where it belongs — it's an operational bounce (reload
  config.yaml / clear a wedge), not a lifecycle state change. It keeps a **fixed menu slot** (Watch=1,
  Clear=2, Restart=3 — numbers never shift): while running it restarts and verifies the service came
  back up; while the service is disabled it doesn't vanish or silently turn into Enable — it points
  you to the Control Center toggle (item 1). This locks in a new "hub menus keep fixed item numbers"
  standard: a state-dependent item holds its slot and explains itself in place rather than disappearing.
- **AdGuardHome Control Center: status reads like every other screen.** The status area is now one
  STATUS list — one fact per row, in the same coloured words the rest of the toolkit uses
  (**ENABLED** / **DISABLED** / **SERVICE DOWN**, **OK** / **MISSING**) — instead of four small blocks of
  dot-separated values. It adds the dashboard's full address (with its real port) when Direct UI
  Access is on, and the release channel. The Direct UI Access, Updates & Channel, and Backup & Recovery
  screens follow the same layout and words.
- **AdGuardHome Control Center now warns when its config is missing.** If `config.yaml` is gone while
  AdGuardHome is still running off already-loaded filter files, the Control Center used to look healthy
  (Run: ✅) and show a contradictory "Lists: 0 · Rules: N" — with no hint the Lists Manager would fail
  with "Config not found". It now shows **Config: MISSING** in the status block and an honest
  "unknown — config.yaml missing" for filters, so a broken config is visible at a glance.
- **AdGuardHome backups are counted and kept tidy.** The status shows how many backups you have (not a
  file count), the temporary safety copies taken while changing Direct UI Access, credentials or lists are
  removed once the change is confirmed instead of piling up in the backup store, and the Restore and
  Cleanup lists now show every backup - including any leftover copy - so everything can be deleted.
- **AdGuardHome Lists Manager: applying changes shows every step.** Confirming now reads as one
  sequence — **Stopping AdGuardHome**, **Applying the list changes** (with a spinner, so removals on
  older hardware no longer look stalled), **Restarting AdGuardHome**, then **Downloading lists**, whose
  line now stays on screen with the result under it (**6 lists downloaded**). The misleading "Backup file
  created" line is gone — that copy is only an undo copy, removed once the change is settled. If lists
  can't fit in the filter storage, AdGuardHome is stopped before they're removed, and each outcome uses a
  plain count ("1 list still downloading", "2 lists failed to download (storage full) and will be
  removed").
- **AdGuardHome is really stopped before its files change.** Every flow that changes AdGuardHome's files
  (update, channel switch, restore, factory reset, list changes, credentials, Direct UI Access, storage
  limit) now waits until the process has actually exited - asking nicely first, then forcing it - and
  changes nothing if it can't. **Factory Reset** reads as one clean sequence, and the Backup Cleanup list
  shows each backup's Version, Channel and Schema like the restore list. Backup Creation and the restore
  picker use the standard [A] All / [N] None / [#] Toggle / [C] Confirm keys.

#### Bandwidth Limiter
- **Bandwidth Limiter network screen is easier to read.** Each band's UP/DOWN is coloured like the
  network's, an unset limit reads NO LIMIT instead of "-", the Router state word takes the colour of its
  dot (BLOCKED stays red, matching the network list), and the open-port list is easier to pick out.

#### System Configuration Viewer
- **System Configuration Viewer: every screen now pages, and there's more to see.** The config views
  used to print straight to the screen (with an ad-hoc pager on Wireless), so long output scrolled
  off. Each of the curated views now goes through the shared paged viewer — `[N]`/`[P]` to move, `[0]`
  to go back — and the extra room was put to use: **Network** now lists every interface (guest / IoT /
  VLANs, not just WAN+LAN) plus DHCP pools, **static leases**, static routes and DNS; **VPN** adds
  Tailscale and ZeroTier; **System** adds NTP, logging, LED, Dynamic DNS and the firmware channel. A
  new **Firewall** view shows the default policy, zones, forwardings, port forwards and traffic rules.
  Wi-Fi passwords are still shown (you own the router); VPN/OpenVPN private keys are never displayed
  (and a safety-net mask catches any stray base64 key). Verified live across the fleet.

#### Benchmarks
- **DNS Benchmark tidied:** a blank line now separates the check from the results, and the timings are
  shown in the value colour instead of switching between green and cyan at an arbitrary 15 ms.

#### Display Settings
- **Menu spacing: you now choose the gap after the numbered items.** A recent macOS update changed how
  Terminal *draws* the number-key emoji (it paints wider) without changing how far it *moves the
  cursor* — a difference invisible to every terminal query, so the toolkit can't detect it and the gap
  came out cramped on one macOS version and loose on another. It's now a deliberate choice instead of a
  guess: on the first launch in macOS Terminal a quick picker (Option 1 / Option 2) lets you pick the
  list whose numbers line up with the `?` Help line, and offers to save it as your default (or keep it
  just for this session). It only appears on genuine macOS Terminal — never on ttyd/web/Linux — so no
  other terminal is ever bothered by it.
- **New "WT" display mode** (Toolkit Management ▸ Display Settings) — full mode with **circled-digit
  keycaps** (`❶ ❷ ❸`) instead of emoji keycaps. These are single-cell glyphs with no per-macOS-version
  drift, so they need no spacing pick at all — a clean option for anyone who'd rather skip the keycap
  question entirely. The warning/info/gear symbols still adapt to whatever terminal you're on.

#### Switch Position Indicator
- Switch indicator help now notes Disable is offered in both ENABLED and SERVICE DOWN (it is the
  service-only feature's removal).

#### Toolkit-wide
- **Every download checks for free space first.** Package installs (Package Manager, Web Terminal, zram,
  LibreSpeed…), Ookla Speedtest, speedtest-go, the toolkit's own update, OpenSpeedTest and AdGuardHome all
  check - before changing anything - that there's room, allowing for flash that compresses. When there
  isn't, nothing is changed and you're told how much is needed; where it makes sense you're offered an
  alternative instead: OpenSpeedTest can go on a USB/SD drive, and a speed test can run from RAM for the
  session. A download that fails part-way no longer leaves a broken program behind. On a USB/SD drive,
  OpenSpeedTest only ever installs into - and uninstalls - a folder of its own, so a folder of yours that
  happens to be called "openspeedtest" is never written into or deleted.
- **No more dead-end menu items.** An option that would only say "nothing to do" now does something
  real: Package System Repair offers **Check for Package System Issues** when all is healthy (Repair Now
  when not), backup menus offer **Check for Backups** when none are saved, the MTU Optimizer offers
  **Recalculate Recommended MTU** when already optimal, and the Bandwidth Limiter offers **Check Router
  Access** when the firewall zone governs it - and each check shows its progress and says what it found
  ("No package system issues found", "Found 2 backups - choose Restore from a Backup"). Options that
  can't apply are left out rather than shown
  (Reset MTU with no override, Disable Limit with no limit - now the last item - and Delete with no
  backups). AdGuardHome's filter space limit is one Enable/Disable option, and on models where GL.iNet
  doesn't use it (e.g. the MT3000) the screen says so instead of offering options that do nothing.
- **Menus read consistently.** Every menu item is now in Title Case ("Enable Persistence", "Check for
  Updates", "Main Menu"), and the AdGuardHome Control Center shows **Persistence** - yellow when a
  firmware update would stop AdGuardHome.
- **Status colours now mean the same thing on every screen.** Red is only for something broken; a missing
  feature or piece of hardware (no fan, no switch, a CPU without AES) is grey, not red; and yellow now also
  flags a setting changed from GL's defaults in a way that could cause harm — no root password, SSH
  password or root login turned off (lockout risk), or a fan limit raised above the factory value (now
  shown with the factory number). Plain facts such as Wi-Fi passwords and file paths are no longer
  coloured, and the System Configuration Viewer's status words are now capitalised like everywhere else.
- **DISABLED now reads grey everywhere** (it was yellow): off-by-choice is a calm, inactive state, so it
  shares grey with NOT INSTALLED and "No Change", and yellow is kept for things actually worth a look.
- **Values are easier to pick out.** Plain facts — versions, sizes, speeds, temperatures, addresses,
  paths — now show in the same soft blue as info messages, so every "label: value" line has clear
  contrast while green stays reserved for "good". Hardware Information keeps its look but its values are
  blue now, with YES/FULL/UP still green; the Fan, Toolkit, AdGuardHome, zram, SSH keys, Bandwidth
  Limiter and System Configuration Viewer screens follow the same rule, and the benchmark tables mark
  "this device" in bold blue. The Bandwidth Limiter's network detail now colours its Status
  (ACTIVE/BYPASSED/INACTIVE) the same way the network list does.
- **Consistency pass on status words and colours.** "Unknown", "Up to date" and similar readings are
  now capitalised like every other status (UNKNOWN, UP TO DATE, AVAILABLE); an empty backup list reads
  NONE in grey everywhere; the AdGuardHome filter limit reads INACTIVE in grey; Display Settings shows
  the saved default in the value colour; the Bandwidth Limiter list colours its Persist column and
  limits; the Fan screen's control mode and the Switch indicator's details read more cleanly; and the
  self-update messages use the standard message style.
- **Failures now read the same everywhere, and always tell you why.** A single `fail_report` shape
  is used across every install / enable / service-start failure: the error, then (when there is one)
  the actual diagnostic — indented — then what to check, then a warning if partial state was left.
  Most importantly, a **failed package install now shows the real reason** (no MIPS build, a missing
  dependency, out of space, a feed error) instead of a bare "Failed to install X" — that output used
  to be thrown away. Same fix for the Ookla and speedtest-go fetches.
- **Broken services report their log inline.** Zram, LibreSpeed, the Switch indicator and AdGuardHome
  now show the last few relevant log lines on a failure instead of telling you to go run `logread`.
- **Every working step is a gear + spinner.** The last static "…ing" lines (AdGuardHome restart/start,
  backup creation, the DNS-benchmark pre-check) now use the spinner, and the two AdGuardHome restarts
  verify the service actually came up instead of assuming success.
- **Consistent message punctuation throughout.** Completed the single-sentence "no trailing period"
  pass across the remaining compound-line messages (case arms, `&&` chains, one-liners).
- **Startup messages stay readable.** Startup now ends with one final step, **Loading the main menu**.
  If anything was reported on the way (for example the keycap spacing you just saved), it holds for
  2 seconds before the menu clears the screen; a clean start passes straight through.

### Bug Fixes
#### AdGuardHome
- **Direct UI Access: fixed a way to end up with an open dashboard.** Enabling it asked twice whether to
  set a password, and backing out of the second question left the router switched to direct access
  without a login — silently, taking effect at the next restart. It now asks once, collects the login
  before changing anything, and backing out leaves Direct UI Access off.
- **Direct UI Access fixes:** a missing config.yaml no longer prints a stray `grep` error or claims a
  password is set — it shows UNKNOWN and points to Recover Configuration. Addresses now use the port
  AdGuardHome really listens on instead of assuming 3000. "UI Direct Access" / "Direct Web UI Access"
  are now consistently **Direct UI Access**.
- **The AdGuardHome "Memory Impact" meter no longer under-reports while lists download.** After an
  apply, AdGuardHome re-downloads filter lists asynchronously, so a big list it hadn't finished
  fetching read as 0 rules — the meter could tell you there was room when there wasn't. The meter now
  reads AdGuardHome's own download log (`logread`) to resolve any list whose file hasn't landed yet: a
  completed download contributes its real `rules_count`, a failed download counts 0, and one still in
  flight uses the catalog estimate, firming up to the exact count as each finishes. Under the meter, a
  short note says how many enabled lists are still downloading, and an error names any that failed
  (with "storage full" when that's the cause); a failed list shows **FAILED** in its Size column.
  Lists you've ticked but not confirmed yet raise no note — their "~" size already marks the estimate.
  The on-disk file stays the primary source, and if the log is unavailable or
  its format changes it falls back to the estimate — never the old under-count. Verified against real
  filter-download logs on the fleet (logged counts matched the on-disk files exactly).
- **The AdGuardHome Control Center no longer freezes when `config.yaml` is missing.** If the
  config file was absent (never set up, or moved), the status screen's list/rule counters ran `awk`
  and `cat` with an empty file argument, which silently reads the terminal and hangs forever on a real
  TTY (invisible to piped tests). The counters now guard the file (`[ -f ]` + `</dev/null`) and use
  `find -exec cat {} +` instead of `| xargs cat`, so a missing config shows zero counts instead of
  hanging. The AdGuardHome list edit/delete helpers got the same `</dev/null` guard.

#### Bandwidth Limiter
- **Bandwidth Limiter: guest / IoT networks fed by a VLAN port are no longer shown as DOWN.** Their
  state used to come only from their Wi-Fi SSIDs, so a guest or IoT network carried on a tagged VLAN
  port (e.g. to a VLAN-aware access point) with its SSIDs off read **DOWN** and offered no limits. The
  wired / VLAN ports on the network's bridge now count: the network reads **UP**, its ports are listed
  under If-State as **Wired/VLAN**, and switching all of its Wi-Fi bands off no longer takes the ports
  down with them. Thanks to mikeyjmatthews for the report.
- **Bandwidth Limiter: bringing interfaces up or down now checks they really did.** It used to report
  success once the setting was saved, even if a Wi-Fi band stayed down. It now waits for each band (or
  the network) to reach the chosen state and, if one doesn't, says which band and what state it's in.
- **Bandwidth Limiter: fixed networks showing a limit that wasn't there.** A network with no
  configured limit could read **ACTIVE/BYPASSED** if a leftover traffic shaper lingered on it (from an
  older version, an interrupted change, or a config that drifted from the kernel) — and because the
  status was tied to the router-wide HW-acceleration toggle, acting on one network visibly changed the
  status of the others. Status now follows the **configured limit**: no limit → INACTIVE, whatever
  stray shaping exists, and one network's action no longer repaints the rest.
- **Bandwidth Limiter: leftover shapers are now cleaned up.** Every teardown was previously scoped to
  the current config, so a shaper whose config entry was gone was orphaned forever — and even Reset
  couldn't clear it. Opening the limiter now sweeps any shaping left on a network with no limit
  (cleaning the ingress filter before the ifb device, so nothing dangles), and Reset does a full sweep.
  Verified end-to-end on real hardware.

#### Hardware Information
- **Hardware Info: Device ID lines up again** once uptime passes 9 days (the day count wasn't counted in
  the column width).

#### System Configuration Viewer
- **System Configuration Viewer — VPN screen: ZeroTier now shows a status line** (it previously printed
  a bare "ZeroTier:" header with nothing under it when no networks were configured), matching Tailscale.
  Tailscale's node IP line is now shown only when there actually is one, instead of an empty "Node:".

#### Benchmarks
- **VPN & Crypto Benchmark: RSA-2048 fixed on newer firmware.** Routers with OpenSSL 3 (e.g. a Beryl AX
  on current firmware) showed 0.0 sign/s and verify/s because the newer output format wasn't recognised;
  the real numbers are now read. A measurement that fails shows `---` instead of a misleading 0.0.

#### Display Settings
- **Numbered menu items no longer show a double gap on macOS Tahoe ("Golden Gate").** The OS
  update changed the width of emoji keycap glyphs (1️⃣) from 1 cell to 2, and the mac terminal profile
  had *assumed* 1 cell (hardcoding a 2-space keycap→label separator), so every numbered row rendered
  with a doubled gap. The toolkit now MEASURES the keycap advance at startup (same cursor-probe it
  already uses for ⚠️ and †) and sets the separator to one visible gap — self-correcting on Tahoe,
  pre-Tahoe macOS, and Linux alike, with no per-OS assumption to go stale again. The Display Settings
  Full-mode preview (which hardcoded the keycap spacing) now follows the same measured separator.
- **Display Settings previews match your terminal.** The sample messages now use the exact spacing
  your terminal really gets (Termius and Windows Terminal were showing extra gaps), including when
  you're currently in Compatible mode.
- **Compatible-mode preview fixed** — it now shows the symbols that terminal will *actually* use (the
  full-width set on PuTTY, the plain-ASCII set elsewhere) instead of a generic set that clipped on PuTTY.

#### Toolkit-wide
- **Success messages are now honest.** The AdGuardHome direct-access Enable / Restart / Disable, the
  fan "Dynamic control restored", the Remote LAN "set" writes, and SSH key-add now confirm the action
  actually took (service up/down, write succeeded, key present) before reporting success — and report
  the real failure otherwise, instead of claiming success unconditionally.
- **"Press any key to continue" now accepts any key.** On this firmware busybox's `read`
  didn't do a true single-key read, so only Enter advanced the prompt and any other key appeared to
  hang. It now reads one key via `stty` raw + `dd` and restores the terminal (same fix for the
  `[P]/[N]` pager reads). Verified on all fleet models. Also: `spin_run`/`countdown_run` now run their
  background command with stdin from `/dev/null`, so a service they (re)start can't inherit the
  terminal and wedge the next keypress.
- **Prompts line up with the menus they follow.** A few yes/no and choice prompts (Toolkit Management,
  Display Settings, the first-run install and the Mac spacing picker) were indented as if an icon were
  missing; they now start at the left edge like every other prompt, and the spacing picker's save
  prompt names the option you picked.

## 2026-09-13
### What's New
#### Toolkit-wide
- **One consistent lifecycle for every installable feature.** The Web Terminal (ttyd), Zram Swap,
  LibreSpeed, OpenSpeedTest, and the Switch Position Indicator now share ONE status + action model, so
  no two screens behave differently. Each shows a single lifecycle status value — **NOT INSTALLED /
  DISABLED / ENABLED / SERVICE DOWN** (colour carries the difference: yellow = you turned it off,
  red = it broke) — and the menu is **context-aware**, showing only the actions that apply:
  - **Install and enable** when nothing is installed (it discloses the package download),
  - **Enable / Disable** to turn it on/off — Disable KEEPS the package and config so re-enabling is
    instant and lossless,
  - **Reinstall** only when a service is down (the fix that re-applies the backend and restarts),
  - **Uninstall** to remove the package entirely (only where a package exists).
  A down service shows just **Reinstall** + its removal (Uninstall for a package-backed feature; the
  switch indicator, which has no package, keeps Disable as its removal) — the sensible flows from a
  broken service are fix or remove, so a standalone Disable isn't offered there.
  Retired the old inconsistent labels (Install and Enable / Install / Reinstall / Disable Service /
  Uninstall Package / Install in Web-UI / Remove from Web-UI / re-apply overlay).
- **Every working step is a gear + spinner** across all five features (no more static "…ing" headers
  or stray blank lines between action lines), matching the rest of the toolkit.
- **Terser, consistent messages.** Single-sentence status/result lines no longer end in a period
  (a period separates sentences; one sentence needs none); progress labels stay natural
  ("Stopping the ttyd service"); result stamps stay telegraphic ("Web Terminal enabled").

#### Switch Position Indicator
- **Switch Position Indicator:** the separate "Web-UI overlay" and "Live updates" rows are collapsed
  into the one **Indicator** lifecycle value (they were always linked); a dead backend now reads
  **SERVICE DOWN** with a **Reinstall** to recover, instead of a silent stale overlay.

### Bug Fixes
#### Persistence
- Persistence toggles for zram / LibreSpeed / OpenSpeedTest now use the portable keep-list helpers
  (no `sed -i`), and LibreSpeed's and OpenSpeedTest's keep-lists now also preserve their service's
  rc.d boot symlink, so the service auto-starts (instead of returning SERVICE DOWN) after a
  keep-settings firmware upgrade.

## 2026-09-09
### What's New
#### Switch Position Indicator
- **Switch Position Indicator** (System Tweaks ▸ Switch Position Indicator). On models with a
  physical toggle switch, it shows which way the switch is actually flipped, right on the Admin Panel's
  **Toggle Button Settings** page — it fills the active side's toggle **green**, greens its LEFT/RIGHT
  label, and tags it "current position". Read-only; it never moves the switch or changes a setting.
  Position and ON/OFF are **derived from the logical switch state the way GL's own button handler does**
  (physical GPIO level XOR the model's active-low flag), so LEFT/RIGHT and ON/OFF always agree — no
  guessing, no manual invert. Status screen (hardware / live position / toggle function / overlay /
  service / persistence), Install / Remove (context aware), `[?]` help, `[0]` exit. Live position comes
  from a tiny Procd backend (`gl_switchpos`) that reads the switch GPIO and publishes it to a static
  file the overlay polls (written only on change — negligible flash wear).
- **Set the toggle-button function from the toolkit.** Assign what the physical switch does, with the
  options derived GL's own way from its `/etc/gl-switch.d` handlers (plus VPN tunnels from route_policy
  and main/guest Wi-Fi) — a flat inline list, empty groups omitted. Wi-Fi assignment warns first (a
  flip can drop the Wi-Fi you manage the router over).

#### Web-UI Tweaks
- **Persist Web-UI tweaks across firmware updates.** Each Web-UI feature (Web Terminal, Fan
  control, Switch indicator) gains an **Enable/Disable persistence** action and a Persistence status
  row. When enabled, the feature's registry + a small boot service are kept on `/etc/sysupgrade.conf`;
  after a firmware update **or a same-version factory reset/reflash** wipes the overlay, the service
  re-applies the enabled overlays from the new firmware's pristine bundle on first boot (it detects a
  wipe from the missing overlay itself, not just a version bump). Re-apply is **backend-first and
  fail-stock** — if GL restructured the bundle so an injection no longer fits, that panel is left
  stock (never corrupted) and reported as a failure. The result is shown once on the next launch.
- **Shared Web-UI injection registry (`glwebui`).** The Web-UI Terminal button, the Fan slider-range
  patch, and the Switch indicator all paint the same admin-panel bundle. They go through one registry
  that rebuilds the bundle from the pristine copy and re-applies **every active** overlay on each change
  — so installing or removing one no longer wipes the others (the old ttyd↔fan collision is gone).
  Existing ttyd/fan installs are migrated into the registry automatically on first use.
- **Web-UI overlays no longer need a manual hard-refresh.** Patching the admin-panel bundle in
  place kept the same filename, so the browser served its cached (stale) copy until the user
  hard-refreshed. The registry now gives the patched bundle a new content hash and repoints the
  single reference in the SPA entry (served no-cache, always re-fetched) — so the browser fetches
  the patched bundle fresh on its own, exactly the way a firmware update busts the cache. This
  matters most for persistence: after an update the overlays come back *and* show up without the
  user knowing to hard-refresh.

#### Persistence
- **Consistent persistence messaging + a data-loss guard.** All persistence toggles across the
  toolkit (Web-UI tweaks, Zram, SSH keys, OpenSpeedTest, LibreSpeed, AdGuardHome updates, Toolkit
  Management) now confirm with one standard line — `Persistence enabled/disabled for <thing>.` — and
  no longer leak a `sysupgrade.conf` path. Disabling persistence for something that would cause
  **irrecoverable data loss** (SSH keys) now warns and asks for confirmation first, rather than a
  quiet info line; recoverable functionality stays a one-line confirm.

## 2026-09-06_20:06
### What's New
#### OpenSpeedTest Server
- **OpenSpeedTest Server is now a native, fully integrated tool.** Host the OpenSpeedTest web app on
  the router (its own nginx on port 8888) to measure LAN / Wi-Fi speed between a device and the router
  — no internet, no app. Replaces the external installer wrapper, conforming to the toolkit's UI: a
  STATUS block, keycap menu, `[?]` Quick Help, spinner, and `[0] Back`.
- **Two download sources, honest space check.** Choose the official GitHub repository (a tarball
  *streamed* straight to flash — lightest footprint) or the GL.iNet mirror (a zip that stages ~32 MB in
  /tmp). The source screen shows live free space vs. what's required, and a **reinstall credits the
  space the current copy will free** so it no longer falsely fails on a space-tight box already hosting
  it. If flash is short it offers to relocate onto a mounted drive.
- **Install / Diagnostics / Uninstall / Persistence** from one screen; persistence keeps it across a
  firmware upgrade. Menu **exit is now `[0]`** (was `[5]`).

## 2026-09-06
### What's New
#### Bandwidth Limiter
- **Network Bandwidth Limiter — see and switch each network's interface.** A new **If-State** column
  shows whether each network is UP or DOWN, and switched-off guest / IoT / VLAN networks now appear in
  the list (they were hidden before) so you can bring them back up right from the limiter.
- **Per-band Wi-Fi control for guest / IoT.** A network with more than one Wi-Fi band (2.4 / 5 / 6 GHz)
  opens a grid where you pick exactly which bands to bring up or down — no longer all-or-nothing. The
  network reads UP while any band is on, DOWN once they're all off.
- **Bringing a network up or down is persistent** (like the GL admin toggle — it survives a reboot) and
  re-applies that network's bandwidth limit automatically when it comes back up.
- **VLAN subnets are now recognized** as VLANs, so a custom VLAN can be toggled and shows its bands.
- **Safety prompt on isolated networks:** enabling "router reachable on all ports" for a network that's
  walled off from your others now warns and asks to confirm first — it would otherwise expose the
  router's admin UI / SSH to that isolated network.
- **Clearer switched-off networks:** a down network shows its configured limit the same on both the list
  and the detail screen, drops the confusing "Persist" line, and states plainly that it stays off across
  reboots until you bring it up.

#### Package and Persistence Manager
- **Tailscale added to the Package & Persistence Manager** — installs the daemon plus GL's integration
  (admin-panel toggle, kill-switch) and removes both cleanly to free the space; available across current
  firmware (opkg and apk).

## 2026-09-01
### What's New
#### AdGuardHome
- **AdGuardHome Lists Manager:** after applying changes it now shows an animated **download-progress**
  spinner ("Downloading lists N of M") while AdGuardHome fetches the newly-enabled lists, instead of
  sitting silently — so a large add no longer looks hung, and the Memory Impact meter is accurate when
  the screen returns. Lists that finish are confirmed; lists that can't fit (filter storage full) are
  reported and removed; lists still downloading are called out as in-progress rather than as failures.
- **Filter Storage Space Limit:** re-enabling the cap now **warns when your current lists won't fit**
  (showing space used vs. available) and asks you to confirm, since lists that don't fit silently stop
  loading. The AdGuardHome Control Center rule count also refreshes correctly now after the storage
  limit is turned on or off.

#### Toolkit-wide
- Multi-line **info / warning / error messages** now indent their continuation lines automatically, so
  wrapped advisories line up cleanly under the icon across the toolkit; converted the last raw advisory
  block on the storage screen to the standard message style.

## 2026-08-28
### What's New
#### AdGuardHome
- Rebuilt the **AdGuardHome Lists Manager** as a two-column editor modeled on the Package & Persistence
  Manager: each list has an **Install** and an **Enable** toggle, typing its number cycles through the
  valid actions for its state, and a **Planned Action** column shows exactly what will happen before you
  Confirm.
- Added a curated, sectioned catalog — **Recommended** (Phantasm22's lists + HaGeZi Pro++ + URLHaus +
  PhishTank/OpenPhish), plus **General**, **Security**, and **Allowlist** picks — alongside any lists you
  already have; the recommended set installs and enables by default.
- Added a **Memory Impact** meter showing the rules AdGuardHome will actually load against the router's RAM
  (and zram swap), turning amber/red as a selection approaches what the box can hold — so big lists can't
  silently exhaust memory.
- Added guard rails for constrained routers: it offers to enable **zram swap** when memory would run high,
  and — on models with a filter-storage cap — warns when a selection won't fit and offers to remove the
  cap.
- After applying, it now **verifies each enabled list actually downloaded**; lists that couldn't (filter
  storage full) are reported and removed instead of being left installed-but-empty.
- Added a **Zram Swap** shortcut and renamed the AdGuardHome "Setup, Access & UI Updates" submenu to
  **Advanced Settings**.

### Bug Fixes
#### AdGuardHome
- Removing a list now reclaims its disk space (AdGuardHome leaves orphaned filter files behind), and
  re-adding a list reuses its file instead of accumulating orphans that can fill a capped filter partition.
- Filter-storage-limit removal (Advanced Settings, and the Lists Manager guard rail) now verifies the
  partition actually unmounted before reporting success, and recovers from a half-removed state.

## 2026-08-27
### What's New
#### Package and Persistence Manager
- **stress-ng** (a CPU stress tool) is now withheld only on kernels older than 6.6 — where a Linux
  memory-pressure bug can hard-crash the router — instead of on all GL.iNet firmware. Newer firmware
  (kernel 6.6+, e.g. OpenWrt 25) can use it safely again; older kernels use `stress` only. Applies to both
  the Package Manager and the CPU stress benchmark.

#### Web-UI Terminal
- The "hard refresh" hint shown after Web-UI Terminal changes now lists the shortcut per browser
  (Chrome / Edge / Firefox: Ctrl+F5 or Ctrl/Cmd + Shift + R; Safari: Cmd + Option + R), on indented lines
  that fit the screen, and reads consistently in both enable and disable.

### Bug Fixes
#### Package and Persistence Manager
- The Package & Persistence Manager could show a package as "persisted" while it wasn't installed,
  and "Disable Persistence" silently did nothing. Persistence now follows installation — a package that
  isn't installed never shows as persisted, uninstalling always clears persistence, and disabling
  persistence on an installed package actually removes it from the sysupgrade keep-list and boot-restore
  list.

## 2026-08-26_17:12
### What's New
#### Package System Repair
- On apk-based firmware, Package System Repair can now also restore the factory package database
  from read-only firmware (`/rom`) as a last resort, matching the opkg behavior (lossy — clearly warned).

#### Web-UI Terminal
- The "hard refresh" hint now includes Safari's shortcut (Cmd+Option+R) alongside Ctrl+F5 and
  Cmd+Shift+R.

### Bug Fixes
#### Package and Persistence Manager
- The Package & Persistence Manager wrongly reported "System changes applied" when a package could
  not actually be removed. Removals are now verified and reported honestly — a package required by other
  installed packages is kept (with the option to type `YES` to force-remove it despite a warning listing
  the dependents), a non-opkg "raw" utility has all of its files removed (no leftovers), and anything that
  could not be removed is listed rather than silently claimed as done.

#### Web-UI Terminal
- The Web-UI Terminal now confirms the ttyd service actually started before reporting success. If it
  did not (an invalid certificate, a wrong system clock, or the port already in use), it shows the reason
  and skips patching the Admin Panel — instead of a false "Installed" message and a button that opens a
  dead page.

## 2026-08-26
### What's New
#### Package System Repair
- Package System Repair now escalates a corrupt installed database through one shared repair
  flow, so "Repair now" and "Repair the installed database" behave and read identically. It tries, in
  order: (1) a safe end-of-file repair; (2) rebuilding the database from opkg's own on-disk per-package
  metadata (`/usr/lib/opkg/info/*.control`), which keeps your actual installed packages; and, only as a
  last resort before re-flashing, (3) restoring the **factory package database from read-only firmware**
  (`/rom`) — lossy (opkg forgets post-factory package records, though the files stay on disk).
- The repair no longer makes a "pre-repair backup" of the corrupt database — there was nothing
  worth restoring in it, and it cluttered the backup list. The "restore a backup" advice now appears only
  when you actually have an earlier backup to roll back to.

## 2026-08-25
### What's New
#### Package System Repair
- **Package System Repair** under System Tweaks. Fixes a corrupted package system — the opkg
  `parse_from_stream_nomalloc: Missing new line character at end of file` error, which makes package
  installs and removals fail (or silently do nothing). It measures the state live (package manager,
  installed database, index cache, internet, backups), then can rebuild the re-fetchable feed cache
  and/or repair the installed database (opkg's `/usr/lib/opkg/status` or apk's `/lib/apk/db/installed`).
  The database is backed up before any change and is never deleted; deeper damage falls back to a restore.
- Package installs now self-heal automatically. If the downloaded feed index is corrupted, the
  toolkit silently rebuilds the (fully re-fetchable) cache; if the installed database is the cause, it
  offers a guarded, backed-up repair inline instead of just failing.

#### Toolkit-wide
- Backups now live in one place — `/etc/glinet_utils/backups`. Existing AdGuardHome backups
  are migrated there automatically when you upgrade to this version; nothing is lost.

### Bug Fixes
#### Bandwidth Limiter
- In the Network Bandwidth Limiter, the "Applying limit" spinner hugged the value-entry line
  when HW acceleration was already off (the confirmation that normally added the spacing was skipped).

## 2026-08-24_21:00
### Bug Fixes
#### Package and Persistence Manager
- The Package Manager showed a blank size for most packages on **apk**-based systems (newer
  GL firmware and OpenWrt 24.10+/25) — the size lookup only understood opkg's package feeds. It now
  reads sizes from `apk info -s` (which covers both installed and available packages), so the Size
  column fills in on apk the same as on opkg. The Ookla **speedtest** binary (installed from Ookla,
  not in any package feed) now shows a size estimate too, like speedtest-go — on both apk and opkg.

## 2026-08-24_20:48
### What's New
#### Bandwidth Limiter
- The Bandwidth Limiter now preflight-checks for `tc` (traffic control) and installs
  `tc-tiny` if it's missing — so shaping still works if the package was removed — instead of
  failing at the first `tc` command. If it can't be installed, it says so instead of silently
  doing nothing.

#### Package and Persistence Manager
- Added **openssl-util** to the Package Manager's installable tools list, so it can be installed
  proactively (the crypto benchmark and Web-UI Terminal HTTPS use it).

## 2026-08-24_20:10
### Bug Fixes
#### Toolkit-wide
- The crypto benchmark and the Web-UI Terminal's HTTPS certificate both need the `openssl`
  command, which GL firmware ships (openssl-util) but stock/vanilla OpenWrt does not — so on bare
  OpenWrt they failed. The toolkit now **installs openssl-util automatically** when `openssl` is
  missing (via the apk/opkg-aware installer) instead of erroring or failing silently.

#### Web-UI Terminal
- The Web-UI Terminal's HTTPS setup printed "Generated certificate" even when generation
  actually failed (e.g. no openssl), leaving ttyd on HTTPS with no cert/key. It now verifies the
  cert and key were really created and **falls back to HTTP** if not.

## 2026-08-24
### What's New
#### Hardware Information
- RAM-size rounding now recognizes the 1.5× sizes (192 MB, 384 MB, 768 MB, 1.5 GB, 3 GB,
  6 GB, 12 GB), so a device with one of those isn't rounded up to the next power of two, and a
  device reporting ~3 GB no longer rounds to 4 GB. Both screens share one rounding helper.

### Bug Fixes
#### Benchmarks
- The memory-throughput benchmark reported the wrong RAM on some devices (a 128 MB
  GL-MT300N "Mango" showed 256 MB) — it used its own estimate (kernel MemTotal + 30 MB, rounded
  up to the next 128) which overshot into the wrong bucket. It now shows the same figure as
  Hardware Info screen 1 (MemTotal rounded to the nearest common size), so the two always agree.

## 2026-08-21_10:01
### What's New
#### Bandwidth Limiter
- The Bandwidth Limiter's "turn off hardware acceleration" prompt is now an **informational
  note** (not a warning) with a **Yes default** — it describes the side effect of the limit you
  just asked for, and that acceleration turns back on by itself when the last limit is removed,
  instead of reading like a caution against limiting.
- The per-network router-access action is now **"Enable / Disable router to be reachable
  on all ports"** (context-aware) instead of "Allow full router access" / "Block router access" —
  the old "Allow" implied a web-UI permission, and "Block" was inaccurate (turning it off only
  falls back to the default partial access; it does not block).

### Bug Fixes
#### Toolkit Management
- The self-installer could replace the installed `glinet_utils` command with a copy of
  **BusyBox** (so it printed `applet not found`) when the toolkit was piped into a shell — `$0`
  resolved to `/bin/sh` → BusyBox and the installer copied that. It now verifies the source really
  is the toolkit (shebang + `# Version:` marker) before copying, and doesn't offer to install at
  all on a piped/stdin run.

#### Bandwidth Limiter
- The router-access detail notices (managed-by-zone / no-zone) now use the standard info
  style with an icon instead of hand-painted yellow text.

## 2026-08-21
### What's New
#### Bandwidth Limiter
- A generalized **Network Bandwidth Limiter** replaces the guest-only limiter. It shapes
  any network the router actually has — LAN, guest, IoT, a VLAN, or a VPN tunnel — discovered
  automatically, in a grid with per-network Download / Upload limits, a measured Router-access
  dot, persistence, and live status. It lives under **Network and VPN Tools** (renamed from VPN
  Tools), alongside SSH Key Management; both moved out of System Tweaks. An existing guest
  limiter is migrated over automatically, so nothing breaks.
- **Router access** per network is measured live from the firewall and shown as a
  red/amber/green dot matching the Remote LAN Access screen — reachable (all ports) / partial
  (some ports, e.g. the DNS + DHCP that GL opens by default) / blocked (no access). When
  partial, the detail page lists exactly which services are open (service / port / proto).
  "Allow full router access" opens all ports; "Block" falls back to partial, so DNS/DHCP keep
  working.
- Hardware acceleration is managed for you — applying any limit disables offload for the
  whole router (shaping needs the software path), and clearing your last limit re-enables it. The
  status line reports it health-aware: **DISABLED** / **ENABLED** shown green when nothing is
  bypassed, and yellow only when acceleration is on while a limit exists (that limit is then
  BYPASSED). **[H]** is a manual Enable / Disable override, **[R] Reset** reverts everything to
  defaults (removes every limit and router rule, re-enables acceleration, stops the background
  service), and the help explains the trade-off with measured CPU-cost figures.
- The detail screen follows the standard vertical layout — Status first, then the fields
  in the same order and names as the grid columns, status values ALL CAPS in both views.
- Removed the old guest-only limiter code (~500 lines) now that the generalized engine
  supersedes it; the System Tweaks help was corrected to match the current menu.

#### Toolkit-wide
- A scrollable **help viewer** — every help screen now pages with `[P]` Previous /
  `[N]` Next / numbered jumps / `[0]` Back instead of scrolling off the top of the window on a
  shorter terminal. Page breaks fall on blank lines so a paragraph never splits across a page,
  and short help still shows on one screen.

### Bug Fixes
#### Remote LAN Access
- Remote LAN Access flow-table columns misaligned on any row carrying the inferred-subnet
  dagger (†). `printf %-Ns` pads by *bytes*, and † is 3 bytes but 1–2 display cells; the columns
  now pad by measured display width (the dagger's cell width is probed per terminal), so they
  line up on macOS Terminal, Termius, ttyd, Windows Terminal, and PuTTY.

#### Toolkit-wide
- The AdGuardHome filter-space, zram-swap, and LibreSpeed removal confirmations painted
  their question yellow with no warning glyph; they now use the standard warning style — the bold
  glyph via the shared helper for the caution line, and a plain question — matching every other
  warning in the toolkit.

## 2026-08-18
### What's New
#### Package and Persistence Manager
- The Package & Persistence Manager now shows a **Size** column (between Package Name
  and Planned Action) and a **Storage** line under the title. Size is the *install* size for
  every package - what it occupies on disk once installed, not the download - measured
  directly for installed packages (firmware/rom ones included) and taken from the package
  index for not-installed ones (an estimate). The Storage line shows the overlay's free space
  and, once changes are staged, the projected free space after them: a conservative "≈" floor
  on a compressing overlay (ubifs/jffs2, where uncompressed sizes overstate real flash use),
  exact on f2fs/ext4, turning amber when it would get low. Sizes are gathered on entry behind
  a spinner; **[S] Sort** toggles size / alphabetical with a ↓ on the sorted column.
- On MIPS routers - where Ookla ships no binary - the Package Manager now offers
  **speedtest-go** as the installable internet speed-test entry (in place of the
  un-installable Ookla `speedtest`). Installing it also makes the "Ookla Internet Speedtest"
  benchmark instant, since it then uses the persistent copy instead of re-fetching each run.
- Added `iperf3` and `iputils-ping` to the Package Manager.
- Planned Action colours now match the confirm screen - green for install/persist,
  red for remove/unpersist, dim grey for no change.
- Size gathering is much faster - sizes come from a single pass over the package
  index feeds instead of one `opkg info` call per package (~3s each on MIPS); a refresh with
  the index already populated dropped from ~19s to ~5s.

### Bug Fixes
#### Package and Persistence Manager
- Not-installed sizes stayed "-" even online - the empty-index check used `ls -A` on
  two directories (which prints directory-name headers, so it never read as empty); it now
  uses `find -type f`, so the index refreshes and sizes appear.
- The Package Manager's divider lines span the full width of the widest row.

## 2026-08-14
### What's New
#### Hardware Information
- The Hardware Info **Network** page (page 3) is now a physical-port panel - a
  column grid (Port · Role · Status · Link · Maps to) grouped by the chip each port
  hangs off. It reads GL's port map (`eth_ports_config_map`) when present, with
  swconfig and raw-netdev fallbacks, so it works on old and new firmware with nothing
  model-specific hardcoded. Fixes two gaps: 2-port devices (which showed no chassis
  ports at all) now render, and multi-fabric devices like the BE14000 now match the
  web UI's silk labels. "Maps to" is the real `ifconfig` interface a port appears as;
  switch-group headers name the uplink and its speed (the switch→SoC pipe, not a
  per-port cap).
- A per-page `[?]` Quick Help for the Hardware Information viewer (it had none)
  - a light explainer for each of the four pages, with a glossary on the Network page
  (Role, Link, Maps to, uplink).
- On the Hardware Info Network page, the "WAN address" and "LAN bridge"
  values now line up in the same column.
- CPU core reporting is topology-aware. Plain multi-core chips still read
  "Cores: N"; multithreaded parts (e.g. MT7621) read "Cores: 2 (4 threads)" and the
  stress test says "Stress testing 4 threads (2 cores)". Physical cores come from the
  kernel's /sys CPU topology, logical from /proc/cpuinfo - no per-model table.

#### Remote LAN Access
- Remote LAN Access subnet detection now uses two scan tiers instead of
  three - a Standard scan that pings the common gateways (no dependency, works
  offline) and, only if that finds nothing, a Full scan that installs fping and
  sweeps every private /24 in seconds. The redundant middle tier is gone, so the
  flow is one scan then at most one prompt.
- The subnet-detection prompt is shorter and more precise ("No remote LAN
  answered on the common subnets. Run a full scan (every private /24, ~30s)?"), the
  standalone "Detecting…" line (which sat without a spinner) is gone, and the fping
  install now shows a spinner.
- The Remote LAN Access topology diagram dropped its left rail, so the
  network column (e.g. `192.168.8.0/24`) lines up with the Status column of the flow
  table directly below it.
- Remote LAN Access [2] runs its SSH-to-peer lookup under a spinner, so the
  up-to-10s probe (a peer with no SSH) shows live progress instead of a frozen
  screen. A scan that finds nothing now says "No remote LAN found automatically"
  before the manual-entry prompt, which itself says "manually" so the reason is clear.
- On the paginated screens (MTU Optimizer, Remote LAN Access) a blank line
  now separates the action list from the [P]/[N] navigation footer, and a blank line
  precedes any status output, matching Hardware Info / Display.

#### Benchmarks
- The Ookla Internet Speedtest now works on MIPS routers (e.g. the GL-MT1300).
  Ookla ships no MIPS build, so on MIPS the toolkit fetches speedtest-go - a maintained
  Go client that measures against the same speedtest.net servers - to /tmp on demand and
  runs a real WAN-to-internet test (download/upload/ping/jitter). Non-MIPS routers use
  the official Ookla binary exactly as before.

#### Toolkit-wide
- Progress spinners no longer print a trailing "…" - the spinner itself
  shows the operation is running, so labels read cleanly (e.g. "Scanning common
  subnets" with the spinner beside it).
- Progress "…" is retired everywhere, not just on the spinners. Static
  action lines (Disabling HW Acceleration, Patching Web-UI, Stopping service, and
  ~25 others) and the two startup spinners drop the trailing dots; when a spinner is
  present it is the only "working" signal.
- Prompts sit flush-left (column 0) with the status lines they follow
  rather than a 3-space indent - one clean left margin - and exactly one blank line
  follows a y/N answer before the resulting action.

### Bug Fixes
#### VPN MTU Optimizer
- The MTU active probe no longer leaves a double blank line after you answer
  "Run the probe? [y/N]".

#### Bandwidth Limiter
- The Guest Network Bandwidth Limiter's "Guest → GL Web UI:" value now lines
  up with the other CONFIGURATION STATUS values (the multibyte → left it one column
  short).

#### Benchmarks
- On MIPS the Ookla speed test used to print "not available", then fall through
  and "run" a missing binary that silently did nothing yet reported "completed". It now
  either runs (via speedtest-go, above) or soft-fails cleanly if the internet is down -
  the same way a failed package install does. (The earlier message that pointed at
  LibreSpeed/iperf3 as substitutes was misleading: those are LAN speed-test targets, not
  a WAN-to-internet measurement.)
- The CPU stress-test countdown no longer leaves a ghost digit when the
  remaining-seconds text shrinks (e.g. "10s" -> "9s"); each redraw clears to end of line.

#### Display Settings
- Termius glyph spacing corrected after a live re-measure. Menu keycaps
  (1-9, 0) and the Help/Clear markers now sit at a single space - a profile-aware
  separator lets Termius narrow to one column while every other terminal (macOS
  Terminal, Windows Terminal, ttyd, PuTTY) stays byte-for-byte identical - and the
  warning/info/action icons drop to one space as well (a current Termius no longer
  clips the trailing cell of a coloured run, so the old sacrificial pad is gone).
  The success/error/hourglass icons keep two spaces: they paint two cells but the
  cursor advances one, so a single space would butt the text.
- On Termius the "Running Ookla/Internet Speedtest" and "Starting iperf3
  Server" headers lost their final character - the leading hourglass made Termius
  clip the last cell of the coloured run; a sacrificial trailing space restores it.

## 2026-08-08
### What's New
#### Display Settings
- PuTTY (and other bare `xterm` / `putty` terminals) now get coloured status
  glyphs in Compatible mode instead of the plain ASCII markers. It uses the emoji
  PuTTY actually renders - ✅ ❌ ⏳ and the 🟢🔴🟡 traffic-light dots - and, because
  PuTTY draws emoji in monochrome, paints them via ANSI so the Remote LAN Access
  stoplights stay distinguishable. Warning/info/action use emoji-default stand-ins
  (❗ 💡 🔧) rather than ⚠️/ℹ️/⚙️, which PuTTY clips to half-glyphs (those are
  text-default codepoints it draws in a single cell). Menu keys - numbers, All,
  help and clear - stay in [brackets], which read cleanly there. Detected by TERM;
  genuinely limited terminals (serial console, TERM=linux/vt100) keep pure ASCII.
- Windows Terminal menus now number options with the bold negative-circled
  digits ❶..❾ + ⓿ (and Ⓐ for "All") instead of [1]..[0] text. The keycap emoji used
  on other terminals (1️⃣) box out on Windows Terminal, but these render cleanly and
  are single-width - advancing one cell, like the keycaps do - so the labels line up
  exactly as they do elsewhere. Help/Clear keep ❓/🆑, which render fine there.

#### VPN MTU Optimizer
- The VPN MTU Optimizer now uses the same paginated layout as Remote LAN
  Access - one tunnel per page, [P]/[N] to move between them, and the four actions
  (Optimize tunnel / Set MTU manually / Verify with an active probe / Reset) act on
  the tunnel on screen. This replaces the old "which tunnel?" picker and the
  all-tunnels batch, and fixes the screen overflowing with three or more tunnels.
  Each page also gains a Status: Active/Inactive line and a Remote-LAN-Access-style
  navigation row.
- The MTU active probe now shows the standard spinner while it searches
  for the largest packet size, instead of a static "Probing ..." line that looked
  frozen during the (few-second) don't-fragment sweep.
- The VPN MTU Optimizer and Remote LAN Access now share one paginated
  layout - a cyan identity line (tunnel + role-aware state: servers UP/DOWN, clients
  CONNECTED/DISCONNECTED with handshake age, ALL CAPS), a density divider sized to
  the widest content line, and a single realtime nav footer ("[P] Previous  Page N
  of M  [N] Next  [1/2/3/4]  [0] Back  [?] Help" - single keypress, cursor at the
  line end, no Choose prompt, shown even on one page where [P]/[N] just refresh). On
  Remote LAN Access the tunnel identity is promoted above the network diagram and
  OUTBOUND/INBOUND is highlighted. Pure-list screens keep no divider.

#### Remote LAN Access
- Remote LAN Access subnet detection now shows a spinner during the scan
  instead of a seconds-remaining countdown. The scan time is network-dependent, so
  the countdown drifted out of sync; the spinner just shows it is still working.

### Bug Fixes
#### VPN MTU Optimizer
- An inconclusive MTU active probe (no reply, or the don't-fragment flag
  ignored) now clears any prior "Verified" basis, so the status returns to
  "Calculated from link MTU" instead of keeping a stale Verified value the path can
  no longer confirm - itself a signal that the tunnel's behaviour changed.

#### AdGuardHome
- The AdGuardHome Backup Cleanup screen's two framing lines were different
  widths (55 vs 62); both now match at the widest content line (60).

## 2026-08-07
### What's New
#### Hardware Information
- The Hardware Information wireless page now shows each radio's supported
  Wi-Fi standards. The Band line carries the marketing generation in parens
  (e.g. "5GHz (Wi-Fi 6)") and a new Protocol line lists the IEEE standards
  (e.g. "802.11a/n/ac/ax"). It reads the chip's real capabilities and is
  band-aware: 802.11ac is 5/6 GHz only, so 2.4 GHz is never labelled "ac" even
  on chips (some MediaTek parts) that advertise a VHT capability block there for
  the vendor 256-QAM rate extension. The generation also distinguishes Wi-Fi 6
  from 6E, which share the 802.11ax standard.
- Flint 4 (GL-BE14000 / MT7988a) is now a recognised model - it appears by
  name in the benchmark comparison tables (VPN/crypto, disk, memory), has its CPU
  clock in the fixed-clock fallback, and is listed among the tested models.

#### Remote LAN Access
- Remote LAN Access now reports MEASURED status, not guesses. Every
  outbound row shows a live reachability probe (from the tunnel address and from
  the real LAN address, to the peer and to the remote LAN), so the top table can
  no longer disagree with a separate test - it IS the test, measured up front on
  entry and re-measured only after a change that could move it. This retires the
  misleading padlock and the wrong "no route here" line; rows that genuinely
  can't be tested from here (inbound flows the remote must start, or an unknown
  subnet) show a plain reason rather than a false status. Status now uses a
  traffic-light set - 🟢 reachable / 🔴 blocked / 🟡 not testable from here -
  which renders at a uniform width across terminals (the earlier ⚠️ mis-sized on
  macOS Terminal). Empty peers now read "no clients" (server) or "no peer"
  (client) instead of the ambiguous "(none)".
- Remote LAN Access can now auto-detect the remote LAN subnet instead of
  making you type it. It sweeps candidate gateways THROUGH the tunnel and keeps
  only those that answer at zero hops (directly across the tunnel, not one hop
  upstream), in escalating tiers - Quick (common gateways, instant), Standard
  (192.168/16 + 172.16/12 + usual 10.x, a couple of seconds), and Full (every
  RFC1918 /24, 139,776 candidates, offered on demand with a countdown). Uses fping
  when present, a shell sweep otherwise. When several subnets are directly
  attached it lists them and lets you pick.
- Remote LAN Access menu was tidied up. Options are now one-per-line and
  use the app-wide Enable/Disable wording; on both directions [1] toggles
  reachability and [2] detects the subnet, with masquerade as an outbound-only
  [3]. The inbound "set up the remote router" option was removed - it only ever
  installed an SSH key and then told you to configure the remote by hand (and hung
  for a minute when the peer had no sshd); that guidance now lives in [?] Help.
  Also added "[?] Help" to the navigation row.
- The Remote LAN Access status legend now labels the third state
  "unknown" (🟡) rather than "not testable from here" - the Change column already
  says why and what to do, so the shorter word avoids reading as a dead-end when
  it just needs the subnet detected.

### Bug Fixes
#### Remote LAN Access
- Remote LAN Access subnet detection now works on a tunnel that has no
  default route - for example an OpenVPN client with no pushed LAN route. The scan
  binds its probes to the tunnel interface, so it never actually needed a default
  route; the guard that required one wrongly refused to scan and sent you to manual
  entry.
- Subnet detection now excludes ALL of this router's own subnets, not just
  the current tunnel and the LAN - including other VPN tunnels that are configured
  but down. It was offering a router's own WireGuard range (reachable across a
  second tunnel) as if it were a remote LAN.
- A few stale references in Remote LAN Access after the menu renumbering -
  the "route needs a subnet" hint pointed at "option 4", a post-route hint
  referenced the removed "test" option, and the "left unknown" message was long
  enough to wrap; all corrected.

#### Bandwidth Limiter
- The Guest Network Bandwidth Limiter's "Help" line was indented one column
  short of the others on some terminals (the help glyph's trailing space differed
  by profile); it now lines up with the numbered options.

#### Display Settings
- On laggy connections (for example Termius over in-flight wifi) the
  toolkit could misdetect the terminal type on startup and pick the wrong glyph
  widths, leaving symbols and colour runs misaligned. The terminal probe now
  waits out the round-trip and reassembles a reply split across reads instead of
  giving up after a fixed fraction of a second, while still answering instantly on
  a responsive terminal.

## 2026-07-31
### What's New
#### Toolkit-wide
- Added an in-screen "[?] Help" to the VPN MTU Optimizer, Remote LAN Access and
  VPN Tools screens (they had none), so every one of those menus can explain
  itself without leaving. The MTU help also explains that a failed active probe
  usually just means the server does not answer ICMP (not that the VPN is down),
  and that the tool keeps the Calculated value when it cannot verify - an
  inconclusive probe means "couldn't verify", not "broken".
- The help screens were made consistent - every one opens with a
  "<Feature> - Quick Help" title, uses the same layout, and is triggered the same
  way. The AdGuardHome Direct Access help now shows your router's real LAN address
  instead of a hard-coded example, and no longer refers to menu items by number.

#### VPN MTU Optimizer
- The VPN MTU active-probe result screen now labels its rows "Calculated
  MTU" and "Verified MTU" (was "Old/New Recommended"), and when a probe cannot
  verify it reads "Verified MTU: unknown" and "Falling back to the Calculated
  <n>; this value was not actively verified" - so an inconclusive probe no longer
  reads as if the value had been confirmed. (Community feedback.)

### Bug Fixes
#### Package and Persistence Manager
- The Package & Persistence Manager's "[?] Help" pointed at a help screen
  that was never written, so pressing it errored instead of showing help. The
  help now exists.

## 2026-07-30
### What's New
#### VPN MTU Optimizer
- Each tunnel on the MTU screen now shows a "Basis" line - whether the
  Recommended MTU is Calculated from the link or Verified by an active probe (with
  the date and target). A verified result is remembered and used as the
  recommendation, and is marked stale (back to Calculated) if the underlying link
  or the server address later changes.
- The active probe measures the path to the server's public address
  first, outside the tunnel, so the result does not depend on the don't-fragment
  flag surviving encapsulation; it falls back to a through-tunnel probe only when
  the public endpoint cannot be reached.
- The probe result screen now speaks the status screen's language - it
  shows Current MTU, Old Recommended (the Calculated value) and New Recommended
  (what the probe found), a plain-language verdict, and reports that the tunnel's
  Basis is now Verified. Network jargon is explained in plain terms, including the
  don't-fragment (DF) edge case where a fragmenting path makes the probe read too
  high (the probe detects that and keeps the Calculated value).

### Bug Fixes
#### VPN MTU Optimizer
- The VPN MTU active probe now works on OpenVPN clients. GL uses OpenVPN's
  `topology subnet`, so the tunnel interface has no kernel peer address and a
  working tunnel previously read as "not probeable". It now finds the far end
  correctly and reads the server's public address from the running config.
- A WireGuard server with a configured-but-never-connected peer no longer
  reports a bogus probe. It targets only a peer that has completed a handshake,
  and says plainly when there is no connected peer to test.

## 2026-07-28_20:43
### What's New
#### Fan Control
- After a Fan setting change the toolkit reminds you to hard-refresh the
  admin panel - a normal reload can show the browser's cached copy and look like
  the change did not take.

#### Web-UI Terminal
- Disabling or uninstalling the Web-UI Terminal now notes that custom
  Fan settings may need re-applying, for the same shared-file reason (only shown
  on models that have a fan).

### Bug Fixes
#### Fan Control
- Changing a Fan setting no longer removes the Web-UI Terminal button.
  Both features patch the same admin-panel file, and a fan change restored that
  file from stock - which silently dropped the terminal button while the toolkit
  still reported it as enabled. The button is now re-applied automatically after
  any fan change that had it.

## 2026-07-28
### What's New
#### Web-UI Terminal
- The Web-UI Terminal screen shows the direct URL and port, so the
  terminal is reachable even if the panel button is missing on some firmware.

### Bug Fixes
#### Web-UI Terminal
- The Web-UI Terminal button did not appear on firmware 4.9.x. The button
  is injected next to the reboot icon in the admin panel header, but it worked
  out WHERE to put itself from the help icon beside it - and from 4.8.6 onward
  that icon moved into a support dropdown, so the button was inserted outside
  the toolbar where nothing could show it. It now positions itself relative to
  the reboot icon alone, which has stayed put across every firmware checked
  (4.3.25 through OpenWrt 25). Verified on both an affected and an unaffected
  firmware so the older ones behave exactly as before.
- The Web-UI Terminal opened too small - 130x29, below the 101x33 some
  screens need, so the toolkit warned about window size inside its own web
  terminal. It now opens at the standard 110x33, with the font pinned so the
  size is consistent rather than following whatever the browser defaults to.
  Resizing, maximising and minimising all still work.
- Status symbols were spaced wrongly in the browser terminal. Ticks,
  crosses and the padlock in the Remote LAN Access table were padded on the
  assumption that the browser draws every symbol one column wide; it draws
  several of them two columns wide, exactly as Termius does. Messages, menu
  rows and that table now line up there.

#### Display Settings
- Text no longer loses its last character in Termius. Lines that mix a
  status glyph with colour were being clipped by one cell per coloured section,
  so "Operation completed successfully" rendered as "successfull" and the
  two-column status row lost a character from BOTH halves. Measured rather than
  guessed: the terminal drops the final cell of each coloured section on any
  line carrying a glyph it paints wider than it reserves space for, so each
  section now ends with a spare space for it to take. A pixel-level overhang
  remains on some glyphs; that is a font metric and cannot be corrected from
  here.
- The display-mode preview's Help row sat a column left of the numbered
  items in Termius, and the same row was misaligned in the browser terminal.
- Termius was reported as "macOS/Linux" in Toolkit Management while the
  Display Settings page correctly identified it. Both now agree.

## 2026-07-27
### What's New
#### Toolkit-wide
- While the toolkit waits for the terminal to apply a resize, it says
  so with a progress message instead of sitting on a blank screen, which read
  as a hang on terminals that ignore the request. The message only appears once
  the wait is long enough to notice; terminals that resize promptly still show
  nothing.
- The window-size prompt now confirms what happened. Rechecking after
  a successful resize says so, and continuing at a small size acknowledges the
  choice, rather than either clearing straight to the splash with no output.

### Bug Fixes
#### Toolkit-wide
- Package installation on OpenWrt 25, which replaced opkg with apk. All
  package operations now go through a small abstraction that picks whichever
  manager the router has, so installing, removing and checking work on both.
  This is what stopped zram swap installing on OpenWrt 25 - nothing about zram
  itself was wrong. This also covers the two places that bootstrap themselves:
  the coreutils-stty install on first run (without which the display silently
  drops to Compatible mode) and the post-upgrade package restoration hook.
- Startup no longer paints the splash and then visibly shifts it, and
  output from the previous run no longer appears above it. Both had the same
  cause - the splash was drawn before the window was widened. Clearing the
  screen does not clear the scrollback, and widening a window pulls
  scrolled-off lines back into view, so the remnants arrived after the clear
  rather than before it. Nothing is drawn now until the window has settled at
  its final size.
- The minimum window height was one row short. Hardware Information
  page 1 needs 33 rows, not 32 - the blank line above the header was missed
  when it was measured.
- The terminal-size check no longer warns about a window that is already
  being resized. It asks the terminal to resize, then waits up to 5 seconds for
  that to take effect before judging, instead of reading the old size
  immediately. Terminals known to ignore the request - Termius - are not asked
  at all, so their advice appears straight away rather than after a wait for
  something that was never going to happen.

#### Benchmarks
- Ookla Speedtest now explains itself instead of failing late on MIPS
  routers. Ookla ships its own binary and does not build one for MIPS, so the
  install could never succeed there - but it only failed after downloading,
  with nothing saying why. It now says so before starting and points at
  LibreSpeed and iperf3, which both work.
- The cooldown pause in the CPU thermal stress test could be skipped
  entirely on a build without busybox's `usleep`, making the "after cooling"
  temperature a duplicate of the peak reading rather than a real measurement.
  It now falls back to a plain sleep of the same length, as the other pauses
  already did.

#### Bandwidth Limiter
- A stray combining character in the guest-limits status made one of the
  two arrows render as a mangled mark. Arrow style is now consistent across
  user-facing text.

#### Display Settings
- The Full-mode samples on the display-mode preview were spaced for a
  typical terminal rather than the one in use, so they rendered short in
  Termius. They now follow the same per-terminal spacing as the rest of the
  toolkit.

## 2026-07-26
### What's New
#### Remote LAN Access
- Remote LAN Access under VPN Tools — a single screen that explains, in
  plain terms, exactly which traffic can cross your VPN tunnel and which cannot,
  and lets you change it. It enumerates every source-and-destination combination
  in both directions rather than showing one summary line, so "it doesn't work"
  becomes a specific row with a specific reason.
- Each row is marked Active, Inactive, or Remote only. "Remote only" means the
  setting lives on the other router and cannot be changed from here — previously
  the most common source of confusion when remote LAN access silently failed.
- Detects the remote LAN subnet automatically where that is possible: from the
  tunnel's own configuration, by querying the remote router over SSH when key
  trust exists, or by probing well-known gateway addresses. Values that were
  guessed rather than read are marked with an asterisk, because a probed subnet
  assumes a /24 that may be wrong.
- Routes and per-peer authorisation are written to GL's own configuration keys,
  so changes appear in the GL web UI under Route Rules and survive a reboot.
- Firewall changes that could cut your own connection now apply under
  commit-confirm: the change is made, and reverts automatically after 30 seconds
  unless you confirm you are still connected. The revert runs detached, so it
  still happens if the session dies mid-change.
- Refuses outright to route between two identical subnets, and never proposes a
  probed subnet that matches your own LAN.
- Reachability testing is honest about what it cannot know: inbound can only be
  proven by the remote router, so it is reported as untestable rather than
  guessed from local configuration.
- The tunnel line reports what it can actually measure: WireGuard shows the real
  time since the last handshake, and flags a peer that has never connected at all
  — which is the first thing to check when nothing works. OpenVPN exposes no
  handshake time, so none is claimed for it.
- Router-to-router SSH key trust can be set up from the screen, letting the
  toolkit query and test the far side without a password each time. Keys the
  toolkit installs are tagged, so revoking removes only its own key and leaves
  any you added by hand untouched.

#### VPN MTU Optimizer
- The OpenVPN MTU recommendation is now derived from the tunnel's actual
  cipher and transport instead of a fixed conservative allowance. Measured against
  a live tunnel, UDP with AES-256-GCM costs 52 bytes, not the 69 previously
  assumed — so a 1500-byte link now recommends 1448 rather than 1431, recovering
  17 bytes of payload on every packet. Where the cipher cannot be determined the
  old conservative figure is still used.

#### Package and Persistence Manager
- Added diffutils to the optional package manager.

#### Toolkit-wide
- On startup the toolkit now checks the real terminal size and says plainly
  if the window is too small, including how many columns or rows are missing. It
  already asks the terminal to resize itself, but some terminals ignore that
  request silently, so this tells you rather than leaving you with a wrapped
  table. Offers a recheck, because several terminals show no size indicator.

### Bug Fixes
#### Remote LAN Access
- Masquerade and remote-access changes are now refused outright when the
  VPN's firewall zone is disabled, instead of appearing to succeed. A disabled
  zone is skipped entirely by the firewall, so the setting was being written and
  read back correctly while having no effect at all.
- The Remote LAN Access status column now uses per-terminal padding
  matched to how each glyph actually renders. On terminals that draw emoji at a
  different width than they report, the Active/Inactive/Remote-only markers no
  longer push the table out of alignment.

## 2026-07-21
### What's New
#### VPN MTU Optimizer
- VPN Tools menu with an MTU Optimizer — detects your active WireGuard and
  OpenVPN tunnels and recommends the right MTU (underlay link MTU minus the
  protocol overhead), so VPN traffic stops fragmenting. Apply with one keypress,
  set manually, clear the override, or run an optional active probe.
- The MTU is written to the router's own VPN configuration, so it shows up in
  the GL web UI under that tunnel's Options and survives a reboot.
- On routers with more than one tunnel, Optimize and Reset can act on every
  tunnel at once ([A] All), each with its own correct value.
- Reset MTU removes the override outright. On older firmware the web UI can set
  an MTU but not clear it again, so this is the only way to get a tunnel back to
  the router's own default.

### Bug Fixes
#### System Configuration Viewer
- View UCI → VPN Configuration now recognizes GL's WireGuard/OpenVPN
  servers and clients instead of only stock-OpenWrt configs, so it no longer
  reads "No active VPN configurations found" on server-only routers.

## 2026-07-12
### What's New
#### Hardware Information
- Hardware Info reports Wi-Fi MIMO from the driver's configured antenna
  chainmask (correct 2x2 / 3x3 / 4x4 per band) instead of inferring it from the
  channel width, which mislabeled radios that run more than two spatial streams.

## 2026-07-10
### What's New
#### Toolkit Management
- Change Log & Updates are now one screen: browse the full history in the house
  pager and update in place with `[U]` — the separate "Check for Updates" item
  is gone.
- Toolkit Management STATUS now shows your running version and whether an update
  is available.
- The changelog viewer marks where your installed version sits, so everything
  above the line is what's new to you.

## 2026-07-09
### What's New
#### Benchmarks
- Benchmark leaderboards expanded — added Flint 2, Beryl AX, Brume 3, Flint 3,
  and Beryl (original) as reference devices.
- VPN & Crypto benchmark now paginates by test (WireGuard / OpenVPN / RSA on
  their own pages), so it stays readable as the device list grows.
- Memory benchmark runs much faster on low-RAM devices (smaller test size).

#### Toolkit Management
- See what's changed before updating, plus a "Display Change Log" option
  under Toolkit Management.

#### Display Settings
- Display Settings now shows your saved default, and your preference survives
  script updates.

#### Toolkit-wide
- Terminal auto-sizing and a dark theme on launch, restored when you exit.
- More reliable terminal detection: it requires a real `stty` and, when it
  can't probe, falls back to clean Compatible mode instead of a mixed profile.

## 2026-07-04
### What's New
#### Benchmarks
- Cross-device benchmark leaderboards (VPN & Crypto, Disk, Memory), ranked
  against saved reference routers instead of a single baseline.

#### Hardware Information
- Robust CPU frequency detection (lscpu / cpufreq sysfs / device-tree OPP).

#### Toolkit Management
- Install as a system command (Toolkit Management) with sysupgrade persistence.

#### AdGuardHome
- Restore only offers components that were actually backed up.

#### Display Settings
- Renders correctly in PuTTY and Windows Terminal, not just macOS/iTerm
  (adaptive symbol set that avoids garbled boxes and misaligned columns).

#### Toolkit-wide
- UI/UX standardization pass across menus: input prompts, alignment, dividers,
  and spacing.

## 2026-04-19
### What's New
#### Zram Swap
- Clearer wording in the zram swap tuning help.

## 2026-04-16
### What's New
#### Web-UI Terminal
- Web terminal (ttyd) now supports HTTPS.

## 2026-04-10
### What's New
#### Web-UI Terminal
- Browser-based web terminal (ttyd) launched straight from the router.

## 2026-03-21
### What's New
#### Bandwidth Limiter
- Guest-network controls — set per-guest speed limits and optionally allow
  the guest network to reach the router.

## 2026-03-15
### What's New
#### Fan Control
- Refined fan-speed calculation.

## 2026-03-13
### What's New
#### Fan Control
- Fan control now shows a live, real-time readout.

#### Benchmarks
- iperf network performance testing.

## 2026-03-12
### What's New
#### Hardware Information
- Faster Hardware Information screen with UI polish.
- Better hardware detection on older routers.

### Bug Fixes
#### Fan Control
- Fixed a rounding error in manual fan control.

## 2026-03-11
### What's New
#### System Tweaks
- System Tweaks menu — fan control, package manager, and SSH-key install.

### Bug Fixes
#### Benchmarks
- Fixed the Apache benchmark package dependency (apache-utils → apache).

## 2026-03-05
### What's New
#### Benchmarks
- Install a LibreSpeed test server.

## 2026-03-02
### What's New
#### Benchmarks
- Ookla Speedtest Server benchmark.
- Stress test display supports a wider range of devices and temperatures.

## 2026-03-01
### What's New
#### Hardware Information
- More reliable CPU info (lscpu) and disk-space reporting when AdGuardHome was
  never installed.

#### Benchmarks
- Unified benchmark UI.

## 2026-02-28
### What's New
#### Hardware Information
- Real-time monitoring of CPU fan, temperature, and uptime.

#### Benchmarks
- Falls back to stress-ng where stress isn't available on OpenWrt.

## 2026-02-22
### What's New
#### Toolkit-wide
- Menu option updates.

## 2026-02-21
### Bug Fixes
#### Hardware Information
- Fixed memory and storage calculation on the Beryl (original).

## 2026-02-20
### What's New
#### Benchmarks
- OpenSpeedTest server installer — the toolkit is now all-in-one.

#### AdGuardHome
- AdGuardHome handles client requests.

### Bug Fixes
#### Toolkit-wide
- Assorted UI fixes.

## 2026-02-19
### Bug Fixes
#### Hardware Information
- Fixed disk-size detection.

#### Benchmarks
- Benchmark UI formatting fixes, including the Memory I/O test.

## 2026-02-15
### What's New
#### Toolkit-wide
- Major reorganization of the toolkit.

#### AdGuardHome
- SOS AdGuardHome factory restore.

#### Benchmarks
- Expanded benchmark suite and added LAN info.
- More precise DNS benchmark.

## 2026-02-11
### What's New
#### AdGuardHome
- Manage AdGuardHome direct access.
- Clean up old backups.

#### Toolkit-wide
- Unified GUI elements.

## 2026-02-10
### What's New
#### Hardware Information
- Wireless detection now reports interface, band, HT mode, MIMO, and channel for
  each radio.

#### AdGuardHome
- AdGuardHome maintenance grouped under an "AdGuardHome Maintenance Hub."

## 2026-02-08
### What's New
#### Toolkit-wide
- First public release.
- AdGuardHome Lists Manager, wireless interface detection, and refined menus,
  help text, and install/removal flows.

## 2026-02-07
### What's New
#### Toolkit-wide
- Initial toolkit script.
