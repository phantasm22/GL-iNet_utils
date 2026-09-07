# Changelog

All notable changes to the GL.iNet Utilities toolkit. Newest first. Versions
match the `# Version:` line in the script — `YYYY-MM-DD`, or `YYYY-MM-DD_HH:MM`
for multiple releases on the same day.

## 2026-09-06_20:06
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
- **Tailscale added to the Package & Persistence Manager** — installs the daemon plus GL's integration
  (admin-panel toggle, kill-switch) and removes both cleanly to free the space; available across current
  firmware (opkg and apk).

## 2026-09-01
- **AdGuardHome Lists Manager:** after applying changes it now shows an animated **download-progress**
  spinner ("Downloading lists N of M") while AdGuardHome fetches the newly-enabled lists, instead of
  sitting silently — so a large add no longer looks hung, and the Memory Impact meter is accurate when
  the screen returns. Lists that finish are confirmed; lists that can't fit (filter storage full) are
  reported and removed; lists still downloading are called out as in-progress rather than as failures.
- **Filter Storage Space Limit:** re-enabling the cap now **warns when your current lists won't fit**
  (showing space used vs. available) and asks you to confirm, since lists that don't fit silently stop
  loading. The AdGuardHome Control Center rule count also refreshes correctly now after the storage
  limit is turned on or off.
- Multi-line **info / warning / error messages** now indent their continuation lines automatically, so
  wrapped advisories line up cleanly under the icon across the toolkit; converted the last raw advisory
  block on the storage screen to the standard message style.

## 2026-08-28
- Rebuilt the **AdGuardHome Lists Manager** as a two-column editor modeled on the Package & Persistence
  Manager: each list has an **Install** and an **Enable** toggle, typing its number cycles through the valid
  actions for its state, and a **Planned Action** column shows exactly what will happen before you Confirm.
- Added a curated, sectioned catalog — **Recommended** (Phantasm22's lists + HaGeZi Pro++ + URLHaus +
  PhishTank/OpenPhish), plus **General**, **Security**, and **Allowlist** picks — alongside any lists you
  already have; the recommended set installs and enables by default.
- Added a **Memory Impact** meter showing the rules AdGuardHome will actually load against the router's RAM
  (and zram swap), turning amber/red as a selection approaches what the box can hold — so big lists can't
  silently exhaust memory.
- Added guard rails for constrained routers: it offers to enable **zram swap** when memory would run high,
  and — on models with a filter-storage cap — warns when a selection won't fit and offers to remove the cap.
- After applying, it now **verifies each enabled list actually downloaded**; lists that couldn't (filter
  storage full) are reported and removed instead of being left installed-but-empty.
- Fixed: removing a list now reclaims its disk space (AdGuardHome leaves orphaned filter files behind), and
  re-adding a list reuses its file instead of accumulating orphans that can fill a capped filter partition.
- Fixed: filter-storage-limit removal (Advanced Settings, and the Lists Manager guard rail) now verifies the
  partition actually unmounted before reporting success, and recovers from a half-removed state.
- Added a **Zram Swap** shortcut and renamed the AdGuardHome "Setup, Access & UI Updates" submenu to
  **Advanced Settings**.

## 2026-08-27
- Fixed: the Package & Persistence Manager could show a package as "persisted" while it wasn't installed,
  and "Disable Persistence" silently did nothing. Persistence now follows installation — a package that
  isn't installed never shows as persisted, uninstalling always clears persistence, and disabling
  persistence on an installed package actually removes it from the sysupgrade keep-list and boot-restore
  list.
- Changed: **stress-ng** (a CPU stress tool) is now withheld only on kernels older than 6.6 — where a Linux
  memory-pressure bug can hard-crash the router — instead of on all GL.iNet firmware. Newer firmware
  (kernel 6.6+, e.g. OpenWrt 25) can use it safely again; older kernels use `stress` only. Applies to both
  the Package Manager and the CPU stress benchmark.
- Changed: the "hard refresh" hint shown after Web-UI Terminal changes now lists the shortcut per browser
  (Chrome / Edge / Firefox: Ctrl+F5 or Ctrl/Cmd + Shift + R; Safari: Cmd + Option + R), on indented lines
  that fit the screen, and reads consistently in both enable and disable.

## 2026-08-26_17:12
- Fixed: the Package & Persistence Manager wrongly reported "System changes applied" when a package could
  not actually be removed. Removals are now verified and reported honestly — a package required by other
  installed packages is kept (with the option to type `YES` to force-remove it despite a warning listing
  the dependents), a non-opkg "raw" utility has all of its files removed (no leftovers), and anything that
  could not be removed is listed rather than silently claimed as done.
- Changed: on apk-based firmware, Package System Repair can now also restore the factory package database
  from read-only firmware (`/rom`) as a last resort, matching the opkg behavior (lossy — clearly warned).
- Fixed: the Web-UI Terminal now confirms the ttyd service actually started before reporting success. If it
  did not (an invalid certificate, a wrong system clock, or the port already in use), it shows the reason
  and skips patching the Admin Panel — instead of a false "Installed" message and a button that opens a
  dead page.
- Changed: the "hard refresh" hint now includes Safari's shortcut (Cmd+Option+R) alongside Ctrl+F5 and
  Cmd+Shift+R.

## 2026-08-26
- Changed: Package System Repair now escalates a corrupt installed database through one shared repair
  flow, so "Repair now" and "Repair the installed database" behave and read identically. It tries, in
  order: (1) a safe end-of-file repair; (2) rebuilding the database from opkg's own on-disk per-package
  metadata (`/usr/lib/opkg/info/*.control`), which keeps your actual installed packages; and, only as a
  last resort before re-flashing, (3) restoring the **factory package database from read-only firmware**
  (`/rom`) — lossy (opkg forgets post-factory package records, though the files stay on disk).
- Changed: the repair no longer makes a "pre-repair backup" of the corrupt database — there was nothing
  worth restoring in it, and it cluttered the backup list. The "restore a backup" advice now appears only
  when you actually have an earlier backup to roll back to.

## 2026-08-25
- New: **Package System Repair** under System Tweaks. Fixes a corrupted package system — the opkg
  `parse_from_stream_nomalloc: Missing new line character at end of file` error, which makes package
  installs and removals fail (or silently do nothing). It measures the state live (package manager,
  installed database, index cache, internet, backups), then can rebuild the re-fetchable feed cache
  and/or repair the installed database (opkg's `/usr/lib/opkg/status` or apk's `/lib/apk/db/installed`).
  The database is backed up before any change and is never deleted; deeper damage falls back to a restore.
- New: package installs now self-heal automatically. If the downloaded feed index is corrupted, the
  toolkit silently rebuilds the (fully re-fetchable) cache; if the installed database is the cause, it
  offers a guarded, backed-up repair inline instead of just failing.
- Changed: backups now live in one place — `/etc/glinet_utils/backups`. Existing AdGuardHome backups
  are migrated there automatically when you upgrade to this version; nothing is lost.
- Fixed: in the Network Bandwidth Limiter, the "Applying limit" spinner hugged the value-entry line
  when HW acceleration was already off (the confirmation that normally added the spacing was skipped).

## 2026-08-24_21:00
- Fixed: the Package Manager showed a blank size for most packages on **apk**-based systems (newer
  GL firmware and OpenWrt 24.10+/25) — the size lookup only understood opkg's package feeds. It now
  reads sizes from `apk info -s` (which covers both installed and available packages), so the Size
  column fills in on apk the same as on opkg. The Ookla **speedtest** binary (installed from Ookla,
  not in any package feed) now shows a size estimate too, like speedtest-go — on both apk and opkg.

## 2026-08-24_20:48
- Changed: the Bandwidth Limiter now preflight-checks for `tc` (traffic control) and installs
  `tc-tiny` if it's missing — so shaping still works if the package was removed — instead of
  failing at the first `tc` command. If it can't be installed, it says so instead of silently
  doing nothing.
- Added: **openssl-util** to the Package Manager's installable tools list, so it can be installed
  proactively (the crypto benchmark and Web-UI Terminal HTTPS use it).

## 2026-08-24_20:10
- Fixed: the crypto benchmark and the Web-UI Terminal's HTTPS certificate both need the `openssl`
  command, which GL firmware ships (openssl-util) but stock/vanilla OpenWrt does not — so on bare
  OpenWrt they failed. The toolkit now **installs openssl-util automatically** when `openssl` is
  missing (via the apk/opkg-aware installer) instead of erroring or failing silently.
- Fixed: the Web-UI Terminal's HTTPS setup printed "Generated certificate" even when generation
  actually failed (e.g. no openssl), leaving ttyd on HTTPS with no cert/key. It now verifies the
  cert and key were really created and **falls back to HTTP** if not.

## 2026-08-24
- Fixed: the memory-throughput benchmark reported the wrong RAM on some devices (a 128 MB
  GL-MT300N "Mango" showed 256 MB) — it used its own estimate (kernel MemTotal + 30 MB, rounded
  up to the next 128) which overshot into the wrong bucket. It now shows the same figure as
  Hardware Info screen 1 (MemTotal rounded to the nearest common size), so the two always agree.
- Changed: RAM-size rounding now recognizes the 1.5× sizes (192 MB, 384 MB, 768 MB, 1.5 GB, 3 GB,
  6 GB, 12 GB), so a device with one of those isn't rounded up to the next power of two, and a
  device reporting ~3 GB no longer rounds to 4 GB. Both screens share one rounding helper.

## 2026-08-21_10:01
- Fixed: the self-installer could replace the installed `glinet_utils` command with a copy of
  **BusyBox** (so it printed `applet not found`) when the toolkit was piped into a shell — `$0`
  resolved to `/bin/sh` → BusyBox and the installer copied that. It now verifies the source really
  is the toolkit (shebang + `# Version:` marker) before copying, and doesn't offer to install at
  all on a piped/stdin run.
- Changed: the Bandwidth Limiter's "turn off hardware acceleration" prompt is now an **informational
  note** (not a warning) with a **Yes default** — it describes the side effect of the limit you
  just asked for, and that acceleration turns back on by itself when the last limit is removed,
  instead of reading like a caution against limiting.
- Changed: the per-network router-access action is now **"Enable / Disable router to be reachable
  on all ports"** (context-aware) instead of "Allow full router access" / "Block router access" —
  the old "Allow" implied a web-UI permission, and "Block" was inaccurate (turning it off only
  falls back to the default partial access; it does not block).
- Fixed: the router-access detail notices (managed-by-zone / no-zone) now use the standard info
  style with an icon instead of hand-painted yellow text.

## 2026-08-21
- Added: a scrollable **help viewer** — every help screen now pages with `[P]` Previous /
  `[N]` Next / numbered jumps / `[0]` Back instead of scrolling off the top of the window on a
  shorter terminal. Page breaks fall on blank lines so a paragraph never splits across a page,
  and short help still shows on one screen.
- Added: a generalized **Network Bandwidth Limiter** replaces the guest-only limiter. It shapes
  any network the router actually has — LAN, guest, IoT, a VLAN, or a VPN tunnel — discovered
  automatically, in a grid with per-network Download / Upload limits, a measured Router-access
  dot, persistence, and live status. It lives under **Network and VPN Tools** (renamed from VPN
  Tools), alongside SSH Key Management; both moved out of System Tweaks. An existing guest
  limiter is migrated over automatically, so nothing breaks.
- Added: **Router access** per network is measured live from the firewall and shown as a
  red/amber/green dot matching the Remote LAN Access screen — reachable (all ports) / partial
  (some ports, e.g. the DNS + DHCP that GL opens by default) / blocked (no access). When
  partial, the detail page lists exactly which services are open (service / port / proto).
  "Allow full router access" opens all ports; "Block" falls back to partial, so DNS/DHCP keep
  working.
- Added: hardware acceleration is managed for you — applying any limit disables offload for the
  whole router (shaping needs the software path), and clearing your last limit re-enables it. The
  status line reports it health-aware: **DISABLED** / **ENABLED** shown green when nothing is
  bypassed, and yellow only when acceleration is on while a limit exists (that limit is then
  BYPASSED). **[H]** is a manual Enable / Disable override, **[R] Reset** reverts everything to
  defaults (removes every limit and router rule, re-enables acceleration, stops the background
  service), and the help explains the trade-off with measured CPU-cost figures.
- Changed: the detail screen follows the standard vertical layout — Status first, then the fields
  in the same order and names as the grid columns, status values ALL CAPS in both views.
- Fixed: Remote LAN Access flow-table columns misaligned on any row carrying the inferred-subnet
  dagger (†). `printf %-Ns` pads by *bytes*, and † is 3 bytes but 1–2 display cells; the columns
  now pad by measured display width (the dagger's cell width is probed per terminal), so they
  line up on macOS Terminal, Termius, ttyd, Windows Terminal, and PuTTY.
- Fixed: the AdGuardHome filter-space, zram-swap, and LibreSpeed removal confirmations painted
  their question yellow with no warning glyph; they now use the standard warning style — the bold
  glyph via the shared helper for the caution line, and a plain question — matching every other
  warning in the toolkit.
- Removed: the old guest-only limiter code (~500 lines) now that the generalized engine
  supersedes it; the System Tweaks help was corrected to match the current menu.

## 2026-08-18
- Added: the Package & Persistence Manager now shows a **Size** column (between Package Name
  and Planned Action) and a **Storage** line under the title. Size is the *install* size for
  every package - what it occupies on disk once installed, not the download - measured
  directly for installed packages (firmware/rom ones included) and taken from the package
  index for not-installed ones (an estimate). The Storage line shows the overlay's free space
  and, once changes are staged, the projected free space after them: a conservative "≈" floor
  on a compressing overlay (ubifs/jffs2, where uncompressed sizes overstate real flash use),
  exact on f2fs/ext4, turning amber when it would get low. Sizes are gathered on entry behind
  a spinner; **[S] Sort** toggles size / alphabetical with a ↓ on the sorted column.
- Added: on MIPS routers - where Ookla ships no binary - the Package Manager now offers
  **speedtest-go** as the installable internet speed-test entry (in place of the
  un-installable Ookla `speedtest`). Installing it also makes the "Ookla Internet Speedtest"
  benchmark instant, since it then uses the persistent copy instead of re-fetching each run.
- Added: `iperf3` and `iputils-ping` to the Package Manager.
- Changed: Planned Action colours now match the confirm screen - green for install/persist,
  red for remove/unpersist, dim grey for no change.
- Fixed: not-installed sizes stayed "-" even online - the empty-index check used `ls -A` on
  two directories (which prints directory-name headers, so it never read as empty); it now
  uses `find -type f`, so the index refreshes and sizes appear.
- Changed: size gathering is much faster - sizes come from a single pass over the package
  index feeds instead of one `opkg info` call per package (~3s each on MIPS); a refresh with
  the index already populated dropped from ~19s to ~5s.
- Fixed: the Package Manager's divider lines span the full width of the widest row.

## 2026-08-14
- Added: the Hardware Info **Network** page (page 3) is now a physical-port panel - a
  column grid (Port · Role · Status · Link · Maps to) grouped by the chip each port
  hangs off. It reads GL's port map (`eth_ports_config_map`) when present, with
  swconfig and raw-netdev fallbacks, so it works on old and new firmware with nothing
  model-specific hardcoded. Fixes two gaps: 2-port devices (which showed no chassis
  ports at all) now render, and multi-fabric devices like the BE14000 now match the
  web UI's silk labels. "Maps to" is the real `ifconfig` interface a port appears as;
  switch-group headers name the uplink and its speed (the switch→SoC pipe, not a
  per-port cap).
- Added: a per-page `[?]` Quick Help for the Hardware Information viewer (it had none)
  - a light explainer for each of the four pages, with a glossary on the Network page
  (Role, Link, Maps to, uplink).
- Changed: Remote LAN Access subnet detection now uses two scan tiers instead of
  three - a Standard scan that pings the common gateways (no dependency, works
  offline) and, only if that finds nothing, a Full scan that installs fping and
  sweeps every private /24 in seconds. The redundant middle tier is gone, so the
  flow is one scan then at most one prompt.
- Changed: the subnet-detection prompt is shorter and more precise ("No remote LAN
  answered on the common subnets. Run a full scan (every private /24, ~30s)?"), the
  standalone "Detecting…" line (which sat without a spinner) is gone, and the fping
  install now shows a spinner.
- Changed: progress spinners no longer print a trailing "…" - the spinner itself
  shows the operation is running, so labels read cleanly (e.g. "Scanning common
  subnets" with the spinner beside it).
- Changed: the Remote LAN Access topology diagram dropped its left rail, so the
  network column (e.g. `192.168.8.0/24`) lines up with the Status column of the flow
  table directly below it.
- Changed: on the paginated screens (MTU Optimizer, Remote LAN Access) a blank line
  now separates the action list from the [P]/[N] navigation footer, and a blank line
  precedes any status output, matching Hardware Info / Display.
- Fixed: the MTU active probe no longer leaves a double blank line after you answer
  "Run the probe? [y/N]".
- Changed: progress "…" is retired everywhere, not just on the spinners. Static
  action lines (Disabling HW Acceleration, Patching Web-UI, Stopping service, and
  ~25 others) and the two startup spinners drop the trailing dots; when a spinner is
  present it is the only "working" signal.
- Changed: Remote LAN Access [2] runs its SSH-to-peer lookup under a spinner, so the
  up-to-10s probe (a peer with no SSH) shows live progress instead of a frozen
  screen. A scan that finds nothing now says "No remote LAN found automatically"
  before the manual-entry prompt, which itself says "manually" so the reason is clear.
- Changed: prompts sit flush-left (column 0) with the status lines they follow
  rather than a 3-space indent - one clean left margin - and exactly one blank line
  follows a y/N answer before the resulting action.
- Fixed: the Guest Network Bandwidth Limiter's "Guest → GL Web UI:" value now lines
  up with the other CONFIGURATION STATUS values (the multibyte → left it one column
  short).
- Added: the Ookla Internet Speedtest now works on MIPS routers (e.g. the GL-MT1300).
  Ookla ships no MIPS build, so on MIPS the toolkit fetches speedtest-go - a maintained
  Go client that measures against the same speedtest.net servers - to /tmp on demand and
  runs a real WAN-to-internet test (download/upload/ping/jitter). Non-MIPS routers use
  the official Ookla binary exactly as before.
- Fixed: on MIPS the Ookla speed test used to print "not available", then fall through
  and "run" a missing binary that silently did nothing yet reported "completed". It now
  either runs (via speedtest-go, above) or soft-fails cleanly if the internet is down -
  the same way a failed package install does. (The earlier message that pointed at
  LibreSpeed/iperf3 as substitutes was misleading: those are LAN speed-test targets, not
  a WAN-to-internet measurement.)
- Changed: Termius glyph spacing corrected after a live re-measure. Menu keycaps
  (1-9, 0) and the Help/Clear markers now sit at a single space - a profile-aware
  separator lets Termius narrow to one column while every other terminal (macOS
  Terminal, Windows Terminal, ttyd, PuTTY) stays byte-for-byte identical - and the
  warning/info/action icons drop to one space as well (a current Termius no longer
  clips the trailing cell of a coloured run, so the old sacrificial pad is gone).
  The success/error/hourglass icons keep two spaces: they paint two cells but the
  cursor advances one, so a single space would butt the text.
- Fixed: on Termius the "Running Ookla/Internet Speedtest" and "Starting iperf3
  Server" headers lost their final character - the leading hourglass made Termius
  clip the last cell of the coloured run; a sacrificial trailing space restores it.
- Fixed: the CPU stress-test countdown no longer leaves a ghost digit when the
  remaining-seconds text shrinks (e.g. "10s" -> "9s"); each redraw clears to end of line.
- Changed: on the Hardware Info Network page, the "WAN address" and "LAN bridge"
  values now line up in the same column.
- Changed: CPU core reporting is topology-aware. Plain multi-core chips still read
  "Cores: N"; multithreaded parts (e.g. MT7621) read "Cores: 2 (4 threads)" and the
  stress test says "Stress testing 4 threads (2 cores)". Physical cores come from the
  kernel's /sys CPU topology, logical from /proc/cpuinfo - no per-model table.

## 2026-08-08
- Added: PuTTY (and other bare `xterm` / `putty` terminals) now get coloured status
  glyphs in Compatible mode instead of the plain ASCII markers. It uses the emoji
  PuTTY actually renders - ✅ ❌ ⏳ and the 🟢🔴🟡 traffic-light dots - and, because
  PuTTY draws emoji in monochrome, paints them via ANSI so the Remote LAN Access
  stoplights stay distinguishable. Warning/info/action use emoji-default stand-ins
  (❗ 💡 🔧) rather than ⚠️/ℹ️/⚙️, which PuTTY clips to half-glyphs (those are
  text-default codepoints it draws in a single cell). Menu keys - numbers, All,
  help and clear - stay in [brackets], which read cleanly there. Detected by TERM;
  genuinely limited terminals (serial console, TERM=linux/vt100) keep pure ASCII.
- Changed: Windows Terminal menus now number options with the bold negative-circled
  digits ❶..❾ + ⓿ (and Ⓐ for "All") instead of [1]..[0] text. The keycap emoji used
  on other terminals (1️⃣) box out on Windows Terminal, but these render cleanly and
  are single-width - advancing one cell, like the keycaps do - so the labels line up
  exactly as they do elsewhere. Help/Clear keep ❓/🆑, which render fine there.
- Changed: Remote LAN Access subnet detection now shows a spinner during the scan
  instead of a seconds-remaining countdown. The scan time is network-dependent, so
  the countdown drifted out of sync; the spinner just shows it is still working.
- Changed: the VPN MTU Optimizer now uses the same paginated layout as Remote LAN
  Access - one tunnel per page, [P]/[N] to move between them, and the four actions
  (Optimize tunnel / Set MTU manually / Verify with an active probe / Reset) act on
  the tunnel on screen. This replaces the old "which tunnel?" picker and the
  all-tunnels batch, and fixes the screen overflowing with three or more tunnels.
  Each page also gains a Status: Active/Inactive line and a Remote-LAN-Access-style
  navigation row.
- Fixed: an inconclusive MTU active probe (no reply, or the don't-fragment flag
  ignored) now clears any prior "Verified" basis, so the status returns to
  "Calculated from link MTU" instead of keeping a stale Verified value the path can
  no longer confirm - itself a signal that the tunnel's behaviour changed.
- Changed: the MTU active probe now shows the standard spinner while it searches
  for the largest packet size, instead of a static "Probing ..." line that looked
  frozen during the (few-second) don't-fragment sweep.
- Changed: the VPN MTU Optimizer and Remote LAN Access now share one paginated
  layout - a cyan identity line (tunnel + role-aware state: servers UP/DOWN, clients
  CONNECTED/DISCONNECTED with handshake age, ALL CAPS), a density divider sized to
  the widest content line, and a single realtime nav footer ("[P] Previous  Page N
  of M  [N] Next  [1/2/3/4]  [0] Back  [?] Help" - single keypress, cursor at the
  line end, no Choose prompt, shown even on one page where [P]/[N] just refresh). On
  Remote LAN Access the tunnel identity is promoted above the network diagram and
  OUTBOUND/INBOUND is highlighted. Pure-list screens keep no divider.
- Fixed: the AdGuardHome Backup Cleanup screen's two framing lines were different
  widths (55 vs 62); both now match at the widest content line (60).

## 2026-08-07
- Added: the Hardware Information wireless page now shows each radio's supported
  Wi-Fi standards. The Band line carries the marketing generation in parens
  (e.g. "5GHz (Wi-Fi 6)") and a new Protocol line lists the IEEE standards
  (e.g. "802.11a/n/ac/ax"). It reads the chip's real capabilities and is
  band-aware: 802.11ac is 5/6 GHz only, so 2.4 GHz is never labelled "ac" even
  on chips (some MediaTek parts) that advertise a VHT capability block there for
  the vendor 256-QAM rate extension. The generation also distinguishes Wi-Fi 6
  from 6E, which share the 802.11ax standard.
- Added: Flint 4 (GL-BE14000 / MT7988a) is now a recognised model - it appears by
  name in the benchmark comparison tables (VPN/crypto, disk, memory), has its CPU
  clock in the fixed-clock fallback, and is listed among the tested models.
- Changed: Remote LAN Access now reports MEASURED status, not guesses. Every
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
- Fixed: on laggy connections (for example Termius over in-flight wifi) the
  toolkit could misdetect the terminal type on startup and pick the wrong glyph
  widths, leaving symbols and colour runs misaligned. The terminal probe now
  waits out the round-trip and reassembles a reply split across reads instead of
  giving up after a fixed fraction of a second, while still answering instantly on
  a responsive terminal.
- Added: Remote LAN Access can now auto-detect the remote LAN subnet instead of
  making you type it. It sweeps candidate gateways THROUGH the tunnel and keeps
  only those that answer at zero hops (directly across the tunnel, not one hop
  upstream), in escalating tiers - Quick (common gateways, instant), Standard
  (192.168/16 + 172.16/12 + usual 10.x, a couple of seconds), and Full (every
  RFC1918 /24, 139,776 candidates, offered on demand with a countdown). Uses fping
  when present, a shell sweep otherwise. When several subnets are directly
  attached it lists them and lets you pick.
- Changed: Remote LAN Access menu was tidied up. Options are now one-per-line and
  use the app-wide Enable/Disable wording; on both directions [1] toggles
  reachability and [2] detects the subnet, with masquerade as an outbound-only
  [3]. The inbound "set up the remote router" option was removed - it only ever
  installed an SSH key and then told you to configure the remote by hand (and hung
  for a minute when the peer had no sshd); that guidance now lives in [?] Help.
  Also added "[?] Help" to the navigation row.
- Fixed: the Guest Network Bandwidth Limiter's "Help" line was indented one column
  short of the others on some terminals (the help glyph's trailing space differed
  by profile); it now lines up with the numbered options.
- Fixed: Remote LAN Access subnet detection now works on a tunnel that has no
  default route - for example an OpenVPN client with no pushed LAN route. The scan
  binds its probes to the tunnel interface, so it never actually needed a default
  route; the guard that required one wrongly refused to scan and sent you to manual
  entry.
- Fixed: subnet detection now excludes ALL of this router's own subnets, not just
  the current tunnel and the LAN - including other VPN tunnels that are configured
  but down. It was offering a router's own WireGuard range (reachable across a
  second tunnel) as if it were a remote LAN.
- Changed: the Remote LAN Access status legend now labels the third state
  "unknown" (🟡) rather than "not testable from here" - the Change column already
  says why and what to do, so the shorter word avoids reading as a dead-end when
  it just needs the subnet detected.
- Fixed: a few stale references in Remote LAN Access after the menu renumbering -
  the "route needs a subnet" hint pointed at "option 4", a post-route hint
  referenced the removed "test" option, and the "left unknown" message was long
  enough to wrap; all corrected.

## 2026-07-31
- Added: an in-screen "[?] Help" to the VPN MTU Optimizer, Remote LAN Access and
  VPN Tools screens (they had none), so every one of those menus can explain
  itself without leaving. The MTU help also explains that a failed active probe
  usually just means the server does not answer ICMP (not that the VPN is down),
  and that the tool keeps the Calculated value when it cannot verify - an
  inconclusive probe means "couldn't verify", not "broken".
- Fixed: the Package & Persistence Manager's "[?] Help" pointed at a help screen
  that was never written, so pressing it errored instead of showing help. The
  help now exists.
- Changed: the help screens were made consistent - every one opens with a
  "<Feature> - Quick Help" title, uses the same layout, and is triggered the same
  way. The AdGuardHome Direct Access help now shows your router's real LAN address
  instead of a hard-coded example, and no longer refers to menu items by number.
- Changed: the VPN MTU active-probe result screen now labels its rows "Calculated
  MTU" and "Verified MTU" (was "Old/New Recommended"), and when a probe cannot
  verify it reads "Verified MTU: unknown" and "Falling back to the Calculated
  <n>; this value was not actively verified" - so an inconclusive probe no longer
  reads as if the value had been confirmed. (Community feedback.)

## 2026-07-30
- Fixed: the VPN MTU active probe now works on OpenVPN clients. GL uses OpenVPN's
  `topology subnet`, so the tunnel interface has no kernel peer address and a
  working tunnel previously read as "not probeable". It now finds the far end
  correctly and reads the server's public address from the running config.
- Fixed: a WireGuard server with a configured-but-never-connected peer no longer
  reports a bogus probe. It targets only a peer that has completed a handshake,
  and says plainly when there is no connected peer to test.
- Changed: the active probe measures the path to the server's public address
  first, outside the tunnel, so the result does not depend on the don't-fragment
  flag surviving encapsulation; it falls back to a through-tunnel probe only when
  the public endpoint cannot be reached.
- Added: each tunnel on the MTU screen now shows a "Basis" line - whether the
  Recommended MTU is Calculated from the link or Verified by an active probe (with
  the date and target). A verified result is remembered and used as the
  recommendation, and is marked stale (back to Calculated) if the underlying link
  or the server address later changes.
- Changed: the probe result screen now speaks the status screen's language - it
  shows Current MTU, Old Recommended (the Calculated value) and New Recommended
  (what the probe found), a plain-language verdict, and reports that the tunnel's
  Basis is now Verified. Network jargon is explained in plain terms, including the
  don't-fragment (DF) edge case where a fragmenting path makes the probe read too
  high (the probe detects that and keeps the Calculated value).

## 2026-07-28_20:43
- Fixed: changing a Fan setting no longer removes the Web-UI Terminal button.
  Both features patch the same admin-panel file, and a fan change restored that
  file from stock - which silently dropped the terminal button while the toolkit
  still reported it as enabled. The button is now re-applied automatically after
  any fan change that had it.
- Changed: disabling or uninstalling the Web-UI Terminal now notes that custom
  Fan settings may need re-applying, for the same shared-file reason (only shown
  on models that have a fan).
- Changed: after a Fan setting change the toolkit reminds you to hard-refresh the
  admin panel - a normal reload can show the browser's cached copy and look like
  the change did not take.

## 2026-07-28
- Fixed: text no longer loses its last character in Termius. Lines that mix a
  status glyph with colour were being clipped by one cell per coloured section,
  so "Operation completed successfully" rendered as "successfull" and the
  two-column status row lost a character from BOTH halves. Measured rather than
  guessed: the terminal drops the final cell of each coloured section on any
  line carrying a glyph it paints wider than it reserves space for, so each
  section now ends with a spare space for it to take. A pixel-level overhang
  remains on some glyphs; that is a font metric and cannot be corrected from
  here.
- Fixed: the display-mode preview's Help row sat a column left of the numbered
  items in Termius, and the same row was misaligned in the browser terminal.
- Fixed: the Web-UI Terminal button did not appear on firmware 4.9.x. The button
  is injected next to the reboot icon in the admin panel header, but it worked
  out WHERE to put itself from the help icon beside it - and from 4.8.6 onward
  that icon moved into a support dropdown, so the button was inserted outside
  the toolbar where nothing could show it. It now positions itself relative to
  the reboot icon alone, which has stayed put across every firmware checked
  (4.3.25 through OpenWrt 25). Verified on both an affected and an unaffected
  firmware so the older ones behave exactly as before.
- Fixed: the Web-UI Terminal opened too small - 130x29, below the 101x33 some
  screens need, so the toolkit warned about window size inside its own web
  terminal. It now opens at the standard 110x33, with the font pinned so the
  size is consistent rather than following whatever the browser defaults to.
  Resizing, maximising and minimising all still work.
- Fixed: status symbols were spaced wrongly in the browser terminal. Ticks,
  crosses and the padlock in the Remote LAN Access table were padded on the
  assumption that the browser draws every symbol one column wide; it draws
  several of them two columns wide, exactly as Termius does. Messages, menu
  rows and that table now line up there.
- Added: the Web-UI Terminal screen shows the direct URL and port, so the
  terminal is reachable even if the panel button is missing on some firmware.
- Fixed: Termius was reported as "macOS/Linux" in Toolkit Management while the
  Display Settings page correctly identified it. Both now agree.

## 2026-07-27
- Fixed: package installation on OpenWrt 25, which replaced opkg with apk. All
  package operations now go through a small abstraction that picks whichever
  manager the router has, so installing, removing and checking work on both.
  This is what stopped zram swap installing on OpenWrt 25 - nothing about zram
  itself was wrong. This also covers the two places that bootstrap themselves:
  the coreutils-stty install on first run (without which the display silently
  drops to Compatible mode) and the post-upgrade package restoration hook.
- Fixed: startup no longer paints the splash and then visibly shifts it, and
  output from the previous run no longer appears above it. Both had the same
  cause - the splash was drawn before the window was widened. Clearing the
  screen does not clear the scrollback, and widening a window pulls
  scrolled-off lines back into view, so the remnants arrived after the clear
  rather than before it. Nothing is drawn now until the window has settled at
  its final size.
- Fixed: the minimum window height was one row short. Hardware Information
  page 1 needs 33 rows, not 32 - the blank line above the header was missed
  when it was measured.
- Changed: while the toolkit waits for the terminal to apply a resize, it says
  so with a progress message instead of sitting on a blank screen, which read
  as a hang on terminals that ignore the request. The message only appears once
  the wait is long enough to notice; terminals that resize promptly still show
  nothing.
- Changed: the window-size prompt now confirms what happened. Rechecking after
  a successful resize says so, and continuing at a small size acknowledges the
  choice, rather than either clearing straight to the splash with no output.
- Fixed: a stray combining character in the guest-limits status made one of the
  two arrows render as a mangled mark. Arrow style is now consistent across
  user-facing text.
- Fixed: Ookla Speedtest now explains itself instead of failing late on MIPS
  routers. Ookla ships its own binary and does not build one for MIPS, so the
  install could never succeed there - but it only failed after downloading,
  with nothing saying why. It now says so before starting and points at
  LibreSpeed and iperf3, which both work.
- Fixed: the Full-mode samples on the display-mode preview were spaced for a
  typical terminal rather than the one in use, so they rendered short in
  Termius. They now follow the same per-terminal spacing as the rest of the
  toolkit.
- Fixed: the cooldown pause in the CPU thermal stress test could be skipped
  entirely on a build without busybox's `usleep`, making the "after cooling"
  temperature a duplicate of the peak reading rather than a real measurement.
  It now falls back to a plain sleep of the same length, as the other pauses
  already did.
- Fixed: the terminal-size check no longer warns about a window that is already
  being resized. It asks the terminal to resize, then waits up to 5 seconds for
  that to take effect before judging, instead of reading the old size
  immediately. Terminals known to ignore the request - Termius - are not asked
  at all, so their advice appears straight away rather than after a wait for
  something that was never going to happen.

## 2026-07-26
- Fixed: masquerade and remote-access changes are now refused outright when the
  VPN's firewall zone is disabled, instead of appearing to succeed. A disabled
  zone is skipped entirely by the firewall, so the setting was being written and
  read back correctly while having no effect at all.
- Fixed: the Remote LAN Access status column now uses per-terminal padding
  matched to how each glyph actually renders. On terminals that draw emoji at a
  different width than they report, the Active/Inactive/Remote-only markers no
  longer push the table out of alignment.
- New: on startup the toolkit now checks the real terminal size and says plainly
  if the window is too small, including how many columns or rows are missing. It
  already asks the terminal to resize itself, but some terminals ignore that
  request silently, so this tells you rather than leaving you with a wrapped
  table. Offers a recheck, because several terminals show no size indicator.
- Changed: the OpenVPN MTU recommendation is now derived from the tunnel's actual
  cipher and transport instead of a fixed conservative allowance. Measured against
  a live tunnel, UDP with AES-256-GCM costs 52 bytes, not the 69 previously
  assumed — so a 1500-byte link now recommends 1448 rather than 1431, recovering
  17 bytes of payload on every packet. Where the cipher cannot be determined the
  old conservative figure is still used.
- Added diffutils to the optional package manager.
- New: Remote LAN Access under VPN Tools — a single screen that explains, in
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

## 2026-07-21
- New: VPN Tools menu with an MTU Optimizer — detects your active WireGuard and
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
- Fixed: View UCI → VPN Configuration now recognizes GL's WireGuard/OpenVPN
  servers and clients instead of only stock-OpenWrt configs, so it no longer
  reads "No active VPN configurations found" on server-only routers.

## 2026-07-12
- Hardware Info reports Wi-Fi MIMO from the driver's configured antenna
  chainmask (correct 2x2 / 3x3 / 4x4 per band) instead of inferring it from the
  channel width, which mislabeled radios that run more than two spatial streams.

## 2026-07-10
- Change Log & Updates are now one screen: browse the full history in the house
  pager and update in place with `[U]` — the separate "Check for Updates" item
  is gone.
- Toolkit Management STATUS now shows your running version and whether an update
  is available.
- The changelog viewer marks where your installed version sits, so everything
  above the line is what's new to you.

## 2026-07-09
- Benchmark leaderboards expanded — added Flint 2, Beryl AX, Brume 3, Flint 3,
  and Beryl (original) as reference devices.
- VPN & Crypto benchmark now paginates by test (WireGuard / OpenVPN / RSA on
  their own pages), so it stays readable as the device list grows.
- Memory benchmark runs much faster on low-RAM devices (smaller test size).
- Terminal auto-sizing and a dark theme on launch, restored when you exit.
- More reliable terminal detection: it requires a real `stty` and, when it
  can't probe, falls back to clean Compatible mode instead of a mixed profile.
- Display Settings now shows your saved default, and your preference survives
  script updates.
- New: see what's changed before updating, plus a "Display Change Log" option
  under Toolkit Management.

## 2026-07-04
- Cross-device benchmark leaderboards (VPN & Crypto, Disk, Memory), ranked
  against saved reference routers instead of a single baseline.
- Renders correctly in PuTTY and Windows Terminal, not just macOS/iTerm
  (adaptive symbol set that avoids garbled boxes and misaligned columns).
- Robust CPU frequency detection (lscpu / cpufreq sysfs / device-tree OPP).
- Install as a system command (Toolkit Management) with sysupgrade persistence.
- UI/UX standardization pass across menus: input prompts, alignment, dividers,
  and spacing.
- Restore only offers components that were actually backed up.

## 2026-04-19
- Clearer wording in the zram swap tuning help.

## 2026-04-16
- Web terminal (ttyd) now supports HTTPS.

## 2026-04-10
- New: browser-based web terminal (ttyd) launched straight from the router.

## 2026-03-21
- New: guest-network controls — set per-guest speed limits and optionally allow
  the guest network to reach the router.

## 2026-03-15
- Refined fan-speed calculation.

## 2026-03-13
- Fan control now shows a live, real-time readout.
- New: iperf network performance testing.

## 2026-03-12
- Faster Hardware Information screen with UI polish.
- Better hardware detection on older routers.
- Fixed a rounding error in manual fan control.

## 2026-03-11
- New: System Tweaks menu — fan control, package manager, and SSH-key install.
- Fixed the Apache benchmark package dependency (apache-utils → apache).

## 2026-03-05
- New: install a LibreSpeed test server.

## 2026-03-02
- New: Ookla Speedtest Server benchmark.
- Stress test display supports a wider range of devices and temperatures.

## 2026-03-01
- More reliable CPU info (lscpu) and disk-space reporting when AdGuardHome was
  never installed.
- Unified benchmark UI.

## 2026-02-28
- New: real-time monitoring of CPU fan, temperature, and uptime.
- Falls back to stress-ng where stress isn't available on OpenWrt.

## 2026-02-22
- Menu option updates.

## 2026-02-21
- Fixed memory and storage calculation on the Beryl (original).

## 2026-02-20
- New: OpenSpeedTest server installer — the toolkit is now all-in-one.
- AdGuardHome handles client requests.
- Assorted UI fixes.

## 2026-02-19
- Fixed disk-size detection.
- Benchmark UI formatting fixes, including the Memory I/O test.

## 2026-02-15
- Major reorganization of the toolkit.
- New: SOS AdGuardHome factory restore.
- Expanded benchmark suite and added LAN info.
- More precise DNS benchmark.

## 2026-02-11
- New: manage AdGuardHome direct access.
- New: clean up old backups.
- Unified GUI elements.

## 2026-02-10
- Wireless detection now reports interface, band, HT mode, MIMO, and channel for
  each radio.
- AdGuardHome maintenance grouped under an "AdGuardHome Maintenance Hub."

## 2026-02-08
- First public release.
- AdGuardHome Lists Manager, wireless interface detection, and refined menus,
  help text, and install/removal flows.

## 2026-02-07
- Initial toolkit script.
