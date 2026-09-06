#!/bin/sh
# GL.iNet Router Toolkit
# Author: phantasm22
# License: GPL-3.0
# Version: 2026-09-06
#
# ── Versioning (bump the line above before every push to GitHub) ─────────────
# The self-updater compares this value as a plain string (test's \> operator),
# so incrementing it is exactly what tells installed copies a newer release
# exists. Forget to bump it and nobody gets the update.
# Format: YYYY-MM-DD  (e.g. 2026-07-04). For multiple releases on the same day as
# the previous version, append _HH:MM in 24-hour time (e.g. 2026-07-04_14:30)
# so each still sorts as newer. It MUST stay lexically sortable — a later
# date/time has to string-compare greater than an earlier one.
# ────────────────────────────────────────────────────────────────────────────
#
# This script provides system utilities for GL.iNet routers including:
# - Hardware information display with pagination
# - AdGuardHome management (UI updates, storage limits, lists)
# - System tweaks (zram, SSH keys, package management)
# - Benchmarking tools (network speed tests, CPU stress test)
# - System configuration viewer
# - Self-update mechanism to fetch latest script from GitHub
# - User-friendly interface with color coding and emojis
# - Robust error handling and input validation
# - Designed for OpenWrt-based GL.iNet routers, tested on various models
# Note: Some features may require specific hardware capabilities or firmware versions.

# =============================================================================
# UI / UX STANDARDS  (read before changing any prompt, menu, or message)
# =============================================================================
# Governance principle
# --------------------
# Clarity first, concision second. Every prompt and selectable label names the
# specific thing it acts on ("Delete this backup?" not "Confirm"). Use plain,
# conversational language and the fewest words that keep the action
# unambiguous - cut filler, never cut comprehension. Generic verbs ("OK", bare
# "Confirm", "Submit") and cryptic abbreviations are prohibited, as is padding
# that adds no information.
#
# "Choose" vs "Enter command"
#   "Choose [...]:"   one input is definitive/terminal (a choice).
#   "Enter command:"  inputs mutate pending on-screen state in a loop until a
#                     separate [C] Confirm (a command is a subset of choice).
#
# Vocabulary (locked)
#   [C] Confirm   [0] Exit / Main menu / Back / Cancel (by depth/context)
#   [?] Help      multi-select: [A] All  [N] None  [#] Toggle
#   pager: [P] Prev  [N] Next         [X] is never used.
#
# Naming (locked)
#   Functions and shell variables are plain snake_case - NEVER a leading
#   underscore. Scope function variables with `local` (declare every one); do
#   not use a _prefix as ad-hoc collision avoidance, that is what `local` is
#   for. Reserved exceptions, do not "clean up":
#     - _S_OK/_S_WARN/... , _TERM_PROFILE, _TERM_ORIG_SIZE, _TERM_RESTORED:
#       deliberate script-global symbol/state vars (uppercase, cross-function).
#     - variables inside the EMBEDDED JAVASCRIPT injected into the ttyd web UI
#       (manage_web_terminal): the _prefix there avoids colliding with the host
#       page's own globals. That is JS, not shell - leave it alone.
#   Before any bulk rename: check the function for embedded awk/JS/sed bodies,
#   and never reverse-rename single letters (\bn\b matches the n in "\n").
#
# [0] label by depth
#   root -> Exit ;  depth-1 child -> Main menu ;  depth-2+ -> Back ;
#   pending/discard screen -> Cancel  (tie-break: does [0] discard pending state?)
#   free-text entry -> advertise cancel inline ("(1280-1500, 0 to cancel)"); a
#   deliberate backout (0 or empty) returns quietly - never an error.
#
# Prompt & flow rules
# 1. Disclose-then-ask, in exactly two parts: a disclosure and a terse prompt.
#    The disclosure (consequence of the non-default answer) is carried by status
#    message(s) - one or more, each properly iconed (ℹ️ info / ⚠️ warning) - OR
#    folded into the prompt line itself; never spread across a status line PLUS
#    separate UNPREFIXED body text. Each status line STATES, it never asks; the
#    one question is the terse prompt, phrased with a specific action verb (not a
#    generic "Continue/Yes"), especially for destructive actions. Don't re-ask
#    what the disclosure already said (no "Are you sure?"). Spacing depends on
#    what the disclosure IS - read => tight, scan => separated: inline PROSE (a
#    warning/explanation that is the decision's context) hugs the prompt, no blank
#    above it (Gestalt proximity); multiple independent warnings get one blank
#    BETWEEN them but still hug the prompt. A reviewable BLOCK the user scans - a
#    list, table, or change-summary - is its own region: separate it from the
#    action/prompt with one blank line or a divider (Gestalt common region; the
#    modal body-vs-footer pattern, same as a menu's options => "Choose").
#    Exception - a MID-FLOW interruption: when the disclosure+prompt appear AFTER the
#    user has already answered a DIFFERENT prompt in the same flow (e.g. typed a value,
#    then a "that requires X - proceed?" surprise), the disclosure (info or warning) is a
#    NEW component, not a leading disclosure - give it ONE blank line ABOVE it to detach it from the
#    finished entry, then hug its own prompt below as usual. (The action that follows
#    the answer still gets its one blank per rule 10.) See _netlimit_offload_ok.
# 2. Yes = the action; the capitalized default marks the safe side
#    (destructive => [y/N], expected/safe => [Y/n]). Never invert (no Yes=no-op).
# 3. Wording is the behavioral contract. Transition framing ("Enable it?") =>
#    N is a no-op (keep current). Declarative framing ("Should this persist?")
#    => N enforces the opposite (removes). Code MUST match the words. Prefer
#    transition framing for stateful toggles; never let N silently destroy.
# 4. State-first, valid transitions only. Show current state, then offer only
#    reachable transitions: for binary state, a single adaptive label that names
#    the concrete next action ("Enable X" when off / "Disable X" when on); an
#    action set (e.g. AGH Service Health [D]/[R]/[0]) for multi-state. Never force
#    the user to act twice to reach a state, and never label an item "Toggle" -
#    the label must state what it will do now. ([#] Toggle stays reserved for the
#    multi-select selection key, a different meaning.)
# 5. Check before you ask. Never present a [y/N] for an action already satisfied
#    or currently impossible. Refuse early and quietly when impossible;
#    warn-and-explain when already satisfied. No silent greying-out of menu
#    items without explanation.
# 6. Idempotent, truthful results. Report the ACTUAL delta ("Enabled" /
#    "Already set - no change" / "Removed" only when something was removed),
#    never a blanket success message.
# 7. Context-appropriate status. Every status/info/success/warning line must be
#    a direct response to the user's preceding action or answer. Never emit a
#    status about a topic the user didn't act on (no orphaned status). If a
#    state is worth surfacing absent a related action, fold it into the relevant
#    action's output rather than printing it standalone.
# 8. Ambient-state, not re-asked. For low-harm, easily reversible state, show
#    the state as status and expose the change as a named action: ask at most
#    once at the natural decision point, never re-ask once satisfied, always
#    offer a visible reversal. Forced/repeated confirmation is reserved for
#    destructive or irreversible actions.
#    A named menu action IS the decision - selecting it commits. Do NOT gate a
#    safe, reversible action behind [y/N]; confirm ONLY when the action is
#    destructive/irreversible (discards state the user set), or has side effects
#    the label doesn't convey (installs a package, mutates live state) - there
#    the disclosure earns the prompt. Don't confirm when the outcome is the
#    ideal/expected state with a visible reversal, or when the user already
#    typed the exact value (typing it IS the commit). Worked example - VPN MTU
#    Optimizer: Optimize and Set-manually do not ask; Reset ([y/N], it discards
#    the user's value) and the active probe ([y/N], it installs iputils and
#    briefly raises the live MTU) do.
#    A selector must never carry an action verb: "[A] All Tunnels" under an
#    "Optimize which tunnel?" header, never "[A] Optimize All Tunnels" - a verb
#    reads as a commit and turns any following prompt into a redundant re-ask.
#    Status word MATCHES the control verb, positive polarity. A state shown as status
#    reads in the SAME verb family as the action that changes it: a feature toggled with
#    Enable/Disable reports ENABLED/DISABLED (not ON/OFF); a device/service switched On/Off
#    or Start/Stop reports ON/OFF or RUNNING/STOPPED. Never pair an Enable/Disable control
#    with an ON/OFF readout, and (toggle-label std) the action label states what pressing
#    does NOW ("[H] Disable HW Acceleration"), never "Toggle". Name the THING in the label,
#    put the STATE in the value, positive-polarity - never a negated label with a boolean
#    ("Disabled: TRUE", "Not persisted: FALSE"): that forces a double-negative read. When a
#    state is desirable on one screen but not intrinsically "good" (HW Acceleration DISABLED
#    is the READY state on the Bandwidth Limiter), COLOR carries the health (green nominal /
#    yellow attention), not the word - see manage_netlimit.
# 9. Dwell mechanism. Match how a screen waits to its information value. User-
#    paced ("Press any key") for anything the user must READ - help, reports,
#    status/lists, and action results whose detail won't survive the return to a
#    cleared menu; also for any error needing user action. Timed auto-clear
#    (toast) ONLY for self-evident feedback that returns to a screen already
#    showing the situation: wrong-key validation (~1s) and content-bearing
#    no-op/cancel notices (~2s). Never zero-dwell - a message must never flash
#    and vanish with no pause.
# 10. Vertical spacing. One blank line is the unit of separation between
#     components (a section and the next prompt, a result and its footer).
#     Separators are leading-owned: the element BELOW emits the gap (a menu's
#     "\nChoose", press_any_key's leading "\n", a section's leading blank);
#     content never carries trailing blanks at a boundary - that is what causes
#     accidental double blanks. press_any_key is the single source of truth for
#     footer spacing (one blank); callers MUST NOT prepend printf "\n" before it.
#     Double blank lines are reserved for major in-screen section dividers only,
#     never at a component boundary. A printf "\n" is context-dependent: after
#     `read -r` (Enter echoed a newline) it is a BLANK line; after read_single_char
#     / `read -rsn1` / a bare prompt (no echoed newline) it is the line TERMINATOR,
#     not a blank - don't add a second expecting a gap. The single-source rule
#     generalizes beyond press_any_key: any function that emits its OWN leading
#     blank (press_any_key, agh_apply_and_restart) is the sole source of that
#     blank - callers MUST NOT emit a blank immediately before calling it.
#
# Help screens
#   Navigation menus AND numbered action/selection menus get a [?] Help entry
#   (rule broadened 2026-07-31 - MTU/RLA/VPN Tools were numbered action screens
#   with no help; they now have it). Pure pickers, binary-state toggles and
#   confirm dialogs still do NOT. [?] is dispatched as `\?|h|H|❓` (not the words
#   "help"/"HELP"), advertised as `printf "%s Help\n" "$NQ"` - ONE space at the call
#   site, because NQ carries its own trailing space so Help aligns with the
#   two-space numbered rows above it. `?` is added to
#   the Choose prompt.
#   Help content is generic and idempotent (NO option numbers - describe actions
#   by name), body opens with the title line "<Feature> - Quick Help", uses
#   `Section\n────` headers with `──` box-drawing dividers and `•` bullets. The
#   universal keys ([0]/[?]) are explained ONCE, in the main-menu help - inner
#   screens don't repeat them. A body needing the router's LAN IP uses an
#   unquoted heredoc + $(get_lan_ip), never a hardcoded address.
#
# Menu & picker input
#   Input mode is decided at the FUNCTIONAL-GROUP level, by constraint:
#     - A group containing any live/refreshing screen (or a paged VIEW like the
#       Hardware Info / Display Settings pagers) is KEY-ONLY - a single keypress
#       (read_single_char, or read -t for refresh); a blocking read would freeze
#       the redraw.
#     - Otherwise the group is KEY + ENTER (read -r) if any member can present a
#       multi-character token: an item number that reaches >=10, or a multi-char
#       command like "CL". ALL members of that group then use key+Enter for
#       consistency, even fixed <=9-item screens within it.
#     - A standalone fixed-<=9 single-char screen MAY be key-only, but never when
#       grouped with a line-based sibling. Text/value entry is always key+Enter.
#     - All major navigation menus are key+Enter.
#   The input prompt is separated from the options/action-bar block by ONE blank
#   line (Gestalt common region: options are a content region, the prompt is the
#   action). Wording is "Choose [<keys>]:" - the bracket lists valid keys, with
#   the item token from picker_range(): the live count as a range ("1-10"), but
#   just "1" for a single item (a range only when there IS a range - never
#   "1-1"), and never a literal "#".
#
# Rendering note
#   Trailing "\033[K" (erase-to-EOL) is load-bearing on in-place redraw screens
#   (fan / status / spinner). Do NOT remove it there.
#
# Progress indicators
#   spin_run (gear/⚙) = indeterminate wait - duration unknown until the command
#   finishes (opkg, openssl, a dd test whose throughput we're measuring).
#   countdown_run (hourglass/⏳) = determinate wait - the caller already knows
#   and told the user the total duration (e.g. a fixed-length stress test); it
#   counts down instead of spinning. Pick by determinacy, not by "which looks
#   nicer" - showing a spinner when the duration is already known withholds
#   information the user was already given.
#
# Table & List Alignment
#   Column justification is decided per-column by a 3-part test - right-justify
#   ONLY if all three hold, else left-justify:
#     1. Values are NOT normalized to near-constant width (i.e. not auto-scaled
#        across units specifically to keep text length ~constant regardless of
#        magnitude - that scaling defeats the entire mechanism right-justify
#        relies on: comparing magnitude by digit position).
#     2. No other element in the row (a bar, icon, or color) already shows
#        relative magnitude.
#     3. The reader's task is genuinely comparing/summing many values, not
#        reading one row as a self-contained status card about one entity.
#   Fails any of the three -> left-justify uniformly (Docker/kubectl-style: all
#   columns left, including numeric-looking ones - this is the default for our
#   small device-comparison leaderboards and toggle/checkbox lists).
#   A column's header MUST share its data row's exact format string (or at
#   minimum identical field-width declarations) wherever feasible - a
#   hand-typed separate header string WILL drift from computed data over time;
#   this is the root cause behind every alignment bug found in this audit.
#   Never center a column header. Screen/section TITLES (print_centered_header)
#   are a different UI element (a heading, not a table column) and are exempt.
#   Boolean/toggle indicators use tight brackets: [Y] [N] [✓] [ ] - content
#   flush against both brackets, no internal space padding. Under a column
#   header, a checkbox/toggle IS centered within its field (the one explicit
#   exception to "never center") - it is a symbol/glyph, not text or a
#   magnitude to compare, and the header word above it stays left-justified
#   per the normal text rule; the two don't need to share a visual midpoint,
#   just the same declared field width.
#   Placeholder/null-value markers (e.g. "---") that mean "not applicable"
#   rather than a real value ARE exempt from the column's justification and
#   may be centered within their field - they are not content being compared,
#   they are a symbol of incomparability, and distinct treatment aids scanning.
#   Centering with an odd remainder (can't split the padding evenly): give the
#   extra space to the right, so content sits one space left of true-center,
#   never right of it.
#   Out of scope: output piped directly from an external command (df, dd) that
#   has its own native formatting; vertical Label: Value blocks (System
#   Information, STATUS panels) which aren't row/column tables at all.
#
# Naming
#   Functions: lowercase snake_case, NO leading underscore, descriptive verb-led
#   (check_*, get_*, is_*, manage_*, show_*, install_*). A leading "_" is reserved
#   for internal runtime STATE variables only (_S_* mode symbols, _TERM_PROFILE).
#   Comments describe the code AS-IS, not its history - changelogs/diffs carry that.
# =============================================================================

# -----------------------------
# Color & Emoji
# -----------------------------
RESET="\033[0m"
CYAN="\033[36m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
GREY="\033[90m"
BOLD="\033[1m"
BLUE="\033[38;5;153m"
HDR2="\033[38;5;148m"   # L2 sub-heading (chartreuse) — one rung below the CYAN L1

SPLASH="
   _____ _          _ _   _      _   
  / ____| |        (_) \\ | |    | |  
 | |  __| |  ______ _|  \\| | ___| |_ 
 | | |_ | | |______| | . \` |/ _ \\ __|
 | |__| | |____    | | |\\  |  __/ |_ 
  \\_____|______|   |_|_| \\_|\\___|\\__|

         GL.iNet Router Toolkit
"

# -----------------------------
# Global Variables
# -----------------------------
AGH_INIT="/etc/init.d/adguardhome"
AGH_DISABLED=0  # 0 = Available, 1 = Missing/Uninstalled
SPIN_LOG="/tmp/.glnet-op.$$"   # scratch log captured from spin_run output
opkg_updated=0
SCRIPT_URL="https://raw.githubusercontent.com/phantasm22/GL-iNet_utils/refs/heads/main/glinet_utils.sh"
CHANGELOG_URL="${SCRIPT_URL%glinet_utils.sh}CHANGELOG.md"
TMP_NEW_SCRIPT="/tmp/glinet_utils_new.sh"
case "$0" in
    /*)  SCRIPT_PATH="$0" ;;
    */*) SCRIPT_PATH="$(pwd)/$0" ;;
    *)   SCRIPT_PATH="$(command -v "$0" 2>/dev/null)" ;;
esac
[ -z "$SCRIPT_PATH" ] && SCRIPT_PATH="$(pwd)/$0"
INSTALL_PROMPTED=0    # Set to 1 after user responds to install prompt; reset by each new version
STARTUP_NOTICE=0      # Set by the install-skip so the update-check spinner runs 2s longer (readable)
INSTALL_PATH="/usr/sbin/glinet_utils"
OUTPUT_PREF="auto"    # "auto"|"full"|"compat" — saved in script; "auto" = detect each run
OUTPUT_MODE="full"    # Runtime: "full"|"compat"; set by detect_output_mode
_TERM_PROFILE="mac"   # Runtime: mac|wt|ttyd|termius|putty|compat; set by detect_output_mode
NSEP="  "             # keycap->label separator: 2 cols default, termius narrows to 1; set by detect_output_mode

# ─────────────────────────────────────────────────────────────────────────────
# Terminal Output Mode Detection
#
# OUTPUT_PREF   "auto"|"full"|"compat"  — persisted in script
# OUTPUT_MODE   "full"|"compat"         — runtime mode
# _TERM_PROFILE mac|wt|ttyd|termius|putty|compat — terminal sub-profile (internal)
#
# Detection flow (auto mode):
#   TERM=xterm/screen/linux/vt*/ansi/putty* → compat (legacy/PuTTY terminals)
#   Otherwise → ensure stty (install coreutils-stty if missing), then probe:
#     Probe 1: ✅ advance=1 → ttyd  (xterm.js: all emoji narrow)
#     Probe 1: ✅ advance=2 → Probe 2: ⚠️+VS16 advance
#       advance=1 → mac  (keycaps ✓, 2sp after ambig+VS symbols)
#       advance=2 → wt   (keycaps ✗, 1sp after ambig+VS symbols)
#
# The probe REQUIRES a real stty (ESC[6n raw read); busybox does not ship one.
# ensure_stty installs coreutils-stty silently on first run. If a real
# (coreutils) stty can't be obtained, output falls back to Compatible mode.
#
# NO_COLOR strips ANSI colors but does not change mode or symbols.
# Two display modes: Full and Compatible.
# ─────────────────────────────────────────────────────────────────────────────

# ---- package manager abstraction --------------------------------------------
# OpenWrt 25 replaced opkg with apk. These wrap the four operations the toolkit
# needs so call sites do not care which is present. Package NAMES are mostly
# unchanged between the two, but not always (e.g. zram-swap resolves to a
# variant under apk) - so an install can still fail on a name basis; that is
# handled per-package, not here.
#
# Defined HERE, above ensure_stty, because detect_output_mode() runs at startup
# and calls ensure_stty long before the rest of the toolkit's helpers exist. A
# definition further down would be invisible at that point and the install would
# fail with "pkg_update: not found" into a redirected log - silently dropping
# the display to Compatible mode.
pkg_mgr() { command -v apk >/dev/null 2>&1 && printf 'apk' || printf 'opkg'; }

# stress-ng can HARD-CRASH a router on kernels before 6.6 (a memory-pressure bug - openwrt#15561, fixed
# in 6.6): its CPU stressor allocates memory and trips the bug where plain `stress` (pure CPU) does not.
# Returns 0 (true) when the RUNNING kernel is susceptible (< 6.6), so stress-ng is withheld both from the
# Package Manager util list and as a CPU-benchmark fallback. Kernel version - not GL-vs-OpenWrt - is the
# real gate (e.g. GL's mt3000 on kernel 6.12 is safe; an old vanilla-OpenWrt box is not).
_stressng_unsafe() {
    local kr kmaj kmin; kr=$(uname -r 2>/dev/null); kmaj=${kr%%.*}; kmin=${kr#*.}; kmin=${kmin%%.*}
    case "$kmaj" in ''|*[!0-9]*) return 0 ;; esac      # unknown kernel -> conservative (treat as unsafe)
    [ "$kmaj" -lt 6 ] && return 0
    [ "$kmaj" -gt 6 ] && return 1
    case "$kmin" in ''|*[!0-9]*) return 0 ;; esac
    [ "$kmin" -lt 6 ]
}

pkg_is_installed() {   # <pkg> -> 0 if installed
    if [ "$(pkg_mgr)" = apk ]; then
        apk info -e "$1" >/dev/null 2>&1
    else
        opkg list-installed 2>/dev/null | grep -q "^$1 "
    fi
}

pkg_install() {        # <pkg>
    if [ "$(pkg_mgr)" = apk ]; then apk add "$1"; else opkg install "$1"; fi
}

pkg_remove() {         # <pkg>  - removes dependencies too where the manager can
    if [ "$(pkg_mgr)" = apk ]; then apk del "$1"; else opkg remove --autoremove "$1"; fi
}

pkg_update() {         # refresh the package index; silently self-heals a corrupted (re-fetchable) feed cache
    if [ "$(pkg_mgr)" = apk ]; then apk update; return; fi
    local out; out=$(opkg update 2>&1); printf '%s\n' "$out"
    # A truncated feed Packages file makes opkg choke with "parse_from_stream_nomalloc: Missing new line
    # character at end of file", which then breaks installs and removes. The feed-index cache under
    # /var/opkg-lists is fully re-fetchable, so clearing + retrying it is non-destructive and safe to do
    # silently. This NEVER touches the installed database /usr/lib/opkg/status - if the parse error
    # persists after this, the corruption is DB-side, and check_opkg_updated offers a guarded, backed-up
    # repair inline (which needs a prompt and so cannot live here in the spinner subshell).
    if printf '%s' "$out" | pkg_parse_sig; then
        PKG_INDEX_HEALED=1
        rm -rf /var/opkg-lists/* /tmp/opkg-lists/* 2>/dev/null
        opkg update 2>&1
    fi
}

# ── Package-system corruption detection & repair ────────────────────────────────────────────────
# Shared by the inline install-time self-heal (check_opkg_updated -> offer_pkg_db_repair) and the
# standalone Package System Repair tool (System Tweaks). opkg throws "parse_from_stream_nomalloc:
# Missing new line character at end of file" when a Packages-format file is TRUNCATED (ends mid-stanza).
# Two sources: the re-fetchable feed cache /var/opkg-lists (fixed by re-downloading - non-destructive)
# and the INSTALLED database /usr/lib/opkg/status (repaired in place, NEVER deleted).
# NOTE: GL's own feed Packages files legitimately omit a trailing newline, so "missing final newline"
# is a corruption signal ONLY for the status DB, never for the cache.
# The installed-database path and its backup namespace depend on the package manager: opkg keeps a
# single /usr/lib/opkg/status; apk keeps /lib/apk/db/installed. Backups of either go to the central
# bk_* store under a per-manager namespace so they never collide.
pkg_db_path() { if [ "$(pkg_mgr)" = apk ]; then printf '/lib/apk/db/installed'; else printf '/usr/lib/opkg/status'; fi; }
pkg_db_ns()   { if [ "$(pkg_mgr)" = apk ]; then printf 'apk'; else printf 'opkg'; fi; }

pkg_parse_sig() { grep -q 'parse_from_stream_nomalloc\|Missing new line character'; }   # reads stdin

# busybox-safe "the last line has no terminating newline": on busybox `od -An -tx1` is unsupported and
# `tail -c1` returns empty, so both mis-detect. `grep -c ''` counts every line INCLUDING a final
# unterminated one, while `wc -l` counts newline characters - a difference means no trailing newline.
_file_missing_final_nl() {   # <file>
    [ -s "$1" ] || return 1
    [ "$(grep -c '' "$1")" -gt "$(wc -l < "$1")" ]
}

# Structural health of the installed opkg database - cheap, offline, and reliable for the documented
# corruption (a healthy status file ends in a newline). Only meaningful for opkg.
pkg_db_broken() { [ "$(pkg_mgr)" = opkg ] && _file_missing_final_nl "$(pkg_db_path)"; }

# The read-only firmware baseline of the installed DB (opkg only): a factory-fresh, parseable copy that
# can un-stick a badly corrupted database without a re-flash. Restoring it is LOSSY (opkg forgets
# post-factory package records; the files stay on disk).
pkg_db_rom() { printf '/rom%s' "$(pkg_db_path)"; }

# Safe, reversible repair of the installed database: append the missing end-of-file newline. Never trims
# or deletes; deeper corruption is escalated by _pkg_db_repair_flow (rebuild-from-metadata, then factory
# /rom) rather than risked here. No pre-repair copy is kept: there is nothing worth backing up (the DB is
# corrupt), and every recovery path - rebuild from info/*.control, /rom, a real user backup - is
# independent of the pre-repair bytes. Returns 0 when the file ends in a newline afterwards.
pkg_db_repair() {
    [ "$(pkg_mgr)" = opkg ] || return 0
    local _db; _db="$(pkg_db_path)"
    [ -f "$_db" ] || return 1
    _file_missing_final_nl "$_db" && printf '\n' >> "$_db"
    ! _file_missing_final_nl "$_db"
}

# Directory of the per-package control metadata opkg keeps on disk (one <pkg>.control per installed pkg).
pkg_db_info_dir() { printf '%s/info' "$(dirname "$(pkg_db_path)")"; }

# Rebuild the installed database from that on-disk metadata (opkg only). Higher fidelity than the /rom
# factory baseline: it preserves the ACTUAL installed set, not just what the firmware shipped. The only
# thing lost is the user/auto-installed and hold flags (there is no on-disk source for them) - so every
# package is marked plainly installed, which is safe (nothing gets auto-removed). "Status: install user
# installed" is opkg's own idiomatic line for an installed package. Returns 0 if it wrote a non-empty DB.
pkg_db_reconstruct() {
    [ "$(pkg_mgr)" = opkg ] || return 1
    local _db _info _tmp _c; _db="$(pkg_db_path)"; _info="$(pkg_db_info_dir)"
    ls "$_info"/*.control >/dev/null 2>&1 || return 1
    _tmp="$_db.reconstruct.$$"
    for _c in "$_info"/*.control; do
        awk '1' "$_c"                                  # normalize: field lines + a guaranteed trailing newline
        printf 'Status: install user installed\n\n'    # mark installed + blank-line stanza separator
    done > "$_tmp"
    [ -s "$_tmp" ] || { rm -f "$_tmp"; return 1; }
    mv "$_tmp" "$_db"
}

# Explicit, forced rebuild of the re-fetchable feed-index cache (non-destructive: the cache is a mirror
# of the online feeds). Used by the standalone tool; the silent per-session heal lives in pkg_update.
pkg_cache_rebuild() {
    if [ "$(pkg_mgr)" = apk ]; then apk update; return; fi
    rm -rf /var/opkg-lists/* /tmp/opkg-lists/* 2>/dev/null
    opkg update 2>&1
}

# Ensure a real (coreutils) `stty` is available for the cursor-advance probe.
# busybox's own stty applet can't drive the probe reliably, so we require the
# coreutils build and install it silently (no prompt) with a small spinner on
# first run. Returns 0 if a coreutils stty is present afterwards, 1 otherwise —
# the caller then falls back to Compatible mode.
ensure_stty() {
    stty --version 2>&1 | grep -qi coreutils && return 0

    local log="/tmp/.stty-install.$$" pid spin='-\|/' c
    ( pkg_update && pkg_install coreutils-stty ) >"$log" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        c=${spin%"${spin#?}"}                  # first character
        spin=${spin#?}$c                       # rotate frames
        printf '\rSetting up terminal support %s' "$c" >/dev/tty
        usleep 100000 2>/dev/null || sleep 1
    done
    wait "$pid"
    printf '\r\033[K' >/dev/tty                # erase the spinner line
    rm -f "$log"
    stty --version 2>&1 | grep -qi coreutils
}

# Cursor advance probe: prints sym at col 1, queries cursor via ESC[6n,
# returns number of columns advanced. Cleans up after itself. Falls back to 2
# (which resolves to the Windows Terminal profile) if stty/the probe is absent.
probe_da2() {
    # Secondary Device Attributes -> "ESC [ > Type ; Version ; Keyboard c".
    # Used only to separate terminals that share an advance signature but render
    # differently. Never consulted on its own: DA2 "0;95" is also emitted by
    # terminals that draw emoji correctly, so callers must pair it with a width
    # check. Returns "Type;Version" or empty.
    local saved stty_bin tmpf="/tmp/.da2.$$" out i
    stty_bin=$(command -v stty 2>/dev/null) || return 1
    saved=$("$stty_bin" -g 2>/dev/null)     || return 1
    "$stty_bin" raw -echo min 0 time 1 2>/dev/null
    printf '\033[>c' >/dev/tty
    # Gather the reply in 0.1s slices until the 'c' terminator lands or a ~1.2s
    # deadline passes. A single fixed-timeout read misdetects on laggy links
    # (Termius over in-flight wifi) whose round-trip exceeds the window, and it
    # cannot reassemble a reply split across reads. Responsive terminals answer
    # on the first slice, so this stays instant for them.
    : > "$tmpf"; i=0
    while [ "$i" -lt 12 ]; do
        dd if=/dev/tty bs=32 count=1 >>"$tmpf" 2>/dev/null
        case "$(cat "$tmpf" 2>/dev/null)" in *c*) break ;; esac
        i=$((i + 1))
    done
    "$stty_bin" "$saved" 2>/dev/null
    out=$(sed 's/.*\[>\([0-9]*\);\([0-9]*\).*/\1;\2/' "$tmpf" 2>/dev/null)
    rm -f "$tmpf"
    case "$out" in [0-9]*\;[0-9]*) printf '%s' "$out" ;; *) return 1 ;; esac
}

probe_advance() {
    local sym="$1" col saved stty_bin tmpf="/tmp/.probe.$$" i
    stty_bin=$(command -v stty 2>/dev/null) || { printf '2'; return; }
    saved=$("$stty_bin" -g 2>/dev/null)       || { printf '2'; return; }
    "$stty_bin" raw -echo min 0 time 1 2>/dev/null
    printf '\r%s\033[6n' "$sym" >/dev/tty
    # Gather the cursor report in 0.1s slices until the 'R' terminator lands or a
    # ~1.2s deadline passes. A single fixed-timeout read timed out on laggy links
    # (Termius over in-flight wifi) and fell back to advance 2 - the Windows
    # Terminal profile - which mismatched the real glyph widths. Responsive
    # terminals answer on the first slice, so startup stays instant for them.
    : > "$tmpf"; i=0
    while [ "$i" -lt 12 ]; do
        dd if=/dev/tty bs=20 count=1 >>"$tmpf" 2>/dev/null
        case "$(cat "$tmpf" 2>/dev/null)" in *R*) break ;; esac
        i=$((i + 1))
    done
    "$stty_bin" "$saved" 2>/dev/null
    printf '\r\033[K' >/dev/tty
    col=$(sed 's/.*\[\([0-9]*\);\([0-9]*\)R.*/\2/' "$tmpf" 2>/dev/null)
    rm -f "$tmpf"
    case "$col" in
        [0-9]*) printf '%d' $((col - 1)) ;;
        *)      printf '2' ;;
    esac
}

detect_output_mode() {
    local ambig wide
    NSEP="  "    # keycap separator default (2 cols); the termius profile narrows it to 1

    # ── Step 1: Determine base mode ──────────────────────────────────────────
    if [ "$OUTPUT_PREF" = "compat" ]; then
        OUTPUT_MODE="compat"
    elif [ "$OUTPUT_PREF" = "full" ]; then
        OUTPUT_MODE="full"
    else
        # "auto" (or any unrecognised value) → detect from environment
        OUTPUT_MODE="full"
        case "${TERM:-dumb}" in
            dumb|unknown|""|xterm|screen|linux|vt100|vt220|ansi|putty*)
                OUTPUT_MODE="compat" ;;
        esac
        [ "${GL_COMPAT+x}" ] && OUTPUT_MODE="compat"   # env var power-user override (force Compatible)
    fi

    # ── Step 2: NO_COLOR — strip ANSI colors only, keep symbols/mode ─────────
    if [ "${NO_COLOR+x}" ]; then
        RESET=""; CYAN=""; GREEN=""; RED=""; YELLOW=""
        GREY=""; BOLD=""; BLUE=""; HDR2=""
    fi

    # ── Step 3: Probe terminal sub-profile (full mode only) ──────────────────
    # The probe needs a real (coreutils) stty; busybox's applet can't drive it.
    # ensure_stty installs coreutils-stty on first run; if one can't be obtained
    # we fall back to Compatible mode (one consistent set), not a mixed profile.
    _TERM_PROFILE="mac"
    if [ "$OUTPUT_MODE" = "full" ]; then
        if ensure_stty; then
            wide=$(probe_advance '✅')
            if [ "$wide" = "1" ]; then
                _TERM_PROFILE="ttyd"            # xterm.js: all emoji adv=1
                # NOTE how narrow this key is: macOS Terminal answers DA2 1;95,
                # differing only in the type digit, and Windows Terminal 0;10.
                # Keying on the version alone would capture Terminal.app. Two
                # things prevent that - the type digit, AND the fact that mac
                # never reaches here because its ✅ advance is 2. Do not relax
                # either condition. (Measured: Termius 0;95, mac 1;95, wt 0;10.)
                # Same advance, different rendering: Termius reports DA2 0;95 and
                # PAINTS ✅ two cells while advancing one, and paints 🔒 one cell
                # while advancing two - the inverse of xterm.js. Only reached when
                # adv==1, so terminals sharing DA2 0;95 that measure correctly
                # (iTerm2) never match.
                case "$(probe_da2 2>/dev/null)" in
                    0\;95) _TERM_PROFILE="termius" ;;
                esac
            else
                ambig=$(probe_advance '⚠️')
                [ "$ambig" = "2" ] && _TERM_PROFILE="wt"
            fi
            # Cell width of the inferred-subnet dagger † (U+2020). It is 3 BYTES but renders
            # 2 cells on macOS Terminal and 1 cell on termius/ttyd/wt/putty (measured with
            # glyph-test.sh), so byte-based padding (%-Ns) misaligns any column that holds a
            # daggered value. Measure it so rla_dispw pads by display width instead.
            DAG_CELLS=$(probe_advance '†')
        else
            OUTPUT_MODE="compat"               # can't probe without a real stty -> use the consistent Compatible set
        fi
    fi
    # Default for compat / un-probed terminals: † is 1 cell there (putty measured 1).
    case "$DAG_CELLS" in 1|2) ;; *) DAG_CELLS=1 ;; esac

    # ── Step 4: Set symbol variables ─────────────────────────────────────────
    if [ "$OUTPUT_MODE" = "full" ]; then

        # Wide emoji (✅ ❌ ⏳): adv=2 on mac/wt, adv=1 on ttyd — 1sp correct for
        # those three. NOT universal: termius advances 1 but PAINTS 2, so it
        # overrides these below. Only safe where advance == painted width.
        # (⏳ is wide-by-default, NOT ambig+VS like ⚠️ ℹ️ ⚙️ — it takes 1sp even
        # in the default profile where those take 2sp)
        _S_OK="✅ "
        _S_ERR="❌ "
        _S_ON="✅"; _S_OFF="❌"           # status icons (emoji already carry color)

        case "$_TERM_PROFILE" in
            ttyd)
                # xterm.js: all emoji adv=1 — 1 trailing space after everything
                # Same rendering as Termius, verified in a real ttyd session:
                # wide-by-default BMP emoji (✅ ❌ ⏳ ❓ 🆑) advance ONE cell but
                # PAINT two, so a single trailing space is drawn over the glyph's
                # right half and the text butts against it. Two gives one visible
                # gap. The ambiguous+VS16 set (⚠️ ℹ️ ⚙️) advances two and paints
                # two, so those stay at one.
                _S_WARN="⚠️ ";  _S_INFO="ℹ️ ";  _S_ACT="⚙️ "
                _S_OK="✅  ";   _S_ERR="❌  ";  _S_TIME="⏳  "
                N1="1️⃣"; N2="2️⃣"; N3="3️⃣"; N4="4️⃣"; N5="5️⃣"
                N6="6️⃣"; N7="7️⃣"; N8="8️⃣"; N9="9️⃣"; N0="0️⃣"
                # NQ carries a trailing space so that, with the ONE space its call
                # sites add, Help lands in the same column as the keycap rows -
                # those get TWO spaces at their call site and the keycap paints a
                # single cell here. Without it Help sits one column short.
                NQ="❓ "; NCL="🆑 "; NA="🅰️"
                # xterm.js advances AND paints all emoji at 1 cell, so pad to
                # the advance. NOT verified against a real ttyd session - if the
                # web terminal paints 2 cells like Termius it needs those pads.
                # Padded to RENDERED width, matching Termius. ✅ ❌ paint 2 -> 6sp;
                # 🔒 resolves to a monochrome TEXT glyph that paints 1 -> 7sp.
                # These were previously inverted (7/7/6) on the assumption that
                # xterm.js paints every emoji at one cell - the comment here even
                # said it was unverified. It is verified now, and it was wrong.
                _S_RLA_AC="  🟢    "; _S_RLA_IA="  🔴    "; _S_RLA_RO="  🟡    "
                ;;
            termius)
                # Inherits ttyd's symbol set; only the fixed-width status cells
                # differ, padded to RENDERED width rather than advance:
                #   ✅ ❌ paint 2 -> 6sp      🔒 paints 1 (mono text glyph) -> 7sp
                # Verified by eye at three font sizes; advances are a wcwidth
                # table lookup and do not vary with font size.
                # Wide-by-default BMP emoji (✅ ❌ ⏳) advance 1 but PAINT 2 here,
                # so a single trailing space is drawn over the glyph's right half
                # and the text butts it - they need TWO for one visible gap.
                # The ambiguous+VS16 set (⚠️ ℹ️ ⚙️) advances 2 AND paints 2, so ONE
                # space is right. It used to carry two as a sacrificial pad because
                # Termius clipped the last cell of a colour run - but a current
                # Termius no longer does (re-measured 2026-08-13 with glyph-test.sh:
                # one space leaves exactly one clean gap), so drop it back to one.
                _S_OK="✅  ";   _S_ERR="❌  ";  _S_TIME="⏳  "
                _S_WARN="⚠️ ";  _S_INFO="ℹ️ ";  _S_ACT="⚙️ "
                # Keycaps PAINT 2 and (re-measured 2026-08-13) ADVANCE 2 in a
                # current Termius, so ONE space after them leaves one clean gap -
                # NSEP is narrowed to a single space here for exactly that. Every
                # numbered-keycap call site reads NSEP, so non-termius profiles keep
                # two spaces (byte-identical) and only termius narrows to one.
                NSEP=" "
                N1="1️⃣"; N2="2️⃣"; N3="3️⃣"; N4="4️⃣"; N5="5️⃣"
                N6="6️⃣"; N7="7️⃣"; N8="8️⃣"; N9="9️⃣"; N0="0️⃣"
                # NQ/NCL (help/clear) are printed with ONE leading space and no NSEP
                # - their spacing is per-glyph, not the keycap separator - so they
                # carry NO trailing space to land at one clean gap like the keycaps.
                NQ="❓"; NCL="🆑"; NA="🅰️"
                _S_RLA_AC="  🟢    "; _S_RLA_IA="  🔴    "; _S_RLA_RO="  🟡    "
                ;;
            wt)
                # Windows Terminal: ambig+VS adv=2 — 1sp sufficient
                # Keycap emoji (1️⃣) and 🅰️ box out here, so numbers use the bold
                # negative-circled digits ❶..❾ + ⓿ (U+2776 / U+24FF) - single-width
                # TEXT glyphs that ADVANCE 1 (as the keycaps do on mac), so the label
                # column lands where the mac profile puts it. The thin circled ①..⓪
                # rendered too small to read. help/clear keep ❓/🆑; All stays Ⓐ (no
                # bold circled letter renders reliably).
                _S_WARN="⚠️ ";  _S_INFO="ℹ️ ";  _S_ACT="⚙️ ";  _S_TIME="⏳ "
                N1="❶"; N2="❷"; N3="❸"; N4="❹"; N5="❺"
                N6="❻"; N7="❼"; N8="❽"; N9="❾"; N0="⓿"
                NQ="❓"; NCL="🆑"; NA="Ⓐ"
                _S_RLA_AC="  🟢    "; _S_RLA_IA="  🔴    "; _S_RLA_RO="  🟡    "
                ;;
            *)
                # macOS Terminal + Linux terminals (default)
                # ambig+VS: adv=1 but visual 2-wide — 2sp leaves 1 visible gap
                _S_WARN="⚠️  ";  _S_INFO="ℹ️  ";  _S_ACT="⚙️  ";  _S_TIME="⏳ "
                N1="1️⃣"; N2="2️⃣"; N3="3️⃣"; N4="4️⃣"; N5="5️⃣"
                N6="6️⃣"; N7="7️⃣"; N8="8️⃣"; N9="9️⃣"; N0="0️⃣"
                NQ="❓"; NCL="🆑"; NA="🅰️"
                _S_RLA_AC="  🟢    "; _S_RLA_IA="  🔴    "; _S_RLA_RO="  🟡    "
                ;;
        esac

    else    # compat — split: PuTTY/xterm render emoji; dumb/serial terminals do not
        # PuTTY (and real xterm) render EMOJI-DEFAULT codepoints (✅ ❌ ⏳ ❓ 🆑 and the
        # 🟢🔴🟡 circles) FULL at 2 cells - but monochrome, so print_* paints them via
        # ANSI.  TEXT-default symbols must be avoided: PuTTY gives ⚠ / info-i / gear one
        # cell and clips their 2-cell fallback glyph to a HALF (proven on-device), so
        # warn/info/action use emoji-default stand-ins (❗ 💡 🔧).  Numbered selectors
        # stay [brackets] (keycaps box, circled digits read poorly); help/clear keep
        # their emoji, which render full.  Stoplight circles are one identical
        # monochrome shape here, so the cells MUST be ANSI-painted to be told apart -
        # baked in with printf so the %s row-render emits real ESC, not a literal
        # \033 string.  Genuinely limited terminals keep the pure-ASCII set.
        case "${TERM:-dumb}" in putty*|xterm) _TERM_PROFILE="putty" ;; *) _TERM_PROFILE="compat" ;; esac
        if [ "$_TERM_PROFILE" = "putty" ]; then
            _S_OK="✅ ";   _S_ERR="❌ "
            _S_ON="${GREEN}✅${RESET}"; _S_OFF="${RED}❌${RESET}"
            _S_WARN="❗ "; _S_INFO="💡 "; _S_ACT="🔧 "; _S_TIME="⏳ "
            N1="[1]"; N2="[2]"; N3="[3]"; N4="[4]"; N5="[5]"
            N6="[6]"; N7="[7]"; N8="[8]"; N9="[9]"; N0="[0]"
            NQ="[?] "; NCL="[CL]"; NA="[A]"
            _S_RLA_AC=$(printf '  %b🟢%b    ' "$GREEN"  "$RESET")
            _S_RLA_IA=$(printf '  %b🔴%b    ' "$RED"    "$RESET")
            _S_RLA_RO=$(printf '  %b🟡%b    ' "$YELLOW" "$RESET")
        else
            _S_OK="[√] "
            _S_ERR="[×] "
            _S_ON="${GREEN}√${RESET}"; _S_OFF="${RED}×${RESET}"   # status icons (need explicit color)
            _S_WARN="[!] "
            _S_INFO="[i] "
            _S_ACT="[❋] "
            _S_TIME="[…] "   # all single-width & PuTTY-safe; [√]/[×] mirror on/off √/× and full-mode ✅/❌, [❋]≈gear, […]=wait
            N1="[1]"; N2="[2]"; N3="[3]"; N4="[4]"; N5="[5]"
            N6="[6]"; N7="[7]"; N8="[8]"; N9="[9]"; N0="[0]"
            NQ="[?] "; NCL="[CL]"; NA="[A]"
            _S_RLA_AC="  [AC]  "; _S_RLA_IA="  [IA]  "; _S_RLA_RO="  [!]   "
        fi
    fi
}

# ── Terminal setup / restore ─────────────────────────────────────────────────
# Best-effort, for the session only: widen the window to a usable size and set a
# dark theme, then put everything back on exit. Terminals that don't support a
# given sequence just ignore it (PuTTY ignores the OSC colors; non-xterm ignore
# the resize), so this is safe everywhere.
TERM_MIN_COLS=110
TERM_MIN_ROWS=33      # measured: Hardware Information page 1 renders 33 visible
                      # lines - a leading blank line, then the header box 3 +
                      # rule + 27 body + rule + nav. The blank line above the
                      # header is easy to miss when counting and is why this was
                      # briefly set to 32. Any shorter and the header scrolls off.
# The widest screen the toolkit draws (Remote LAN Access rule = 101 cols). Below
# this, tables wrap and alignment is lost. Distinct from TERM_MIN_COLS, which is
# what we *ask* for - some terminals (Termius, verified) ignore the resize
# escape entirely, so we advise the user instead of assuming it worked.
TERM_NEED_COLS=101
_TERM_ORIG_SIZE=""    # "rows;cols" saved at setup; empty = nothing to restore
_TERM_RESIZE_SENT=""  # set when terminal_setup actually asked for a resize
_TERM_RESTORED=""

# Message helpers. Defined HERE rather than further down because
# terminal_size_advisory runs before that point and needs them; the ${VARS} they
# reference are resolved at call time, so an early definition is safe.
# Continuation lines in a message (written as "\n" by the caller) are auto-indented
# to align under the text, past the leading glyph - callers no longer add spaces.
print_success() { local m="${1//\\n/\\n   }"; printf "%b\n" "${BOLD}${GREEN}${_S_OK}${RESET}${GREEN}${m}${RESET}"; }
print_error()   { local m="${1//\\n/\\n   }"; printf "%b\n" "${BOLD}${RED}${_S_ERR}${RESET}${RED}${m}${RESET}"; }
print_warning() { local m="${1//\\n/\\n   }"; printf "%b\n" "${BOLD}${YELLOW}${_S_WARN}${RESET}${YELLOW}${m}${RESET}"; }
print_info()    { local m="${1//\\n/\\n   }"; printf "%b\n" "${BOLD}${BLUE}${_S_INFO}${RESET}${BLUE}${m}${RESET}"; }

# Standardized "hard refresh your browser" advisory - shown after any change that patches the Web UI.
# A print_info heading + 3-space-indented per-browser continuation lines (reserved indent for wrapped
# body under a heading, per the UX standard); each line stays within the 110-col window.
_hard_refresh_hint() {
    print_info "Hard-refresh your browser to load the change:"
    printf "   Chrome / Edge / Firefox:  Ctrl+F5, or Ctrl/Cmd + Shift + R\n"
    printf "   Safari:                   Cmd + Option + R\n"
}
print_action()  { printf "%b\n" "${BOLD}${CYAN}${_S_ACT}${RESET}${CYAN}$1${RESET}"; }

terminal_setup() {
    local sz r c nr nc
    [ "${GL_NO_TERM_SETUP+x}" ] && return          # power-user opt-out
    [ -t 1 ] || return                              # only on a real terminal
    [ -n "$TMUX" ] && return                         # not inside tmux
    case "${TERM:-}" in screen*|tmux*) return ;; esac

    printf '\033]11;#000000\007\033]10;#ffffff\007'  # best-effort dark theme (OSC 11/10)

    # Grow only (never shrink). Needs a real stty to read the size so we can
    # restore it on exit; skip just the resize if stty isn't available.
    command -v stty >/dev/null 2>&1 || return
    sz=$(stty size 2>/dev/null </dev/tty); r=${sz% *}; c=${sz#* }
    case "$r" in ''|*[!0-9]*) return ;; esac
    case "$c" in ''|*[!0-9]*) return ;; esac
    _TERM_ORIG_SIZE="${r};${c}"
    nr=$r; nc=$c
    [ "$c" -lt "$TERM_MIN_COLS" ] && nc=$TERM_MIN_COLS
    [ "$r" -lt "$TERM_MIN_ROWS" ] && nr=$TERM_MIN_ROWS
    if [ "$nr" != "$r" ] || [ "$nc" != "$c" ]; then
        # Termius ignores CSI 8t. Asking anyway would make the advisory wait for
        # a resize that provably never lands, so skip the request and let the
        # advisory judge the real size immediately. Note the profile is only
        # probed in full mode, so a Termius user in Compatible mode is not
        # recognised here and still waits out the (bounded) settle window.
        if [ "$_TERM_PROFILE" != termius ]; then
            printf '\033[8;%s;%st' "$nr" "$nc"
            _TERM_RESIZE_SENT=1  # the advisory must let this land before judging
        fi
    fi
}

terminal_size_advisory() {
    # Called after terminal_setup, which may or may not have been honoured.
    # Re-reads the real size and tells the user plainly if it is too small,
    # offering a recheck because some terminals give no visible size indicator.
    [ "${GL_NO_TERM_SETUP+x}" ] && return
    [ -t 1 ] || return
    command -v stty >/dev/null 2>&1 || return
    # terminal_setup asks for a resize with CSI 8t and the terminal applies it
    # asynchronously - the reply has to travel back through the pty, so reading
    # stty straight away catches the OLD size and warns about a window that is
    # already being corrected. Wait for it to settle, but only when a resize was
    # actually requested, and never for long.
    #
    # The budget is a 5s DEADLINE rather than a tick count, so it holds whichever
    # sleep this box has. usleep is a busybox applet that is not on every build;
    # fractional `sleep` is not an option at all - it errors on some routers and
    # on others (MT1300) parses as ZERO, which would busy-spin and bring the
    # spurious warning straight back.
    if [ -n "$_TERM_RESIZE_SENT" ]; then
        _tsz_start=$(date +%s)
        _tsz_end=$(( _tsz_start + 5 ))
        _tsz_spin='-\|/'
        while [ "$(date +%s)" -lt "$_tsz_end" ]; do
            sz=$(stty size 2>/dev/null </dev/tty); r=${sz% *}; c=${sz#* }
            case "$r$c" in *[!0-9]*|'') break ;; esac
            { [ "$c" -ge "$TERM_NEED_COLS" ] && [ "$r" -ge "$TERM_MIN_ROWS" ]; } && \
                { printf '\r\033[K'; return; }
            # Say something once this is slow enough to look like a hang. A
            # terminal that honours the resize lands well inside a second, so
            # staying silent until then keeps the normal path clean instead of
            # trading one flash for another.
            if [ "$(( $(date +%s) - _tsz_start ))" -ge 1 ]; then
                _tsz_c=${_tsz_spin%"${_tsz_spin#?}"}
                _tsz_spin=${_tsz_spin#?}${_tsz_c}
                printf '\rChecking window size %s' "$_tsz_c"
            fi
            # 100ms, not 250: the window between the terminal reflowing scrollback
            # back into view and the caller clearing it is one tick long, and that
            # tick is the brief flash of the previous run's output on startup.
            usleep 100000 2>/dev/null || sleep 1
        done
        printf '\r\033[K'
    fi
    _tsz_warned=""
    while true; do
        sz=$(stty size 2>/dev/null </dev/tty); r=${sz% *}; c=${sz#* }
        case "$r" in ''|*[!0-9]*) return ;; esac
        case "$c" in ''|*[!0-9]*) return ;; esac
        if [ "$c" -ge "$TERM_NEED_COLS" ] && [ "$r" -ge "$TERM_MIN_ROWS" ]; then
            # Only reachable with a warning on screen if the user rechecked, and
            # a recheck that prints nothing reads as if the key did nothing. Say
            # it worked, then hold it - the caller clears the screen on return.
            if [ -n "$_tsz_warned" ]; then
                print_success "Window is now ${c} x ${r}. Continuing."
                sleep 2
            fi
            return
        fi
        _tsz_warned=1
        printf '\n'
        print_warning "This window is ${c} x ${r}. Some screens need ${TERM_NEED_COLS} x ${TERM_MIN_ROWS}."
        [ "$c" -lt "$TERM_NEED_COLS" ] && \
            print_info "Too narrow by $((TERM_NEED_COLS - c)) columns - wide tables will wrap and lose their alignment."
        [ "$r" -lt "$TERM_MIN_ROWS" ] && \
            print_info "Too short by $((TERM_MIN_ROWS - r)) rows - full screens will scroll."
        print_info "This toolkit asks the terminal to resize itself, but some terminals"
        print_info "ignore that. Widen the window by hand, then recheck."
        printf '\n [R] Recheck size   [C] Continue anyway: '
        read -r _tsz_ans
        printf '\n'
        case "$_tsz_ans" in
            r|R) continue ;;
            *)  # Same reasoning as the recheck path: acknowledge the choice
                # rather than clearing straight to the splash.
                print_info "Continuing at ${c} x ${r}. Some screens will wrap or scroll."
                sleep 2
                return ;;
        esac
    done
}

terminal_restore() {
    [ -n "$_TERM_RESTORED" ] && return              # idempotent - run once
    _TERM_RESTORED=1
    stty sane 2>/dev/null </dev/tty                 # restore line discipline: single-char reads (or a Ctrl-C mid-read) can leave the tty raw
    printf '\033[?25h'                              # ensure cursor visible
    printf '\033]110\007\033]111\007'              # reset fg/bg to profile defaults
    [ -n "$_TERM_ORIG_SIZE" ] && printf '\033[8;%st' "$_TERM_ORIG_SIZE"
}

# Clear, size the terminal, then clear again and draw. Nothing user-facing is
# painted until the geometry is final, because anything drawn beforehand is
# visibly disturbed by the resize: the splash gets painted, then jumps as the
# window grows. A grow also pulls scrolled-off lines back down into view -
# `clear` is ESC[H ESC[J, which erases the visible screen but NOT the
# scrollback - so remnants of the previous run land ABOVE whatever was already
# drawn, which no amount of clearing beforehand can prevent.
#
# The first clear is for detect_output_mode: on first run it installs
# coreutils-stty, and its "Setting up terminal support..." spinner should have a
# clean screen to appear on. It has to run before terminal_setup, which needs
# the detected profile to decide whether asking for a resize is worthwhile.
command -v clear >/dev/null 2>&1 && clear
detect_output_mode

# Widen + dark-theme the terminal for this session; restore it all on exit.
terminal_setup
terminal_size_advisory

command -v clear >/dev/null 2>&1 && clear
printf "%b\n" "$SPLASH"
trap 'terminal_restore' EXIT
trap 'terminal_restore; exit 130' INT
trap 'terminal_restore; exit 143' TERM

# -----------------------------
# Cleanup any previous updates
# -----------------------------
case "$0" in
    *.new)
        ORIGINAL="${0%.new}"
        printf "%s Applying update...\n" "$_S_ACT"
        # Carry the saved display preference into the new copy — an update swaps
        # the whole script, which would otherwise reset OUTPUT_PREF to default.
        old_pref=$(sed -n 's/^OUTPUT_PREF="\([^"]*\)".*/\1/p' "$ORIGINAL" 2>/dev/null)
        case "$old_pref" in
            full|compat) sed -i "s/^OUTPUT_PREF=\"[^\"]*\"/OUTPUT_PREF=\"$old_pref\"/" "$0" ;;
        esac
        mv -f "$0" "$ORIGINAL" && chmod +x "$ORIGINAL"
        printf "%s Update applied. Restarting...\n" "$_S_OK"
        sleep 3
        stty sane 2>/dev/null </dev/tty
        exec "$ORIGINAL" "$@"
        ;;
esac

# -----------------------------
# Utility Functions
# -----------------------------
# Count set bits in a hex mask ("0x7" -> 3). Empty/invalid -> 0. Used to turn an
# antenna chainmask into a spatial-stream count.
popcount_hex() {
    local pc_n pc_c
    case "$1" in ''|0x|0X) printf '0'; return ;; esac
    pc_n=$(( $1 )); pc_c=0
    while [ "$pc_n" -gt 0 ]; do pc_c=$(( pc_c + (pc_n & 1) )); pc_n=$(( pc_n >> 1 )); done
    printf '%s' "$pc_c"
}

# wifi_protocol <phy> <band>  ->  "802.11<letters>|Wi-Fi <gen>"  (empty gen -> just
# the standards). Reads the PHY's *capabilities* from `iw phy info` - HT (11n),
# VHT (11ac), HE (11ax), EHT (11be) - and composes the standards list correct for
# the BAND. This is band-aware on purpose: 802.11ac (VHT) is defined for 5/6 GHz
# only, so it is NEVER listed on 2.4 GHz even though some drivers (e.g. MediaTek
# on the MT1300) advertise a VHT capability block there - that is the
# vendor 256-QAM rate extension, not real 11ac. 6 GHz has no legacy/HT/VHT floor:
# HE (ax) is its minimum. Generation disambiguates Wi-Fi 6 vs 6E (both 802.11ax).
wifi_protocol() {
    local wp_phy="$1" wp_band="$2" wp_info wp_ht=0 wp_vht=0 wp_he=0 wp_eht=0 wp_std wp_gen=""
    wp_info=$(iw phy "$wp_phy" info 2>/dev/null)
    [ -z "$wp_info" ] && { printf 'N/A|'; return; }
    printf '%s\n' "$wp_info" | grep -qE '^[[:space:]]+Capabilities:' && wp_ht=1
    printf '%s\n' "$wp_info" | grep -q  'VHT Capabilities'            && wp_vht=1
    printf '%s\n' "$wp_info" | grep -q  'HE Iftypes'                  && wp_he=1
    printf '%s\n' "$wp_info" | grep -q  'EHT Iftypes'                 && wp_eht=1
    case "$wp_band" in
        2.4GHz)
            wp_std="b/g"
            [ "$wp_ht"  = 1 ] && { wp_std="$wp_std/n";  wp_gen="Wi-Fi 4"; }
            [ "$wp_he"  = 1 ] && { wp_std="$wp_std/ax"; wp_gen="Wi-Fi 6"; }
            [ "$wp_eht" = 1 ] && { wp_std="$wp_std/be"; wp_gen="Wi-Fi 7"; } ;;
        6GHz)
            wp_std="ax"; wp_gen="Wi-Fi 6E"
            [ "$wp_eht" = 1 ] && { wp_std="ax/be"; wp_gen="Wi-Fi 7"; } ;;
        *)  # 5 GHz (and any other band that reports the a/n/ac lineage)
            wp_std="a"
            [ "$wp_ht"  = 1 ] && { wp_std="$wp_std/n";  wp_gen="Wi-Fi 4"; }
            [ "$wp_vht" = 1 ] && { wp_std="$wp_std/ac"; wp_gen="Wi-Fi 5"; }
            [ "$wp_he"  = 1 ] && { wp_std="$wp_std/ax"; wp_gen="Wi-Fi 6"; }
            [ "$wp_eht" = 1 ] && { wp_std="$wp_std/be"; wp_gen="Wi-Fi 7"; } ;;
    esac
    printf '802.11%s|%s' "$wp_std" "$wp_gen"
}

press_any_key() {
    printf "\nPress any key to continue... "
    read -rsn1
    printf "\n"
}

read_single_char() {
    read -rsn1 char
    printf "%s" "$char"
}

# Item-selection token for a picker prompt: "1-N" only when there is an actual
# range; a single item prints just "1". Empty/zero count -> "1" (safe default).
picker_range() {
    [ "${1:-0}" -gt 1 ] 2>/dev/null && printf '1-%s' "$1" || printf '1'
}

print_centered_header() {
    title="$1"
    width=48
    title_display_len=${#title}
    case "$title" in
        *[🖥️📡🌐🔒⚙️💾📊🛡️📋☁️]*) title_display_len=$((title_display_len - 2)) ;;
    esac
    
    padding=$(((width - title_display_len) / 2))
    padding_right=$((width - padding - title_display_len))
    
    printf "\n%b\n" "${CYAN}┌────────────────────────────────────────────────┐${RESET}"
    printf "%b" "${CYAN}│"
    printf "%*s" $padding ""
    printf "%s" "$title"
    printf "%*s" $padding_right ""
    printf "%b\n" "│${RESET}"
    printf "%b\n\n" "${CYAN}└────────────────────────────────────────────────┘${RESET}"
}


# Helper: Secure Password Input with Asterisks
get_password() {
    local prompt="$1"
    local password=""
    local char=""
    local backspace=$(printf '\177')
    local ctrl_h=$(printf '\b')

    printf "%s" "$prompt" >&2  
    while :; do
        read -s -n 1 char
        if [ -z "$char" ] || [ "$char" = "$(printf '\r')" ]; then
            break
        fi

        if [ "$char" = "$backspace" ] || [ "$char" = "$ctrl_h" ]; then
            if [ ${#password} -gt 0 ]; then
                password="${password%?}"
                printf "\b \b" >&2
            fi
        else
            password="$password$char"
            printf "*" >&2
        fi
    done
    printf "\n" >&2
    printf "%s" "$password" 
}

# -----------------------------
# Changelog viewer
# -----------------------------
# show_changelog [ARGS...]
#   Fetches CHANGELOG.md and renders it newest-first in the house pager. When the
#   running version is behind the newest entry, a grey "your version" rule marks
#   the boundary between new-to-you entries (above) and already-installed ones
#   (below), and a [U] Update key appears in the footer -> apply_update, which
#   re-downloads and restarts. One render path for both the startup prompt and
#   the Toolkit Management menu; $CL_EXIT_LABEL sets the [0] label ("Skip" from
#   startup, "Back" from the menu). Page height comes from `stty size`, or a
#   safe 22-line default when stty can't report one. ARGS forward to apply_update
#   for the exec-on-restart. Returns 1 if the changelog can't be fetched.
show_changelog() {
    local cl_file="/tmp/.gl-changelog.$$" cl_rn="/tmp/.gl-cl-render.$$"
    local local_ver latest behind exitlbl
    local total rows plines pages start end page key i starts nstart

    local_ver="$(grep -m1 '^# Version:' "$SCRIPT_PATH" | awk '{print $3}' | tr -d '\r')"
    [ -z "$local_ver" ] && local_ver="0000-00-00"
    exitlbl="${CL_EXIT_LABEL:-Back}"

    if ! wget -q -O "$cl_file" "$CHANGELOG_URL" 2>/dev/null || [ ! -s "$cl_file" ]; then
        rm -f "$cl_file"
        return 1
    fi

    # Newest "## <version>" header is the latest release.
    latest="$(grep -m1 '^## ' "$cl_file" | awk '{print $2}')"
    if [ -n "$latest" ] && [ "$latest" \> "$local_ver" ]; then behind=1; else behind=0; fi

    # Render newest-first (drop the intro before the first header). When behind,
    # emit a grey boundary rule just before the first entry that is <= your
    # version, so everything above the rule is new to you.
    awk -v local="$local_ver" -v behind="$behind" -v g="$GREY" -v r="$RESET" '
        /^## / {
            seen = 1
            if (behind && !marked && ($2 "") <= (local "")) {
                printf " %s─────────────────────  your version: %s  ─────────────────────%s\n\n", g, local, r
                marked = 1
            }
            print; next
        }
        seen { print }
    ' "$cl_file" > "$cl_rn"
    rm -f "$cl_file"

    total=$(wc -l < "$cl_rn" 2>/dev/null)
    case "$total" in ''|*[!0-9]*) total=0 ;; esac
    if [ "$total" -eq 0 ]; then
        rm -f "$cl_rn"
        return 1
    fi

    # Changelog lines per screen: real height minus chrome, else a safe default.
    rows=$(stty size 2>/dev/null | awk '{print $1}')
    case "$rows" in
        ''|*[!0-9]*) plines=22 ;;
        *) plines=$((rows - 8)); [ "$plines" -lt 12 ] && plines=12 ;;
    esac

    # Page-start line numbers, snapped so a page never breaks mid-bullet: fill up
    # to plines lines, then back the cut up to the nearest header/bullet/rule so a
    # wrapped bullet's continuation lines stay with it. Hard-cuts only if a single
    # unit is taller than one page.
    starts=$(awk -v plines="$plines" '
        { safe[NR] = ($0 ~ /^## / || $0 ~ /^- / || index($0, "your version:")) ? 1 : 0 }
        END {
            total = NR; s = 1; printf "%d", s
            while (s + plines <= total) {
                cut = s + plines
                while (cut > s + 1 && !safe[cut]) cut--
                if (cut <= s + 1) cut = s + plines
                printf " %d", cut
                s = cut
            }
        }' "$cl_rn")
    [ -z "$starts" ] && starts=1                  # defensive: never wedge navigation on empty awk output
    pages=$(echo "$starts" | awk '{print NF}')
    case "$pages" in ''|*[!0-9]*|0) pages=1 ;; esac

    page=1
    while :; do
        start=$(echo "$starts" | cut -d' ' -f"$page")
        nstart=$(echo "$starts" | cut -d' ' -f"$((page + 1))")
        if [ -n "$nstart" ]; then end=$((nstart - 1)); else end=$total; fi
        clear
        print_centered_header "Change Log"
        printf "\n"
        sed -n "${start},${end}p" "$cl_rn"
        printf " ──────────────────────────────────────────────────────────────────────────────\n"

        # House pager footer: [P] Previous  <chips|Page X/Y>  [N] Next  [U]?  [0] label.
        # Numbered chips up to 9 pages (read_single_char can't take a two-digit
        # jump); a "Page X of Y" counter beyond that.
        printf " [P] Previous   "
        if [ "$pages" -le 9 ]; then
            i=1
            while [ "$i" -le "$pages" ]; do
                if [ "$i" -eq "$page" ]; then printf "%b[%d]%b " "$BOLD" "$i" "$RESET"
                else printf "%b[%d]%b " "$GREY" "$i" "$RESET"; fi
                i=$((i + 1))
            done
        else
            printf "%bPage %d of %d%b   " "$BOLD" "$page" "$pages" "$RESET"
        fi
        printf "  [N] Next   "
        [ "$behind" -eq 1 ] && printf "[U] Update   "
        printf "[0] %s  " "$exitlbl"

        key=$(read_single_char)
        printf "\n"
        case "$key" in
            p|P) [ "$page" -gt 1 ]        && page=$((page - 1)) ;;
            n|N) [ "$page" -lt "$pages" ] && page=$((page + 1)) ;;
            u|U) if [ "$behind" -eq 1 ]; then
                     apply_update "$@"   # execs on success; returns here only on failure
                     press_any_key
                 fi ;;
            0)   break ;;
            [1-9]) if [ "$pages" -le 9 ] && [ "$key" -le "$pages" ]; then
                       page="$key"
                   fi ;;
            *)   : ;;
        esac
    done

    rm -f "$cl_rn"
    return 0
}

# apply_update [ARGS...] : download the latest script, swap it in, and restart.
# Used by the changelog viewer's [U]. Execs on success (never returns); returns
# 1 on a download/write failure so the viewer can recover and let you retry.
apply_update() {
    if ! spin_run "Downloading update" wget -q -O "$TMP_NEW_SCRIPT" "$SCRIPT_URL"; then
        rm -f "$SPIN_LOG" 2>/dev/null
        print_warning "Download failed (network or GitHub issue)."
        return 1
    fi
    rm -f "$SPIN_LOG" 2>/dev/null
    print_action "Updating"
    if ! cp "$TMP_NEW_SCRIPT" "$SCRIPT_PATH.new" || ! chmod +x "$SCRIPT_PATH.new"; then
        print_warning "Could not write ${SCRIPT_PATH}.new (permissions?)."
        rm -f "$TMP_NEW_SCRIPT" 2>/dev/null
        return 1
    fi
    print_success "Upgrade complete. Restarting"
    stty sane 2>/dev/null </dev/tty   # reset line discipline (a raw-mode keypress triggered us) so the restarted copy can read input
    exec "$SCRIPT_PATH.new" "$@"
}

# --- Generic paged viewer (shared by every help screen) ----------------------
# Page-start line numbers for a body file at <plines> lines/page, each break SNAPPED back to
# the nearest blank line so a page never splits a paragraph; hard-cut only if one block is
# taller than a page. Pure (no terminal, no globals) so it is unit-testable in isolation.
_paged_starts() {   # <plines> <file>  -> space-separated 1-based start line numbers
    awk -v plines="$1" '
        { blank[NR] = ($0 ~ /^[[:space:]]*$/) ? 1 : 0 }
        END {
            total=NR; if (total==0) { print 1; exit }
            s=1; out=s
            while (s + plines <= total) {
                cut = s + plines
                while (cut > s + 1 && !blank[cut-1]) cut--     # back up to end a page on a blank
                if (cut <= s + 1) cut = s + plines             # a single block > one page: hard-cut
                out = out " " cut; s = cut
            }
            print out
        }' "$2"
}
# One keypress from the CONTROLLING TERMINAL, not stdin - show_paged's stdin is the heredoc
# body it just consumed. Returns "0" on EOF/no-tty so a non-interactive caller breaks cleanly.
# One keypress from the CONTROLLING TERMINAL (show_paged's stdin is the consumed heredoc body).
# Char-raw for the single read, then restore a SANE line discipline so the next page's newlines
# carry a carriage return (ONLCR) - a caller that left the tty in raw/char mode (the live Fan /
# Hardware screens) would otherwise make paged output staircase down the screen. "0" on EOF.
_pg_key() {
    local k
    stty -icanon -echo min 1 time 0 </dev/tty 2>/dev/null
    k=$(dd bs=1 count=1 2>/dev/null </dev/tty)
    stty sane </dev/tty 2>/dev/null
    [ -n "$k" ] && printf '%s' "$k" || printf '0'
}

# show_paged <title> [exit-label]  - scrollable viewer for pre-formatted text read from STDIN
# (a heredoc). Reuses the changelog house-pager: [P] Previous / numbered chips or Page X/Y /
# [N] Next / [0] Back, page breaks snapped to blank lines. Content that fits one screen shows a
# plain dwell. Non-interactive (a pipe, or no controlling terminal - e.g. the E2E harness):
# dumps the body once and returns, so nothing hangs.
show_paged() {
    local title="$1" exitlbl="${2:-Back}" body rows plines starts pages page start nstart end key i div total
    body=$(mktemp 2>/dev/null || echo "/tmp/.glpage.$$")
    cat > "$body"
    # strip whitespace first: BSD/macOS `wc -l` left-pads its count ("   13"), and the
    # non-numeric guard would then reset a valid total to 0 -> empty body. busybox does not
    # pad, so the fleet was unaffected, but keep it portable for the harness + other shells.
    total=$(wc -l < "$body" 2>/dev/null | tr -d ' \t'); case "$total" in ''|*[!0-9]*) total=0 ;; esac
    if [ ! -r /dev/tty ] || [ ! -t 1 ]; then      # non-interactive: dump, don't page
        clear 2>/dev/null; print_centered_header "$title"; sed '/./,$!d' "$body"; rm -f "$body"; return 0
    fi
    # A caller (the live Fan / Hardware screens) may hand us a tty still in raw/char mode; force a
    # sane line discipline so our multi-line rendering does not staircase. Restored + screen
    # cleared on exit so the caller's in-place redraw starts from a clean slate (not overlaid).
    stty sane </dev/tty 2>/dev/null
    rows=$(stty size 2>/dev/null </dev/tty | awk '{print $1}')
    case "$rows" in ''|*[!0-9]*) plines=22 ;; *) plines=$((rows - 8)); [ "$plines" -lt 12 ] && plines=12 ;; esac
    starts=$(_paged_starts "$plines" "$body")
    pages=$(printf '%s' "$starts" | awk '{print NF}'); case "$pages" in ''|*[!0-9]*|0) pages=1 ;; esac
    div=$(awk 'BEGIN{s="";for(i=0;i<78;i++)s=s"─";print s}')
    page=1
    while :; do
        # awk, not `cut -f`: POSIX cut PASSES THROUGH a single-field line (starts="1" on a
        # single-page body), so `cut -f2` returned "1" on busybox -> end=0 -> empty body. awk
        # yields "" for an out-of-range field, so nstart is correctly empty on the last page.
        start=$(echo "$starts" | awk -v p="$page" '{print $p}')
        nstart=$(echo "$starts" | awk -v p="$((page+1))" '{print $p}')
        [ -n "$nstart" ] && end=$((nstart-1)) || end="$total"
        # print_centered_header already leaves ONE blank line under the box (its trailing \n\n),
        # which matches every other screen - so no extra printf '\n' here (that was a second gap).
        # `sed '/./,$!d'` drops any leading blank lines of THIS page's slice (some help bodies, e.g.
        # the Hardware pages, open with a blank line) so the body starts right under that one gap.
        clear; print_centered_header "$title"
        sed -n "${start},${end}p" "$body" | sed '/./,$!d' | sed 's/^/ /'    # indent body 1 col to align with the divider/footer
        if [ "$pages" -le 1 ]; then
            printf '\n %b[0] %s   (or any key)%b ' "$GREY" "$exitlbl" "$RESET"; _pg_key >/dev/null; printf '\n'; break
        fi
        printf ' %s\n' "$div"
        printf ' [P] Previous   '
        if [ "$pages" -le 9 ]; then
            i=1; while [ "$i" -le "$pages" ]; do
                [ "$i" -eq "$page" ] && printf '%b[%d]%b ' "$BOLD" "$i" "$RESET" || printf '%b[%d]%b ' "$GREY" "$i" "$RESET"
                i=$((i+1)); done
        else printf '%bPage %d of %d%b   ' "$BOLD" "$page" "$pages" "$RESET"; fi
        printf '  [N] Next   [0] %s  ' "$exitlbl"
        key=$(_pg_key); printf '\n'
        case "$key" in
            p|P) [ "$page" -gt 1 ] && page=$((page-1)) ;;
            n|N) [ "$page" -lt "$pages" ] && page=$((page+1)) ;;
            0)   break ;;
            [1-9]) { [ "$pages" -le 9 ] && [ "$key" -le "$pages" ]; } && page="$key" ;;
            *)   : ;;
        esac
    done
    stty sane </dev/tty 2>/dev/null; clear    # leave a sane tty + clean screen for the caller
    rm -f "$body"; return 0
}

# -----------------------------
# Self-update check (startup)
# -----------------------------
# Runs once at launch: fetches the remote version, records UPDATE_STATUS and
# REMOTE_VERSION for the Toolkit Management STATUS block, and — only when a newer
# release exists — offers to open the changelog viewer (where [U] applies it).
# Silent when already current, so startup stays quiet unless there's news.
check_self_update() {
    local ans rc
    LOCAL_VERSION="$(grep -m1 '^# Version:' "$SCRIPT_PATH" | awk '{print $3}' | tr -d '\r')"
    [ -z "$LOCAL_VERSION" ] && LOCAL_VERSION="0000-00-00"

    # Fetch the remote copy to read its version. When a first-run install-skip
    # notice is on screen (STARTUP_NOTICE), let the spinner run 2s longer so the
    # message reads as productive activity instead of a dead pause. The sh -c
    # wrapper preserves wget's real exit code across the padding sleep. Its inner
    # rc= is single-quoted and runs in that child shell - it is NOT this
    # function's local rc, and the two never interact. Don't "fix" the name.
    if [ "$STARTUP_NOTICE" = 1 ]; then
        spin_run "Checking for updates" sh -c 'wget -q -O "$1" "$2"; rc=$?; sleep 2; exit $rc' sh "$TMP_NEW_SCRIPT" "$SCRIPT_URL"
    else
        spin_run "Checking for updates" wget -q -O "$TMP_NEW_SCRIPT" "$SCRIPT_URL"
    fi
    rc=$?
    if [ "$rc" -ne 0 ]; then
        rm -f "$SPIN_LOG" 2>/dev/null
        UPDATE_STATUS="unknown"
        return 1
    fi
    rm -f "$SPIN_LOG" 2>/dev/null

    REMOTE_VERSION="$(grep -m1 '^# Version:' "$TMP_NEW_SCRIPT" | awk '{print $3}' | tr -d '\r')"
    [ -z "$REMOTE_VERSION" ] && REMOTE_VERSION="0000-00-00"
    rm -f "$TMP_NEW_SCRIPT" >/dev/null 2>&1

    if [ "$REMOTE_VERSION" \> "$LOCAL_VERSION" ]; then
        UPDATE_STATUS="available"
        printf "\nA new version is available. View Change Log & Update? [Y/n]: "
        read -r ans
        printf "\n"
        case "$ans" in
            n|N) print_info "Skipping the change log and update — available in the Toolkit Management menu."; sleep 2 ;;
            *)   CL_EXIT_LABEL="Skip"; show_changelog "$@"; CL_EXIT_LABEL="" ;;
        esac
    else
        UPDATE_STATUS="current"
    fi
}

# -----------------------------
# System Detection Functions
# -----------------------------
# Run a command in the background with a "<label>... <spinner>" indicator, then
# finalize the line (label, no spinner) and return the command's exit status.
# Output is captured to $SPIN_LOG so the caller can inspect it on failure.
spin_run() {
    local label="$1"; shift
    local pid rc c spin='-\|/'
    "$@" >"$SPIN_LOG" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        c=${spin%"${spin#?}"}; spin=${spin#?}$c
        printf "\r${BOLD}${CYAN}${_S_ACT}${RESET}${CYAN}%s${RESET} %s" "$label" "$c"
        usleep 100000 2>/dev/null || sleep 1
    done
    wait "$pid"; rc=$?
    printf "\r${BOLD}${CYAN}${_S_ACT}${RESET}${CYAN}%s${RESET}\033[K\n" "$label"
    return "$rc"
}

# Like spin_run, but for a command with a KNOWN fixed duration (the caller
# already told the user how long) - shows seconds remaining instead of a
# generic spinner. Output is captured to $SPIN_LOG, same as spin_run.
countdown_run() {
    local label="$1" total="$2"; shift 2
    local pid rc remain
    "$@" >"$SPIN_LOG" 2>&1 &
    pid=$!
    remain=$total
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${BOLD}${CYAN}${_S_TIME}${RESET}${CYAN}%s${RESET} %ds remaining\033[K" "$label" "$remain"
        sleep 1
        [ "$remain" -gt 0 ] && remain=$((remain - 1))
    done
    wait "$pid"; rc=$?
    printf "\r${BOLD}${CYAN}${_S_TIME}${RESET}${CYAN}%s${RESET}\033[K\n" "$label"
    return "$rc"
}

# Diagnose a failed network operation: pings the internet, then the package
# server, and prints targeted advice. Returns 0 only if both are reachable.
check_connectivity() {
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        print_error "→ No internet connectivity (cannot reach 8.8.8.8)"
    elif ! ping -c 1 -W 3 downloads.openwrt.org >/dev/null 2>&1; then
        print_error "→ Internet works, but cannot reach the package server (DNS or repo issue?)"
    else
        return 0
    fi
    printf "\n"
    print_info "Common fixes:"
    printf "   • Check your internet connection\n"
    printf "   • Try: ping fw.gl-inet.com or ping downloads.openwrt.org\n"
    printf "   • Check date/time is correct (HTTPS validation)\n"
    printf "   • Re-flash firmware if repositories are very old or corrupted\n"
    return 1
}

# Refresh the package index once per session (gated by $opkg_updated). Shows a
# spinner; on failure prints diagnostics and returns non-zero - callers decide
# how to recover (it no longer exits the program).
check_opkg_updated() {
    [ "$opkg_updated" -eq 1 ] && return 0
    if spin_run "Updating package lists" pkg_update; then
        opkg_updated=1
        rm -f "$SPIN_LOG" 2>/dev/null
        return 0
    fi
    # pkg_update already tried the silent, non-destructive cache heal. If opkg is STILL throwing the
    # Packages-parse error, the corruption is in the installed database - offer a guarded, backed-up
    # repair inline (only when we can actually prompt).
    if [ -r /dev/tty ] && tail -n 40 "$SPIN_LOG" 2>/dev/null | pkg_parse_sig; then
        if offer_pkg_db_repair; then
            opkg_updated=1
            rm -f "$SPIN_LOG" 2>/dev/null
            return 0
        fi
        rm -f "$SPIN_LOG" 2>/dev/null
        return 1
    fi
    print_error "Package index update failed."
    check_connectivity
    print_info "Collected errors:"
    tail -n 20 "$SPIN_LOG" 2>/dev/null | grep -E '^(\*|\*\*\*|Collected errors:|wget returned)' | sed 's/^/  /'
    printf "\n"
    rm -f "$SPIN_LOG" 2>/dev/null
    return 1
}

# Inline, guarded repair of a corrupted installed opkg database - offered when the package index update
# keeps failing with the Packages-parse error after the silent cache heal. Warns, confirms (default No),
# backs up before any change, and only applies the safe end-of-file repair. Returns 0 only if the system
# parses clean afterwards; deeper corruption is deferred to the standalone Package System Repair tool.
offer_pkg_db_repair() {
    printf "\n"
    print_warning "The package database appears to be corrupted."
    printf "   opkg can't parse ${GREY}%s${RESET}, so installs and removals will fail until it is fixed.\n" "$(pkg_db_path)"
    printf "   Only a safe end-of-file repair is applied.\n\n"
    printf "Repair the package database now? [y/N]: "; read -r _pdr; printf "\n"
    case "$_pdr" in
        y|Y) ;;
        *) print_info "Skipped. You can repair it later via System Tweaks ▸ Package System Repair."; return 1 ;;
    esac
    spin_run "Repairing the installed database" pkg_db_repair
    spin_run "Verifying the package index" pkg_update
    if ! tail -n 40 "$SPIN_LOG" 2>/dev/null | pkg_parse_sig; then
        print_success "Package database repaired."
        return 0
    fi
    print_error "The automatic repair could not resolve it."
    print_info "Open System Tweaks ▸ Package System Repair to restore a backup or review options."
    return 1
}

# Ensure <pkg> is installed: no-op if already present, else refresh lists and
# install it with a spinner. $2 = optional friendly name for messages.
# Returns 0 if the package is installed afterwards, 1 otherwise.
install_package() {
    local pkg="$1" name="${2:-$1}"
    pkg_is_installed "$pkg" && return 0
    check_opkg_updated || return 1
    spin_run "Installing $name" pkg_install "$pkg"
    if pkg_is_installed "$pkg"; then
        print_success "Installed: $name"
        rm -f "$SPIN_LOG" 2>/dev/null
        return 0
    fi
    print_error "Failed to install $name."
    check_connectivity
    rm -f "$SPIN_LOG" 2>/dev/null
    return 1
}

# Ensure an external COMMAND is available, installing its package if the binary is missing (via the
# apk/opkg-aware install_package). For tools stock/vanilla OpenWrt does not ship by default - e.g.
# `openssl` lives in openssl-util, which GL firmware includes but bare OpenWrt does not. Returns 0
# if the command is present afterwards, 1 if still missing.
require_cmd() {   # <command> <package> [<friendly-name>]
    command -v "$1" >/dev/null 2>&1 && return 0
    install_package "$2" "${3:-$2}"
    command -v "$1" >/dev/null 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────
# Backup / restore module — shared by the AdGuardHome Backup & Recovery suite and
# the Package System Repair tool. Backups live CENTRALLY under
# /etc/glinet_utils/backups/<namespace>/, one file per component per timestamp,
# named "<basename>.<ts>" (ts = YYYYMMDDHHMMSS). Overlay-persistent (survives a
# reboot); intentionally NOT added to /etc/sysupgrade.conf (a backup is firmware-
# specific). A multi-component backup shares ONE ts across its components.
# ─────────────────────────────────────────────────────────────────────────────
BK_ROOT="/etc/glinet_utils/backups"

bk_ts()   { date +%Y%m%d%H%M%S; }                        # new backup timestamp
bk_date() {   # <ts> -> "YYYY-MM-DD HH:MM"
    local t="$1"; printf '%s-%s-%s %s:%s' "${t:0:4}" "${t:4:2}" "${t:6:2}" "${t:8:2}" "${t:10:2}"
}
bk_dir()  { local d="$BK_ROOT/$1"; mkdir -p "$d" 2>/dev/null; printf '%s' "$d"; }   # <ns> -> ensure+echo dir

bk_save() {   # <ns> <ts> <path>  -> copy path to <dir>/<basename>.<ts>  (skips a missing source)
    [ -f "$3" ] || return 1
    cp "$3" "$(bk_dir "$1")/$(basename "$3").$2"
}
bk_list() {   # <ns> [basename]  -> timestamps newest-first (for that component, or the union of all)
    local d; d="$(bk_dir "$1")"
    ls "$d/${2:+$2.}"* 2>/dev/null | sed 's/.*\.//' | grep -xE '[0-9]{14}' | sort -ru | awk '!seen[$0]++'
}
bk_has()  { [ -f "$(bk_dir "$1")/$2.$3" ]; }             # <ns> <basename> <ts>
bk_restore() {   # <ns> <ts> <path>  -> copy <dir>/<basename>.<ts> back to path
    local src; src="$(bk_dir "$1")/$(basename "$3").$2"
    [ -f "$src" ] && cp "$src" "$3"
}
bk_delete() { rm -f "$(bk_dir "$1")"/*."$2" 2>/dev/null; }   # <ns> <ts> -> all components for that ts
bk_size_kb() {   # <ns> <ts> -> total KB of all components for that ts (0 if none)
    du -sk "$(bk_dir "$1")"/*."$2" 2>/dev/null | awk '{s+=$1} END{print s+0}'
}

# One-time migration of legacy co-located "<path>.backup.<ts>" backups into the central store.
# Usage: bk_migrate_legacy <ns> <original-path>...  (e.g. the AGH config/binary/init paths).
bk_migrate_legacy() {
    local ns="$1"; shift; local d orig base f ts
    d="$(bk_dir "$ns")"
    for orig in "$@"; do
        base="$(basename "$orig")"
        for f in "$orig".backup.*; do
            [ -f "$f" ] || continue
            ts="${f##*.backup.}"
            case "$ts" in ''|*[!0-9]*) continue ;; esac
            [ -f "$d/$base.$ts" ] || mv "$f" "$d/$base.$ts"
        done
    done
}

get_lan_ip() {
    local lan_ip
    lan_ip=$(ip -4 addr show br-lan 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
    [ -z "$lan_ip" ] && lan_ip=$(uci -q get network.lan.ipaddr)
    [ -z "$lan_ip" ] && lan_ip="192.168.8.1"
    echo "${lan_ip}"
}

get_free_space() {
        local path="$1"
        while [ -n "$path" ] && [ ! -d "$path" ]; do
            path="${path%/*}"
        done
        [ -z "$path" ] && path="/"
        df -Ph "$path" 2>/dev/null | awk 'NR==2 {print $4}'
    }

get_fan_speed() {
    local fan_val=""
    local gl_path="/proc/gl-hw-info/fan"
    local node=""
    if [ -f "$gl_path" ]; then
        read -r node rest < "$gl_path" 2>/dev/null
        if [ -n "$node" ]; then
            for f in /sys/class/hwmon/"$node"/fan*_input; do
                if [ -f "$f" ]; then
                    read -r fan_val < "$f" 2>/dev/null
                    break
                fi
            done
        fi
    fi
    if [ -z "$fan_val" ]; then
        for f in /sys/class/hwmon/hwmon*/fan*_input; do
            if [ -f "$f" ]; then
                read -r fan_val < "$f" 2>/dev/null
                break
            fi
        done
    fi
    echo "${fan_val:-N/A}"
}

get_cpu_temp() {
    local raw_temp=""
    local temp_path=""
    if [ -f /proc/gl-hw-info/temperature ]; then
        read -r temp_path < /proc/gl-hw-info/temperature 2>/dev/null
    fi
    if [ -f "$temp_path" ]; then
        read -r raw_temp < "$temp_path" 2>/dev/null
    fi
    if [ -z "$raw_temp" ]; then
        for f in /sys/class/hwmon/hwmon*/temp*_input; do
            if [ -f "$f" ]; then
                read -r raw_temp < "$f" 2>/dev/null
                break
            fi
        done
    fi
    if [ -n "$raw_temp" ] && [ "$raw_temp" -ge 1000 ]; then
        local whole=$((raw_temp / 1000))
        local decimal=$(( (raw_temp % 1000) / 10 ))
        local formatted_decimal=$(printf "%02d" "$decimal")
        echo "$whole.$formatted_decimal"
    else
        echo "unknown"
    fi
}

get_cpu_vendor_model() {
    if [ -f /proc/device-tree/compatible ]; then
        result=$(tr '\0' '\n' < /proc/device-tree/compatible 2>/dev/null | grep -iE '^(mediatek|qcom|qca),' | head -1 | sed -E 's/^(mediatek|qcom|qca),/\1 /i; s/mt/MT/i; s/ipq/IPQ/i; s/qca/QCA/i')
        
        if [ -n "$result" ]; then
            printf "%s" "$result"
        else
            printf "Unknown"
        fi
    else
        printf "Unknown"
    fi
}

# Best-effort max CPU clock in MHz. Sources, most authoritative first; prints
# nothing if none are readable, so the caller simply omits the Frequency line.
#   1) lscpu             - x86 and boards that populate the MHz fields
#   2) cpufreq sysfs max - boards with a running DVFS governor
#   3) device-tree OPP   - opp-hz (64-bit big-endian Hz) decoded via hexdump;
#                          boards with an OPP table but no cpufreq driver loaded
#   4) last resort       - known fixed clocks for legacy SoCs that expose no
#                          OPP/cpufreq/lscpu data; only reached when 1-3 fail
get_cpu_freq_mhz() {
    local mhz khz v f

    if command -v lscpu >/dev/null 2>&1; then
        mhz=$(lscpu 2>/dev/null | awk -F: '/CPU max MHz/{print $2; exit}' | tr -dc '0-9.')
        [ -z "$mhz" ] && mhz=$(lscpu 2>/dev/null | awk -F: '/CPU MHz/{print $2; exit}' | tr -dc '0-9.')
        [ -n "$mhz" ] && { printf '%s' "$mhz"; return; }
    fi

    khz=0
    for f in /sys/devices/system/cpu/cpufreq/policy*/cpuinfo_max_freq \
             /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq; do
        [ -r "$f" ] || continue
        v=$(cat "$f" 2>/dev/null)
        [ "${v:-0}" -gt "$khz" ] 2>/dev/null && khz=$v
    done
    [ "$khz" -gt 0 ] 2>/dev/null && { printf '%s' "$((khz / 1000))"; return; }

    if command -v hexdump >/dev/null 2>&1; then
        mhz=$(for f in /proc/device-tree/cpus/opp_table*/opp*/opp-hz; do
                  [ -f "$f" ] && hexdump -v -e '1/1 "%u "' "$f"
                  echo
              done | awk '{v=0; for(i=1;i<=NF;i++) v=v*256+$i; if(v>m) m=v}
                         END{if(m>0) printf "%.0f", m/1000000}')
        [ -n "$mhz" ] && { printf '%s' "$mhz"; return; }
    fi

    # Last resort: known fixed clocks for legacy SoCs with no programmatic source.
    case "$(get_cpu_vendor_model)" in
        *MT7988*)  printf '1800' ;; # Flint 4 (BE14000)
        *MT7986*)  printf '2000' ;; # Flint 2
        *MT7981*)  printf '1300' ;; # Beryl AX
        *MT7621*)  printf '880'  ;; # Beryl
        *SF19A28*) printf '1000' ;; # Opal
        *IPQ4018*) printf '717'  ;; # Slate Plus
    esac
}

# CPU topology, portable across the fleet's MIPS + ARM. Emits "<logical> <physical>":
#   logical  = grep -c ^processor        - every thread (what the stress test loads)
#   physical = distinct core_id in /sys  - real cores; equals logical on non-SMT parts
# Falls back to logical when /sys exposes no topology, so a plain multi-core chip reads
# "N cores" and only multithreaded parts (e.g. MT7621: 2 cores / 4 threads) differ.
# Verified on the fleet: MT7621 -> "4 2", ARM quad -> "4 4", ARM dual -> "2 2".
cpu_counts() {
    local _l _p
    _l=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
    case "$_l" in ''|*[!0-9]*) _l=1 ;; esac
    [ "$_l" -lt 1 ] && _l=1
    _p=$(cat /sys/devices/system/cpu/cpu*/topology/core_id 2>/dev/null | sort -u | grep -c .)
    case "$_p" in ''|*[!0-9]*) _p=0 ;; esac
    { [ "$_p" -lt 1 ] || [ "$_p" -gt "$_l" ]; } && _p="$_l"
    printf '%s %s' "$_l" "$_p"
}

# Round a MB figure UP to the nearest standard RAM size. Kernel MemTotal is ALWAYS below PHYSICAL
# by a variable, sometimes-large amount (kernel image + MediaTek/Qualcomm reserved-memory carve-outs
# - measured 11-162 MB across the fleet, the 162 on a Qualcomm IPQ5332). Rounding to the next
# standard size recovers physical; fine-grained rounding (nearest 32/16/8) would just echo the
# under-report. The 1.5x sizes (192/384/768/1536/3072/6144/12288) keep a 768 MB / 1.5 GB device from
# over-rounding to the next power of two. >16 GB falls to a 256 MB grid.
_mem_bucket() {
    local m=$1 s
    for s in 32 64 128 192 256 384 512 768 1024 1536 2048 3072 4096 6144 8192 12288 16384; do
        [ "$m" -le "$s" ] && { printf '%s' "$s"; return; }
    done
    printf '%s' "$(( (m + 255) / 256 * 256 ))"
}

get_mem_stats() {
    local t=0 a=0 f=0
    if [ -f /proc/meminfo ]; then
        while read -r label value unit; do
            case "$label" in
                MemTotal:)     t=$((value / 1024)) ;;
                MemAvailable:) a=$((value / 1024)) ;;
                MemFree:)      f=$((value / 1024)) ;;
            esac
            [ "$t" -gt 0 ] && [ "$a" -gt 0 ] && [ "$f" -gt 0 ] && break
        done < /proc/meminfo
    fi
    mem_rounded=$(_mem_bucket "$t")
    mem_total=$t
    mem_avail=$a
    mem_free=$f
    mem_used=$((t - a))
    mem_buffcache=$((a - f))
    local p_scaled=0
    if [ "$t" -gt 0 ]; then
        p_scaled=$(( (mem_used * 1000) / t ))
    fi
    mem_p_whole=$((p_scaled / 10))
    mem_p_decimal=$((p_scaled % 10))
}

get_agh_config() {
    if [ ! -f "$AGH_INIT" ]; then
        return 1
    fi
    
    config_path=$(grep -o '\-c [^ ]*' "$AGH_INIT" | awk '{print $2}')
    if [ -n "$config_path" ] && [ -f "$config_path" ]; then
        printf "%s" "$config_path"
        return 0
    fi
    
    return 1
}

get_agh_workdir() {
    if [ ! -f "$AGH_INIT" ]; then
        return 1
    fi
    
    workdir=$(grep -o '\-w [^ ]*' "$AGH_INIT" | awk '{print $2}')
    if [ -n "$workdir" ] && [ -d "$workdir" ]; then
        printf "%s" "$workdir"
        return 0
    fi
    
    return 1
}

is_agh_running() {
    if ! pidof AdGuardHome >/dev/null 2>&1; then
        return 1
    fi

    if netstat -tunlp | grep -q "AdGuardHome"; then
        return 0
    fi

    return 1
}

# Apply a config/file change while PRESERVING AdGuardHome's run-state.
# Restarts AGH only if it was running before the change; a deliberately-stopped
# service is left stopped (no false "failed to start"). Reverts from backup only
# if AGH WAS running and fails to come back.
#   $1 = was_running (1/0)
#   $2 = backup file ("" to skip revert)
#   $3 = restore target ("" to skip revert)
#   $4 = success context message (optional)
#   $5 = note shown when AGH is stopped (optional; default = deferred-apply note; "-" suppresses)
# Returns 0 when AGH ends in its expected state, 1 on a genuine restart failure.
agh_apply_and_restart() {
    local was_running="$1" backup="$2" target="$3" ctx="$4"
    local stopped_note="${5:-AdGuardHome is stopped — changes will apply when it next starts.}"
    printf "\n"
    if [ "$was_running" != "1" ]; then
        print_success "${ctx:-Changes saved.}"
        [ "$stopped_note" = "-" ] || print_info "$stopped_note"
        return 0
    fi
    $AGH_INIT start >/dev/null 2>&1; sleep 2
    if is_agh_running; then
        print_success "${ctx:-Changes applied.}"
        print_success "AdGuardHome restarted successfully."
        return 0
    fi
    if [ -n "$backup" ] && [ -n "$target" ]; then
        print_error "AdGuardHome failed to start! Reverting"
        cp "$target" "${target}.error.$(date +%Y%m%d%H%M%S)" 2>/dev/null
        cp "$backup" "$target"
        $AGH_INIT start >/dev/null 2>&1; sleep 2
        if is_agh_running; then
            print_warning "Restored last known good configuration."
            return 1
        fi
        print_error "Could not restart AdGuardHome even after reverting — check the configuration manually."
        return 1
    fi
    print_error "AdGuardHome failed to start — check the configuration manually."
    return 1
}

# Service run-state control (Start / Restart / Stop). Surfaced at the top of the
# Control Center because it is the most-used action and answers the STATUS line.
agh_service_control() {
    if is_agh_running; then
        printf "\n"
        print_warning "Service is RUNNING."
        printf "Disable, Restart, or Cancel? [D/R/0]: "; read -r confirm
        if [ "$confirm" = "d" ] || [ "$confirm" = "D" ]; then
            uci set adguardhome.config.enabled='0' && uci set adguardhome.config.dns_enabled='0' && uci commit adguardhome
            $AGH_INIT stop >/dev/null 2>&1; sleep 1; printf "\n"; print_success "Service Disabled"
        elif [ "$confirm" = "r" ] || [ "$confirm" = "R" ]; then
            $AGH_INIT restart >/dev/null 2>&1; sleep 2; printf "\n"; print_success "Service Restarted"
        fi
    else
        printf "\n"
        print_warning "Service is STOPPED."
        printf "Enable the service? [y/N]: "; read -r confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            uci set adguardhome.config.enabled='1' && uci set adguardhome.config.dns_enabled='1' && uci commit adguardhome
            $AGH_INIT enable >/dev/null 2>&1; sleep 1; $AGH_INIT start >/dev/null 2>&1; sleep 2; printf "\n"; print_success "Service Enabled"
        fi
    fi
    press_any_key
}

# Mask a colon-delimited MAC address, keeping only the last octet visible.
mask_mac() {
    printf '%s' "$1" | awk -F: '{out=""; for(i=1;i<NF;i++) out=out"**:"; print out $NF}'
}

# Mask a string, keeping only its last 2 characters visible (same length out
# as in, so masking never shifts column alignment).
mask_keep_tail() {
    local s="$1" len tail_part stars i=0
    len=${#s}
    [ "$len" -le 2 ] && { printf '%s' "$s"; return; }
    tail_part=$(printf '%s' "$s" | tail -c 2)
    stars=""
    while [ "$i" -lt "$((len - 2))" ]; do stars="${stars}*"; i=$((i + 1)); done
    printf '%s%s' "$stars" "$tail_part"
}

# -----------------------------
# Hardware Information Display
# -----------------------------
# ---- Hardware Info page 3: physical port panel (data-driven) -----------------
# Reads GL's port map (eth_ports_config_map) when present, else swconfig, else raw
# netdevs; renders a column grid grouped by fabric with an accurate "Maps to" (the
# real ifconfig netdev). Nothing model-specific is hardcoded - silk labels, chip
# names, roles and speeds all come from the device at runtime.
hwnet_spd() { case "$1" in 10000)echo 10G;; 5000)echo 5G;; 2500)echo 2.5G;; 1000)echo 1G;; 100)echo 100M;; 10)echo 10M;; ""|-1|0)echo "-";; *)echo "${1}M";; esac; }
hwnet_lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
hwnet_mac() { hwnet_lc "$(cat "/sys/class/net/$1/address" 2>/dev/null)"; }
hwnet_dev_by_mac() {                    # mac -> first netdev carrying it
    _m=$(hwnet_lc "$1"); [ -z "$_m" ] && return 1
    for _p in /sys/class/net/*; do
        [ "$(hwnet_lc "$(cat "$_p/address" 2>/dev/null)")" = "$_m" ] && { echo "${_p##*/}"; return 0; }
    done; return 1
}
hwnet_bridge() {                        # -> primary LAN bridge (br-lan, else first br-*)
    [ -e /sys/class/net/br-lan ] && { echo br-lan; return; }
    for _p in /sys/class/net/br-*; do [ -e "$_p" ] && { echo "${_p##*/}"; return; }; done
}
hwnet_conduit() { ip -o link show "$1" 2>/dev/null | sed -n 's/^[0-9]*: [^@]*@\([^:]*\):.*/\1/p' | head -1; }
hwnet_lan_vlandev() {                   # main_if -> the VLAN sub-netdev whose MAC == bridge MAC
    _mif="$1"; _bm=$(hwnet_mac "$(hwnet_bridge)"); [ -z "$_bm" ] && return 1
    for _p in /sys/class/net/"$_mif".*; do [ -e "$_p" ] || continue
        [ "$(hwnet_mac "${_p##*/}")" = "$_bm" ] && { echo "${_p##*/}"; return 0; }
    done; return 1
}
hwnet_state() {                         # rs -> up|mbps / down| / na|
    case "$1" in
        sw:*) _r=${1#sw:}; _sw=${_r%%:*}; _pt=${_r#*:}
            _raw=$(swconfig dev "$_sw" port "$_pt" show 2>/dev/null | grep 'link:')
            if echo "$_raw" | grep -q 'link:up'; then echo "up|$(echo "$_raw" | sed -n 's/.*speed:\([0-9]*\)base.*/\1/p')"
            elif echo "$_raw" | grep -q 'link:down'; then echo "down|"; else echo "na|"; fi ;;
        nd:*) _nd=${1#nd:}
            _st=$(ubus call network.device status "{\"name\":\"$_nd\"}" </dev/null 2>/dev/null)
            if [ -n "$_st" ]; then
                _sp=$(echo "$_st" | sed -n 's/.*"speed": "\(-\{0,1\}[0-9]*\)[FH]".*/\1/p')
                _car=$(echo "$_st" | sed -n 's/.*"carrier": \(true\|false\).*/\1/p' | head -1)
                [ "$_car" = true ] && echo "up|$_sp" || echo "down|"; return
            fi
            _car=$(cat "/sys/class/net/$_nd/carrier" 2>/dev/null); _sp=$(cat "/sys/class/net/$_nd/speed" 2>/dev/null)
            [ "$_car" = 1 ] && echo "up|$_sp" || echo "down|" ;;
    esac
}
hwnet_grp_meta() {                      # grp label uplink -> record group once (with uplink speed)
    grep -q "^$1$TAB" "$NG" 2>/dev/null && return
    _us=""; [ -n "$3" ] && _us=$(hwnet_spd "$(cat "/sys/class/net/$3/speed" 2>/dev/null)")
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$_us" >> "$NG"
}
hwnet_collect() {
    NT="/tmp/.glnet-net.$$"; NG="$NT.g"; TAB=$(printf '\t'); SRC=""
    : > "$NT"; : > "$NG"
    if [ -f /etc/config/eth_ports_config_map ]; then
        SRC="GL port map"
        for _s in $(uci -q show eth_ports_config_map 2>/dev/null | sed -n 's/^eth_ports_config_map\.\([^.=]*\)=port$/\1/p'); do
            silk=$(uci -q get "eth_ports_config_map.$_s.silk"); [ -z "$silk" ] && silk=$(uci -q get "eth_ports_config_map.$_s.name")
            mode=$(uci -q get "eth_ports_config_map.$_s.mode"); [ -z "$mode" ] && mode=$(uci -q get "eth_ports_config_map.$_s.default_mode")
            role=$(printf '%s' "$mode" | tr 'a-z' 'A-Z'); [ -z "$role" ] && role="-"
            typ=$(uci -q get "eth_ports_config_map.$_s.type")
            prt=$(uci -q get "eth_ports_config_map.$_s.port")
            sw=$(uci -q get "eth_ports_config_map.$_s.switch")
            mif=$(uci -q get "eth_ports_config_map.$_s.main_interface")
            dmac=$(uci -q get "eth_ports_config_map.$_s.default_mac")
            case "$typ" in
                gsw) grp="${sw:-switch0}"; rs="sw:$grp:$prt"
                     md=$(hwnet_dev_by_mac "$dmac" 2>/dev/null)
                     if   [ -n "$md" ]; then mapsto="$md"
                     elif [ "$role" = LAN ]; then mapsto=$(hwnet_lan_vlandev "$mif" 2>/dev/null); [ -z "$mapsto" ] && mapsto="${mif:-?}"
                     else mapsto="${mif:-?}"; fi
                     chip=$(swconfig list 2>/dev/null | sed -n "s/^Found: $grp - \(.*\)$/\1/p")
                     hwnet_grp_meta "$grp" "${grp}${chip:+ · $chip}" "$mif" ;;
                dsa) rs="nd:$prt"; mapsto="$prt"; _con=$(hwnet_conduit "$prt")
                     if [ -n "$_con" ]; then grp="socsw"; hwnet_grp_meta socsw "SoC switch (DSA)" "$_con"
                     else grp="direct"; hwnet_grp_meta direct "Direct SoC" ""; fi ;;
                *)   rs="nd:$prt"; mapsto="$prt"; grp="direct"; hwnet_grp_meta direct "Direct SoC" "" ;;
            esac
            printf '%s\t%s\t%s\t%s\t%s\n' "$grp" "$silk" "$role" "$rs" "$mapsto" >> "$NT"
        done
    elif [ -n "$(swconfig list 2>/dev/null)" ]; then
        # No GL port map, but there IS a switch: derive the CHASSIS ports from the
        # network config, not by dumping every swconfig port (which includes CPU and
        # inter-switch trunks that aren't physical ports).
        SRC="network config"
        # WAN: each wan* interface's device, when it's a real netdev port.
        for _wi in wan wan2 wan3; do
            _wd=$(uci -q get "network.$_wi.device"); [ -z "$_wd" ] && continue
            case "$_wd" in br-*|@*) continue ;; esac
            [ -e "/sys/class/net/$_wd" ] || continue
            hwnet_grp_meta wan "WAN" ""
            _wl=WAN; [ "$_wi" != wan ] && _wl=$(printf '%s' "$_wi" | tr a-z A-Z)
            printf 'wan\t%s\tWAN\tnd:%s\t%s\n' "$_wl" "$_wd" "$_wd" >> "$NT"
        done
        # LAN: untagged port numbers in a *lan* switch_vlan are real ports; the "Nt"
        # tag is the CPU/uplink (== the switch's cpu port), excluded. The owning switch
        # is the one whose cpu port matches that tag.
        _brdev=$(ls /sys/class/net/"$(hwnet_bridge)"/brif/ 2>/dev/null | grep -E '^(eth|lan)' | head -1)
        [ -z "$_brdev" ] && _brdev=$(hwnet_bridge)
        _lann=0
        for _v in $(uci -q show network 2>/dev/null | sed -n 's/^network\.\([^.=]*\)=switch_vlan$/\1/p'); do
            case "$_v" in *lan*) ;; *) continue ;; esac
            _pl=$(uci -q get "network.$_v.ports"); [ -z "$_pl" ] && continue
            _cpu=""; for _t in $_pl; do case "$_t" in *t) _cpu=${_t%t} ;; esac; done
            _sw=""
            for _s2 in $(swconfig list 2>/dev/null | awk '{print $2}'); do
                [ "$(swconfig dev "$_s2" help 2>&1 | sed -n 's/.*cpu @ \([0-9]*\).*/\1/p')" = "$_cpu" ] && { _sw="$_s2"; break; }
            done
            [ -z "$_sw" ] && _sw=$(swconfig list 2>/dev/null | awk 'NR==1{print $2}')
            _chip=$(swconfig list 2>/dev/null | sed -n "s/^Found: $_sw - \(.*\)$/\1/p")
            hwnet_grp_meta lan "LAN  ($_sw${_chip:+ · $_chip})" ""
            for _t in $_pl; do
                case "$_t" in *t) continue ;; esac
                _lann=$((_lann+1))
                printf 'lan\tLAN%s\tLAN\tsw:%s:%s\t%s\n' "$_lann" "$_sw" "$_t" "$_brdev" >> "$NT"
            done
        done
    else
        SRC="netdev"
        hwnet_grp_meta soc "SoC ports" ""
        bwan=$(jsonfilter -e '@.network.wan.device' -i /etc/board.json </dev/null 2>/dev/null)
        blan=$(jsonfilter -e '@.network.lan.device' -i /etc/board.json </dev/null 2>/dev/null)
        [ -z "$bwan" ] && bwan=$(uci -q get network.wan.device)
        [ -z "$bwan" ] && bwan=$(uci -q get network.wan.ifname)
        [ -z "$blan" ] && blan=$(uci -q get network.lan.device)
        blan="$blan $(ls "/sys/class/net/$(hwnet_bridge)/brif/" 2>/dev/null | tr '\n' ' ')"
        _cand=""
        for _p in /sys/class/net/*; do _n=${_p##*/}
            case "$_n" in lo|br-*|wlan*|wg*|ovpn*|apcli*|ra|rai|rax|ra[0-9]*|rai[0-9]*|rax[0-9]*|*.*|ifb*|tailscale*|teql*|wds*|mesh*|sit*|ip6*|gre*) continue ;; esac
            [ "$(cat "$_p/type" 2>/dev/null)" = 1 ] || continue
            [ -e "$_p/carrier" ] || continue
            _cand="$_cand $_n"
        done
        _haslw=0; for _n in $_cand; do case "$_n" in lan[0-9]*|wan|wan[0-9]*) _haslw=1 ;; esac; done
        for _n in $_cand; do
            [ "$_haslw" = 1 ] && case "$_n" in eth[0-9]*) continue ;; esac
            case " $bwan " in
                *" $_n "*) silk=WAN; role=WAN ;;
                *) case " $blan " in
                    *" $_n "*) case "$_n" in lan[0-9]*) silk=$(printf '%s' "$_n" | tr a-z A-Z) ;; *) silk=LAN ;; esac; role=LAN ;;
                    *) case "$_n" in
                        wan*) silk=$(printf '%s' "$_n" | tr a-z A-Z); role=WAN ;;
                        lan*) silk=$(printf '%s' "$_n" | tr a-z A-Z); role=LAN ;;
                        *)    silk=$(printf '%s' "$_n" | tr a-z A-Z); role="-" ;;
                    esac ;;
                esac ;;
            esac
            printf 'soc\t%s\t%s\tnd:%s\t%s\n' "$silk" "$role" "$_n" "$_n" >> "$NT"
        done
    fi
}
hwnet_render() {
    # Colour rule: cyan = section labels; green = UP, grey = DOWN (state ONLY, so
    # nothing else is grey or it reads as "down"); everything structural is plain.
    printf ' %bPhysical Ports%b\n' "$CYAN" "$RESET"
    printf '   %b%-11s %-4s  %-6s  %-6s  %s%b\n' "$CYAN" "Port" "Role" "Status" "Link" "Maps to" "$RESET"
    printf '   ────────────────────────────────────────────\n'
    while IFS="$TAB" read grp glabel uplink uspeed; do
        _u=""; [ -n "$uplink" ] && _u="   uplink $uplink${uspeed:+ ($uspeed to SoC)}"
        printf ' %b%s%b%s\n' "$HDR2" "$glabel" "$RESET" "$_u"
        grep "^$grp$TAB" "$NT" 2>/dev/null | while IFS="$TAB" read g silk role rs mapsto; do
            st=$(hwnet_state "$rs"); state=${st%%|*}; mb=${st#*|}; link=$(hwnet_spd "$mb")
            case "$state" in
                up) statc=$GREEN; stat=UP;   linkc=$GREEN ;;
                *)  statc=$GREY;  stat=DOWN; linkc=$GREY; link="-" ;;
            esac
            printf '   %-11s %-4s  %b%-6s%b  %b%-6s%b  %s\n' \
                "$silk" "$role" "$statc" "$stat" "$RESET" "$linkc" "$link" "$RESET" "$mapsto"
        done
    done < "$NG"
    printf '\n'
    _wandev=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')
    _wanip=$(ip -4 -o addr show "$_wandev" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
    [ -n "$_wanip" ] && printf ' %bWAN address:%b %s%s\n' "$CYAN" "$RESET" "$_wanip" "${_wandev:+ ($_wandev)}"
    _br=$(hwnet_bridge)
    if [ -n "$_br" ]; then
        _ip=$(ip -4 -o addr show "$_br" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
        _mem=$(ls "/sys/class/net/$_br/brif/" 2>/dev/null | grep -E '^(eth|lan|wan)' | tr '\n' ' ' | sed 's/ *$//')
        printf ' %bLAN bridge:%b  %s%s%s\n' "$CYAN" "$RESET" "$_br" "${_ip:+ ($_ip)}" "${_mem:+ = $_mem}"
    fi
    printf '\n %bLegend:%b %bUP%b link   %bDOWN%b no-link\n' "$BOLD" "$RESET" "$GREEN" "$RESET" "$GREY" "$RESET"
    rm -f "$NT" "$NG"
}

# Per-page quick help for the Hardware Information viewer. $1 = the page on screen.
show_hardware_help() {
    # Per-page help for the Hardware Information screen (current page in $1); each page's help
    # is short and shown through the shared paged viewer.
    case "${1:-1}" in
        2) show_paged "Hardware Information - Help" <<'HELPEOF'

 Page 2 - Hardware Crypto Acceleration
   Whether the CPU accelerates the ciphers your VPNs use. AES-GCM
   (OpenVPN / IPsec) needs PMULL; ChaCha20 (WireGuard) needs NEON/SIMD.
   Green means the hardware fast path is available.

 On the Hardware Info screen: [P]/[N] or [1-4] change pages, [0] exits.
HELPEOF
        ;;
        3) show_paged "Hardware Information - Help" <<'HELPEOF'

 Page 3 - Network Interfaces
   Every physical port, grouped by the chip it hangs off.

     Role     WAN or LAN - a WAN/LAN port shows its current job.
     Link     the speed it negotiated ( - when down ).
     Maps to  the Linux interface it appears as (as in ifconfig).
              Switch ports share one VLAN netdev; DSA ports each get
              their own, so LAN6 can map to lan5.
     uplink   the switch-to-SoC link and its speed - the pipe OUT of
              the switch, not a per-port limit. Ports on the same chip
              switch among themselves at full speed.

 On the Hardware Info screen: [P]/[N] or [1-4] change pages, [0] exits.
HELPEOF
        ;;
        4) show_paged "Hardware Information - Help" <<'HELPEOF'

 Page 4 - Wireless Interfaces
   Each Wi-Fi radio: band, protocol (Wi-Fi 4/5/6/7), channel width,
   MIMO streams and the current channel.

 On the Hardware Info screen: [P]/[N] or [1-4] change pages, [0] exits.
HELPEOF
        ;;
        *) show_paged "Hardware Information - Help" <<'HELPEOF'

 Page 1 - System Overview
   Device model, CPU, memory, storage and uptime. This page refreshes
   live once a second. Press * to reveal or hide the serial and MAC.

 On the Hardware Info screen: [P]/[N] or [1-4] change pages, [0] exits.
HELPEOF
        ;;
    esac
}

show_hardware_info() {
    page=1
    reveal_ids=0
    total_pages=4
    nav_choice=""
    
    clear
    hash -r
    if ! command -v lscpu >/dev/null 2>&1; then
        print_centered_header "Hardware Information"
        install_package lscpu "lscpu (enhanced CPU info)"
        clear
    fi

    if command -v uci >/dev/null 2>&1; then
        hostname=$(uci get system.@system[0].hostname 2>/dev/null)
    fi

    if [ -f /proc/gl-hw-info/device_mac ]; then
        mac=$(cat /proc/gl-hw-info/device_mac 2>/dev/null)
    fi

    if [ -f /proc/gl-hw-info/device_sn ]; then
        sn=$(cat /proc/gl-hw-info/device_sn 2>/dev/null)
    fi

    if [ -f /proc/gl-hw-info/device_ddns ]; then
        ddns=$(cat /proc/gl-hw-info/device_ddns 2>/dev/null)
    fi

    cpu_vendor_model=$(get_cpu_vendor_model)

    # "Cores: N" normally; "P (L threads)" only when the chip is multithreaded (SMT),
    # e.g. MT7621 = 2 cores / 4 threads. cpu_counts() emits "<logical> <physical>".
    _cc=$(cpu_counts); cpu_logical=${_cc% *}; cpu_phys=${_cc#* }
    if [ "$cpu_phys" -lt "$cpu_logical" ]; then
        cpu_cores="$cpu_phys ($cpu_logical threads)"
    else
        cpu_cores="$cpu_logical"
    fi

    cpu_freq=$(get_cpu_freq_mhz)

    # 1. Primary: GL.iNet Universal Hardware Info (4.x+ Firmware)
    if [ -f /proc/gl-hw-info/flash_size ]; then
        flash_raw=$(cat /proc/gl-hw-info/flash_size | sed 's/MiB/MB/')
        
        # Determine type: eMMC is usually > 1GB or specifically on Brume/Flint series
        # But we can be precise by checking for the block device existence
        if [ -b /dev/mmcblk0 ]; then
            type="eMMC"
        else
            type="NAND Flash"
        fi
        storage_info=$(printf "   Physical %s: %b%s%b\n" "$type" "${GREEN}" "$flash_raw" "${RESET}")
    
    # 2. Smart dmesg detection
    elif dmesg | grep -iE "nand|spi|mtd|mmc" | grep -iq "MiB"; then
        d_line=$(dmesg | grep -iE "nand|spi|mtd|mmc" | grep -i "MiB" | head -n 1)
        d_size=$(echo "$d_line" | grep -oE '[0-9]+ MiB' | sed 's/MiB/MB/')
        
        case "$(echo "$d_line" | tr 'A-Z' 'a-z')" in
            *nand*) type="NAND Flash" ;;
            *spi*)  type="SPI Flash" ;;
            *mmc*)  type="eMMC" ;;
            *)      type="Flash Storage" ;;
        esac
        storage_info=$(printf "   Physical %s: %b%s%b\n" "$type" "${GREEN}" "$d_size" "${RESET}")
    
    # 3. Check for eMMC
    elif [ -b /dev/mmcblk0 ]; then
        mmc_blocks=$(cat /sys/block/mmcblk0/size)
        # Convert 512-byte blocks to MB
        mmc_mb=$((mmc_blocks * 512 / 1024 / 1024))
        
        if [ "$mmc_mb" -ge 1000 ]; then
            mmc_gb=$(( (mmc_mb + 512) / 1024 ))
            storage_info=$(printf "   Physical eMMC: %b%d GB%b\n" "${GREEN}" "$mmc_gb" "${RESET}")
        else
            storage_info=$(printf "   Physical eMMC: %b%d MB%b\n" "${GREEN}" "$mmc_mb" "${RESET}")
        fi

    # 4. Fallback to MTD 
    elif [ -f /proc/mtd ]; then
        max_hex=$(awk 'NR>1 {print $2}' /proc/mtd | sort -r | head -n 1)
        
        if [ -n "$max_hex" ]; then
            # Convert Hex to Decimal bytes using shell printf
            flash_bytes=$(printf "%d" "0x$max_hex")
            flash_mb=$((flash_bytes / 1024 / 1024))
            
            if [ "$flash_mb" -ge 1000 ]; then
                flash_gb=$(( (flash_mb + 512) / 1024 ))
                storage_info=$(printf "   Physical NAND: %b%d GB%b\n" "${GREEN}" "$flash_gb" "${RESET}")
            else
                storage_info=$(printf "   Physical NAND: %b%d MB%b\n" "${GREEN}" "$flash_mb" "${RESET}")
            fi
        fi
    else
        storage_info=$(printf "   Physical Storage: %bUnknown%b\n" "${RED}" "${RESET}")
    fi

    refresh_counter=0

    while true; do
        if [ "$page" -eq 1 ]; then 
            printf '\033[H\033[J'
            printf '\033[?25l'
            if [ $((refresh_counter % 10)) -eq 0 ]; then
                fsdata=$(df -Ph | head -1 | sed 's/^/   /')
                fstmp=$(df -Ph | grep -E "^/dev/" | grep -v "tmpfs" | head -3 | sed 's/^/   /')
            fi
            else 
                clear
        fi
        print_centered_header "Hardware Information"
        printf " ──────────────────────────────────────────────────────────────────────────────\n"
        case $page in
            1)  
                printf " %b%bPage 1 of $total_pages: System Overview%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                if [ "$reveal_ids" -eq 1 ]; then
                    reveal_label="${YELLOW}[*] Hide${RESET}"; mac_disp="$mac"; sn_disp="$sn"
                else
                    reveal_label="${YELLOW}[*] Reveal${RESET}"; mac_disp=$(mask_mac "$mac"); sn_disp=$(mask_keep_tail "$sn")
                fi
                printf " %b%-38s%b%b\n" "${CYAN}" "System Information:" "${RESET}" "$reveal_label"

                [ -n "$hostname" ] && printf "   Model:    %b%-26s%b" "${GREEN}" "$hostname" "${RESET}"
                [ -n "$mac" ] && printf "Device MAC: %b%s%b" "${GREEN}" "$mac_disp" "${RESET}"
                printf "\n"

                if [ -f /etc/glversion ]; then
                    firmware=$(cat /etc/glversion 2>/dev/null)
                    [ -n "$firmware" ] && printf "   Firmware: %b%-26s%b" "${GREEN}" "$firmware" "${RESET}"
                fi

                [ -n "$sn" ] && printf "Device SN:  %b%s%b" "${GREEN}" "$sn_disp" "${RESET}"
                printf "\n"

                if [ -f /proc/uptime ]; then
                    read -r uptime_seconds rest < /proc/uptime
                    uptime_raw=${uptime_seconds%.*}
                    up_d=$((uptime_raw / 86400))
                    up_h=$(( (uptime_raw % 86400) / 3600 ))
                    up_m=$(( (uptime_raw % 3600) / 60 ))
                    up_s=$(( uptime_raw % 60 ))
                    time_string=$(printf "%02d:%02d:%02d" "$up_h" "$up_m" "$up_s")  
                    printf "   Uptime:   %b%d Day(s), %-13s%b" "${GREEN}" "$up_d" "$time_string" "${RESET}"
                else
                    printf "   Uptime:   %b%-23s%b" "${YELLOW}" "Unknown" "${RESET}"
                fi

                ddns_disp="$ddns"; [ "$reveal_ids" -ne 1 ] && ddns_disp=$(mask_keep_tail "$ddns")
                [ ! -z "$ddns" ] && printf "   Device ID:  %b%s%b" "${GREEN}" "$ddns_disp" "${RESET}"
                
                printf "\n\n"
                printf " %b\n" "${CYAN}CPU:${RESET}"
                printf "   Vendor/Model:    %b%s%b\n" "${GREEN}" "$cpu_vendor_model" "${RESET}"
                [ -n "$cpu_cores" ] && printf "   Cores:           %b%-16s%b" "${GREEN}" "$cpu_cores" "${RESET}"
                [ -n "$cpu_freq" ] && printf "   Frequency:  %b%.0f MHz%b" "${GREEN}" "$cpu_freq" "${RESET}"
                printf "\n"
                
                cpu_temp=$(get_cpu_temp)
                if [ "$cpu_temp" = "unknown" ]; then
                    printf "   CPU Temperature: %b%-17s%b\033[K" "${YELLOW}" "Unknown" "${RESET}"
                else
                    printf "   CPU Temperature: %b%-17s%b\033[K" "${GREEN}" "$cpu_temp°C" "${RESET}"
                fi
                
                fan_speed=$(get_fan_speed)
                [ -n "$fan_speed" ] && printf "   Fan Speed:  %b%s RPM%b\033[K" "${GREEN}" "$fan_speed" "${RESET}"
                printf "\n"

                read -r cpu_label user nice system idle iowait irq softirq rest < /proc/stat
                total=$((user + nice + system + idle + iowait + irq + softirq))
                diff_total=$((total - prev_total))
                diff_idle=$((idle - prev_idle))
                if [ "$diff_total" -gt 0 ]; then
                    cpu_percentage=$(( (diff_total - diff_idle) * 100 / diff_total ))
                fi
                prev_total=$total
                prev_idle=$idle
                [ -n "$cpu_percentage" ] && printf "   CPU Usage:       %b%-5s%b %-10s" "${GREEN}" "$cpu_percentage%" "${RESET}" ""
                
                read -r load_1 load_5 load_15 rest < /proc/loadavg
                cpu_load="${load_1}, ${load_5}, ${load_15}"
                [ -n "$cpu_load" ] && printf "   Load Avg:   %b%s%b\033[K" "${GREEN}" "$cpu_load" "${RESET}"
                printf "\n\n"

                printf " %b\n" "${CYAN}Memory:${RESET}"
                
                get_mem_stats
                mem_display=$(
                printf "   Soldered RAM:    %b%-9s %-6s%b" "${GREEN}" "$mem_rounded MB" "" "${RESET}"
                printf "   Free RAM:   %b%s%b\n" "${GREEN}" "$mem_free MB" "${RESET}"
                printf "   Total Usable:    %b%-9s %-6s%b" "${GREEN}" "$mem_total MB" "" "${RESET}"
                printf "   Used RAM:   %b%d MB (%d.%d%%)%b\n" "${GREEN}" "$mem_used" "$mem_p_whole" "$mem_p_decimal" "${RESET}"
                printf "   Available RAM:   %b%-9s %-6s%b" "${GREEN}" "$mem_avail MB" "" "${RESET}"
                printf "   Buff/Cache: %b%s MB%b\033[K\n" "${GREEN}" "$mem_buffcache" "${RESET}"
                )
                printf "%b\n" "$mem_display\n"

                printf " %b\n" "${CYAN}Storage:${RESET}"
                printf "$storage_info\n"
                
                printf "\n %b\n" "${CYAN}Filesystem Usage:${RESET}"
                printf "%b\n%b\n" "$fsdata" "$fstmp"
                ;;
                
            2)
                printf " %b%bPage 2 of $total_pages: Hardware Crypto Acceleration%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                # Capabilities come from CPU HWCAP feature flags, NOT /proc/crypto.
                # OpenSSL/OpenVPN (userspace) and kernel/Go WireGuard both pick their
                # accelerated paths from these flags; /proc/crypto is the wrong layer.
                feat_line=$(grep -m1 -iE '^(features|flags)[[:space:]]*:' /proc/cpuinfo 2>/dev/null)
                has_aes=0; has_pmull=0; has_sha1=0; has_sha2=0; has_sha512=0; has_simd=0
                case " $feat_line " in *" aes "*)    has_aes=1    ;; esac
                case " $feat_line " in *" pmull "*)  has_pmull=1  ;; esac
                case " $feat_line " in *" sha1 "*)   has_sha1=1   ;; esac
                case " $feat_line " in *" sha2 "*)   has_sha2=1   ;; esac
                case " $feat_line " in *" sha512 "*) has_sha512=1 ;; esac
                case " $feat_line " in *" asimd "*|*" neon "*) has_simd=1 ;; esac

                cpu_features=$(printf '%s\n' "$feat_line" | grep -oE 'aes|pmull|sha1|sha2|sha512|sha3|asimd|neon' | tr '\n' ' ')
                [ -n "$cpu_features" ] && printf " CPU Features: %b%s%b\n\n" "${GREEN}" "${cpu_features% }" "${RESET}"

                # Per-algorithm value color/text (AES-GCM auth = GHASH needs PMULL;
                # ChaCha20-Poly1305 needs SIMD/NEON).
                aes_c=$RED; aes_t=NO; [ "$has_aes" -eq 1 ]    && { aes_c=$GREEN; aes_t=YES; }
                gcm_c=$RED; gcm_t=NO; [ "$has_pmull" -eq 1 ]  && { gcm_c=$GREEN; gcm_t=YES; }
                cha_c=$RED; cha_t=NO; [ "$has_simd" -eq 1 ]   && { cha_c=$GREEN; cha_t=YES; }
                s1_c=$RED;  s1_t=NO;  [ "$has_sha1" -eq 1 ]   && { s1_c=$GREEN;  s1_t=YES; }
                s2_c=$RED;  s2_t=NO;  [ "$has_sha2" -eq 1 ]   && { s2_c=$GREEN;  s2_t=YES; }
                s5_c=$RED;  s5_t=NO;  [ "$has_sha512" -eq 1 ] && { s5_c=$GREEN;  s5_t=YES; }

                printf " %b\n" "${CYAN}Hardware-Accelerated Algorithms:${RESET}"
                printf "   %-43s%b%s%b\n" "AES (OpenVPN, IPsec, TLS):"                "$aes_c" "$aes_t" "${RESET}"
                printf "   %-43s%b%s%b\n" "AES-GCM / GHASH (OpenVPN AEAD):"           "$gcm_c" "$gcm_t" "${RESET}"
                printf "   %-43s%b%s%b\n" "ChaCha20-Poly1305 (WireGuard, Tailscale):" "$cha_c" "$cha_t" "${RESET}"
                printf "   %-43s%b%s%b\n" "SHA-1 (HMAC, legacy TLS):"                 "$s1_c"  "$s1_t"  "${RESET}"
                printf "   %-43s%b%s%b\n" "SHA-256 (TLS, HMAC, firmware integrity):"  "$s2_c"  "$s2_t"  "${RESET}"
                printf "   %-43s%b%s%b\n" "SHA-512 (TLS/HMAC):"                       "$s5_c"  "$s5_t"  "${RESET}"

                # VPN verdict: FULL / LIMITED / NONE.
                if [ "$has_simd" -eq 1 ]; then wg_v="${GREEN}FULL${RESET}"; else wg_v="${RED}NONE${RESET}"; fi
                if   [ "$has_aes" -eq 1 ] && [ "$has_pmull" -eq 1 ]; then ovpn_v="${GREEN}FULL${RESET}"
                elif [ "$has_aes" -eq 1 ];                          then ovpn_v="${YELLOW}LIMITED${RESET}"
                else                                                     ovpn_v="${RED}NONE${RESET}"
                fi

                printf "\n %b\n" "${CYAN}VPN Performance Assessment:${RESET}"
                printf "   %-43s%b\n" "WireGuard / Tailscale:" "$wg_v"
                printf "   %-43s%b\n" "OpenVPN:"               "$ovpn_v"
                ;;
                
            3)
                printf " %b%bPage 3 of $total_pages: Network Interfaces%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                hwnet_collect </dev/null
                hwnet_render </dev/null
                ;;
            4)
                printf " %b%bPage 4 of $total_pages: Wireless Interfaces%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                radio_count=0
                # Use UCI as the source of truth for the Radio list
                for radio in $(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1); do
                    radio_count=$((radio_count + 1))
                    
                    # 1. Configuration from UCI
                    htmode=$(uci -q get wireless.${radio}.htmode)
                    band=$(uci -q get wireless.${radio}.band)
                    
                    # 2. Map Radio to Interface (ra0, rai0, etc.)
                    iface=""
                    for iface_sec in $(uci show wireless | grep "=wifi-iface" | cut -d. -f2 | cut -d= -f1); do
                        if [ "$(uci -q get wireless.${iface_sec}.device)" = "$radio" ]; then
                            iface=$(uci -q get wireless.${iface_sec}.ifname)
                            break
                        fi
                    done

                    # 3. Real-time Channel Extraction (The Fix)
                    current_chan="N/A"
                    if [ -n "$iface" ] && command -v iwinfo >/dev/null 2>&1; then
                        # This sed regex finds the word 'Channel' and grabs the number following it
                        current_chan=$(iwinfo "$iface" info 2>/dev/null | sed -n 's/.*Channel: \([0-9]*\).*/\1/p')
                    fi
                    
                    # Fallback to UCI config if live data is missing
                    if [ -z "$current_chan" ]; then
                        current_chan=$(uci -q get wireless.${radio}.channel)
                    fi

                    # 4. MIMO from the driver's *configured* antenna chainmask
                    #    (popcount of TX/RX): 0x3=2x2, 0x7=3x3, 0xf=4x4. This is
                    #    the operating config, not the chip's max ("Available").
                    #    N/A when the driver can't report it.
                    mimo="N/A"
                    if [ -n "$iface" ] && command -v iw >/dev/null 2>&1; then
                        phy=$(cat "/sys/class/net/$iface/phy80211/name" 2>/dev/null)
                        if [ -n "$phy" ]; then
                            ant=$(iw phy "$phy" info 2>/dev/null | grep -i 'Configured Antennas')
                            tx=$(printf '%s' "$ant" | sed -n 's/.*TX \(0x[0-9a-fA-F]*\).*/\1/p')
                            rx=$(printf '%s' "$ant" | sed -n 's/.*RX \(0x[0-9a-fA-F]*\).*/\1/p')
                            txn=$(popcount_hex "$tx"); rxn=$(popcount_hex "$rx")
                            [ "$txn" -gt 0 ] && [ "$rxn" -gt 0 ] && mimo="${txn}x${rxn}"
                        fi
                    fi

                    # 5. Band Display
                    case "$band" in
                        2g) band="2.4GHz" ;;
                        5g) band="5GHz" ;;
                        6g) band="6GHz" ;;
                    esac

                    # 6. Supported standards + Wi-Fi generation (band-aware chip
                    #    capability). The generation rides the Band line in parens;
                    #    the 802.11 letters get their own Protocol line below it.
                    proto="N/A"; wgen=""
                    if [ -n "$iface" ] && command -v iw >/dev/null 2>&1; then
                        wphy=$(cat "/sys/class/net/$iface/phy80211/name" 2>/dev/null)
                        if [ -n "$wphy" ]; then
                            wp=$(wifi_protocol "$wphy" "$band")
                            proto=${wp%|*}; wgen=${wp#*|}
                        fi
                    fi

                    printf " %bRadio %d: %s%b\n" "${CYAN}" "$radio_count" "$radio" "${RESET}"
                    printf "   Interface: %b%s%b\n" "${GREEN}" "${iface:-N/A}" "${RESET}"
                    if [ -n "$wgen" ]; then
                        printf "   Band:      %b%s%b  (%s)\n" "${GREEN}" "$band" "${RESET}" "$wgen"
                    else
                        printf "   Band:      %b%s%b\n" "${GREEN}" "$band" "${RESET}"
                    fi
                    printf "   Protocol:  %b%s%b\n" "${GREEN}" "$proto" "${RESET}"
                    printf "   HT Mode:   %b%s%b\n" "${GREEN}" "${htmode:-N/A}" "${RESET}"
                    printf "   MIMO:      %b%s%b\n" "${GREEN}" "$mimo" "${RESET}"
                    printf "   Channel:   %b%s%b\n" "${GREEN}" "${current_chan:-Auto}" "${RESET}"
                    printf "\n"
                done
                ;;
        esac
        
        printf " ──────────────────────────────────────────────────────────────────────────────\n"
        printf " [P] Previous   "
        i=1
        while [ $i -le $total_pages ]; do
            if [ $i -eq $page ]; then
                printf "%b[%d]%b " "${BOLD}" "$i" "${RESET}"
            else
                printf "%b[%d]%b " "${GREY}" "$i" "${RESET}"
            fi
            i=$((i + 1))
        done
        printf "  [N] Next   [0] Main menu   [?] Help  "
        
        if [ "$page" -eq 1 ]; then
            nav_choice=""
            read -t 1 -n 1 nav_choice
            refresh_counter=$((refresh_counter + 1))
            [ "$refresh_counter" -gt 1000 ] && refresh_counter=0
            printf '\033[?25h'
        else
            nav_choice=$(read_single_char)
        fi
        
        case "$nav_choice" in
            p|P|b|B) [ $page -gt 1 ] && page=$((page - 1)) && clear;;
            n|N) [ $page -lt $total_pages ] && page=$((page + 1)) && clear;;
            1|2|3|4)
                if [ "$page" -ne "$nav_choice" ]; then
                    page=$nav_choice
                    clear
                fi
                ;;
            '*') reveal_ids=$((1 - reveal_ids)); clear ;;
            \?|h|H|❓) show_hardware_help "$page"; clear ;;
            0) return ;;
        esac
    done
}

# -----------------------------
# AdGuardHome UI Updates Management
# -----------------------------
show_agh_ui_help() {
    show_paged "AdGuardHome UI Updates - Help" << 'HELPEOF'
AdGuardHome UI Updates - Quick Help

What it does
───────────────────────────────
This option controls whether AdGuardHome is allowed to automatically check for and 
download new versions of its web interface (UI) directly from the AdGuard servers.

Two modes:
• ENABLED  → AdGuardHome can update its own UI automatically when a new version is released
• DISABLED → UI updates are blocked (the --no-check-update flag is added)

Why would you want to disable UI updates?
─────────────────────────────────────────
On GL.iNet routers, the recommended approach is often to **disable automatic UI updates** because:

• GL.iNet provides their own pre-packaged, tested version of AdGuardHome
• Auto-updating the UI can sometimes cause compatibility issues with GL.iNet's custom firmware
• It may overwrite GL.iNet-specific patches or branding
• Manual updates through GL.iNet's firmware or the package manager are usually safer and better integrated

When should you enable UI updates?
──────────────────────────────────
• You are running a standalone/community-installed AdGuardHome (not the GL.iNet version)
• You want the very latest UI features and fixes as soon as they are released
• You are comfortable troubleshooting potential compatibility problems

Quick recommendation for most GL.iNet users:
• Keep UI Updates **DISABLED** (default safe choice on GL firmware)
• Only enable if you specifically need a newer UI feature and understand the risks

In this menu you can:
• Enable or disable UI Updates (adds/removes the --no-check-update flag).
• Enable or disable update persistence, so AdGuardHome survives firmware updates.

Note: Changing this setting restarts AdGuardHome automatically if already started. 
      Your filtering rules and stats are preserved.
HELPEOF
}

manage_agh_ui_updates() {
    while true; do
        clear
        print_centered_header "AdGuardHome UI Updates Management"

        if is_agh_running; then
            agh_pid=$(pidof AdGuardHome)
        else
            agh_pid=""
        fi

        printf " %b\n" "${CYAN}CURRENT STATUS${RESET}"
        if [ -z "$agh_pid" ]; then
            printf "   Running: %b\n" "$_S_OFF"
        else
            printf "   Running: %b (PID: %s)\n" "$_S_ON" "$agh_pid"
        fi

        if grep -q -- "--no-check-update" "$AGH_INIT"; then
            printf "   UI Updates: %bDISABLED%b\n" "${RED}" "${RESET}"
        else
            printf "   UI Updates: %bENABLED%b\n" "${GREEN}" "${RESET}"
        fi

        up_conf="/etc/sysupgrade.conf"
        updates_persist="0"

        if [ -s "$up_conf" ]; then
            updates_persist="1"
            for entry in "/usr/bin/AdGuardHome" "/etc/init.d/adguardhome" "/etc/AdGuardHome/config.yaml"; do
                if ! grep -qFx "$entry" "$up_conf" 2>/dev/null; then
                    updates_persist="0"
                    break
                fi
            done
        fi

        if [ "$updates_persist" -eq "1" ]; then
            printf "   Update Persistence: %bENABLED%b\n\n" "${GREEN}" "${RESET}"
        else
            printf "   Update Persistence: %bDISABLED%b\n\n" "${RED}" "${RESET}"
        fi
        
        # Adaptive labels (Rule 4): offer only the valid transition for each state.
        local ui_label ui_action persist_label
        if grep -q -- "--no-check-update" "$AGH_INIT"; then
            ui_label="Enable UI Updates"; ui_action="enable"
        else
            ui_label="Disable UI Updates"; ui_action="disable"
        fi
        if [ "$updates_persist" -eq 1 ]; then
            persist_label="Disable update persistence across firmware updates"
        else
            persist_label="Enable update persistence across firmware updates"
        fi

        printf "%s%s%s\n" "$N1" "$NSEP" "$ui_label"
        printf "%s%s%s\n" "$N2" "$NSEP" "$persist_label"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-2/0/?]: "
        read -r agh_choice
        printf "\n"

        case $agh_choice in
            1)
                agh_was_running=0; is_agh_running && agh_was_running=1
                if [ "$ui_action" = "enable" ]; then
                    if [ "$updates_persist" -eq 0 ]; then
                        print_warning "UI updates are currently set to not persist across firmware updates.\nEnabling UI updates may cause compatibility issues during firmware\nupdates due to legacy binaries being reinstalled. Consider enabling\nupdate persistence to avoid this problem."
                    else
                        print_info "UI updates are currently set to persist across firmware updates."
                        printf "\n"
                    fi
                    printf "Proceed with changes? [y/N]: "; read -r confirm
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    sed -i 's/--no-check-update[[:space:]]*//g' "$AGH_INIT"
                    agh_apply_and_restart "$agh_was_running" "" "" "UI updates enabled."
                else
                    printf "Disable UI updates? [y/N]: "; read -r confirm
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    sed -i '/procd_set_param command/ s/ \(-c\|--config\)/ --no-check-update \1/' "$AGH_INIT"
                    agh_apply_and_restart "$agh_was_running" "" "" "UI updates disabled."
                fi
                press_any_key
                ;;
            2)
                if [ "$updates_persist" -eq 1 ]; then
                    printf "Disable update persistence across firmware updates? [y/N]: "; read -r confirm ; printf "\n"
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    sed -i "/\/usr\/bin\/AdGuardHome/d" /etc/sysupgrade.conf
                    sed -i "/\/etc\/init.d\/adguardhome/d" /etc/sysupgrade.conf
                    sed -i "/\/etc\/AdGuardHome\/config.yaml/d" /etc/sysupgrade.conf
                    print_success "Update persistence disabled in $up_conf"
                else
                    printf "Enable update persistence across firmware updates? [y/N]: "; read -r confirm ; printf "\n"
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    [ ! -f "$up_conf" ] && touch "$up_conf"
                    for entry in "/usr/bin/AdGuardHome" "/etc/init.d/adguardhome" "/etc/AdGuardHome/config.yaml"; do
                        grep -qFx "$entry" "$up_conf" || echo "$entry" >> "$up_conf"
                    done
                    print_success "Update persistence enabled in $up_conf"
                fi
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_ui_help
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# AdGuardHome Storage Management
# -----------------------------
show_agh_storage_help() {
    show_paged "AdGuardHome Filter Space Limit - Help" << 'HELPEOF'
AdGuardHome Filter Space Limit - Quick Help

Why the limit exists
────────────────────
On 512MB RAM routers (MT3600BE, some newer GL models), GL.iNet creates a 10MB file 
and mounts it as /etc/AdGuardHome/data/filters. This caps filter cache space to 
prevent AdGuardHome from consuming too much RAM and crashing the router.

Removing this limit lets you use bigger blocklists (e.g. HaGeZi Pro++, multi-list setups), 
but significantly increases RAM usage when filters are loaded/updated.

Risks if you remove it without mitigation
─────────────────────────────────────────
• High RAM pressure → router slowdown, OOM killer, or crashes
• Especially bad with many clients, VPN, or heavy filtering

Strong recommendation
─────────────────────
Enable **zram swap** first (Advanced Settings → Zram Swap → Install & Enable).
Zram gives fast compressed swap in RAM, greatly reduces memory pressure,
and is safe for most GL.iNet 512MB devices. The Lists Manager also offers to
enable zram automatically when a selection would run memory high.

Only remove the limit after zram is active.

Re-enabling the limit
─────────────────────
If your installed lists are already larger than the cap, turning the limit back
on will warn you (space used vs. available) and ask you to confirm - lists that
don't fit silently stop loading, so remove some first or leave the limit off.
HELPEOF
}

# Remove the GL filter-space limit (the loop-mounted filters partition).
# Shared mechanical action used by both AdGuardHome Storage Management and the
# AdGuardHome Lists Manager so the two never diverge. Prints its own progress.
# Returns 0 on success, 1 if there was nothing to do or a step failed.
agh_remove_filter_limit() {
    local workdir; workdir=$(get_agh_workdir)
    [ -z "$workdir" ] && { print_error "Could not find AdGuardHome working directory"; return 1; }
    local fdir="$workdir/data/filters"

    # Assess both halves of the limit independently: the live mount and the init call.
    # A prior partial run can leave them inconsistent (call commented but still mounted),
    # which we must recover from - not bail on.
    local mounted=0; awk -v d="$fdir" '$2==d{f=1} END{exit !f}' /proc/mounts && mounted=1
    local call_active=0; grep -qE "^[[:space:]]*mount_filter_img[[:space:]]+" "$AGH_INIT" && call_active=1

    if [ "$mounted" -eq 0 ] && [ "$call_active" -eq 0 ]; then
        print_warning "Filter space limitation is already INACTIVE on the system."
        return 1
    fi

    local agh_pid=""
    if is_agh_running; then
        agh_pid=$(pidof AdGuardHome)
        $AGH_INIT stop >/dev/null 2>&1; sleep 2
    fi

    # Unmount, then VERIFY it actually released before we touch the init script - so a
    # busy mount can't leave us in the half-done state that reports false success.
    if [ "$mounted" -eq 1 ]; then
        local loop_dev; loop_dev=$(awk -v d="$fdir" '$2==d{print $1; exit}' /proc/mounts)
        umount "$fdir" 2>/dev/null || umount "$loop_dev" 2>/dev/null
        sleep 1
        # A lingering kernel/journal handle can keep a plain umount "busy" even with AGH
        # stopped; a lazy unmount detaches it safely (the partition is being discarded).
        if awk -v d="$fdir" '$2==d{f=1} END{exit !f}' /proc/mounts; then
            umount -l "$fdir" 2>/dev/null; sleep 1
        fi
        if awk -v d="$fdir" '$2==d{f=1} END{exit !f}' /proc/mounts; then
            [ -n "$agh_pid" ] && { $AGH_INIT start >/dev/null 2>&1; sleep 1; }
            print_error "Could not unmount the filter partition (still in use) - nothing changed. Try again."
            return 1
        fi
        print_success "Unmounted filter partition"
        [ -n "$loop_dev" ] && losetup -d "$loop_dev" 2>/dev/null
    fi

    [ -f "$workdir/data.img" ] && { rm -f "$workdir/data.img" && print_success "Removed data.img file"; }

    if [ "$call_active" -eq 1 ]; then
        sed -i "s|^\([[:space:]]*\)\(mount_filter_img[[:space:]]\)|\1# \2|" "$AGH_INIT"
        print_success "Disabled the mount in the init script"
    fi

    if [ -n "$agh_pid" ]; then
        $AGH_INIT start >/dev/null 2>&1; sleep 2
        is_agh_running && print_success "AdGuardHome restarted successfully" || print_error "AdGuardHome did not restart"
    fi
    print_success "Filter space limit removed!"
    return 0
}

manage_agh_storage() {
    while true; do
        clear
        print_centered_header "AdGuardHome Storage Management"

        AGH_WORKDIR=$(get_agh_workdir)
        if [ -z "$AGH_WORKDIR" ]; then
            print_error "Could not find AdGuardHome working directory"
            press_any_key
            return
        fi
        
        printf " %b\n" "${CYAN}STORAGE STATUS${RESET}"
        printf "   Working Directory: %b%s%b\n" "${GREEN}" "$AGH_WORKDIR" "${RESET}"

        sub_section_shown=0
         if [ -d "$AGH_WORKDIR/data" ]; then
            sub_section_shown=1
            printf "\n %b\n" "${CYAN}$AGH_WORKDIR/data Directory:${RESET}"
            df -Ph "$AGH_WORKDIR/data" 2>/dev/null | tail -1 | awk '{printf "   Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi

        if [ -d "$AGH_WORKDIR/data/filters" ]; then
            sub_section_shown=1
            printf "\n %b\n" "${CYAN}$AGH_WORKDIR/data/filters Directory:${RESET}"
            df -Ph "$AGH_WORKDIR/data/filters" 2>/dev/null | tail -1 | awk '{printf "   Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi

        [ "$sub_section_shown" -eq 1 ] && printf "\n"
        limit_active=0
        if grep -q "$AGH_WORKDIR/data/filters" /proc/mounts; then
            limit_active=1
            # Calculate actual size from the mount point
            current_limit=$(df -Pm "$AGH_WORKDIR/data/filters" | tail -1 | awk '{print $2}')
            printf "   Filter Space Limit: %bACTIVE (%sMB)%b\n" "${YELLOW}" "$current_limit" "${RESET}"
        else
            printf "   Filter Space Limit: %bINACTIVE%b\n" "${GREEN}" "${RESET}"
        fi
        
        printf "\n%s%sRemove Filter Space Limitation\n" "$N1" "$NSEP"
        printf "%s%sRe-enable Filter Space Limitation\n" "$N2" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-2/0/?]: "
        read -r storage_choice
        printf "\n"

        local exec_pattern="^[[:space:]]*mount_filter_img[[:space:]]+"
        local comment_pattern="^[[:space:]]*#[[:space:]]*mount_filter_img[[:space:]]+"
        
        case $storage_choice in
            1)
                if [ "$limit_active" -eq 0 ]; then
                    print_warning "Filter space limitation is already INACTIVE on the system."
                    press_any_key; continue
                fi

                if ! grep -qE "$exec_pattern" "$AGH_INIT"; then
                    print_error "Could not find a feature call to disable."
                    press_any_key; continue
                fi
                
                print_info "GL.iNet caps the AGH filter cache (~9MB loop partition) to protect RAM on ~512MB models."
                print_info "Removing it allows larger/more lists, but raises RAM use and can destabilize small-RAM routers."

                if ! swapon -s 2>/dev/null | grep -q zram; then
                    printf "\n"
                    print_warning "WARNING: Zram swap is NOT enabled!"
                    printf "\n"
                    print_info "It is strongly recommended to enable zram swap before adding aditional filter lists."
                fi
                
                printf "Remove the filter storage limit anyway? [y/N]: "
                read -r confirm
                printf "\n"
                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    print_info "Operation cancelled."
                    press_any_key
                    continue
                fi

                agh_remove_filter_limit
                cached_rules=""   # AGH re-loads filters -> Control Center must recount
                press_any_key
                ;;
            2)
                if [ "$limit_active" -eq 1 ]; then
                    print_warning "Filter space limitation is already ACTIVE."
                    press_any_key; continue
                fi
                
                if ! grep -q "mount_filter_img" "$AGH_INIT"; then
                    print_warning "Filter space limitation feature is not supported on this device/firmware."
                    press_any_key
                    continue
                fi

                if grep -qE "$exec_pattern" "$AGH_INIT"; then
                    print_warning "Filter space limitation is already enabled or not supported on this device/firmware."
                    press_any_key; continue
                fi

                if ! grep -qE "$comment_pattern" "$AGH_INIT"; then
                    print_error "Could not find a feature call to re-enable."
                    press_any_key; continue
                fi

                # Warn if the current filter lists won't fit once the cap is back - the ones
                # that don't fit will silently fail to load (effectively disabled). The cap
                # size comes from the (commented) mount_filter_img call: bs x count, ext4 ~90%.
                _mfi=$(grep -oE "mount_filter_img[[:space:]]+[0-9]+[A-Za-z]?[[:space:]]+[0-9]+" "$AGH_INIT" | head -1)
                _sz=$(echo "$_mfi" | awk '{print $2}'); _cnt=$(echo "$_mfi" | awk '{print $3}')
                _num=$(echo "$_sz" | grep -oE '[0-9]+'); _unit=$(echo "$_sz" | grep -oE '[A-Za-z]' | head -1)
                case "$_unit" in G|g) _mul=1048576 ;; K|k) _mul=1 ;; *) _mul=1024 ;; esac
                _cap_kb=0; [ -n "$_num" ] && [ -n "$_cnt" ] && _cap_kb=$(( _num * _mul * _cnt ))
                _usable_kb=$(( _cap_kb * 9 / 10 ))
                _use_kb=$(du -sk "$AGH_WORKDIR/data/filters" 2>/dev/null | awk '{print $1}')
                case "$_use_kb" in ''|*[!0-9]*) _use_kb=0 ;; esac
                if [ "$_cap_kb" -gt 0 ] && [ "$_use_kb" -gt "$_usable_kb" ]; then
                    print_warning "Your filter lists use ~$(( _use_kb / 1024 ))MB, but this limit only holds ~$(( _usable_kb / 1024 ))MB."
                    print_info "Lists that don't fit won't load - remove some, or leave the limit off for full space."
                    printf "Re-enable the filter storage limit anyway? [y/N]: "; read -r _reyn
                    printf "\n"
                    if [ "$_reyn" != "y" ] && [ "$_reyn" != "Y" ]; then
                        print_info "Operation cancelled."; press_any_key; continue
                    fi
                fi

                if is_agh_running; then
                    agh_pid=$(pidof AdGuardHome)
                    $AGH_INIT stop >/dev/null 2>&1; sleep 1
                else
                    agh_pid=""
                fi
                
                sed -i "s|^\([[:space:]]*\)#[[:space:]]*\(mount_filter_img[[:space:]]\)|\1\2|" "$AGH_INIT"
                print_success "Re-enabled execution call in init script"
                
                if [ -n "$agh_pid" ]; then
                    $AGH_INIT start >/dev/null 2>&1; sleep 2
                    if is_agh_running; then
                        print_success "AdGuardHome restarted successfully"
                        print_success "Filter space limit re-enabled!"
                    else
                        print_error "Failed to restart AdGuardHome"
                    fi
                fi
                cached_rules=""   # AGH re-loads filters -> Control Center must recount
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_storage_help
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# AdGuardHome Lists Management
# -----------------------------
show_agh_lists_help() {
    show_paged "AdGuardHome Lists Manager - Help" << 'HELPEOF'
AdGuardHome Lists Manager - Quick Help

What it does
────────────────────────────────────────────────────────────────────────
Pick which DNS filter lists AdGuardHome installs and enables. Each list has
two toggles:

  • Install  - the list is present in AdGuardHome's config
  • Enable   - AdGuardHome actually loads and uses it

Typing a list's number cycles it through the sensible steps for its current
state, and the Planned Action column shows exactly what will happen:

  • a Missing list    ->  Install + Enable  ->  Install (leave off)  ->  no change
  • an Active list    ->  Remove  ->  Disable  ->  no change
  • an Inactive list  ->  Enable  ->  Remove  ->  no change

Nothing is applied until you press [C] Confirm and approve the summary.

The screen
────────────────────────────────────────────────────────────────────────
  • Memory Impact (top): a bar of the rules that will actually load, against
    this box's RAM (plus zram swap if enabled). Green is comfortable; it turns
    (high)/(critical) as the enabled lists approach what the box can hold.
  • Size: each list's rule count - a real count once downloaded, or a "~"
    estimate before then.
  • Sections: Recommended (a curated, safe default set), General, Security,
    Allowlist, and any of "Your Other Lists" already in the config.

Staying safe on small boxes
────────────────────────────────────────────────────────────────────────
Before applying a heavy set, the manager can:

  • offer to enable zram swap (compressed RAM headroom) when memory would run
    high on a low-RAM router; and
  • warn - on models with a filter-storage cap - when the selection won't fit,
    offering to remove the cap (also under Advanced Settings).

After applying, it waits for the newly-enabled lists to download - showing
progress - so the screen doesn't look hung and the Memory Impact meter is
accurate on return. Lists that finish are confirmed; any that could not fit
(storage full) are reported and removed so nothing is left half-installed; any
still downloading are noted as in-progress (AdGuardHome keeps retrying).
HELPEOF
}

# ============================================================
# AdGuardHome Lists Manager — helpers
# ============================================================

# Echo a list's status by name in the config: 0=missing 1=inactive 2=active
agh_list_status() {
    local sv
    sv=$(awk -v n="$1" '
        BEGIN { RS = "[[:space:]]*- "; FS = "\n" }
        index($0, "name: " n) || index($0, "name: \"" n "\"") {
            if ($0 ~ "enabled: true")  { print "true";  exit }
            if ($0 ~ "enabled: false") { print "false"; exit }
        }' "$2")
    case "$sv" in true) echo 2 ;; false) echo 1 ;; *) echo 0 ;; esac
}

# Echo the numeric id of an installed list by name (empty if not found).
agh_list_id() {
    awk -v n="$1" '
        BEGIN { RS = "[[:space:]]*- "; FS = "\n" }
        index($0, "name: " n) || index($0, "name: \"" n "\"") {
            for (i=1;i<=NF;i++) if ($i ~ /id:/) { x=$i; sub(/.*id:[[:space:]]*/,"",x); gsub(/[^0-9]/,"",x); if (x!="") { print x; exit } }
        }' "$2"
}

# Echo a list's real rule count (wc of AGH's local filter file) or a fallback.
#   $1 name  $2 config  $3 workdir  $4 fallback
agh_list_rulecount() {
    local id f
    id=$(agh_list_id "$1" "$2")
    f="$3/data/filters/$id.txt"
    if [ -n "$id" ] && [ -n "$3" ] && [ -f "$f" ]; then
        grep -vc '^!\|^#\|^[[:space:]]*$' "$f"
    else
        echo "${4:-0}"
    fi
}

# Format a rule count: 1234567 -> 1.2M, 12345 -> 12.3K, else the number.
agh_fmt_rules() {
    local n="${1:-0}"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$n" -ge 1000000 ]; then awk -v x="$n" 'BEGIN{printf "%.1fM", x/1000000}'
    elif [ "$n" -ge 1000 ]; then awk -v x="$n" 'BEGIN{printf "%.1fK", x/1000}'
    else printf "%s" "$n"; fi
}

# Derived planned-action text (mirrors the Package Manager's get_action_text).
#   $1 t_i  $2 t_e  $3 o_i  $4 o_e   (target/original install & enable)
get_agh_action_text() {
    local ti=$1 te=$2 oi=$3 oe=$4
    if [ "$ti" = "$oi" ] && [ "$te" = "$oe" ]; then echo "No Change"; return; fi
    if [ "$oi" = 0 ] && [ "$ti" = 1 ]; then
        [ "$te" = 1 ] && echo "> Install + Enable" || echo "> Install"; return
    fi
    if [ "$oi" = 1 ] && [ "$ti" = 1 ] && [ "$te" != "$oe" ]; then
        [ "$te" = 1 ] && echo "> Enable" || echo "> Disable"; return
    fi
    if [ "$oi" = 1 ] && [ "$ti" = 0 ]; then echo "> Remove"; return; fi
    echo "No Change"
}

# Delete a list's 4-line block from the config by name.  Matches the name
# literally (awk index) so parentheses/+/. in list names don't break it.
agh_delete_block() {
    local cfg="$2" nl sd
    nl=$(awk -v n="$1" 'index($0,"name: " n) || index($0,"name: \"" n "\"") {print NR; exit}' "$cfg")
    [ -z "$nl" ] && return 0
    sd=$(awk -v L="$nl" 'NR<=L && /enabled:/{last=NR} END{print last+0}' "$cfg")
    [ "$sd" -gt 0 ] 2>/dev/null || return 0
    sed -i "${sd},$((sd + 3))d" "$cfg"
}

# Flip the enabled: flag of a list's block by name.  $2 = true|false, $3 = config
# Matches the name literally (awk index) for parens/+/. safety.
agh_set_enabled() {
    local cfg="$3" val="$2" nl el
    nl=$(awk -v n="$1" 'index($0,"name: " n) || index($0,"name: \"" n "\"") {print NR; exit}' "$cfg")
    [ -z "$nl" ] && return 0
    el=$(awk -v L="$nl" 'NR<=L && /enabled:/{last=NR} END{print last+0}' "$cfg")
    [ "$el" -gt 0 ] 2>/dev/null || return 0
    sed -i "${el}s/enabled: .*/enabled: $val/" "$cfg"
}

# Append a new enabled list block to the correct section.
#   $1 name  $2 type(Blocklist|Allowlist)  $3 url  $4 uniq-counter  $5 config
agh_add_block() {
    local n="$1" t="$2" u="$3" count="$4" cfg="$5" ts th nb
    # Stable id derived from the URL, so re-adding the same list reuses its file
    # instead of orphaning a new one (AGH never reclaims orphaned filter files, and
    # a full capped partition then fails downloads with ENOSPC). Fallback: timestamp.
    ts=$(printf '%s' "$u" | md5sum 2>/dev/null | cut -c1-8)
    ts=$(printf '%d' "0x$ts" 2>/dev/null)
    case "$ts" in ''|0|*[!0-9]*) ts="$(( $(date +%s) - 1769040000 ))$count" ;; esac
    nb="- enabled: true\\
url: $u\\
name: \"$n\"\\
id: $ts"
    th="filters:"; [ "$t" = "Allowlist" ] && th="whitelist_filters:"
    sed -i "s/^$th \[\]/$th/" "$cfg"
    sed -i "/^$th/a $nb" "$cfg"
    sed -i "s/^- enabled:/  - enabled:/" "$cfg"
    sed -i "s/^url:/    url:/" "$cfg"
    sed -i "s/^name:/    name:/" "$cfg"
    sed -i "s/^id:/    id:/" "$cfg"
}

# Sum of rules for lists that will be ACTIVE after apply (t_i=1 & t_e=1).
# Sum of rules AGH will actually LOAD: active lists that have a real file (est=0),
# plus lists being newly enabled (o_e=0 -> will download).  An already-enabled list
# with no file (est=1 & o_e=1 = a failed/ENOSPC download) is NOT loaded, so excluded.
agh_proj_active_rules() { awk -F'|' '{ if($7==1 && $8==1 && ($11==0 || $6==0)) s+=$9 } END{print s+0}' "$1"; }

# Total memory capacity in MB, inclusive of zram swap.
agh_capacity_mb() {
    local mt st
    mt=$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo 2>/dev/null); : "${mt:=0}"
    st=$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo 2>/dev/null); : "${st:=0}"
    echo "$mt $st $((mt + st))"
}

# Filled-block count (0..20) for the projected active rules given capacity MB.
agh_mem_fill() {
    local active="$1" cap_mb="$2" ceil filled
    ceil=$(( (cap_mb - 128) * 1000 )); [ "$ceil" -lt 1000 ] && ceil=1000
    filled=$(( active * 20 / ceil ))
    [ "$filled" -gt 20 ] && filled=20; [ "$filled" -lt 0 ] && filled=0
    echo "$filled"
}

# Print the Memory Health meter line for the current target selection ($1=LISTS_DATA).
agh_memory_meter() {
    local active mt st cap filled i bar swaptxt status
    active=$(agh_proj_active_rules "$1")
    read -r mt st cap <<EOF
$(agh_capacity_mb)
EOF
    filled=$(agh_mem_fill "$active" "$cap")
    bar=""; i=1
    while [ "$i" -le 20 ]; do
        if [ "$i" -le "$filled" ]; then
            if   [ "$i" -le 14 ]; then bar="${bar}${GREEN}█${RESET}"
            elif [ "$i" -le 18 ]; then bar="${bar}${YELLOW}█${RESET}"
            else                       bar="${bar}${RED}█${RESET}"; fi
        else bar="${bar}${GREY}░${RESET}"; fi
        i=$((i + 1))
    done
    status=""
    if   [ "$filled" -gt 18 ]; then status="  ${RED}(critical)${RESET}"
    elif [ "$filled" -gt 14 ]; then status="  ${YELLOW}(high)${RESET}"; fi
    swaptxt=""; [ "$st" -gt 0 ] && swaptxt=" + ${st}MB zram"
    printf "%b\n" " ${CYAN}Memory Impact${RESET}   [${bar}]   $(agh_fmt_rules "$active") rules · ${mt}MB RAM${swaptxt}${status}"
}

# Prevention guard rails before applying.  $1 = LISTS_DATA.  Reuses the System
# Tweaks zram + filter-limit actions so behavior never diverges.
agh_lists_guard_rails() {
    local data="$1" active mt st cap filled workdir free_kb add_kb
    _agh_storage_over=0   # global: set if the capped partition stays too small -> verify downloads after apply
    active=$(agh_proj_active_rules "$data")
    read -r mt st cap <<EOF
$(agh_capacity_mb)
EOF
    filled=$(agh_mem_fill "$active" "$cap")

    # zram: projected memory in the yellow/red zone and zram not active
    if [ "$filled" -gt 14 ] && ! swapon -s 2>/dev/null | grep -q zram; then
        printf "\n"
        if [ "$filled" -gt 18 ]; then
            print_warning "Enabling these lists (~$(agh_fmt_rules "$active") rules) puts memory in the CRITICAL zone on ${mt}MB RAM."
        else
            print_warning "Enabling these lists (~$(agh_fmt_rules "$active") rules) puts memory in the HIGH zone on ${mt}MB RAM."
        fi
        print_info "zram swap adds compressed headroom and is strongly recommended before loading them."
        printf "Enable zram swap now? [Y/n]: "; read -r _zr
        if [ "$_zr" != "n" ] && [ "$_zr" != "N" ]; then
            printf "\n"
            zram_install_enable
            print_info "Manage this later in AdGuardHome -> Advanced Settings -> Zram Swap."
        fi
    fi

    # filter storage limit: on a capped partition, warn only if the post-apply
    # footprint of ALL installed lists (t_i=1) exceeds the partition CAPACITY.
    # Comparing to capacity (not current free) avoids a false warning when the
    # same lists are re-added and their old files still linger on disk.
    workdir=$(get_agh_workdir)
    if [ -n "$workdir" ] && grep -q "$workdir/data/filters" /proc/mounts; then
        cap_kb=$(df -Pk "$workdir/data/filters" 2>/dev/null | tail -1 | awk '{print $2}')
        # Only ENABLED lists download to disk (AGH never fetches disabled ones), so
        # project active lists (t_i=1 & t_e=1) - matches the Memory Impact meter.
        proj_kb=$(awk -F'|' '{ if($7==1 && $8==1) s+=$9 } END{ printf "%d", (s*25)/1024 }' "$data")
        case "$cap_kb" in ''|*[!0-9]*) cap_kb=0 ;; esac
        if [ "$cap_kb" -gt 0 ] && [ "$proj_kb" -gt "$cap_kb" ]; then
            _agh_storage_over=1
            printf "\n"
            print_warning "The selected lists (~$((proj_kb/1024))MB) exceed the ~$((cap_kb/1024))MB filter storage limit."
            print_info "Removing the filter space limit lets them download."
            printf "Remove the filter storage limit now? [y/N]: "; read -r _sl
            if [ "$_sl" = "y" ] || [ "$_sl" = "Y" ]; then
                printf "\n"
                agh_remove_filter_limit && _agh_storage_over=0
                print_info "Manage this later in AdGuardHome -> Advanced Settings -> Filter Storage Space Limit."
            fi
        fi
    fi
}

# Remove downloaded filter files whose id is no longer referenced in the config.
# AGH leaves orphaned <id>.txt behind when a list is removed, which keeps the
# capped filter partition full and inflates the cached rule count. Run with AGH
# stopped; a wrongly-removed file is re-fetched on the next update, so it is safe.
agh_clean_orphan_filters() {
    local cfg="$1" wd="$2" f id
    { [ -z "$wd" ] || [ ! -d "$wd/data/filters" ]; } && return 0
    for f in "$wd"/data/filters/*.txt; do
        [ -f "$f" ] || continue
        id=$(basename "$f" .txt)
        case "$id" in ''|*[!0-9]*) continue ;; esac
        grep -qE "^[[:space:]]*id:[[:space:]]*${id}[[:space:]]*$" "$cfg" 2>/dev/null || rm -f "$f"
    done
}

manage_agh_lists() {
    # Curated, sectioned roster.  Fields: section|name|type|approx_rules|url
    # Recommended => ★ default Install+Enable.  AdGuard-catalog lists use AdGuard's
    # HostlistsRegistry mirror; Phantasm lists use their GitHub raw URLs.
    AGH_ROSTER="Recommended|Phantasm22's Blocklist|Blocklist|50|https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/blocklist.txt
Recommended|HaGeZi's Pro++ Blocklist|Blocklist|250000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_51.txt
Recommended|Malicious URL Blocklist (URLHaus)|Blocklist|3000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt
Recommended|Phishing URL Blocklist (PhishTank and OpenPhish)|Blocklist|30000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_30.txt
Recommended|Phantasm22's CDN Allow List|Allowlist|50|https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/allowlist.txt
Recommended|Phantasm22's Apps and User Flow Allow List|Allowlist|50|https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/allowlist2.txt
General|OISD Blocklist Small|Blocklist|50000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_5.txt
General|OISD Blocklist Big|Blocklist|250000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_27.txt
General|HaGeZi's Normal Blocklist|Blocklist|120000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_34.txt
General|HaGeZi's Pro Blocklist|Blocklist|180000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_48.txt
General|HaGeZi's Ultimate Blocklist|Blocklist|275000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_49.txt
General|Steven Black's List|Blocklist|130000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_33.txt
General|AdGuard DNS filter|Blocklist|60000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
General|1Hosts (Lite)|Blocklist|70000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt
General|Peter Lowe's Blocklist|Blocklist|3500|https://adguardteam.github.io/HostlistsRegistry/assets/filter_3.txt
General|Dan Pollock's List|Blocklist|15000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_4.txt
General|AWAvenue Ads Rule|Blocklist|30000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_53.txt
Security|Phishing Army|Blocklist|15000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_18.txt
Security|NoCoin Filter List|Blocklist|5000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_8.txt
Security|HaGeZi's Badware Hoster Blocklist|Blocklist|2000|https://adguardteam.github.io/HostlistsRegistry/assets/filter_55.txt
Security|HaGeZi's DNS Rebind Protection|Blocklist|200|https://adguardteam.github.io/HostlistsRegistry/assets/filter_71.txt
Allowlist|HaGeZi's Allowlist Referral|Allowlist|500|https://adguardteam.github.io/HostlistsRegistry/assets/filter_45.txt"

    local RULE; RULE=$(printf '─%.0s' $(seq 1 106))
    local PAGE_SIZE=12

    # Build LISTS_DATA (idx|section|name|type|o_i|o_e|t_i|t_e|rules|url|est).
    # Spinner while filter files are counted (can take ~2s on MIPS).
    _agh_build_lists() {
        local workdir idx r_sec r_name r_type r_est r_url stat oi oe ti te rc est cbase c_type c_name _id cest
        workdir=$(get_agh_workdir)
        : > "$LISTS_DATA"
        idx=1
        while IFS='|' read -r r_sec r_name r_type r_est r_url; do
            [ -z "$r_name" ] && continue
            stat=$(agh_list_status "$r_name" "$AGH_CONFIG")
            oi=0; oe=0
            case "$stat" in 1) oi=1; oe=0 ;; 2) oi=1; oe=1 ;; esac
            if [ "$r_sec" = "Recommended" ]; then ti=1; te=1; else ti=$oi; te=$oe; fi
            # est=0 only when a real downloaded file exists; a list enabled in config
            # but with no file (never fetched, or a failed ENOSPC download) is est=1
            # (shown "~" and excluded from the loaded-memory meter).
            _id=$(agh_list_id "$r_name" "$AGH_CONFIG")
            if [ -n "$_id" ] && [ -s "$workdir/data/filters/$_id.txt" ]; then
                rc=$(grep -vc '^!\|^#\|^[[:space:]]*$' "$workdir/data/filters/$_id.txt"); est=0
            else
                rc="$r_est"; est=1
            fi
            printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
                "$idx" "$r_sec" "$r_name" "$r_type" "$oi" "$oe" "$ti" "$te" "$rc" "$r_url" "$est" >> "$LISTS_DATA"
            idx=$((idx + 1))
        done <<EOF
$AGH_ROSTER
EOF
        cbase=$idx
        awk '
            /^filters:/ || /^whitelist_filters:/ {in_sec=1; type=($1=="filters:"?"Blocklist":"Allowlist")}
            /^[a-z_]+:/ && !/^filters:/ && !/^whitelist_filters:/ {in_sec=0}
            in_sec && /name: / { gsub(/^[[:space:]]*name:[[:space:]]*/, ""); gsub(/^"|",?$/, ""); if ($0 != "") print type "|" $0 }
        ' "$AGH_CONFIG" | while IFS='|' read -r c_type c_name; do
            if ! grep -Fq "|$c_name|" "$LISTS_DATA"; then
                stat=$(agh_list_status "$c_name" "$AGH_CONFIG")
                oi=1; oe=0; [ "$stat" = 2 ] && oe=1
                _id=$(agh_list_id "$c_name" "$AGH_CONFIG")
                if [ -n "$_id" ] && [ -s "$workdir/data/filters/$_id.txt" ]; then
                    rc=$(grep -vc '^!\|^#\|^[[:space:]]*$' "$workdir/data/filters/$_id.txt"); cest=0
                else
                    rc=0; cest=1
                fi
                printf "%s|Your Other Lists|%s|%s|%s|%s|%s|%s|%s|CUSTOM|%s\n" \
                    "$cbase" "$c_name" "$c_type" "$oi" "$oe" "$oi" "$oe" "$rc" "$cest" >> "$LISTS_DATA"
                cbase=$((cbase + 1))
            fi
        done
    }

    while true; do
        clear
        print_centered_header "AdGuardHome Lists Manager"
        AGH_CONFIG=$(get_agh_config)
        [ -z "$AGH_CONFIG" ] && { print_error "Config not found"; press_any_key; return; }
        LISTS_DATA=$(mktemp -t agh_data.XXXXXX)
        spin_run "Reading list sizes" _agh_build_lists

        page=1
        while true; do
            total=$(wc -l < "$LISTS_DATA" 2>/dev/null | tr -dc '0-9'); : "${total:=0}"
            pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE )); [ "$pages" -lt 1 ] && pages=1
            [ "$page" -gt "$pages" ] && page=$pages
            start=$(( (page - 1) * PAGE_SIZE + 1 )); end=$(( page * PAGE_SIZE )); [ "$end" -gt "$total" ] && end=$total

            clear
            print_centered_header "AdGuardHome Lists Manager"
            agh_memory_meter "$LISTS_DATA"
            printf "\n"
            printf "       %-7s %-7s %-6s %-48s %-9s %s\n" "Install" "Enable" "Type" "Name" "Size" "Planned Action"
            printf " %s\n" "$RULE"
            last_sec=""
            sed -n "${start},${end}p" "$LISTS_DATA" | while IFS='|' read -r c_idx c_sec c_name c_type c_oi c_oe c_ti c_te c_rules c_url c_est; do
                if [ "$c_sec" != "$last_sec" ]; then
                    [ -n "$last_sec" ] && printf "\n"
                    printf " %b%s%b\n" "$HDR2" "$c_sec" "$RESET"
                    last_sec="$c_sec"
                fi
                i_box="  [ ]  "; [ "$c_ti" = 1 ] && i_box="  [✓]  "
                e_box="  [ ]  "; [ "$c_te" = 1 ] && e_box="  [✓]  "
                ty="Block"; [ "$c_type" = "Allowlist" ] && ty="Allow"
                action=$(get_agh_action_text "$c_ti" "$c_te" "$c_oi" "$c_oe")
                case "$action" in
                    "No Change")        acol="$GREY" ;;
                    *Remove*|*Disable*) acol="$RED" ;;
                    *)                  acol="$GREEN" ;;
                esac
                dn="$c_name"; [ "${#dn}" -gt 48 ] && dn="$(printf '%.45s' "$dn")..."
                if [ "$c_est" = 1 ]; then sz="~$(agh_fmt_rules "$c_rules")"; else sz="$(agh_fmt_rules "$c_rules")"; fi
                printf " %-5s %s %s %-6s %-48s %-9s %b%s%b\n" "$c_idx." "$i_box" "$e_box" "$ty" "$dn" "$sz" "$acol" "$action" "$RESET"
            done
            printf " %s\n" "$RULE"
            printf " [P] Previous   Page %s of %s   [N] Next   [#] Toggle   [C] Confirm   [0] Back   [?] Help\n" "$page" "$pages"
            printf "\n Choose [%s-%s/N/P/C/0/?]: " "$start" "$end"
            read -r input

            case "$input" in
                "") ;;
                p|P) [ "$page" -gt 1 ] && page=$((page - 1)) ;;
                n|N) [ "$page" -lt "$pages" ] && page=$((page + 1)) ;;
                0) rm -f "$LISTS_DATA"; return ;;
                c|C)
                    ci=""; cinst=""; cen=""; cdis=""; crem=""
                    while IFS='|' read -r i sec n ty oi oe ti te rules url est; do
                        [ -z "$n" ] && continue
                        act=$(get_agh_action_text "$ti" "$te" "$oi" "$oe")
                        case "$act" in
                            "> Install + Enable") ci="${ci}  + ${n}
" ;;
                            "> Install")  cinst="${cinst}  + ${n} (installed, left disabled)
" ;;
                            "> Enable")   cen="${cen}  + ${n}
" ;;
                            "> Disable")  cdis="${cdis}  - ${n}
" ;;
                            "> Remove")   crem="${crem}  - ${n}
" ;;
                        esac
                    done < "$LISTS_DATA"
                    if [ -z "${ci}${cinst}${cen}${cdis}${crem}" ]; then
                        print_warning "No changes to apply (all planned actions are 'No Change')"
                        sleep 2; continue
                    fi

                    clear
                    print_centered_header "Confirm List Changes"
                    [ -n "$ci" ]    && printf "%bInstall + Enable:%b\n%s" "$GREEN" "$RESET" "$ci"
                    [ -n "$cinst" ] && printf "%bInstall (left disabled):%b\n%s" "$GREEN" "$RESET" "$cinst"
                    [ -n "$cen" ]   && printf "%bEnable:%b\n%s" "$GREEN" "$RESET" "$cen"
                    [ -n "$cdis" ]  && printf "%bDisable:%b\n%s" "$YELLOW" "$RESET" "$cdis"
                    [ -n "$crem" ]  && printf "%bRemove:%b\n%s" "$RED" "$RESET" "$crem"

                    agh_lists_guard_rails "$LISTS_DATA"

                    printf "\nProceed with list changes? [y/N]: "; read -r confirm
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue

                    stamp=$(date +%Y%m%d%H%M%S)
                    BACKUP_FILE="${AGH_CONFIG}.backup.${stamp}"
                    cp "$AGH_CONFIG" "$BACKUP_FILE"
                    agh_was_running=0; is_agh_running && agh_was_running=1
                    [ "$agh_was_running" -eq 1 ] && { $AGH_INIT stop >/dev/null 2>&1; sleep 1; }

                    count=0
                    while IFS='|' read -r i sec n ty oi oe ti te rules url est; do
                        [ -z "$n" ] && continue
                        act=$(get_agh_action_text "$ti" "$te" "$oi" "$oe")
                        case "$act" in
                            "> Install + Enable") agh_add_block "$n" "$ty" "$url" "$count" "$AGH_CONFIG"; count=$((count + 1)) ;;
                            "> Install")          agh_add_block "$n" "$ty" "$url" "$count" "$AGH_CONFIG"; agh_set_enabled "$n" false "$AGH_CONFIG"; count=$((count + 1)) ;;
                            "> Enable")           agh_set_enabled "$n" true "$AGH_CONFIG" ;;
                            "> Disable")          agh_set_enabled "$n" false "$AGH_CONFIG" ;;
                            "> Remove")           agh_delete_block "$n" "$AGH_CONFIG" ;;
                        esac
                    done < "$LISTS_DATA"

                    for head in "filters" "whitelist_filters"; do
                        if grep -qE "^$head:|^  $head:" "$AGH_CONFIG"; then
                            next_line=$(grep -A 1 -E "^$head:|^  $head:" "$AGH_CONFIG" | tail -n 1)
                            if ! echo "$next_line" | grep -q "\- enabled:"; then
                                sed -i "/^$head:/ s/.*/$head: []/" "$AGH_CONFIG"
                                sed -i "/^  $head:/ s/.*/  $head: []/" "$AGH_CONFIG"
                            fi
                        fi
                    done

                    # Reclaim disk: drop filter files for lists no longer in the config
                    # (AGH leaves them behind), so removals actually free the partition.
                    agh_clean_orphan_filters "$AGH_CONFIG" "$(get_agh_workdir)"

                    if agh_apply_and_restart "$agh_was_running" "$BACKUP_FILE" "$AGH_CONFIG" "Changes applied."; then
                        print_success "Backup file created: $(basename "$BACKUP_FILE")"
                    fi

                    # AGH fetches enabled lists asynchronously after the restart, so "config
                    # saved" != "list loaded". Wait for the newly-enabled lists to download,
                    # with progress, so the screen doesn't look hung and the Memory Impact meter
                    # is accurate on return.  A pending list = active target with no file yet ($11=1).
                    _wd=$(get_agh_workdir)
                    _pending=$(awk -F'|' '$7==1 && $8==1 && $11==1 {c++} END{print c+0}' "$LISTS_DATA")
                    if [ "$agh_was_running" -eq 1 ] && [ "$_pending" -gt 0 ]; then
                        printf "\n"
                        # Spin smoothly at ~0.1s/frame (like spin_run) while re-checking the
                        # filter files only every ~2s, so the spinner animates instead of ticking
                        # once per file check.  Cap ~50s (500 frames).
                        _spin='-\|/'; _frame=0; _prev=-1; _stall=0; _done=0; _failed=""
                        while [ "$_frame" -lt 500 ]; do
                            if [ $((_frame % 20)) -eq 0 ]; then
                                _done=0; _failed=""
                                while IFS='|' read -r _i _sec _n _ty _oi _oe _ti _te _r _u _e; do
                                    { [ "$_ti" = 1 ] && [ "$_te" = 1 ] && [ "$_e" = 1 ]; } || continue
                                    _id=$(agh_list_id "$_n" "$AGH_CONFIG")
                                    if [ -n "$_id" ] && [ -s "$_wd/data/filters/$_id.txt" ]; then
                                        _done=$((_done + 1))
                                    else
                                        _failed="${_failed}  - ${_n}
"
                                    fi
                                done < "$LISTS_DATA"
                                [ "$_done" -ge "$_pending" ] && break
                                # Stop early only if nothing progressed AND nothing is mid-download
                                # (AGH writes a hidden temp file while fetching); ENOSPC fails instantly.
                                if [ "$_done" = "$_prev" ] && ! ls "$_wd"/data/filters/.*.txt* >/dev/null 2>&1; then
                                    _stall=$((_stall + 1)); [ "$_stall" -ge 3 ] && break
                                else _stall=0; fi
                                _prev=$_done
                            fi
                            _c=${_spin%"${_spin#?}"}; _spin=${_spin#?}$_c
                            printf "\r${BOLD}${CYAN}${_S_ACT}${RESET}${CYAN}Downloading lists %s of %s${RESET} %s " "$_done" "$_pending" "$_c"
                            usleep 100000 2>/dev/null || sleep 1
                            _frame=$((_frame + 1))
                        done
                        printf "\r\033[K"
                        if [ -z "$_failed" ]; then
                            print_success "Downloaded $_pending list(s)."
                        elif [ "${_agh_storage_over:-0}" = 1 ]; then
                            # ENOSPC: these cannot fit - remove them so nothing is left
                            # installed+enabled-but-empty (there is no clean re-apply from that state).
                            while IFS='|' read -r _i _sec _n _ty _oi _oe _ti _te _r _u _e; do
                                { [ "$_ti" = 1 ] && [ "$_te" = 1 ]; } || continue
                                _id=$(agh_list_id "$_n" "$AGH_CONFIG")
                                { [ -n "$_id" ] && [ -s "$_wd/data/filters/$_id.txt" ]; } && continue
                                agh_delete_block "$_n" "$AGH_CONFIG"
                            done < "$LISTS_DATA"
                            agh_clean_orphan_filters "$AGH_CONFIG" "$_wd"
                            $AGH_INIT restart >/dev/null 2>&1
                            print_error "These lists could NOT download - lists storage is full - and were removed:"
                            printf "%s\n" "$_failed"
                            print_info "Free space in Advanced Settings -> Filter Storage Space Limit, then add them again."
                        else
                            print_warning "These lists have not finished downloading:"
                            printf "%s\n" "$_failed"
                            print_info "AdGuardHome keeps retrying - check back shortly, or check your connection."
                        fi
                    fi

                    cached_rules=""   # force the Control Center to recount rules after a change
                    press_any_key; rm -f "$LISTS_DATA"; break
                    ;;
                \?|h|H|❓) show_agh_lists_help ;;
                [0-9]*)
                    if [ "$input" -ge "$start" ] 2>/dev/null && [ "$input" -le "$end" ] 2>/dev/null; then
                        awk -F'|' -v t="$input" 'BEGIN{OFS="|"} {
                            if($1==t){
                                oi=$5+0; oe=$6+0; ti=$7+0; te=$8+0;
                                cur=2*ti+te;                                  # (0,0)=0 (1,0)=2 (1,1)=3
                                if(oi==0 && oe==0)      split("0 3 2",ord," ");   # missing:  none -> install+enable -> install
                                else if(oi==1 && oe==1) split("3 0 2",ord," ");   # active:   nochange -> remove -> disable
                                else                    split("2 3 0",ord," ");   # inactive: nochange -> enable -> remove
                                idx=1; for(k=1;k<=3;k++) if(ord[k]==cur) idx=k;
                                nx=ord[(idx % 3)+1];
                                $7=int(nx/2); $8=nx%2;
                            }
                            print
                        }' "$LISTS_DATA" > "$LISTS_DATA.tmp" && mv "$LISTS_DATA.tmp" "$LISTS_DATA"
                    else
                        print_error "Item $input is not on this page"; sleep 1
                    fi
                    ;;
                *) print_error "Invalid option"; sleep 1 ;;
            esac
        done
    done
}

# -----------------------------
# AdGuardHome Direct Access Management
# -----------------------------

show_agh_direct_help() {
    local lan_ip
    lan_ip=$(get_lan_ip)
    show_paged "AdGuardHome Direct Access - Help" << HELPEOF

AdGuardHome Direct Access - Quick Help

What it does
────────────
Reach the AdGuardHome dashboard directly, bypassing the GL.iNet admin login.

  • ON:  the dashboard is served at http://${lan_ip}:3000
  • OFF: port 3000 redirects to port 80 (the standard GL.iNet login)

Web UI credentials
──────────────────
Bypassing the GL.iNet login removes its protection, so a username and password
are set on AdGuardHome itself (a secure bcrypt hash). Set these before leaving
Direct Access on, or the dashboard is open to anyone on your LAN.

Remove password
───────────────
Clears the AdGuardHome credentials, leaving the dashboard fully open on the LAN.
Use only if you want no login at all.

Notes
─────
  • Backups: a timestamped copy of the init script and config.yaml is saved
    before each change (.backup.YYYYMMDDHHMMSS).
  • Persistence: a firmware update overwrites the init script - re-enable
    Direct Access afterwards to restore it.

HELPEOF
}

update_agh_credentials() {
    local u_retry p_retry
    clear
    print_centered_header "Set Web UI Credentials"
    if [ "$PASS_STATUS" = "✅" ]; then
        print_warning "A password is already set. Proceeding will overwrite it."
        printf "\n"
    else 
        print_warning "No password currently set. This will create a new username and password."
    fi
    printf "Set Web UI credentials? [y/N]: "
    read -r confirm
    printf "\n"
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return

    # Dependency Check
    if ! command -v htpasswd >/dev/null 2>&1; then
        install_package apache "apache utils" || { press_any_key; return; }
    fi

    # Input capture — username (suggest root; blank offers retry/cancel)
    while true; do
        printf "Enter Username (e.g. root): "
        read -r user_name
        [ -n "$user_name" ] && break
        printf "\n"
        print_warning "Username cannot be blank."
        printf "Try again? [Y/n]: "; read -r u_retry; printf "\n"
        case "$u_retry" in n|N) print_info "Operation cancelled."; return ;; esac
    done

    # Password with confirmation; blank or mismatch offers retry/cancel
    while true; do
        user_pass=$(get_password "Enter Password: ")
        if [ -z "$user_pass" ]; then
            printf "\n"
            print_warning "Password cannot be blank."
            printf "Try again? [Y/n]: "; read -r p_retry; printf "\n"
            case "$p_retry" in n|N) print_info "Operation cancelled."; return ;; esac
            continue
        fi
        user_pass_conf=$(get_password "Confirm Password: ")
        if [ "$user_pass" = "$user_pass_conf" ]; then
            break
        fi
        printf "\n"
        print_warning "Passwords do not match."
        printf "Try again? [Y/n]: "; read -r p_retry; printf "\n"
        case "$p_retry" in n|N) print_info "Operation cancelled."; return ;; esac
    done

    BCRYPT_HASH=$(htpasswd -n -B -b "$user_name" "$user_pass" | cut -d: -f2)

    

    # --- VALIDATION LOGIC ---
    [ -z "$TIMESTAMP" ] && TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_FILE="$AGH_CONF.backup.$TIMESTAMP"
    cp "$AGH_CONF" "$BACKUP_FILE"

    # Validate structure BEFORE touching the service (reads only)
    local ESC_HASH=$(echo "$BCRYPT_HASH" | sed 's/[&]/\\&/g')
    local mode=""
    if grep -q "users: \[\]" "$AGH_CONF"; then
        mode="empty"
    elif grep -q "^users:" "$AGH_CONF"; then
        line_num=$(grep -n "^users:" "$AGH_CONF" | cut -d: -f1)
        check_name=$(sed -n "$((line_num+1))p" "$AGH_CONF")
        check_pass=$(sed -n "$((line_num+2))p" "$AGH_CONF")
        if echo "$check_name" | grep -q " - name:" && echo "$check_pass" | grep -q "password:"; then
            mode="block"
        else
            print_error "Unexpected YAML structure detected below 'users:' line."
            print_warning "Manual edit required to avoid corrupting config."
            press_any_key; return
        fi
    else
        print_error "Could not find 'users:' key in $AGH_CONF"
        press_any_key; return
    fi

    # Commit: stop (only if running), edit, then restart-if-was-running
    agh_was_running=0; is_agh_running && agh_was_running=1
    [ "$agh_was_running" -eq 1 ] && { $AGH_INIT stop >/dev/null 2>&1; sleep 1; }

    if [ "$mode" = "empty" ]; then
        sed -i "\|users: \[\]|c\users:\n  - name: $user_name\n    password: \"$ESC_HASH\"" "$AGH_CONF"
    else
        sed -i "$((line_num+1))s|- name: .*|- name: $user_name|" "$AGH_CONF"
        sed -i "$((line_num+2))s|password: .*|password: \"$ESC_HASH\"|" "$AGH_CONF"
    fi

    if agh_apply_and_restart "$agh_was_running" "$BACKUP_FILE" "$AGH_CONF" "Credentials updated."; then
        print_success "Backup created: $(basename "$BACKUP_FILE")"
    fi
    press_any_key
}

manage_agh_direct_access() {
    while true; do
        clear
        print_centered_header "AdGuardHome Direct Access"
        lan_ipaddr=$(get_lan_ip)
        AGH_CONF=$(get_agh_config)
        DIRECT_STATUS="❌"; direct_disp="$_S_OFF"
        grep -q -- "--glinet" "$AGH_INIT" || { DIRECT_STATUS="✅"; direct_disp="$_S_ON"; }

        PASS_STATUS="✅"; pass_disp="$_S_ON"
        grep -q "users: \[\]" "$AGH_CONF" && { PASS_STATUS="❌"; pass_disp="$_S_OFF"; }

        printf " ${CYAN}STATUS${RESET}\n"
        printf "   Direct Web UI Access: %b\n" "$direct_disp"
        printf "   Web UI Username / Password Set: %b\n\n" "$pass_disp"
        local direct_label="Enable Direct Access (Switch to Standalone)"
        [ "$DIRECT_STATUS" = "✅" ] && direct_label="Disable Direct Access (Switch to Integrated)"
        printf "%s%s%s\n" "$N1" "$NSEP" "$direct_label"
        printf "%s%sAdd/Update Web UI Credentials (Username/Password)\n" "$N2" "$NSEP"
        printf "%s%sRemove Web UI Password (Set to Open Access)\n" "$N3" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        
        printf "\nChoose [1-3/0/?]: "
        read -r direct_choice
        TIMESTAMP=$(date +%Y%m%d%H%M%S)

        case $direct_choice in
            1)
                clear
                if [ "$DIRECT_STATUS" = "❌" ]; then
                    print_centered_header "Enable AdGuardHome Direct Access"
                    print_warning "AdGuardHome direct access bypasses GL.iNet Web UI security."
                    printf "\n"
                    print_warning "If no password is set, and you bypass setting a password, the UI will be ${BOLD}UNSECURED.${RESET}"
                    printf "\n"
                    print_info "Once enabled, you can access AdGuardHome Web UI at ${BOLD}http://$lan_ipaddr:3000${RESET}"
                    printf "Enable Direct Access? [y/N]: "
                else
                    print_centered_header "Disable AdGuardHome Direct Access"
                    print_warning "AdGuardHome direct Web UI access via http://$lan_ipaddr:3000 will be disabled."
                    printf "\n"
                    print_warning "Any passwords set will remain but will be bypassed."
                    printf "\n"
                    print_info "Once disabled, you can access the AdGuardHome Web UI at: ${BOLD}http://$lan_ipaddr/${RESET}"
                    printf "Disable Direct Access? [y/N]: "
                fi
                read -r confirm
                [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue

                cp "$AGH_INIT" "$AGH_INIT.backup.$TIMESTAMP"
                agh_was_running=0; is_agh_running && agh_was_running=1

                if [ "$DIRECT_STATUS" = "✅" ]; then
                    # Turning Direct Access OFF (Integrated Mode)
                    sed -i 's/AdGuardHome /AdGuardHome --glinet /g' "$AGH_INIT"
                    agh_apply_and_restart "$agh_was_running" "$AGH_INIT.backup.$TIMESTAMP" "$AGH_INIT" "Direct Access disabled (Integrated Mode)."
                    press_any_key
                else
                    # Turning Direct Access ON (Standalone Mode)
                    sed -i 's/ --glinet//g' "$AGH_INIT"
                    if [ "$PASS_STATUS" = "❌" ]; then
                        printf "\n"
                        print_warning "No username/password has been set for AdGuardHome."
                        printf "Would you like to set one now? [Y/n]: "
                        read -r set_pass
                        printf "\n"
                        if [ "$set_pass" != "n" ] && [ "$set_pass" != "N" ]; then
                            update_agh_credentials && continue
                        else
                            print_warning "AdGuardHome Web UI will be UNSECURED (no password)."
                            agh_apply_and_restart "$agh_was_running" "$AGH_INIT.backup.$TIMESTAMP" "$AGH_INIT" "Direct Access enabled (Standalone Mode)."
                            press_any_key
                        fi
                    else
                        agh_apply_and_restart "$agh_was_running" "$AGH_INIT.backup.$TIMESTAMP" "$AGH_INIT" "Direct Access enabled (Standalone Mode)."
                        press_any_key
                    fi
                fi
                ;;

            2) update_agh_credentials;;  

            3)
                clear
                print_centered_header "Remove AdGuardHome Web UI Password"
                if [ "$PASS_STATUS" = "❌" ]; then
                    print_warning "No password currently exists."
                    press_any_key; continue
                fi
                if [ "$DIRECT_STATUS" = "✅" ]; then
                    print_warning "This removes the Web UI credentials, leaving AdGuardHome OPEN (unsecured)."
                else
                    print_warning "This removes the AdGuardHome Web UI credentials."
                fi
                printf "Remove credentials? [y/N]: "
                read -r confirm
                [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue

                BACKUP_FILE="$AGH_CONF.backup.$TIMESTAMP"
                cp "$AGH_CONF" "$BACKUP_FILE"
                agh_was_running=0; is_agh_running && agh_was_running=1
                [ "$agh_was_running" -eq 1 ] && { $AGH_INIT stop >/dev/null 2>&1; sleep 1; }

                # Find users: block and replace with users: []
                line_num=$(grep -n "^users:" "$AGH_CONF" | cut -d: -f1)
                # Delete the next two lines (- name and password) then change users: to users: []
                if ! grep -q "users: \[\]" "$AGH_CONF"; then
                    sed -i "$((line_num+1)),$((line_num+2))d" "$AGH_CONF"
                fi
                sed -i "${line_num}s/users:.*/users: []/" "$AGH_CONF"

                agh_apply_and_restart "$agh_was_running" "$BACKUP_FILE" "$AGH_CONF" "Web UI password removed."
                press_any_key
                ;;

            0) return ;;
            \?|h|H|❓) show_agh_direct_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}


# -----------------------------
# AdGuardHome Control Center
# -----------------------------

show_agh_help() {
    show_paged "AdGuardHome Hub - Help" << 'HELPEOF'
AdGuardHome Control Center - Quick Help

What it does
────────────
The hub for AdGuardHome (the router's DNS ad-blocker): control the service,
manage filter lists, run backups, and reach the dashboard.

What each item does
───────────────────
SERVICE: Start, restart or stop the AdGuardHome daemon. Listed first because
   it is the most-used control and answers the STATUS line above the menu.

ALLOW/BLOCKLISTS: Add or remove filter subscriptions (block and allow lists).

ADVANCED SETTINGS: the filter storage-space limit, Zram Swap, Direct Access
   (UI entry points), and UI Updates (binary lifecycle).

BACKUP SUITE:
   - SAVE: Generates timestamped sync points for Config and Binary.
   - RESTORE: Allows modular injection of previous system states.
   - MANAGE: Cleanup utility to purge redundant backup files.

LOGS & MAINTENANCE:
   - LOGS: Real-time 'logread' stream for diagnostic observation.
   - CACHE: Flushes filter data to resolve download/checksum errors.

FACTORY RESET: Reconstructs the environment using read-only firmware
   defaults located in the /rom partition.

NOTES:
- Edits apply when AdGuardHome restarts. If the service is stopped, changes
  are saved and take effect the next time you start it.
- RULE DISCREPANCY: 'Raw' counts include all text lines. The Web UI
  displays a lower 'Optimized' count after deduplication.
- 10MB LIMIT: Crucial for routers with small flash storage. When
  active, it restricts filter space to prevent storage exhaustion.
- LOGS: Query logs are often in /tmp (RAM). If 'Free Space' is 
  low, the system may become unstable.
HELPEOF
}

create_agh_backup() {
    local ts=$(date +%Y%m%d%H%M%S)
    local b_cfg="Y"
    local b_bin="N"
    local b_ini="N"
    local AGH_CONFIG=$(get_agh_config)

    while true; do
        clear
        print_centered_header "AdGuardHome Backup Creation"
        printf " TIMESTAMP: $ts\n"
        printf "\n #  Sel Component\n"
        printf " ────────────────────────────────────────────────────────────\n"
        printf " 1. [%s] Configuration Settings (YAML)\n" "$b_cfg"
        printf " 2. [%s] App Binary (AdGuardHome Executable)\n" "$b_bin"
        printf " 3. [%s] Startup Script (init.d)\n" "$b_ini"
        printf " ────────────────────────────────────────────────────────────\n"
        printf " [#] Toggle Component   [S] Save Backup   [0] Cancel\n"
        printf "\n Choose [1-3/S/0]: "
        read -r s_choice
        s_choice=$(echo "$s_choice" | tr 'A-Z' 'a-z')
        
        case "$s_choice" in
            1) [ "$b_cfg" = "Y" ] && b_cfg="N" || b_cfg="Y" ;;
            2) [ "$b_bin" = "Y" ] && b_bin="N" || b_bin="Y" ;;
            3) [ "$b_ini" = "Y" ] && b_ini="N" || b_ini="Y" ;;
            s)
                if [ "$b_cfg" = "N" ] && [ "$b_bin" = "N" ] && [ "$b_ini" = "N" ]; then
                    printf "\n"
                    print_error "Nothing selected to save."
                    sleep 1
                    continue
                fi

                printf "\n"
                print_info "Creating Selected Backups"
                # Atomic Save Logic
                [ "$b_cfg" = "Y" ] && bk_save agh "$ts" "$AGH_CONFIG"
                [ "$b_bin" = "Y" ] && bk_save agh "$ts" "/usr/bin/AdGuardHome"
                [ "$b_ini" = "Y" ] && bk_save agh "$ts" "/etc/init.d/adguardhome"
                
                printf "\n"
                print_success "Backup $ts completed!"
                press_any_key
                return 0
                ;;
            0) return 1 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

manage_agh_backups() {
    while true; do
        local backups=$(bk_list agh config.yaml)
        [ -z "$backups" ] && { print_error "No backups found."; sleep 2; return; }

        clear
        print_centered_header "Pick a Backup Date"
        printf " %-3s  %-18s  %s  %s   %s\n" "#" "Date / Time" "Conf" "Bin" "Init"
        printf " ─────────────────────────────────────────\n"

        local i=1
        local map_file="/tmp/agh_bk_map"
        > "$map_file"

        for ts in $backups; do
            local p_date="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}"
            local has_bin="[N]"; bk_has agh AdGuardHome "$ts" && has_bin="[Y]"
            local has_ini="[N] "; bk_has agh adguardhome "$ts" && has_ini="[Y] "

            printf " %-3s  %-18s  %s  %s   %s\n" "$i." "$p_date" "[Y] " "$has_bin" "$has_ini"
            printf "%s|%s\n" "$i" "$ts" >> "$map_file"
            i=$((i+1))
        done
        printf " ────────────────────────────────────────────\n"
        printf " [#] To Restore   [0] Cancel\n"
        printf "\n Choose [%s/0]: " "$(picker_range $((i-1)))"
        read -r b_choice
        printf "\n"
        [ -z "$b_choice" ] || [ "$b_choice" = "0" ] && return

        local selected_ts=$(grep "^$b_choice|" "$map_file" | cut -d'|' -f2)
        if [ -z "$selected_ts" ]; then 
            print_error "Invalid selection"; sleep 1; continue
        fi

        # Only components with a backup for this timestamp are restorable. The
        # timestamp comes from a config backup, so config always exists; binary
        # and init are optional - show (and allow toggling) only what's present,
        # numbered sequentially so there are no gaps.
        local bin_avail=0; bk_has agh AdGuardHome "$selected_ts" && bin_avail=1
        local ini_avail=0; bk_has agh adguardhome "$selected_ts" && ini_avail=1
        local fix_cfg="Y"
        local fix_bin="Y"; [ "$bin_avail" -eq 0 ] && fix_bin="N"
        local fix_ini="Y"; [ "$ini_avail" -eq 0 ] && fix_ini="N"
        while true; do
            clear
            print_centered_header "Select items to restore from: $selected_ts"
            printf " #  Sel Component\n"
            printf " ────────────────────────────────────────────────────────────\n"
            local n=0 cfg_n=0 bin_n=0 ini_n=0
            n=$((n+1)); cfg_n=$n; printf " %d. [%s] Configuration Settings\n" "$n" "$fix_cfg"
            if [ "$bin_avail" -eq 1 ]; then n=$((n+1)); bin_n=$n; printf " %d. [%s] App Binary (AdGuardHome)\n" "$n" "$fix_bin"; fi
            if [ "$ini_avail" -eq 1 ]; then n=$((n+1)); ini_n=$n; printf " %d. [%s] Startup Script (init.d)\n" "$n" "$fix_ini"; fi
            printf " ────────────────────────────────────────────────────────────\n"
            printf " [#] Toggle Restore   [C] Confirm   [0] Cancel\n"
            printf "\n Choose [%s/C/0]: " "$(picker_range "$n")"
            read -r s_choice
            s_choice=$(echo "$s_choice" | tr 'A-Z' 'a-z')
            if [ "$s_choice" = "0" ]; then
                return
            elif [ "$s_choice" = "c" ]; then
                if [ "$fix_cfg" = "N" ] && [ "$fix_bin" = "N" ] && [ "$fix_ini" = "N" ]; then
                    printf "\n"
                    print_error "Nothing selected to restore. Select an option or 0 to cancel."
                    press_any_key
                    continue
                fi
                printf "\nApplying Restore...\n"
                agh_was_running=0; is_agh_running && agh_was_running=1
                [ "$agh_was_running" -eq 1 ] && { $AGH_INIT stop >/dev/null 2>&1; sleep 1; }
                [ "$fix_cfg" = "Y" ] && bk_restore agh "$selected_ts" "/etc/AdGuardHome/config.yaml"
                [ "$fix_bin" = "Y" ] && bk_restore agh "$selected_ts" "/usr/bin/AdGuardHome"
                [ "$fix_ini" = "Y" ] && bk_restore agh "$selected_ts" "/etc/init.d/adguardhome"
                agh_apply_and_restart "$agh_was_running" "" "" "Restore complete."
                press_any_key; return
            elif [ "$s_choice" = "$cfg_n" ]; then
                [ "$fix_cfg" = "Y" ] && fix_cfg="N" || fix_cfg="Y"
            elif [ "$bin_avail" -eq 1 ] && [ "$s_choice" = "$bin_n" ]; then
                [ "$fix_bin" = "Y" ] && fix_bin="N" || fix_bin="Y"
            elif [ "$ini_avail" -eq 1 ] && [ "$s_choice" = "$ini_n" ]; then
                [ "$fix_ini" = "Y" ] && fix_ini="N" || fix_ini="Y"
            else
                print_error "Invalid option"; sleep 1
            fi
        done
    done
}

delete_agh_backups() {
    local map_file="/tmp/agh_del_map"
    [ -f "$map_file" ] && rm -f "$map_file"
    while true; do
        local backups=$(bk_list agh config.yaml)
        [ -z "$backups" ] && { print_error "No backups found."; sleep 2; return; }

        # Initialize map file if it doesn't exist (Index|Timestamp|Selected)
        if [ ! -f "$map_file" ]; then
            local i=1
            for ts in $backups; do
                echo "$i|$ts|0" >> "$map_file"
                i=$((i+1))
            done
        fi

        clear
        print_centered_header "AdGuardHome Backup Cleanup"
        printf " %-3s  %-4s  %-18s  %s  %s   %s  %s\n" "Sel" "Idx" "Date / Time" "Conf" "Bin" "Init" "Size"
        printf " ────────────────────────────────────────────────────────────\n"

        while IFS='|' read -r idx ts sel; do
            local p_date="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}"
            local s_box="[ ]"; [ "$sel" -eq 1 ] && s_box="[✓]"

            # Check presence of components
            local c="[Y] "; bk_has agh config.yaml "$ts" || c="[N] "
            local b="[Y]"; bk_has agh AdGuardHome "$ts" || b="[N]"
            local n="[Y] "; bk_has agh adguardhome "$ts" || n="[N] "

            # Calculate total size for this timestamp (components now live in the central store)
            local ts_bytes=0 _bkd; _bkd=$(bk_dir agh)
            for f in "$_bkd/config.yaml.$ts" "$_bkd/AdGuardHome.$ts" "$_bkd/adguardhome.$ts"; do
                [ -f "$f" ] && ts_bytes=$((ts_bytes + $(ls -nl "$f" | awk '{print $5}')))
            done
            
            # Convert to human readable
            local p_size="0B"
            if [ "$ts_bytes" -ge 1048576 ]; then
                p_size=$(awk "BEGIN {printf \"%.1fM\", $ts_bytes/1048576}")
            elif [ "$ts_bytes" -ge 1024 ]; then
                p_size=$(awk "BEGIN {printf \"%.1fK\", $ts_bytes/1024}")
            else
                p_size="${ts_bytes}B"
            fi

            printf " %s  %-4s  %-18s  %s  %s   %s  %-6s\n" "$s_box" "$idx." "$p_date" "$c" "$b" "$n" "$p_size"
        done < "$map_file"

        printf " ────────────────────────────────────────────────────────────\n"
        printf " [A] All   [N] None   [#] Toggle   [C] Confirm   [0] Cancel\n"
        bk_count=$(wc -l < "$map_file" 2>/dev/null | tr -dc '0-9')
        printf "\n Choose [%s/A/N/C/0]: " "$(picker_range "$bk_count")"
        read -r input
        local cmd=$(echo "$input" | tr 'A-Z' 'a-z')

        case "$cmd" in
            a) sed -i 's/|0$/|1/' "$map_file" ;;
            n) sed -i 's/|1$/|0/' "$map_file" ;;
            [1-9]*) 
                if grep -q "^$cmd|" "$map_file"; then
                    local current_state=$(grep "^$cmd|" "$map_file" | cut -d'|' -f3)
                    local new_state=$((1 - current_state))
                    sed -i "s/^\($cmd|[^|]*|\).*/\1$new_state/" "$map_file"
                else
                    print_error "Index $cmd not found"; sleep 1
                fi ;;
            c)
                if ! grep -q "|1$" "$map_file"; then
                    printf "\n"
                    print_error "No backups selected."; sleep 2; continue
                fi
                printf "\n"
                print_warning "WARNING: You are about to permanently delete selected backups."
                printf "Delete selected backups? [y/N]: "; read -r confirm
                case "$confirm" in
                    y|Y)
                    while IFS='|' read -r idx ts sel; do
                        [ "$sel" -eq 1 ] && bk_delete agh "$ts"
                    done < "$map_file"
                    printf "\n"
                    print_success "Selected backups purged."
                    press_any_key;
                    rm -f "$map_file"
                    return ;;
                    *) print_error "Deletion cancelled." ; sleep 2 ; continue ;;
                esac ;;
            0) rm -f "$map_file"; return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

show_agh_setup_help() {
    show_paged "AdGuardHome Advanced Settings - Help" << 'HELPEOF'
AdGuardHome Advanced Settings - Quick Help

What it does
────────────
Groups the AdGuardHome settings that aren't day-to-day filtering:

  • Filter Storage Space Limit - how much room its filter data may use
  • Zram Swap - compressed RAM swap; adds memory headroom so more/larger
    lists can load without exhausting RAM
  • UI Direct Access & Web UI login - reach the dashboard directly, with its
    own username and password
  • UI Updates - whether AdGuardHome may update its own web interface

Each item opens its own screen with full details and its own help.
HELPEOF
}

sub_setup_config() {
    while true; do
        clear
        print_centered_header "AdGuardHome Advanced Settings"
        printf "%s%sFilter Storage Space Limit\n" "$N1" "$NSEP"
        printf "%s%sZram Swap\n" "$N2" "$NSEP"
        printf "%s%sUI Direct Access\n" "$N3" "$NSEP"
        printf "%s%sUI Updates\n" "$N4" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-4/0/?]: "
        read -r s_opt
        case "$s_opt" in
            \?|h|H|❓) show_agh_setup_help ;;
            1) manage_agh_storage ;;
            2) manage_zram ;;
            3) manage_agh_direct_access ;;
            4) manage_agh_ui_updates ;;
            0) break ;;
            *) print_error "Invalid option"; sleep 1;;
        esac
    done
}

show_agh_backup_help() {
    show_paged "AdGuardHome Backup & Recovery - Help" << 'HELPEOF'
AdGuardHome Backup & Recovery - Quick Help

What it does
────────────
Create, restore and manage backups of your AdGuardHome setup.

What a backup contains
──────────────────────
The configuration (config.yaml), the AdGuardHome binary, and the startup
script - enough to restore a working install.

Notes
─────
  • Backups are timestamped, so you can keep several and roll back to any one
    if a change goes wrong.
  • They are stored centrally in /etc/glinet_utils/backups and survive a reboot;
    older in-place backups are moved there automatically.
  • A firmware update can replace the binary and script; restore a backup to
    recover.
HELPEOF
}

sub_backup_recovery() {
    # Sweep any legacy co-located backups (from older versions and from the transactional auto-backups
    # the credential / direct-access screens still make) into the central store so they appear + are managed.
    bk_migrate_legacy agh "$(get_agh_config)" /usr/bin/AdGuardHome /etc/init.d/adguardhome
    while true; do
        get_agh_stats
        clear
        print_centered_header "AdGuardHome Backup & Recovery Suite"
        printf " ${CYAN}OVERVIEW${RESET}\n"
        printf "   Latest: %s  ·  Total Files: %s\n\n" "${bk_date:-None}" "${bk_file_count:-0}"
        printf " ${CYAN}STORAGE STATUS${RESET}\n"
        printf "   Used: %s  ·  Free: %s\n" "${bk_total_u:-0B}" "${qlog_f:-N/A}"
        printf " ────────────────────────────────────────────────\n\n"
        printf "%s%sSave a New Backup\n" "$N1" "$NSEP"
        printf "%s%sRestore from Backup\n" "$N2" "$NSEP"
        printf "%s%sManage/Delete Backups\n" "$N3" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-3/0/?]: "
        read -r b_opt
        case "$b_opt" in
            \?|h|H|❓) show_agh_backup_help ;;
            1) create_agh_backup ;;
            2) manage_agh_backups ;;
            3) delete_agh_backups ;;
            0) break ;;
            *) print_error "Invalid option"; sleep 1;;
        esac
    done
}

show_agh_service_help() {
    show_paged "AdGuardHome Logs & Maintenance - Help" << 'HELPEOF'
AdGuardHome Logs & Maintenance - Quick Help

What it does
────────────
Diagnostics for AdGuardHome: watch its live logs and clear its cached filter
files.

When to use
───────────
  • Live logs - to see what AdGuardHome is doing (queries, blocks, errors),
    e.g. after changing filter lists.
  • Clear cache - to force it to re-fetch filter data if a list looks stale.

Note: starting, stopping and restarting the service is on the Control Center,
not here.
HELPEOF
}

sub_service_health() {
    while true; do
        clear
        print_centered_header "AdGuardHome Logs & Maintenance"
        printf "%s%sWatch Live Logs\n" "$N1" "$NSEP"
        printf "%s%sClear Filter Cache\n" "$N2" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-2/0/?]: "
        read -r h_opt
        case "$h_opt" in
            \?|h|H|❓) show_agh_service_help ;;
            1)
               clear
               print_centered_header "AdGuardHome System Logs (Ctrl+C to exit)"
               sleep 1
               trap 'printf "\n\n"; print_warning "Stopping log viewing"' INT
               logread -l 20 -e "AdGuardHome" 2>/dev/null
               logread -f -e "AdGuardHome" 2>/dev/null
               trap - INT
               press_any_key
               ;;
            2)
               printf "\n"
               print_warning "This clears all cached filter files; AdGuardHome re-downloads them on next start."
               printf "Clear filter cache? [y/N]: "; read -r confirm
               if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                   local wd=$(get_agh_workdir)
                   agh_was_running=0; is_agh_running && agh_was_running=1
                   rm -rf "${wd:-/etc/AdGuardHome}/data/filters/"* 2>/dev/null
                   agh_apply_and_restart "$agh_was_running" "" "" "Filters purged." "-"
                   cached_rules=""
               fi
               press_any_key ;;
            0) break ;;
            *) print_error "Invalid option"; sleep 1;;
        esac
    done
}

sub_confirm_factory_reset() {
    local L_INIT="/etc/init.d/adguardhome"
    local L_BIN="/usr/bin/AdGuardHome"
    local L_CONF="/etc/AdGuardHome/config.yaml"
    local init_ok=0 bin_ok=0 conf_ok=0
    local was_running=0
    local was_uci_enabled=0

    printf "\n"
    print_warning "WARNING: This will restore factory system files and defaults from /rom"
    printf "Restore factory defaults? [y/N]: "; read -r confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { printf "\n"; print_info "Operation cancelled."; press_any_key; return; }

    # --- 1. Pre-Check State & Stop Phase ---
    # Call the function directly to check the exit status
    is_agh_running && was_running=1
    
    if [ "$(uci -q get adguardhome.config.enabled)" = "1" ]; then
        was_uci_enabled=1
    fi

    if [ "$was_running" -eq 1 ]; then
        printf "\n"
        print_info "AdGuardHome is currently running. Stopping service"
        [ -f "$L_INIT" ] && $L_INIT stop >/dev/null 2>&1; sleep 1
        sleep 1
        if is_agh_running; then
            kill -9 $(pidof AdGuardHome) >/dev/null 2>&1; sleep 1
        fi
        print_success "Service stopped successfully."
    fi

    # --- 2. Restore Files from ROM ---
    [ -f "/rom$L_INIT" ] && cp -f "/rom$L_INIT" "$L_INIT" && chmod +x "$L_INIT" && init_ok=1
    [ -f "/rom$L_BIN" ]  && cp -f "/rom$L_BIN" "$L_BIN"   && chmod +x "$L_BIN"  && bin_ok=1
    [ -f "/rom$L_CONF" ] && cp -f "/rom$L_CONF" "$L_CONF" && conf_ok=1
    
    # --- 3. Report Status ---
    printf "\n"
    [ $init_ok -eq 1 ] && print_success "Init Script restored" || print_error "Init Script missing in ROM"
    [ $bin_ok -eq 1 ]  && print_success "Binary restored"      || print_error "Binary missing in ROM"
    [ $conf_ok -eq 1 ] && print_success "Config yaml restored" || print_error "Config missing in ROM"
    printf "\n"

    # --- 4. Finalization Logic ---
    if [ $init_ok -eq 1 ] && [ $bin_ok -eq 1 ] && [ $conf_ok -eq 1 ]; then
        # Handle administrative state (UCI)
        if [ "$was_uci_enabled" -eq 1 ]; then
            uci set adguardhome.config.enabled='1' && uci set adguardhome.config.dns_enabled='1' && uci commit adguardhome
            $L_INIT enable >/dev/null 2>&1; sleep 1
            print_success "Full recovery successful! AdGuardHome auto-start re-enabled."
            printf "\n"
        else
            print_warning "AdGuardHome was disabled in UCI."
            printf "Enable AdGuardHome? [y/N]: "; read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then 
                uci set adguardhome.config.enabled='1' && uci set adguardhome.config.dns_enabled='1' && uci commit adguardhome
                $L_INIT enable >/dev/null 2>&1; sleep 1
                printf "\n"
                print_success "AdGuardHome enabled in GL Web UI and UCI."
                printf "\n"
                was_uci_enabled=1
            fi
        fi
        
        # Handle operational state (Running)
        if [ "$was_running" -eq 1 ]; then
            print_info "Automatically restarting service"
            $L_INIT start >/dev/null 2>&1; sleep 2; print_success "Service restored to running state."
        elif [ "$was_uci_enabled" -eq 1 ]; then
            print_warning "AdGuardHome is enabled but not running."
            printf "Start the service? [y/N]: "; read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then 
                printf "\n"
                print_info "Starting AdGuardHome"
                printf "\n"
                $L_INIT start >/dev/null 2>&1; sleep 2; print_success "Service started successfully."
            fi
        fi
    elif [ $init_ok -eq 1 ] || [ $bin_ok -eq 1 ] || [ $conf_ok -eq 1 ]; then
        print_warning "Partial recovery. Some files are still missing."
    else
        print_error "Recovery failed. Files not found in /rom or write error."
    fi
    press_any_key
}

get_agh_stats() {
    # 1. Basic Status Icons
    run_icon="$_S_OFF"; is_agh_running && run_icon="$_S_ON"
    local web_enabled=$(uci -q get adguardhome.config.enabled)
    web_icon="$_S_OFF"; [ "$web_enabled" = "1" ] && web_icon="$_S_ON"
    
    # 2. Setup Paths
    local AGH_CONFIG=$(get_agh_config)
    local workdir=$(get_agh_workdir)
    local data_dir="${workdir:-/etc/AdGuardHome}/data"

    # 3. List & Rules Logic
    # Count ENABLED lists only (installed + enabled), matching the rules count which
    # reflects what AGH actually loaded - a disabled list contributes neither.
    list_count=$(awk '
        /^filters:/ || /^whitelist_filters:/ {in_sec=1}
        /^[a-z_]+:/ && !/^filters:/ && !/^whitelist_filters:/ {in_sec=0}
        in_sec && /- enabled: true/ {c++}
        END {print c+0}
    ' "$AGH_CONFIG" 2>/dev/null)
    case "$list_count" in ''|*[!0-9]*) list_count=0 ;; esac
    if [ -z "$cached_rules" ]; then
        local raw_val=$(find "$data_dir/filters" -type f 2>/dev/null | xargs cat 2>/dev/null | wc -l)
        cached_rules=$(printf "$raw_val" | awk '{len=length($0); for(i=len-3;i>0;i-=3) $0=substr($0,1,i) "," substr($0,i+1); print $0}')
    fi

    # 4. Storage Metric: Filters
    filt_u=$(du -sh "$data_dir/filters" 2>/dev/null | awk '{print $1}')
    filt_f=$(get_free_space "$data_dir/filters")
    [ "$filt_f" = "0" ] && filt_f="0B"   # df prints a bare "0" at zero free; keep a unit

    # 5. Storage Metric: Query Logs (DBs + JSON)
    local q_bytes=0
    for f in "$data_dir/stats.db" "$data_dir/sessions.db" "$data_dir/querylog.json"; do
        [ -f "$f" ] && q_bytes=$((q_bytes + $(ls -nl "$f" | awk '{print $5}')))
    done
    qlog_u=$(awk "BEGIN {printf \"%.1fM\", ${q_bytes:-0}/1048576}")
    qlog_f=$(get_free_space "$data_dir")

    # 6. Backup Storage & Last Date (central store - see bk_* / BK_ROOT)
    local _bkd; _bkd=$(bk_dir agh)

    local bk_bytes=$(find "$_bkd" -type f -exec ls -nl {} + 2>/dev/null | awk '{sum += $5} END {print sum + 0}')

    bk_total_u=$(awk "BEGIN {
        mbs = $bk_bytes / 1048576;
        if (mbs > 0 && mbs < 0.1) printf \"0.01M\";
        else printf \"%.2fM\", mbs;
    }")

    bk_file_count=$(find "$_bkd" -type f 2>/dev/null | wc -l)

    local last_bk_file=$(ls -t "$_bkd"/config.yaml.* 2>/dev/null | head -n1)
    if [ -n "$last_bk_file" ]; then
        local ts=$(echo "$last_bk_file" | sed 's/.*\.//')
        bk_date="${ts:0:4}-${ts:4:2}-${ts:6:2}"
    else
        bk_date="None"
    fi

    # 7. Version Info
    v_num=$(/usr/bin/AdGuardHome --version 2>/dev/null | awk '{print $4}')
}

agh_control_center() {
    while true; do
        get_agh_stats
        clear
        print_centered_header "AdGuardHome Control Center"
        printf " ${CYAN}STATUS${RESET}\n   Run: %b  ·  GL WebUI: %b  ·  Version: v%s\n\n" "${run_icon:-$_S_OFF}" "${web_icon:-$_S_OFF}" "${v_num:-N/A}"
        printf " ${CYAN}FILTERS${RESET}\n   Lists: %s  ·  Rules: %s\n\n" "${list_count:-0}" "${cached_rules:-0}"
        printf " ${CYAN}STORAGE${RESET}\n   Filters: %s/%s  ·  Logs: %s/%s\n\n" "${filt_u:-0B}" "${filt_f:-N/A}" "${qlog_u:-0B}" "${qlog_f:-N/A}"
        printf " ${CYAN}BACKUP${RESET}\n   Date: %s  ·  Size: %s  ·  Files: %s\n\n" "${bk_date:-None}" "${bk_total_u:-0B}" "${bk_file_count:-0}"
        printf " ────────────────────────────────────────────────\n\n"
        local svc_label="Start AdGuardHome"
        is_agh_running && svc_label="Restart / Stop AdGuardHome"
        printf "%s%s%s\n" "$N1" "$NSEP" "$svc_label"
        printf "%s%sManage Allow/Blocklists\n" "$N2" "$NSEP"
        printf "%s%sAdvanced Settings\n" "$N3" "$NSEP"
        printf "%s%sBackup & Recovery Suite\n" "$N4" "$NSEP"
        printf "%s%sLogs & Maintenance\n" "$N5" "$NSEP"
        printf "%s Reset to Factory Settings (Start Over)\n" "$NCL"
        printf "%s%sMain menu\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-5/CL/0/?]: "
        read -r choice

        case "$choice" in
            1) agh_service_control ;;
            2) manage_agh_lists ;;
            3) sub_setup_config ;;
            4) sub_backup_recovery ;;
            5) sub_service_health ;;
            [cC][lL]) sub_confirm_factory_reset ;;
            0) break ;;
            \?|h|H|❓) show_agh_help ;;
            *) print_error "Invalid option"; sleep 1;;
        esac
    done
}

# -----------------------------
# System Tweaks
# -----------------------------

# --- Zram Swap Management ---

show_zram_help() {
    show_paged "Zram Swap - Help" << 'HELPEOF'
Zram Swap – Quick Help

What is zram swap?
──────────────────
Zram creates a compressed block device in your router's RAM and uses it as swap space. 
Instead of writing swap data to slow flash storage (which wears it out quickly), zram 
compresses the data and keeps it in RAM. This is much faster and protects your NAND/eMMC.

Main benefits on GL.iNet routers:
• Greatly improves performance when RAM is low (e.g. heavy VPN, AdGuardHome, many clients)
• Reduces lag and stuttering under memory pressure
• Does not use or impact the router's flash storage
• Uses minimal CPU overhead on modern router SoCs

Typical recommendations:
• 50% of total RAM is a good starting size (e.g. 256 MB on a 512 MB router)
• Most GL.iNet users enable it if they run AdGuardHome + VPN or have ≥10–15 devices connected

When should you use it?
Yes → if your router frequently runs out of RAM or you notice slowdowns
No  → if you have 1 GB+ RAM and very light usage

Important notes:
• Zram uses some CPU to compress/decompress → not ideal on very old/slow CPUs
• Data in zram is lost on reboot (normal for swap)
• Routers with 512MB flash or less will have a forced limit for AdGuardHome allow/block lists.

Reach this screen from System Tweaks, or from AdGuardHome -> Advanced Settings
-> Zram Swap (it pairs with the filter storage-space limit).

In this menu you can:
1. Install & enable zram swap
2. Disable it (stops and disables on boot)
3. Enable/Disable Persistence - survives firmware updates
4. Completely uninstall the package
HELPEOF
}

# Install and enable zram swap (shared by the Zram menu and the AGH Lists Manager
# onboarding so the two never diverge). Prints its own progress.
# Returns 0 if zram swap ends up active, 1 otherwise.
zram_install_enable() {
    if ! pkg_is_installed zram-swap; then
        install_package zram-swap || return 1
    fi
    if [ ! -f /etc/init.d/zram ]; then
        print_error "Zram init script not found"
        return 1
    fi
    print_info "Enabling and starting zram swap"
    /etc/init.d/zram enable >/dev/null 2>&1; sleep 1
    /etc/init.d/zram start >/dev/null 2>&1; sleep 2
    print_success "Zram swap enabled and started"
    if swapon -s 2>/dev/null | grep -q zram; then
        print_success "Zram swap is working correctly"
        return 0
    fi
    print_warning "Zram swap may not be working properly"
    return 1
}

manage_zram() {
    local up_conf="/etc/sysupgrade.conf"
    local laz_list="/etc/lazarus.list"

    while true; do
		hash -r
        zram_persisting=0
        if grep -qFx "/etc/init.d/zram" "$up_conf" 2>/dev/null; then
            zram_persisting=1
        fi

        clear
        print_centered_header "Zram Swap Management"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        if command -v zram >/dev/null 2>&1 || [ -f /etc/init.d/zram ]; then
            if /etc/init.d/zram enabled 2>/dev/null; then
                printf "   Zram Swap:   %bENABLED%b\n" "${GREEN}" "${RESET}"
                
                if [ -f /sys/block/zram0/disksize ]; then
                    disksize=$(cat /sys/block/zram0/disksize 2>/dev/null)
                    disksize_mb=$((disksize / 1024 / 1024))
                    printf "   Disk Size: %d MB\n" "$disksize_mb"
                fi
                
                if swapon -s 2>/dev/null | grep -q zram; then
                    printf "   Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                else
                    printf "   Status: %bINACTIVE%b\n" "${YELLOW}" "${RESET}"
                fi
            else
                printf "   Zram Swap:   %bDISABLED%b\n" "${YELLOW}" "${RESET}"
            fi
        else
            printf "   Zram Swap:   %bNOT INSTALLED%b\n" "${RED}" "${RESET}"
        fi
        if [ "$zram_persisting" -eq 1 ]; then
                printf "   Persistence: %bENABLED%b\n\n" "${GREEN}" "${RESET}"
            else
                printf "   Persistence: %bDISABLED%b\n\n" "${YELLOW}" "${RESET}"
        fi
        
        local zram_persist_label="Enable Persistence"
        [ "$zram_persisting" -eq 1 ] && zram_persist_label="Disable Persistence"
        printf "%s%sInstall and Enable\n" "$N1" "$NSEP"
        printf "%s%sDisable\n" "$N2" "$NSEP"
        printf "%s%s%s\n" "$N3" "$NSEP" "$zram_persist_label"
        printf "%s%sUninstall Package\n" "$N4" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-4/0/?]: "
        read -r zram_choice
        printf "\n"
        
        case $zram_choice in
            1)
                zram_install_enable
                press_any_key
                ;;
            2)
                if [ -f /etc/init.d/zram ]; then
                    /etc/init.d/zram stop >/dev/null 2>&1; sleep 1
                    /etc/init.d/zram disable >/dev/null 2>&1; sleep 1
                    print_success "Zram swap disabled and stopped"
                else
                    print_warning "Zram swap is not installed"
                fi
                press_any_key
                ;;
            3)
                if [ ! -f /etc/init.d/zram ]; then
                    print_error "Zram swap is not installed."
                else
                    local z_paths="/etc/init.d/zram /etc/config/system"
                    
                    if [ "$zram_persisting" -eq 0 ]; then
                        for p in $z_paths; do
                            grep -qFx "$p" "$up_conf" || echo "$p" >> "$up_conf"
                        done
                        grep -qFx "zram-swap" "$laz_list" 2>/dev/null || echo "zram-swap" >> "$laz_list"
                        create_lazarus_hook
                        print_success "Zram persistence enabled."
                    else
                        for p in $z_paths; do
                            sed -i "\|$p|d" "$up_conf" 2>/dev/null
                        done
                        sed -i "\|zram-swap|d" "$laz_list" 2>/dev/null
                        print_warning "Zram persistence disabled."
                    fi
                fi
                press_any_key
                ;;
            4)
                if pkg_is_installed zram-swap; then
                    printf "Remove zram-swap package? [y/N]: "
                    read -r confirm
                    printf "\n"
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        [ -f /etc/init.d/zram ] && /etc/init.d/zram stop >/dev/null 2>&1; sleep 1
                        pkg_remove zram-swap >/dev/null 2>&1
                        for p in /etc/init.d/zram /etc/config/system; do
                            sed -i "\|$p|d" "$up_conf" 2>/dev/null
                        done
                        sed -i "\|zram-swap|d" "$laz_list" 2>/dev/null
                        
                        print_success "zram-swap package removed"
                    else
                        printf "Removal cancelled."
                    fi
                else
                    print_warning "zram-swap package is not installed"
                fi
                press_any_key
                ;;
            \?|h|H|❓)
                show_zram_help
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# --- Fan Management Module ---

show_fan_help() {
    show_paged "Fan Management - Help" << 'HELPEOF'
Fan Management – Quick Help

How the Fan Controller Works:
─────────────────────────────
The /usr/bin/gl_fan process uses a PID-style controller to manage speed 
based on three primary temperature setpoints.

The Setpoints Explained:
• Minimum: The temperature where the fan starts spinning at its lowest 
  voltage. Setting this higher keeps the fan off longer.
• Fan-On: The "Target" temperature. The controller will ramp the fan up 
  toward 100% speed as it approaches and exceeds this value.
• Warning: Primarily used for system logs and UI alerts. Usually set 
  equal to or slightly higher than the Fan-On setpoint.
• Max: This script's custom "Unlock." It extends the slider range
  in the web interface, allowing you to set thresholds up to 120°C.

Thermal Hierarchy (Safety Rules):
─────────────────────────────────
To prevent logic loops, the following rules are enforced:
  Minimum ≤ Fan-On ≤ Max
  Warning must be between Minimum and Max.

Dynamic vs. Manual Mode:
• Dynamic: The system automatically adjusts RPM based on heat.
• Manual: Forces the fan to a specific percentage (0-100%). 
  Note: Manual mode persists until you re-enable Dynamic control.

Safety Warning:
────────────────
Extending limits beyond 100°C can lead to hardware throttling or 
emergency shutdowns. Most silicon is rated for ~105°C. Use 110°C+ 
only if you understand the thermal risks to your specific model.
HELPEOF
}

manage_fan_settings() {
    current_model=$(cat /proc/gl-hw-info/model)
    nav_choice=""

    reset_to_factory(){
        # The app bundle restored below is the SAME file the Web-UI Terminal
        # button is injected into, so this reset wipes the button. Note WHETHER
        # it was there before we clobber it, then put it back at the end - so a
        # fan change never silently removes the terminal. (This function runs on
        # every fan setpoint change, not just the explicit factory reset.)
        local _rtf_had_term=0
        local _rtf_app=$(find /www/js/ -name "app.*.js.gz" -type f | head -n 1)
        [ -n "$_rtf_app" ] && zcat "$_rtf_app" 2>/dev/null | grep -q "term-wrapper" && _rtf_had_term=1

        # 1. Restore the 'Engine' (The Library) and the 'Seed' (The ROM config)
        if [ -f "/rom/lib/functions/gl_util.sh" ]; then 
            cp "/rom/lib/functions/gl_util.sh" "/lib/functions/gl_util.sh"
        fi

        if [ -f "/rom/etc/config/glfan" ]; then 
            cp "/rom/etc/config/glfan" "/etc/config/glfan"
        fi
        
        # 2. Trigger the Internal Provisioner
        # This populates UCI with the REAL factory defaults for THIS specific model
        . /lib/functions/gl_util.sh
        fan_init
        uci commit glfan
        
        # 3. Restore Web UI Visuals & Logic from ROM
        if [ -f "/rom/www/views/gl-sdk4-ui-overview.common.js.gz" ]; then
            cp "/rom/www/views/gl-sdk4-ui-overview.common.js.gz" "/www/views/gl-sdk4-ui-overview.common.js.gz"
        fi
        
        local app_rom_gz=$(find /rom/www/js/ -name "app.*.js.gz" -type f | head -n 1)
        if [ -n "$app_rom_gz" ]; then
            cp "$app_rom_gz" "/www/js/$(basename "$app_rom_gz")"
        fi

        if [ -f "/rom/www/i18n/gl-sdk4-ui-overview.en.json" ]; then
            cp "/rom/www/i18n/gl-sdk4-ui-overview.en.json" "/www/i18n/gl-sdk4-ui-overview.en.json"
        fi
        
        /etc/init.d/gl_fan restart >/dev/null 2>&1

        # Put the Web-UI Terminal button back if it was there before the restore.
        # from_rom=0: append onto the bundle we just restored, so this coexists
        # with any fan patches a caller applies afterwards rather than resetting
        # the file yet again.
        if [ "$_rtf_had_term" = 1 ] && [ -n "$_rtf_app" ]; then
            _inject_terminal_into "$_rtf_app" \
                "$(grep -q "option ssl '1'" /etc/config/ttyd 2>/dev/null && echo https || echo http)" 0
        fi
    }

    sync_system_and_ui() {
        # Start at a good working state
        reset_to_factory       
        
        local n_min=$1  # Minimum (The Floor)
        local n_cur=$2  # Fan-On (The current target)
        local n_wrn=$3  # Warning (The visual/system trigger)
        local n_max=$4  # Maximum (The Ceiling)
        
        local b_min=$((n_min - 1)) 
        local b_max=$((n_max + 1))
        local util_file="/lib/functions/gl_util.sh"

        # --- 1. System Logic & Backend Variable Sync ---
        # Patch the hardware floor comparisons in the fan control library
        sed -i "s/-lt 6[0-9]/-lt $n_min/g" "$util_file"
        sed -i "s/-lt 7[0-9]/-lt $n_min/g" "$util_file"

        # Use the model identifier to target the correct code block for assignments
        if awk "/$current_model[)]/,/;;/" "$util_file" | grep -q "temperature="; then
            sed -i "/$current_model[)]/,/;;/ s/\(minimum_temperature=\)[0-9]*/\1$n_min/" "$util_file"
            sed -i "/$current_model[)]/,/;;/ s/\([[:space:]]temperature=\)[0-9]*/\1$n_cur/" "$util_file"
        else
            sed -i "s/\(local minimum_temperature=\)[0-9]*/\1$n_min/" "$util_file"
            sed -i "s/\(local temperature=\)[0-9]*/\1$n_cur/" "$util_file"
        fi
        sed -i "s/warn_temperature=.*$/warn_temperature=\"$n_wrn\"/" "$util_file"

        # --- 2. UCI Persistence ---
        uci set glfan.globals.minimum_temperature="$n_min"
        uci set glfan.globals.temperature="$n_cur"
        uci set glfan.globals.warn_temperature="$n_wrn"
        uci commit glfan

        # --- 3. View Component Patching (UI Logic & Visuals) ---
        local view_gz="/www/views/gl-sdk4-ui-overview.common.js.gz"
        [ ! -f "$view_gz" ] && cp "/rom$view_gz" "$view_gz"
        gunzip -f "$view_gz"
        local v="/www/views/gl-sdk4-ui-overview.common.js"

        # SECTION A: Computed Property Overrides (Dynamic Shadowing)
        sed -i "s/minimum_temperature:t/minimum_temperature:ignore,t=$n_min/g" "$v"
        sed -i "s/maximum_temperature:t/maximum_temperature:ignore,t=$n_max/g" "$v"
        sed -i "s/maximumTemperature:()=>[0-9]*/maximumTemperature:()=>$n_max/g" "$v"

        # SECTION B: Literal Logic Guards (Integer Boundaries)
        sed -i "s/t<70/t<$n_min/g" "$v"
        sed -i "s/t>90/t>$n_max/g" "$v"
        sed -i "s/ature=70/ature=$n_min/g" "$v"
        sed -i "s/ature=90/ature=$n_max/g" "$v"

        # SECTION C: Universal Component Logic (Snap-Back Prevention)
        sed -i "s/t<this.minimumTemperature/t<$n_min/g" "$v"
        sed -i "s/t>this.maximumTemperature/t>$n_max/g" "$v"
        sed -i "s/this.temperature=this.minimumTemperature/this.temperature=$n_min/g" "$v"
        sed -i "s/this.temperature=this.maximumTemperature/this.temperature=$n_max/g" "$v"

        # SECTION D: Physical Slider Attributes (Visual Buffer)
        sed -i "s/attrs:{min:[^,]*[0-9a-zA-Z.-]*,max:[0-9a-zA-Z.+-]*/attrs:{min:$b_min,max:$b_max/g" "$v"

        # SECTION E: Slider Scale & Step Labels
        local marks_obj="${n_min}:'${n_min}°C'"
        local span=$((n_max - n_min))
        local interval=10
        [ "$span" -le 50 ] && interval=5
        for i in $(seq $((n_min + $interval)) "$interval" "$n_max"); do
            marks_obj="$marks_obj,$i:'$i°C'"
        done
        sed -i "s/marks:t.tMarks/marks:{$marks_obj}/g" "$v"

        # SECTION F: Information Strings (Info Box / Localization)
        # The pristine string is a template - "fan start is $$$$ ~ $$$$ ." - so
        # replacing it with literals is what pins the displayed range.
        #
        # The view-bundle sed below currently matches nothing: 0 occurrences on
        # every firmware we have (4.3.25 through OpenWrt 25) versus exactly 1 in
        # the i18n JSON. It is KEPT DELIBERATELY - our oldest device is fanless,
        # so the fan path has never been exercised on early firmware and we
        # cannot show the phrase was never in the view there. It costs nothing.
        local info_pattern="fan start is [^.]*"
        local info_replacement="fan start is $n_min °C ~ $n_max °C "
        sed -i "s/$info_pattern/$info_replacement/g" "$v"
        [ -f "/www/i18n/gl-sdk4-ui-overview.en.json" ] && \
        sed -i "s/$info_pattern/$info_replacement/g" "/www/i18n/gl-sdk4-ui-overview.en.json"

        # --- 4. Global Application Controller Patch (Validator Range) ---
        local app_gz=$(find /www/js/ -name "app.*.js.gz" -type f | head -n 1)
        if [ -n "$app_gz" ]; then
            gunzip -f "$app_gz"
            local app_file="${app_gz%.gz}"
            # Unlock the global validator range
            sed -i "s/[0-9]\{1,3\}||i<[0-9]\{2,3\}/${n_min}||i<$((n_max + 1))/g" "$app_file"
            # Prevent initial state snap-back on page load
            sed -i "s/temperature:6[90]/temperature:$n_cur/g" "$app_file"
            sed -i "s/temperature:76/temperature:$n_cur/g" "$app_file"
            gzip -f "$app_file"
        fi

        # 5. Deployment
        gzip -f "$v"
        /etc/init.d/gl_fan restart
    }
    
    clear
    printf '\033[?25l'
    
    while true; do
        
        # 1. State Capture & Fanless Detection
        has_fan=true
        [ ! -d "/sys/class/thermal/cooling_device0" ] && has_fan=false

        c_mode="DYNAMIC (System)"
        c_mode_color="${GREEN}"
        if ! pgrep -f '/usr/bin/gl_fan' >/dev/null; then
            c_mode="MANUAL (Static)"
            c_mode_color="${YELLOW}"
        fi
        
        c_temp_fmt=$(get_cpu_temp)
        c_fan_rpm="N/A"
        c_speed_pct=0
        
        if [ "$has_fan" = "true" ]; then
            c_fan_rpm=$(get_fan_speed)
            c_pwm=$(cat /sys/class/thermal/cooling_device0/cur_state 2>/dev/null)
            [ -z "$c_pwm" ] && c_pwm=0
            c_speed_pct=$(( (c_pwm * 100 + 127) / 255 ))
        fi

        # 2. Get Current UI Max Setpoint
        local view_gz="/www/views/gl-sdk4-ui-overview.common.js.gz"
        local util_file="/lib/functions/gl_util.sh"
        local attrs_block=$(gzip -dc "$view_gz" 2>/dev/null | grep -oE "attrs:\{min:[-0-9]+,max:[0-9]+")

        if [ -n "$attrs_block" ]; then
            raw_min=$(echo "$attrs_block" | cut -d: -f3 | cut -d, -f1)
            raw_max=$(echo "$attrs_block" | cut -d: -f4)
            u_min=$((raw_min + 1))
            ui_max=$((raw_max - 1))
        else
            u_min=$(gzip -dc "$view_gz" 2>/dev/null | grep -oE "minimumTemperature:[^}]*" | grep -oE "[0-9]{2,3}" | head -n 1)
            ui_max=$(gzip -dc "$view_gz" 2>/dev/null | grep -oE "maximumTemperature:[^}]*" | grep -oE "[0-9]{2,3}" | head -n 1)
        fi

        # --- 3. UCI Configuration State (The "Truth") ---
        u_cur=$(uci -q get glfan.globals.temperature)
        u_wrn=$(uci -q get glfan.globals.warn_temperature)

        # --- 4. Sanitization & Fallbacks ---
        [ -z "$u_min" ] && u_min=70
        [ -z "$ui_max" ] && ui_max=90
        [ -z "$u_cur" ] && u_cur=75
        [ -z "$u_wrn" ] && u_wrn=75

        printf '\033[H'
        print_centered_header "Fan Management"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        if [ "$has_fan" = "false" ]; then
            printf "   Hardware:          %bNOT DETECTED (Fanless Unit)%b\033[K\n" "${RED}" "${RESET}"
        else
            printf "   Control Mode:      %b%s%b\033[K\n" "$c_mode_color" "$c_mode" "${RESET}"
            printf "   Current Speed:     %d%% (%s RPM)\033[K\n" "$c_speed_pct" "$c_fan_rpm"
        fi
        printf "   Temperature:       %b%s°C%b\033[K\n\n" "${WHITE}" "$c_temp_fmt" "${RESET}"

        printf " %b\n" "${CYAN}SYSTEM & WEB UI SETTINGS${RESET}"
        printf "   Minimum Setpoint:  %s°C\033[K\n" "${u_min:-UNKNOWN}"
        printf "   Fan-On Setpoint:   %s°C\033[K\n" "${u_cur:-UNKNOWN}"
        printf "   Warning Setpoint:  %s°C\033[K\n" "${u_wrn:-UNKNOWN}"
        printf "   Max Setpoint:      %b%s°C%b\033[K\n\n" "${YELLOW}" "$ui_max" "${RESET}"

        if [ "$has_fan" = "false" ]; then
            print_warning "Fan settings are disabled on fanless hardware.\033[K"
            printf "%s%sBack\033[K\n" "$N0" "$NSEP"
            printf "\nChoose [0/?]: \033[K"
        else
            printf "%s%sSet Static Fan Speed (0-100%%)\033[K\n" "$N1" "$NSEP"
            printf "%s%sEnable Dynamic Fan Control\033[K\n" "$N2" "$NSEP"
            printf "%s%sSet Minimum Setpoint\033[K\n" "$N3" "$NSEP"
            printf "%s%sSet Fan-On Setpoint\033[K\n" "$N4" "$NSEP"
            printf "%s%sSet Warning Setpoint\033[K\n" "$N5" "$NSEP"
            printf "%s%sSet Maximum Setpoint\033[K\n" "$N6" "$NSEP"
            printf "%s%sReset to Factory Defaults\033[K\n" "$N7" "$NSEP"
            printf "%s%sBack\033[K\n" "$N0" "$NSEP"
            printf "%s Help\033[K\n" "$NQ"
            printf "\nChoose [1-7/0/?]: \033[K"
        fi
               
        printf '\033[?25h'
        read -t 1 -n 1 fan_choice
        printf "\n"

        if [ -n "$fan_choice" ]; then
            current_choice="$fan_choice"
            fan_choice=""
            printf "\n"
        
            if [ "$has_fan" = "false" ]; then
                case "$current_choice" in
                    0) return ;;
                    \?|h|H|❓) show_fan_help; continue ;;
                    *) continue ;;
                esac
            fi

            case "$current_choice" in
                1)
                    printf "Enter Speed %% (0-100): "
                    read -r pct
                    printf "\n"
                    pct=$(echo "$pct" | tr -dc '0-9')
                    if [ -n "$pct" ] && [ "$pct" -le 100 ]; then
                        /etc/init.d/gl_fan stop >/dev/null 2>&1
                        echo "$(( (pct * 255 + 50) / 100 ))" > /sys/class/thermal/cooling_device0/cur_state
                        print_success "Manual mode active: $pct%"
                    else
                        print_error "Invalid input."
                    fi
                    press_any_key; clear ;;
                2)
                    /etc/init.d/gl_fan enable >/dev/null 2>&1
                    /etc/init.d/gl_fan restart >/dev/null 2>&1
                    print_success "Dynamic control restored"
                    press_any_key; clear ;;
                3)
                    printf "Set new Minimum Setpoint (0°C - %s°C): " "$u_cur"
                    read -r val
                    val=$(echo "$val" | tr -dc '0-9')
                    if [ -n "$val" ] && [ "$val" -le "$u_cur" ]; then
                        sync_system_and_ui "$val" "$u_cur" "$u_wrn" "$ui_max"
                        printf "\n"
                        print_success "Minimum setpoint updated to ${val}°C (System & UI)."
                        print_info "Hard-refresh the admin panel (Ctrl/Cmd-Shift-R) to see it - a plain reload may serve the cached copy."
                    else
                        printf "\n"
                        print_error "Must be a number and ≤ Fan-On ($u_cur°C)"
                    fi
                    press_any_key; clear ;;
                4)
                    printf "New Fan-On Setpoint (%s°C - %s°C): " "$u_min" "$ui_max"
                    read -r val
                    printf "\n"
                    val=$(echo "$val" | tr -dc '0-9')
                    if [ -n "$val" ] && [ "$val" -ge "$u_min" ] && [ "$val" -le "$ui_max" ]; then
                        sync_system_and_ui "$u_min" "$val" "$u_wrn" "$ui_max"
                        printf "\n"
                        print_success "Fan-On setpoint updated"
                        print_info "Hard-refresh the admin panel (Ctrl/Cmd-Shift-R) to see it - a plain reload may serve the cached copy."
                    else
                        printf "\n"
                        print_error "Must be between Min ($u_min°C) and Max ($ui_max°C)"
                    fi
                    press_any_key; clear ;;
                5)
                    printf "New Warning Setpoint (%s°C - %s°C): " "$u_min" "$ui_max"
                    read -r val
                    printf "\n"
                    val=$(echo "$val" | tr -dc '0-9')
                    if [ -n "$val" ] && [ "$val" -ge "$u_min" ] && [ "$val" -le "$ui_max" ]; then
                        sync_system_and_ui "$u_min" "$u_cur" "$val" "$ui_max"
                        printf "\n"
                        print_success "Warning setpoint updated"
                        print_info "Hard-refresh the admin panel (Ctrl/Cmd-Shift-R) to see it - a plain reload may serve the cached copy."
                    else
                        printf "\n"
                        print_error "Must be between Min ($u_min°C) and Max ($ui_max°C)"
                    fi
                    press_any_key; clear ;;
                6)
                    print_warning "DANGER: EXTENDING AND SETTING THERMAL LIMITS PAST 90°C MAY CAUSE DAMAGE TO YOUR DEVICE!"
                    printf "Set new Maximum Setpoint (%s°C - 120°C): " "$u_cur"
                    read -r val
                    val=$(echo "$val" | tr -dc '0-9')
                    if [ -n "$val" ] && [ "$val" -ge "$u_cur" ] && [ "$val" -le 120 ]; then
                        if [ "$val" -lt $u_wrn ]; then
                            printf "\n"
                            print_warning "New Max is below current Warning setpoint. Adjusting Warning to match new Max."
                            printf "\n"
                            u_wrn="$val"
                        fi
                        sync_system_and_ui "$u_min" "$u_cur" "$u_wrn" "$val"
                        printf "\n"
                        print_success "Max setpoint updated to ${val}°C."
                        print_info "Hard-refresh the admin panel (Ctrl/Cmd-Shift-R) to see it - a plain reload may serve the cached copy."
                    else
                        printf "\n"
                        print_error "Must be between Fan-On ($u_cur°C) and 120°C"
                    fi
                    press_any_key; clear ;;
                7)
                    print_warning "Restoring to Factory Defaults"
                    reset_to_factory
                    printf "\n"
                    print_success "Factory defaults restored."
                    print_info "Hard-refresh the admin panel (Ctrl/Cmd-Shift-R) to see it - a plain reload may serve the cached copy."
                    press_any_key; clear ;;
                0) return ;;
                \?|h|H|❓) show_fan_help; clear; continue ;;
                *) print_error "Invalid option"; sleep 1; clear ;;
            esac
            printf "\033[?25l"
        fi
    done
}

# Set HW Acceleration
# To Disable: set_hw_accel 0
# To Disable and disabled web-UI toggle: set_hw_accel 0 restrict
# To Enable:  set_hw_accel 1

set_hw_accel() {
    local target_state=$1  # 0 (Off) or 1 (On)
    local mode=$2          # "restrict" to disable web-UI toggle
    local kicked=0

    # --- A. PRE-FLIGHT & UI LOCK MANAGEMENT ---
    if [ "$target_state" = "1" ]; then
        # 1. Precision Check: Block enable if REAL user QoS rules exist
        local real_limits=$(uci show qos | grep "\.mac=" | grep -v "00:00:00:00:00:00" | wc -l)
        if [ "$real_limits" -gt 0 ]; then
            return 1
        fi
        
        # 2. Surgical Unlock: Remove our padlock 
        uci -q delete qos.000000000000
        local idx=0
        while [ -n "$(uci -q get qos.@client[$idx])" ]; do
            if [ "$(uci -q get qos.@client[$idx].mac)" = "00:00:00:00:00:00" ]; then
                uci delete qos.@client[$idx]
            else
                idx=$((idx + 1))
            fi
        done
        uci commit qos
    else
        # 3. Handle Disabling: Apply UI padlock only if in 'restrict' mode
        if [ "$mode" = "restrict" ]; then
            uci set qos.000000000000=queue
            uci set qos.000000000000.mac='00:00:00:00:00:00'
            uci set qos.000000000000.download='1000000'
            uci set qos.000000000000.upload='1000000'
            uci set qos.000000000000.cnt='1'
            uci commit qos
        else
            uci -q delete qos.000000000000
            local idx=0
            while [ -n "$(uci -q get qos.@client[$idx])" ]; do
                if [ "$(uci -q get qos.@client[$idx].mac)" = "00:00:00:00:00:00" ]; then
                    uci delete qos.@client[$idx]
                else
                    idx=$((idx + 1))
                fi
            done
            uci commit qos
        fi
    fi
    
    # 1. OPENWRT FIREWALL OFFLOADING
    # Skip raw firewall offload on Qualcomm/ECM routers to prevent Web UI bugs
    if [ ! -f "/etc/config/ecm" ]; then
        uci -q set firewall.@defaults[0].flow_offloading="$target_state"
        uci -q set firewall.@defaults[0].flow_offloading_hw="$target_state"
        uci -q set firewall.@defaults[0].nss_offloading="$target_state"
        uci commit firewall
    fi

    # 2. HARDWARE SPECIFIC: Qualcomm 
    if [ -f "/etc/config/ecm" ] && [ -x "/etc/init.d/qca-nss-ecm" ]; then
        uci set ecm.global.enabled="$target_state"
        uci commit ecm
        if [ "$target_state" = "0" ]; then
            /etc/init.d/qca-nss-ecm stop
            [ -e /sys/kernel/debug/ecm/ecm_db/defunct_all ] && echo 1 > /sys/kernel/debug/ecm/ecm_db/defunct_all
        else
            /etc/init.d/qca-nss-ecm start
        fi
        kicked=1
    fi

    # 3. HARDWARE SPECIFIC: MediaTek 
    if [ -f "/etc/config/mtkhnat" ] && [ -x "/etc/init.d/mtk-hwnat-post" ]; then
        uci set mtkhnat.global.enable="$target_state"
        uci commit mtkhnat
        if [ "$target_state" = "0" ]; then
            /etc/init.d/mtk-hwnat-post stop
        else
            /etc/init.d/mtk-hwnat-post start
        fi
        kicked=1
    fi

    # 4. THE CATCH-ALL: Standard/Beryl (MT1300) or Unknown
    if [ "$kicked" -eq 0 ]; then
        /etc/init.d/firewall reload >/dev/null 2>&1
    fi

    # 5. UI SYNC: Ensure gl_eqos picks up the ghost changes immediately
    [ -x /usr/bin/gl_eqos ] && /usr/bin/gl_eqos restart >/dev/null 2>&1
}

# --- Network Bandwidth Limiter (generalized: shapes any discovered LAN/guest/IoT/VLAN/VPN) --
# One interface-generic engine (extracted + unit-tested as netlimit_engine/service). tc/IFB
# HTB scheme (2% DL / 4% UL overhead) applied per $iface.
NETLIMIT_CONF="${NETLIMIT_CONF:-/etc/netlimit.conf}"
NETLIMIT_INIT="${NETLIMIT_INIT:-/etc/init.d/netlimit}"
NETLIMIT_GUEST_OLD="${NETLIMIT_GUEST_OLD:-/etc/init.d/guest_limiter}"
NL_MAP="${NL_MAP:-/tmp/netlimit_map}"

_netlimit_hash() {
    awk 'function ord(c){return index(CH,c)}
         BEGIN{ for(i=1;i<256;i++) CH=CH sprintf("%c",i);
                s=ARGV[1]; h=5381;
                for(i=1;i<=length(s);i++) h=(h*33+ord(substr(s,i,1)))%2000000011;
                printf "%d", h }' "$1"
}
netlimit_ifbname() {
    local iface="$1" name="${1}-ifb"
    if [ "${#name}" -le 15 ]; then printf '%s' "$name"; else printf 'ifb%s' "$(_netlimit_hash "$iface")"; fi
}
netlimit_tc_apply_cmds() {   # <iface> <dl_mbit> <ul_mbit>
    local iface="$1" dl="${2:-0}" ul="${3:-0}" ifb; ifb=$(netlimit_ifbname "$iface")
    case "$dl" in ''|*[!0-9]*) dl=0 ;; esac; case "$ul" in ''|*[!0-9]*) ul=0 ;; esac
    local dl_kbit=$(( dl * 1020 )) ul_kbit=$(( ul * 1040 ))
    if [ "$ul" -gt 0 ]; then
        echo "ip link add dev $ifb type ifb"
        echo "ip link set dev $ifb up"
        echo "tc qdisc add dev $ifb root handle 1: htb default 1"
        echo "tc class add dev $ifb parent 1: classid 1:1 htb rate ${ul_kbit}kbit ceil ${ul_kbit}kbit burst 15k cbuffer 15k"
        echo "tc qdisc add dev $iface clsact"
        echo "tc filter add dev $iface ingress protocol ip u32 match u32 0 0 action mirred egress redirect dev $ifb"
        echo "tc filter add dev $iface ingress protocol ipv6 u32 match u32 0 0 action mirred egress redirect dev $ifb"
    fi
    if [ "$dl" -gt 0 ]; then
        echo "tc qdisc add dev $iface root handle 1: htb default 1"
        echo "tc class add dev $iface parent 1: classid 1:1 htb rate ${dl_kbit}kbit ceil ${dl_kbit}kbit burst 15k cbuffer 15k"
    fi
}
netlimit_tc_clear_cmds() {   # <iface>
    local iface="$1" ifb; ifb=$(netlimit_ifbname "$iface")
    echo "tc qdisc del dev $iface root 2>/dev/null"
    echo "tc qdisc del dev $iface clsact 2>/dev/null"
    echo "ip link set dev $ifb down 2>/dev/null"
    echo "ip link del dev $ifb 2>/dev/null"
}
netlimit_zone_of() {   # <network-name> -> firewall zone
    local net="$1" i=0 zn nets m
    while true; do
        zn=$(uci -q get "firewall.@zone[$i].name") || break
        nets=$(uci -q get "firewall.@zone[$i].network")
        for m in $nets; do [ "$m" = "$net" ] && { printf '%s' "$zn"; return 0; }; done
        i=$((i+1))
    done
    return 1
}
netlimit_discover() {   # emits name|iface|type|zone per shapeable network
    local dump names name dev up proto type zone
    # </dev/null: ubus reads stdin and would BLOCK on a real TTY / eat the menu keystroke.
    dump=$(ubus call network.interface dump 2>/dev/null </dev/null); [ -z "$dump" ] && return 1
    names=$(printf '%s' "$dump" | jsonfilter -e '@.interface[*].interface' 2>/dev/null); [ -z "$names" ] && return 1
    printf '%s\n' "$names" | while read -r name; do
        [ -z "$name" ] && continue
        case "$name" in loopback|lo|wan|wan6|wan_*|wwan*|modem*) continue ;; esac
        up=$(printf '%s'  "$dump" | jsonfilter -e "@.interface[@.interface=\"$name\"].up"        2>/dev/null | head -1)
        [ "$up" != "true" ] && continue
        dev=$(printf '%s' "$dump" | jsonfilter -e "@.interface[@.interface=\"$name\"].l3_device" 2>/dev/null | head -1)
        [ -z "$dev" ] && dev=$(printf '%s' "$dump" | jsonfilter -e "@.interface[@.interface=\"$name\"].device" 2>/dev/null | head -1)
        [ -z "$dev" ] && continue
        proto=$(printf '%s' "$dump" | jsonfilter -e "@.interface[@.interface=\"$name\"].proto" 2>/dev/null | head -1)
        type=""
        case "$proto" in wireguard|openvpn) type=vpn ;; esac
        case "$dev"   in wg*|tun*|ovpn*|tap*) type=vpn ;; esac
        [ -z "$type" ] && case "$name" in guest*) type=guest ;; iot*) type=iot ;; lan) type=lan ;; esac
        # GL VLAN subnets present as a bridge device (br-vlanN) but carry a vlan_id - classify by
        # that, else the br-* case below would mislabel them 'bridge' (so they'd not be toggleable).
        [ -z "$type" ] && [ -n "$(uci -q get "network.$name.vlan_id" 2>/dev/null)" ] && type=vlan
        [ -z "$type" ] && case "$dev" in br-*) type=bridge ;; *.*) type=vlan ;; *) type=iface ;; esac
        zone=$(netlimit_zone_of "$name")
        [ "$zone" = "wan" ] && continue
        printf '%s|%s|%s|%s\n' "$name" "$dev" "$type" "${zone:-}"
    done
}
netlimit_discover_disabled() {   # emits name|dev|type|zone for CONFIGURED-BUT-DISABLED guest/iot/vlan
    # netlimit_discover reads `ubus network.interface dump`, which OMITS disabled interfaces entirely,
    # so a switched-off guest/iot network never appears there. Read those from uci instead, classify
    # with the SAME rules, and keep ONLY the guest/iot/vlan class - that allow-list is what filters
    # out the pile of disabled wan6/tethering6/modem_*/secondwan* noise a router accumulates.
    local name proto dev type zone
    uci -q show network 2>/dev/null | sed -n "s/^network\.\([A-Za-z0-9_]*\)\.disabled='1'\$/\1/p" | while read -r name; do
        [ -z "$name" ] && continue
        case "$name" in loopback|lo|wan|wan6|wan_*|wwan*|modem*|tethering*|secondwan*) continue ;; esac
        proto=$(uci -q get "network.$name.proto")
        dev=$(uci -q get "network.$name.device"); [ -z "$dev" ] && dev="br-$name"
        type=""
        case "$proto" in wireguard|openvpn|wgclient|wgserver|ovpnclient|ovpnserver) type=vpn ;; esac
        case "$dev"   in wg*|tun*|ovpn*|tap*) type=vpn ;; esac
        [ -z "$type" ] && case "$name" in guest*) type=guest ;; iot*) type=iot ;; esac
        [ -z "$type" ] && [ -n "$(uci -q get "network.$name.vlan_id" 2>/dev/null)" ] && type=vlan
        [ -z "$type" ] && case "$dev"  in *.*) type=vlan ;; esac
        case "$type" in guest|iot|vlan) ;; *) continue ;; esac   # allow-list: everything else stays hidden
        zone=$(netlimit_zone_of "$name")
        printf '%s|%s|%s|%s\n' "$name" "$dev" "$type" "${zone:-}"
    done
}
netlimit_conf_list()  { [ -f "$NETLIMIT_CONF" ] && grep -vE '^#|^[[:space:]]*$' "$NETLIMIT_CONF"; return 0; }
netlimit_conf_get()   { netlimit_conf_list | awk -F'|' -v i="$1" '$1==i{print; exit}'; }
netlimit_conf_field() { netlimit_conf_get "$1" | cut -d'|' -f"$2"; }
netlimit_conf_put()   { # iface dl ul webui persist
    local tmp="${NETLIMIT_CONF}.$$"
    { netlimit_conf_list | awk -F'|' -v i="$1" '$1!=i'
      printf '%s|%s|%s|%s|%s\n' "$1" "${2:-0}" "${3:-0}" "${4:-0}" "${5:-0}"; } > "$tmp" && mv "$tmp" "$NETLIMIT_CONF"
}
netlimit_conf_del()   {
    local tmp="${NETLIMIT_CONF}.$$"
    netlimit_conf_list | awk -F'|' -v i="$1" '$1!=i' > "$tmp" && mv "$tmp" "$NETLIMIT_CONF"
    [ -s "$NETLIMIT_CONF" ] || rm -f "$NETLIMIT_CONF"
}
netlimit_any_limited() { netlimit_conf_list | awk -F'|' '($2+0)>0||($3+0)>0{n++} END{exit !n}'; }
netlimit_service_write() {
    cat > "$NETLIMIT_INIT" <<'INITEOF'
#!/bin/sh /etc/rc.common
# netlimit - per-interface bandwidth limiter (generated by glinet_utils; do not edit).
START=99
STOP=10
CONF=/etc/netlimit.conf
_ifbname() {
    local n="${1}-ifb"
    if [ "${#n}" -le 15 ]; then printf '%s' "$n"; else
        printf 'ifb%s' "$(awk 'function ord(c){return index(CH,c)} BEGIN{for(i=1;i<256;i++)CH=CH sprintf("%c",i);s=ARGV[1];h=5381;for(i=1;i<=length(s);i++)h=(h*33+ord(substr(s,i,1)))%2000000011;printf "%d",h}' "$1")"
    fi
}
_apply() {
    local iface="$1" dl="$2" ul="$3" ifb dk uk; ifb=$(_ifbname "$iface"); dk=$((dl*1020)); uk=$((ul*1040))
    if [ "$ul" -gt 0 ]; then
        ip link add dev "$ifb" type ifb; ip link set dev "$ifb" up
        tc qdisc add dev "$ifb" root handle 1: htb default 1
        tc class add dev "$ifb" parent 1: classid 1:1 htb rate ${uk}kbit ceil ${uk}kbit burst 15k cbuffer 15k
        tc qdisc add dev "$iface" clsact
        tc filter add dev "$iface" ingress protocol ip   u32 match u32 0 0 action mirred egress redirect dev "$ifb"
        tc filter add dev "$iface" ingress protocol ipv6 u32 match u32 0 0 action mirred egress redirect dev "$ifb"
    fi
    if [ "$dl" -gt 0 ]; then
        tc qdisc add dev "$iface" root handle 1: htb default 1
        tc class add dev "$iface" parent 1: classid 1:1 htb rate ${dk}kbit ceil ${dk}kbit burst 15k cbuffer 15k
    fi
}
_clear() {
    local iface="$1" ifb; ifb=$(_ifbname "$iface")
    tc qdisc del dev "$iface" root   2>/dev/null
    tc qdisc del dev "$iface" clsact 2>/dev/null
    ip link set dev "$ifb" down 2>/dev/null
    ip link del dev "$ifb"      2>/dev/null
}
_flush() {
    [ -x /etc/init.d/mtk-hwnat ]   && /etc/init.d/mtk-hwnat   restart 2>/dev/null
    [ -x /etc/init.d/shortcut-fe ] && /etc/init.d/shortcut-fe restart 2>/dev/null
    [ -x /etc/init.d/bridger ]     && /etc/init.d/bridger     restart >/dev/null 2>&1
}
_rows() { [ -f "$CONF" ] && grep -vE '^#|^[[:space:]]*$' "$CONF"; }
start() {
    _rows | while IFS='|' read -r iface dl ul webui persist; do
        [ -z "$iface" ] && continue
        case "$dl" in ''|*[!0-9]*) dl=0 ;; esac; case "$ul" in ''|*[!0-9]*) ul=0 ;; esac
        [ "$dl" -eq 0 ] && [ "$ul" -eq 0 ] && continue
        i=0; while [ ! -d "/sys/class/net/$iface" ] && [ "$i" -lt 30 ]; do sleep 1; i=$((i+1)); done
        _clear "$iface"; _apply "$iface" "$dl" "$ul"
    done
    _flush
}
stop() {
    _rows | while IFS='|' read -r iface rest; do [ -n "$iface" ] && _clear "$iface"; done
    _flush
}
INITEOF
    chmod +x "$NETLIMIT_INIT"
}
netlimit_reload() {
    [ -f "$NETLIMIT_INIT" ] || netlimit_service_write
    "$NETLIMIT_INIT" enable  >/dev/null 2>&1
    "$NETLIMIT_INIT" restart >/dev/null 2>&1
}
netlimit_persist_sync() {
    local sc=/etc/sysupgrade.conf
    sed -i '\|/etc/init.d/netlimit|d; \|/etc/netlimit.conf|d' "$sc" 2>/dev/null
    if netlimit_conf_list | awk -F'|' '($5+0)>0{n++} END{exit !n}'; then
        grep -qxF '/etc/init.d/netlimit' "$sc" 2>/dev/null || echo '/etc/init.d/netlimit' >> "$sc"
        grep -qxF '/etc/netlimit.conf'   "$sc" 2>/dev/null || echo '/etc/netlimit.conf'   >> "$sc"
    fi
}
# Shaping needs the software path: offload OFF whenever any limit is active, ON when none.
# Uses the toolkit's set_hw_accel so GL's qos padlock is handled.
netlimit_offload_sync() {
    if netlimit_any_limited; then set_hw_accel 0 restrict >/dev/null 2>&1; else set_hw_accel 1 >/dev/null 2>&1; fi
}
netlimit_set() {   # iface dl ul  (0/0 removes)
    local i="$1" dl="${2:-0}" ul="${3:-0}" wb ps
    wb=$(netlimit_conf_field "$i" 4); ps=$(netlimit_conf_field "$i" 5)
    # Clear this interface's live shaping FIRST: on removal the row is gone before the service
    # restarts, so the service's stop() (which only clears rows still in the config) would
    # otherwise orphan it. On a change/set the reload re-applies from the new config.
    netlimit_tc_clear_cmds "$i" | sh 2>/dev/null
    if [ "$dl" -eq 0 ] && [ "$ul" -eq 0 ]; then netlimit_conf_del "$i"
    else netlimit_conf_put "$i" "$dl" "$ul" "${wb:-0}" "${ps:-0}"; fi
    netlimit_service_write; netlimit_offload_sync; netlimit_reload; netlimit_persist_sync
}
netlimit_lan_ip() { ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1; }
# input policy (ACCEPT|REJECT|DROP) of a firewall zone -------------------------------------
netlimit_zone_input() {   # <zone-name>
    local zone="$1" i=0 zn
    [ -z "$zone" ] && return 1
    while zn=$(uci -q get "firewall.@zone[$i].name"); do
        [ "$zn" = "$zone" ] && { uci -q get "firewall.@zone[$i].input"; return 0; }
        i=$((i+1))
    done
    return 1
}
netlimit_is_isolated() {   # <network-name> <zone> -> rc 0 if the network is walled off from others
    # GL's per-network isolate flag, or a zone that rejects/drops forwarding to other networks.
    [ "$(uci -q get "network.$1.isolate" 2>/dev/null)" = 1 ] && return 0
    local i=0 zn fwd
    while zn=$(uci -q get "firewall.@zone[$i].name" 2>/dev/null); do
        if [ "$zn" = "$2" ]; then
            fwd=$(uci -q get "firewall.@zone[$i].forward" 2>/dev/null)
            case "$fwd" in REJECT|DROP|reject|drop) return 0 ;; *) return 1 ;; esac
        fi
        i=$((i+1))
    done
    return 1
}
# MEASURED router reachability from a network's zone -> open|allowed|blocked|na -------------
# Read from the LIVE firewall, never inferred from our own config (see the "measure, don't
# prune" rule). A zone whose input is ACCEPT (lan, and often VPN zones) reaches the router by
# policy - we can't "block" that additively and won't try (blocking the LAN would lock the
# admin out). A reject/drop zone is blocked unless our Allow-<zone>-Router rule is present.
# Router-directed ACCEPT rules (name|ports|proto) for <zone>: ENABLED rules with src=zone and
# NO dest zone (input direction = to the router itself). Parses `uci show firewall` in ONE pass
# so the grid stays cheap on MIPS. Firewall config <-> nft stay in lockstep (fw4 recompiles on
# reload; no offload-style divergence), so reading uci here is a faithful measurement.
netlimit_router_allows() {   # <zone>
    [ -z "$1" ] && return 1
    uci show firewall 2>/dev/null | awk -v z="$1" '
        match($0,/^firewall\.[^.=]+=rule$/){ s=$0; sub(/^firewall\./,"",s); sub(/=rule$/,"",s); ord[++n]=s; next }
        match($0,/^firewall\.[^.=]+\.[^.=]+=/){
            eq=index($0,"="); lhs=substr($0,1,eq-1); v=substr($0,eq+1);
            gsub(/^\047|\047$/,"",v); gsub(/\047 \047/," ",v);            # unquote uci value / list
            r=substr(lhs,10); d=index(r,"."); s=substr(r,1,d-1); o=substr(r,d+1);
            if(o=="name")nm[s]=v; else if(o=="src")sr[s]=v; else if(o=="dest")de[s]=v;
            else if(o=="target")tg[s]=v; else if(o=="enabled")en[s]=v;
            else if(o=="dest_port")dp[s]=v; else if(o=="proto")pr[s]=v;
        }
        END{ for(i=1;i<=n;i++){s=ord[i]; if(sr[s]==z && de[s]=="" && tg[s]=="ACCEPT" && en[s]!="0") printf "%s|%s|%s\n",nm[s],dp[s],pr[s]} }'
}
# MEASURED router reachability -> open|full|partial|blocked|na (read from the LIVE firewall):
#   open    = zone input ACCEPT (reachable by policy; lan + VPN-accept zones - not togglable)
#   full    = zone rejects, but an all-ports ACCEPT-to-router rule is present (our Allow rule)
#   partial = only port-restricted ACCEPT-to-router rules (typically DNS/DHCP) - some services
#   blocked = no ACCEPT-to-router rules at all (rare - even DNS closed)
#   na      = no firewall zone
netlimit_router_state() {   # <zone>
    local zone="$1" pol allows nm dp pr any=0 all=0
    [ -z "$zone" ] && { echo na; return; }
    pol=$(netlimit_zone_input "$zone")
    [ "$pol" = "ACCEPT" ] && { echo open; return; }
    allows=$(netlimit_router_allows "$zone")
    [ -z "$allows" ] && { echo blocked; return; }
    while IFS='|' read -r nm dp pr; do
        [ -z "$nm" ] && continue
        any=1; [ -z "$dp" ] && all=1
    done <<EOF
$allows
EOF
    [ "$all" = 1 ] && echo full || { [ "$any" = 1 ] && echo partial || echo blocked; }
}
netlimit_webui() {   # iface zone 0|1  -- allow this network to reach the ROUTER itself
    # Opens the router's own LAN IP (ALL services: admin UI, speedtest, NTP, SSH, ...) to the
    # network - NOT the rest of the LAN subnet (other devices; that isolation is the zone's
    # forwarding policy). DNS/DHCP have their own dedicated zone rules, so blocking this never
    # breaks name resolution.
    # NB: compute rule AFTER zone is set - ash expands all `local` RHS before assigning, so a
    # `rule="...${zone}..."` on the same local line would see the empty outer zone.
    local iface="$1" zone="$2" on="$3" lan rule
    rule="netlimit_${zone}_router"; lan=$(netlimit_lan_ip)
    uci -q delete "firewall.$rule"; uci -q delete "firewall.netlimit_${zone}_webui"   # + legacy name
    if [ "$on" = "1" ] && [ -n "$zone" ] && [ -n "$lan" ]; then
        uci set "firewall.$rule=rule"; uci set "firewall.$rule.name=Allow-${zone}-Router"
        uci set "firewall.$rule.src=$zone"; uci set "firewall.$rule.dest_ip=$lan"; uci set "firewall.$rule.target=ACCEPT"
    fi
    uci commit firewall; /etc/init.d/firewall reload >/dev/null 2>&1
    # The uci firewall rule IS the persistent source of truth (survives reboot on its own) and
    # the UI reads it back live via netlimit_router_state - so nothing to record in our conf.
}
netlimit_ifset() {   # <network-name> <up|down> - PERSISTENT enable/disable, mirrors GL's own toggle
    # Flip network.<name>.disabled AND the disabled flag on every wifi-iface bound to it (so the
    # SSID follows the network up/down), commit (survives reboot), then reload network + wireless.
    # disabled='1' = DOWN. Wireless reload briefly re-applies all radios - unavoidable when a
    # guest/iot SSID is attached/detached; GL's toggle does the same.
    local net="$1" want="$2" dis w dev dl ul j=0
    [ "$want" = up ] && dis=0 || dis=1
    dev=$(uci -q get "network.$net.device" 2>/dev/null); [ -z "$dev" ] && dev="br-$net"
    uci -q set "network.$net.disabled=$dis"
    for w in $(uci -q show wireless 2>/dev/null | sed -n "s/^wireless\.\(.*\)\.network='$net'\$/\1/p"); do
        uci -q set "wireless.$w.disabled=$dis"
    done
    uci commit network; uci commit wireless
    /etc/init.d/network reload >/dev/null 2>&1
    command -v wifi >/dev/null 2>&1 && wifi reload >/dev/null 2>&1
    netlimit_reshape "$dev" "$want"
    return 0
}
netlimit_reshape() {   # <dev> <up|down> - re-apply this interface's configured limit on up, clear on down
    # Bringing an interface up does NOT restore its shaping, so re-apply THIS interface's configured
    # limit directly. (A full netlimit_reload would stall ~30s on any OTHER limited-but-down network,
    # since the service waits for each iface to appear.) Applying regardless of offload keeps the qdisc
    # present, so the row reads BYPASSED (offload on) / ACTIVE (offload off) like the others. On down,
    # tear the shaping down so no orphan ifb device lingers.
    local dev="$1" want="$2" dl ul j=0
    dl=$(netlimit_conf_field "$dev" 2); ul=$(netlimit_conf_field "$dev" 3)
    case "$dl" in ''|*[!0-9]*) dl=0 ;; esac; case "$ul" in ''|*[!0-9]*) ul=0 ;; esac
    if [ "$want" = up ]; then
        if [ "$dl" -gt 0 ] || [ "$ul" -gt 0 ]; then
            while [ ! -d "/sys/class/net/$dev" ] && [ "$j" -lt 10 ]; do sleep 1; j=$((j+1)); done
            netlimit_tc_clear_cmds "$dev" | sh 2>/dev/null
            netlimit_tc_apply_cmds "$dev" "$dl" "$ul" | sh 2>/dev/null
        fi
    else
        netlimit_tc_clear_cmds "$dev" | sh 2>/dev/null
    fi
}
netlimit_net_wifi() {   # <net> -> "iface|band|ssid|disabled" per wifi-iface; 2.4/5/6 GHz first, Other last
    # Band comes from the iface's radio (wireless.<radio>.band = 2g/5g/6g). MLO member links (wlanmld*)
    # and any iface without a 2/5/6 band are "Other": iface shown, band+ssid blanked (forward-compat if
    # MLO is ever surfaced for guest/iot). Annotate-sort-strip (busybox `sort -t -k` is a no-op).
    local net="$1" sec dev band ssid dis blabel k
    for sec in $(uci -q show wireless 2>/dev/null | sed -n "s/^wireless\.\(.*\)\.network='$net'\$/\1/p"); do
        dev=$(uci -q get "wireless.$sec.device" 2>/dev/null)
        band=$(uci -q get "wireless.$dev.band" 2>/dev/null)
        ssid=$(uci -q get "wireless.$sec.ssid" 2>/dev/null)
        dis=$(uci -q get "wireless.$sec.disabled" 2>/dev/null); [ "$dis" = 1 ] || dis=0
        case "$sec" in *mld*|*mlo*) band="" ;; esac
        case "$band" in 2g) blabel="2.4 GHz"; k=1 ;; 5g) blabel="5 GHz"; k=2 ;; 6g) blabel="6 GHz"; k=3 ;; *) blabel=""; ssid=""; k=9 ;; esac
        printf '%s %s|%s|%s|%s\n' "$k" "$sec" "$blabel" "$ssid" "$dis"
    done | sort -n | sed 's/^[0-9]* //'
}
netlimit_net_ifstate() {   # <net> -> up|down (band-aware: a wifi network is UP iff any of its SSIDs is up)
    [ "$(uci -q get "network.$1.disabled" 2>/dev/null)" = 1 ] && { echo down; return; }
    local sec any_wifi=0 any_up=0
    for sec in $(uci -q show wireless 2>/dev/null | sed -n "s/^wireless\.\(.*\)\.network='$1'\$/\1/p"); do
        any_wifi=1; [ "$(uci -q get "wireless.$sec.disabled" 2>/dev/null)" = 1 ] || any_up=1
    done
    if [ "$any_wifi" = 1 ]; then [ "$any_up" = 1 ] && echo up || echo down; else echo up; fi
}
netlimit_bands_apply() {   # <net> <dev> <mapfile: idx|iface|band|ssid|sel(=up)> - apply band selection
    local net="$1" dev="$2" mf="$3" idx sec band ssid sel any_up=0
    while IFS='|' read -r idx sec band ssid sel; do
        [ -z "$sec" ] && continue
        if [ "$sel" = 1 ]; then uci -q set "wireless.$sec.disabled=0"; any_up=1
        else uci -q set "wireless.$sec.disabled=1"; fi
    done < "$mf"
    # The network master follows the bands: enabled iff at least one band is up.
    [ "$any_up" = 1 ] && uci -q set "network.$net.disabled=0" || uci -q set "network.$net.disabled=1"
    uci commit wireless; uci commit network
    /etc/init.d/network reload >/dev/null 2>&1
    command -v wifi >/dev/null 2>&1 && wifi reload >/dev/null 2>&1
    [ "$any_up" = 1 ] && netlimit_reshape "$dev" up || netlimit_reshape "$dev" down
    return 0
}
netlimit_guest_parse() {   # <initscript> -> "dl ul"
    local f="$1" dl ul
    dl=$(sed -n 's/^#[[:space:]]*LIMIT_DL=//p' "$f" 2>/dev/null | head -1)
    ul=$(sed -n 's/^#[[:space:]]*LIMIT_UL=//p' "$f" 2>/dev/null | head -1)
    case "$dl" in ''|*[!0-9]*) dl=0 ;; esac; case "$ul" in ''|*[!0-9]*) ul=0 ;; esac
    printf '%s %s' "$dl" "$ul"
}
netlimit_migrate_guest() {
    [ -f "$NETLIMIT_GUEST_OLD" ] || return 0
    local dl ul ps=0; set -- $(netlimit_guest_parse "$NETLIMIT_GUEST_OLD"); dl="$1"; ul="$2"
    grep -qxF '/etc/init.d/guest_limiter' /etc/sysupgrade.conf 2>/dev/null && ps=1
    { [ "$dl" -gt 0 ] || [ "$ul" -gt 0 ]; } && netlimit_conf_put br-guest "$dl" "$ul" 0 "$ps"
    "$NETLIMIT_GUEST_OLD" stop >/dev/null 2>&1; "$NETLIMIT_GUEST_OLD" disable >/dev/null 2>&1
    rm -f "$NETLIMIT_GUEST_OLD"; sed -i '\|/etc/init.d/guest_limiter|d' /etc/sysupgrade.conf 2>/dev/null
    netlimit_service_write; netlimit_offload_sync; netlimit_reload; netlimit_persist_sync
}
offload_platform() { [ -f /etc/config/ecm ] && { echo qualcomm-ecm; return; }; [ -f /etc/config/mtkhnat ] || [ -d /sys/kernel/debug/hnat ] && { echo mediatek-hnat; return; }; nft list ruleset 2>/dev/null | grep -q 'flowtable' && { echo flowtable; return; }; echo unknown; }
# on|off, mechanism-aware: the toggle key differs by platform -
# ecm.global.enabled (Qualcomm), mtkhnat.global.enable (MediaTek), else the firewall flowtable.
offload_state() {
    if [ -f /etc/config/ecm ]; then [ "$(uci -q get ecm.global.enabled)" = "1" ] && echo on || echo off; return; fi
    if [ -f /etc/config/mtkhnat ]; then [ "$(uci -q get mtkhnat.global.enable)" = "1" ] && echo on || echo off; return; fi
    [ "$(uci -q get firewall.@defaults[0].flow_offloading)" = "1" ] && echo on || echo off
}
# false on any hardware-offload platform - a veth/namespace flow never HW-offloads there.
offload_namespace_eligible() {
    [ -f /etc/config/ecm ] && return 1
    [ -f /etc/config/mtkhnat ] && return 1
    [ -d /sys/kernel/debug/hnat ] && return 1
    [ "$(uci -q get firewall.@defaults[0].flow_offloading_hw)" = "1" ] && return 1
    return 0
}
offload_ref_ceiling() {
    case "$(sed -n 's/.*machine.*: //p;s/system type.*: //p' /proc/cpuinfo 2>/dev/null | head -1)$(uname -m)" in
        *MT7621*|*mips*|*mipsel*) echo 700 ;; *) echo 0 ;;
    esac
}

# Full revert: strip every limit + our firewall rules, re-enable HW acceleration, drop
# persistence, and stop/remove the boot service. Leaves the box as if netlimit never ran.
netlimit_reset_all() {
    local iface s changed=0
    # 1. clear live shaping for every configured interface
    netlimit_conf_list | while IFS='|' read -r iface s; do
        [ -n "$iface" ] && netlimit_tc_clear_cmds "$iface" | sh 2>/dev/null
    done
    # 2. delete every netlimit_* firewall rule we ever created (router + legacy webui names)
    for s in $(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\(netlimit_[A-Za-z0-9_]*\)=rule$/\1/p'); do
        uci -q delete "firewall.$s"; changed=1
    done
    [ "$changed" = 1 ] && { uci commit firewall; /etc/init.d/firewall reload >/dev/null 2>&1; }
    # 3. drop config, boot service, and persistence entries
    rm -f "$NETLIMIT_CONF"
    [ -f "$NETLIMIT_INIT" ] && { "$NETLIMIT_INIT" stop >/dev/null 2>&1; "$NETLIMIT_INIT" disable >/dev/null 2>&1; rm -f "$NETLIMIT_INIT"; }
    sed -i '\|/etc/init.d/netlimit|d; \|/etc/netlimit.conf|d' /etc/sysupgrade.conf 2>/dev/null
    # 4. restore hardware acceleration
    set_hw_accel 1 >/dev/null 2>&1
}

# Raw adaptive reachability glyph, matching the Remote LAN Access screen's status vocabulary
# (green reachable / red blocked / yellow unknown). Terminal-adaptive via OUTPUT_MODE so PuTTY
# and dumb terminals get the [AC]/[IA]/[!] compat text the RLA legend uses. For the grid COLUMN
# use the pre-padded _S_RLA_* cells instead (glyph-width-aware, keep the column aligned).
_nl_dot() {   # reachable | blocked | unknown
    if [ "$OUTPUT_MODE" = compat ]; then
        case "$1" in reachable) printf '[AC]' ;; blocked) printf '[IA]' ;; *) printf '[!]' ;; esac
    else
        case "$1" in
            reachable) printf '%b🟢%b' "$GREEN"  "$RESET" ;;
            blocked)   printf '%b🔴%b' "$RED"    "$RESET" ;;
            *)         printf '%b🟡%b' "$YELLOW" "$RESET" ;;
        esac
    fi
}

# best-effort service name for a dest_port spec (empty = "all"; unrecognised = "-")
_nl_svc() {
    case " ${1:-} " in
        "  ")                                     echo "all" ;;
        *" 53 "*)                                 echo "DNS" ;;
        *" 67-68 "*|*" 67 "*|*" 68 "*)            echo "DHCP" ;;
        *" 123 "*)                                echo "NTP" ;;
        *" 22 "*)                                 echo "SSH" ;;
        *" 80 "*|*" 443 "*|*" 8080 "*|*" 8443 "*) echo "Web-UI" ;;
        *)                                        echo "-" ;;
    esac
}
# proto field display: empty firewall proto means "any"; normalise the tcp/udp pair
_nl_proto() {
    case "${1:-}" in
        "")                  echo "any" ;;
        "tcp udp"|"udp tcp") echo "tcp+udp" ;;
        *)                   echo "$1" ;;
    esac
}

# format a rate in Mbps (0 -> em dash); collapse exact thousands to Gbps so 10000 -> "10 Gbps".
_nl_rate() {
    local r="${1:-0}"; case "$r" in ''|0|*[!0-9]*) printf -- '-'; return ;; esac
    if [ "$r" -ge 1000 ] && [ $(( r % 1000 )) -eq 0 ]; then printf '%s Gbps' "$(( r / 1000 ))"
    else printf '%s Mbps' "$r"; fi
}

# Shaping needs the software path, so it can't coexist with HW acceleration. Rather than
# silently flip offload off, confirm it first (it's a whole-router forwarding change).
# Returns 0 to proceed; only prompts when offload is currently ON.
_netlimit_offload_ok() {
    [ "$(offload_state)" = off ] && return 0
    # INFO, not a warning: this is a side-effect disclosure for the action the user just asked
    # for, not a caution against it - so ℹ️, one concise factual line, and a [Y/n] default (they
    # already entered a limit; the change auto-reverts). Mid-flow interruption keeps its blank above (rule #1).
    printf '\n'
    print_info "Bandwidth limiting requires HW acceleration OFF and may impact network and router performance."
    printf "Apply the limit now? [Y/n]: "
    local a; read -r a
    # The blank line before the apply gear is added by the caller (so it also appears when this
    # confirm is skipped - i.e. HW accel already off); here we only space the cancel message.
    case "$a" in n|N) printf '\n'; print_info "Cancelled - HW acceleration left on."; sleep 1; return 1 ;; *) return 0 ;; esac
}

show_netlimit_help() {
    show_paged "Network Bandwidth Limiter - Help" << 'HELPEOF'
Network Bandwidth Limiter - Quick Help

Sets a download/upload speed ceiling on any of the router's networks - guest, IoT,
a LAN, a VLAN, or a VPN tunnel - discovered automatically (a network only appears if
it exists on this device). Switched-off guest / IoT / VLAN networks are shown too,
marked DOWN, so you can bring them back up from here.

The grid
--------
  * Each row is a network: its If-State (UP, or DOWN if it's switched off), its Download /
    Upload limits, whether it can reach the router itself (Router), whether the limit persists
    across firmware upgrades, and whether a limit is ACTIVE right now (a limit shows BYPASSED
    if HW acceleration is on, since offload skips the shaper). Router and Status are MEASURED
    from the live firewall and tc state, not from stored settings.
  * Pick a number to open that network and set its limits.
  * [R] Reset reverts everything to defaults: removes every limit and router rule,
    re-enables HW acceleration, and stops the background service (asks first).

Hardware acceleration
---------------------
  * Shaping needs the software forwarding path, so it can't run while HW acceleration is
    enabled. This is automatic: setting a limit DISABLES acceleration for the whole router,
    and clearing your last limit re-enables it - you don't normally touch it.
  * The status line at the top reports it. DISABLED (green) is the normal state while you
    shape. ENABLED is green when you have no limits (nothing is bypassed) and turns YELLOW
    if it is on while a limit exists - that limit is then BYPASSED (offload skips the
    shaper) until acceleration is disabled again.
  * [H] is a manual override (Enable / Disable) of that automatic behaviour. You rarely
    need it - it's there to force acceleration on or off independently of your limits.
  * What it costs (measured): shaping moves forwarding into software, so the CPU does more
    per packet. On a dual-core MediaTek router pushing ~309 Mbit/s of routed traffic, CPU
    went from about 8% with offload ON to about 48% with it OFF - and the software path on
    that class of chip tops out near 700 Mbit/s. So on a 1 Gbps WAN there's comfortable
    headroom for everyday use; it bites harder on 2.5G/10G links or when you're near that
    ceiling. Faster CPUs (newer Flint-class routers) pay far less.

Per-network options
-------------------
  * Download / Upload: a ceiling in Mbps; 0 removes that direction.
  * Router access: whether this network can reach the router's OWN services (admin UI,
    speedtest, NTP, SSH, ...) on its LAN IP - not other devices on the LAN subnet. Measured
    live from the firewall and shown with a RAG dot (green = reachable, matching the Remote
    LAN Access screen):
      - reachable (green)  every port on the router is reachable (all ports)
      - partial   (yellow) only some ports - typically the DNS/DHCP that GL opens by
                           default; the detail page lists exactly which (service/port/proto)
      - blocked   (red)    no router services reachable at all (rare)
    "Enable router to be reachable on all ports" opens every port; the matching "Disable ..."
    removes only that and falls back to partial (it does NOT block - DNS/DHCP keep working).
    On an ISOLATED network (walled off from your other networks) it warns and confirms first,
    since opening all ports also exposes the router's admin UI / SSH to that network.
    Networks whose zone already accepts input (the LAN,
    and typically VPN zones) are "managed by zone" and not toggled here - that would risk
    locking you out. (Only ACCEPT rules are counted; hand-written nft rules outside uci are
    not, and the exact reachable set can differ if custom DROP rules interleave.)
  * Persistence: a limit ALWAYS survives a reboot (the service is enabled and its config
    lives on the overlay). This keeps it across a firmware UPGRADE too, by adding it to the
    sysupgrade backup - so "NO" means reboot-safe but lost on a firmware upgrade.
  * Disable: remove the limit entirely.
  * Bring interface(s) UP / DOWN: switch a guest / IoT / VLAN network on or off - a persistent
    change, like the GL admin toggle, so it survives a reboot. A network with multiple Wi-Fi
    bands (2.4 / 5 / 6 GHz) opens a grid where you pick which bands to bring up or down - the
    network reads UP while any band is up, DOWN once all are off; single-interface networks (a
    wired VLAN) toggle as a whole. A switched-off network offers only "Bring interface(s) UP",
    since limits and router access don't apply until it's up. The LAN and VPN tunnels are never
    toggled here. Turning bands on/off briefly re-applies Wi-Fi, so other wireless may drop for
    a moment.
HELPEOF
}

_netlimit_bands_edit() {   # <net> <dev> - multi-select which sub-interfaces (bands) are UP; apply on [C]
    # Mirrors the AdGuardHome Backup Cleanup selector: a persistent selection map, checkmark = "this
    # band should be UP". Confirm applies every band's wireless.disabled and syncs network.disabled.
    local net="$1" dev="$2" mf="/tmp/nl_bands_map" input cmd idx sec band ssid sel box _bdiv i
    rm -f "$mf"; i=1
    netlimit_net_wifi "$net" | while IFS='|' read -r sec band ssid dis; do
        [ -z "$sec" ] && continue
        [ "$dis" = 1 ] && echo "$i|$sec|$band|$ssid|0" >> "$mf" || echo "$i|$sec|$band|$ssid|1" >> "$mf"
        i=$((i+1))
    done
    [ -s "$mf" ] || { rm -f "$mf"; return; }
    _bdiv=$(awk -F'|' 'function m(a,b){return a>b?a:b} {w=25+m(16,length($2))+length($4); if(w>x)x=w} END{s="";for(i=0;i<x;i++)s=s"─";print s}' "$mf")
    while true; do
        clear
        print_centered_header "$net - Wi-Fi Bands"
        printf " %-3s  %-4s  %-16s  %-9s  %s\n" "Sel" "Idx" "Iface" "Band" "SSID"
        printf " %s\n" "$_bdiv"
        while IFS='|' read -r idx sec band ssid sel; do
            box="[ ]"; [ "$sel" = 1 ] && box="[✓]"
            printf " %s  %-4s  %-16s  %-9s  %s\n" "$box" "$idx." "$sec" "${band:--}" "${ssid:--}"
        done < "$mf"
        printf " %s\n" "$_bdiv"
        printf " [A] All   [N] None   [#] Toggle   [C] Confirm   [0] Cancel\n"
        i=$(wc -l < "$mf" | tr -dc '0-9')
        printf "\n Choose [%s/A/N/C/0]: " "$(picker_range "$i")"
        read -r input; cmd=$(echo "$input" | tr 'A-Z' 'a-z'); printf '\n'
        case "$cmd" in
            a) sed -i 's/|0$/|1/' "$mf" ;;
            n) sed -i 's/|1$/|0/' "$mf" ;;
            [1-9]*)
                if grep -q "^$cmd|" "$mf"; then
                    sel=$(grep "^$cmd|" "$mf" | cut -d'|' -f5)
                    sed -i "s/^\($cmd|[^|]*|[^|]*|[^|]*|\).*/\1$((1-sel))/" "$mf"
                else print_error "Index $cmd not found"; sleep 1; fi ;;
            c) spin_run "Applying Wi-Fi bands" netlimit_bands_apply "$net" "$dev" "$mf"; rm -f "$mf"; return ;;
            0) rm -f "$mf"; return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}
_netlimit_edit() {   # <map-line>
    local idx name iface type zone dl ul wb ps st ans rl ifstate _dis _togglable _iso dev _wcount _bup _banded _blabel
    IFS='|' read -r idx name iface type zone dl ul wb ps st ifstate <<EOF
$1
EOF
    case "$type" in guest|iot|vlan) _togglable=1 ;; *) _togglable=0 ;; esac
    dev=$(uci -q get "network.$name.device" 2>/dev/null); [ -z "$dev" ] && dev="$iface"
    while true; do
        clear
        print_centered_header "$name - Bandwidth Limit"
        dl=$(netlimit_conf_field "$iface" 2); ul=$(netlimit_conf_field "$iface" 3)
        ps=$(netlimit_conf_field "$iface" 5); wb=$(netlimit_router_state "$zone")   # MEASURED, live
        : "${dl:=0}"; : "${ul:=0}"; : "${ps:=0}"
        st="INACTIVE"
        if tc qdisc show dev "$iface" 2>/dev/null | grep -q htb; then
            [ "$(offload_state)" = off ] && st="ACTIVE" || st="BYPASSED (HW accel on)"
        fi
        # Sub-interfaces (Wi-Fi bands) on this network's bridge, and how many are up. A network with
        # 2+ bands gets per-band control (a grid); 0-1 stays the simple whole-interface toggle.
        _wcount=0; _bup=0; _banded=0
        if [ "$_togglable" = 1 ]; then
            _wcount=$(netlimit_net_wifi "$name" | grep -c .)
            _bup=$(netlimit_net_wifi "$name" | awk -F'|' '$4!=1{c++} END{print c+0}')
            [ "$_wcount" -ge 2 ] && _banded=1
        fi
        # Recompute If-State live - band-aware for wifi networks (UP iff any band up), else the
        # network.disabled flag. It flips when the user brings the interface(s) up/down below.
        case "$type" in
            guest|iot) ifstate=$(netlimit_net_ifstate "$name") ;;
            *) _dis=$(uci -q get "network.$name.disabled" 2>/dev/null); [ "$_dis" = 1 ] && ifstate=down || ifstate=up ;;
        esac
        [ "$ifstate" = down ] && wb=na   # a down network is unreachable - don't imply a router state
        # Standard vertical-menu layout (see [[ui-vertical-menu-structure]]): the Status summary
        # leads, then a blank line, then the detail fields (grid-column order: Network, Interface,
        # Download, Upload, Router, Persist), then a blank line, then the numbered options. Status
        # VALUES are ALL CAPS (UX std); identifiers (network name, br-*) stay lowercase.
        printf " %bStatus:%b      %s\n\n" "$CYAN" "$RESET" "$st"
        printf " %bNetwork:%b     %s\n" "$CYAN" "$RESET" "$name"
        printf " %bInterface:%b   %s\n" "$CYAN" "$RESET" "$iface"
        if [ "$ifstate" = down ]; then printf " %bIf-State:%b    %bDOWN%b\n" "$CYAN" "$RESET" "$GREY" "$RESET"
        else printf " %bIf-State:%b    UP\n" "$CYAN" "$RESET"; fi
        # For multi-band wifi networks, break the If-State down per band (2.4/5/6 GHz, then Other).
        if [ "$_banded" = 1 ]; then
            netlimit_net_wifi "$name" | while IFS='|' read -r _bi _bb _bs _bd; do
                [ -z "$_bi" ] && continue
                if [ "$_bd" = 1 ]; then printf "   %-10s %bDOWN%b\n" "${_bb:-$_bi}" "$GREY" "$RESET"
                else printf "   %-10s UP\n" "${_bb:-$_bi}"; fi
            done
        fi
        printf " %bDownload:%b    %s\n" "$CYAN" "$RESET" "$(_nl_rate "$dl")"
        printf " %bUpload:%b      %s\n" "$CYAN" "$RESET" "$(_nl_rate "$ul")"
        if [ "$ifstate" = down ]; then
            rl="$(printf '%b—%b' "$GREY" "$RESET") N/A"   # down: no router relationship (grey, not a RAG dot)
        else
            case "$wb" in
                open)    rl="$(_nl_dot reachable) REACHABLE (managed by zone)" ;;
                full)    rl="$(_nl_dot reachable) REACHABLE (all ports)" ;;
                partial) rl="$(_nl_dot partial) PARTIAL (some ports)" ;;
                blocked) rl="$(_nl_dot blocked) BLOCKED (no access)" ;;
                *)       rl="$(_nl_dot unknown) N/A" ;;
            esac
        fi
        printf " %bRouter:%b      %s\n" "$CYAN" "$RESET" "$rl"
        # Only partial needs a breakdown (which services) - the parenthetical already says
        # "all ports" / "no access" for the other states.
        if [ "$wb" = partial ]; then
            printf "   %bopen to router:%b\n" "$GREY" "$RESET"
            netlimit_router_allows "$zone" | while IFS='|' read -r _n _dp _pr; do
                [ -z "$_n" ] && continue
                printf "     %-8s %-12s %s\n" "$(_nl_svc "$_dp")" "${_dp:-all}" "$(_nl_proto "$_pr")"
            done
        fi
        # A limit ALWAYS survives reboot (service enabled, config on overlay); "Persist" is
        # specifically about a firmware UPGRADE (sysupgrade backup) - spell that out so "NO"
        # is never read as "lost on reboot".
        # Persist is a LIMIT attribute (does the limit survive a firmware upgrade) - meaningless and
        # confusing on a switched-off network, so suppress it there; the OFF note covers reboot state.
        if [ "$ifstate" != down ]; then
            if [ "$ps" = 1 ]; then printf " %bPersist:%b     YES  %b(survives firmware upgrades)%b\n" "$CYAN" "$RESET" "$GREY" "$RESET"
            else printf " %bPersist:%b     NO   %b(reboot-safe; lost on firmware upgrade)%b\n" "$CYAN" "$RESET" "$GREY" "$RESET"; fi
        fi
        printf "\n"
        if [ "$ifstate" = down ]; then
            # A switched-off network can't be shaped or reached, so the only action is to bring it
            # up. NOTE: "Bring interface UP/DOWN" (not the standard Enable/Disable) is a DELIBERATE
            # exception to the toggle-label standard, chosen so the verb matches the If-State value.
            printf " %bThis network is OFF and stays off across reboots until you bring it up.%b\n" "$GREY" "$RESET"
            printf " %bBring it up to set limits or router access.%b\n\n" "$GREY" "$RESET"
            if [ "$_banded" = 1 ]; then printf " %s%sBring interfaces UP\n" "$N1" "$NSEP"
            else printf " %s%sBring interface UP\n" "$N1" "$NSEP"; fi
            printf " %s%sBack\n" "$N0" "$NSEP"
            printf "\nChoose [1/0]: "
            read -r ans; printf "\n"
            case "$ans" in
                1) if [ "$_banded" = 1 ]; then _netlimit_bands_edit "$name" "$dev"
                   else spin_run "Bringing $name up" netlimit_ifset "$name" up; fi ;;
                0) return ;;
                *) print_error "Invalid option"; sleep 1 ;;
            esac
        else
            printf " %s%sSet download limit\n" "$N1" "$NSEP"
            printf " %s%sSet upload limit\n"   "$N2" "$NSEP"
            case "$wb" in
                blocked|partial) printf " %s%sEnable router to be reachable on all ports\n" "$N3" "$NSEP" ;;
                full)            printf " %s%sDisable router to be reachable on all ports\n" "$N3" "$NSEP" ;;
                *)               printf " %s%sRouter access (managed by zone)\n" "$N3" "$NSEP" ;;
            esac
            [ "$ps" = 1 ] && printf " %s%sDisable persistence\n" "$N4" "$NSEP" || printf " %s%sEnable persistence\n" "$N4" "$NSEP"
            printf " %s%sDisable limit\n" "$N5" "$NSEP"
            # guest/iot/vlan can be switched off from here (never lan/vpn); verb matches If-State.
            # Multi-band networks get a per-band grid with a state-dependent label (all up -> DOWN;
            # a mix -> UP or DOWN); single-interface ones keep the simple whole-interface toggle.
            if [ "$_banded" = 1 ]; then
                [ "$_bup" -eq "$_wcount" ] && _blabel="Bring interfaces DOWN" || _blabel="Bring interfaces UP or DOWN"
                printf " %s%s%s\n" "$N6" "$NSEP" "$_blabel"
            elif [ "$_togglable" = 1 ]; then
                printf " %s%sBring interface DOWN\n" "$N6" "$NSEP"
            fi
            printf " %s%sBack\n" "$N0" "$NSEP"
            { [ "$_banded" = 1 ] || [ "$_togglable" = 1 ]; } && printf "\nChoose [1-6/0]: " || printf "\nChoose [1-5/0]: "
            read -r ans; printf "\n"
            case "$ans" in
                1) printf "Download limit in Mbps (0 = none): "; read -r v; case "$v" in
                     ''|*[!0-9]*) print_error "Numbers only"; sleep 1 ;;
                     *) if [ "$v" -gt 0 ] || [ "$ul" -gt 0 ]; then _netlimit_offload_ok || continue; fi
                        printf '\n'
                        spin_run "Applying limit" netlimit_set "$iface" "$v" "$ul" ;; esac ;;
                2) printf "Upload limit in Mbps (0 = none): "; read -r v; case "$v" in
                     ''|*[!0-9]*) print_error "Numbers only"; sleep 1 ;;
                     *) if [ "$v" -gt 0 ] || [ "$dl" -gt 0 ]; then _netlimit_offload_ok || continue; fi
                        printf '\n'
                        spin_run "Applying limit" netlimit_set "$iface" "$dl" "$v" ;; esac ;;
                3) case "$wb" in
                     blocked|partial)
                        # Opening ALL router ports to an ISOLATED network exposes admin UI/SSH to a
                        # network deliberately walled off from everything else - warn and confirm.
                        if netlimit_is_isolated "$name" "$zone"; then
                            print_warning "'$name' is an ISOLATED network - walled off from your other networks.\nOpening all router ports also exposes the router's admin UI, SSH and other\nservices to any device on it."
                            printf "Open all router ports to '$name' anyway? [y/N]: "; read -r _iso; printf '\n'
                            case "$_iso" in y|Y) ;; *) continue ;; esac
                        fi
                        spin_run "Updating firewall" netlimit_webui "$iface" "$zone" 1 ;;
                     full)            spin_run "Updating firewall" netlimit_webui "$iface" "$zone" 0 ;;
                     open)            print_info "Router access for '$name' is governed by its firewall zone (input policy =\nACCEPT), not by this limiter. To change it, edit the '$zone' zone in the firewall."
                                      press_any_key ;;
                     *)               print_info "This network has no firewall zone, so router access can't be toggled here."
                                      press_any_key ;;
                   esac ;;
                4) netlimit_conf_put "$iface" "$dl" "$ul" "$(netlimit_conf_field "$iface" 4)" "$([ "$ps" = 1 ] && echo 0 || echo 1)"; netlimit_persist_sync ;;
                5) spin_run "Removing limit" netlimit_set "$iface" 0 0 ;;
                6) if [ "$_banded" = 1 ]; then _netlimit_bands_edit "$name" "$dev"
                   elif [ "$_togglable" = 1 ]; then spin_run "Bringing $name down" netlimit_ifset "$name" down
                   else print_error "Invalid option"; sleep 1; fi ;;
                0) return ;;
                *) print_error "Invalid option"; sleep 1 ;;
            esac
        fi
    done
}

_nl_map_row() {   # name iface type zone ifstate -> name|iface|type|zone|dl|ul|wb|ps|st|ifstate
    local name="$1" iface="$2" type="$3" zone="$4" ifstate="$5" dl ul ps wb st
    if [ "$ifstate" = down ]; then
        # A down network can't be reached or actively shaped, but its configured limit PERSISTS
        # (re-applies when brought up), so show the REAL limit - matching the edit screen - rather
        # than blanking it. Only Router (unreachable) and Status (not shaping) are N/A here.
        dl=$(netlimit_conf_field "$iface" 2); ul=$(netlimit_conf_field "$iface" 3)
        ps=$(netlimit_conf_field "$iface" 5)
        : "${dl:=0}"; : "${ul:=0}"; : "${ps:=0}"
        wb=na; st=inactive
    else
        dl=$(netlimit_conf_field "$iface" 2); ul=$(netlimit_conf_field "$iface" 3)
        ps=$(netlimit_conf_field "$iface" 5); wb=$(netlimit_router_state "$zone")   # wb = MEASURED router-state token
        : "${dl:=0}"; : "${ul:=0}"; : "${ps:=0}"
        # active only when the shaping is actually in effect: tc present AND offload off.
        # tc present but offload on = configured-but-bypassed (offload skips the shaper).
        st=inactive
        if tc qdisc show dev "$iface" 2>/dev/null | grep -q htb; then
            [ "$(offload_state)" = off ] && st=active || st=bypassed
        fi
    fi
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$name" "$iface" "$type" "$zone" "$dl" "$ul" "$wb" "$ps" "$st" "$ifstate"
}
_netlimit_build_map() {
    netlimit_migrate_guest 2>/dev/null
    local tmp="${NL_MAP}.tmp"; : > "$tmp"
    # Pass 1: live, shapeable networks (ubus) -> If-State UP. For wifi networks (guest/iot) the state
    # is band-aware: a network whose SSIDs are all switched off reads DOWN even if its bridge is up.
    netlimit_discover | while IFS='|' read -r name iface type zone; do
        [ -z "$iface" ] && continue
        case "$type" in
            guest|iot) _nl_map_row "$name" "$iface" "$type" "$zone" "$(netlimit_net_ifstate "$name")" >> "$tmp" ;;
            *)         _nl_map_row "$name" "$iface" "$type" "$zone" up >> "$tmp" ;;
        esac
    done
    # Pass 2: configured-but-DISABLED guest/iot/vlan (uci) -> If-State DOWN (shown + toggleable).
    netlimit_discover_disabled | while IFS='|' read -r name iface type zone; do
        [ -z "$name" ] && continue
        _nl_map_row "$name" "$iface" "$type" "$zone" down >> "$tmp"
    done
    # Number the whole set at the end (down rows fall after the live ones, so they sort last).
    awk '{print NR"|"$0}' "$tmp" > "$NL_MAP"; rm -f "$tmp"
}

manage_netlimit() {
    local _div; _div=$(awk 'BEGIN{s="";for(i=0;i<89;i++)s=s"─";print s}')
    clear; print_centered_header "Network Bandwidth Limiter"
    spin_run "Discovering networks" _netlimit_build_map
    # Preflight: shaping needs tc (tc-tiny). Present on GL firmware; require_cmd reinstalls it if a
    # user removed it. (The HTB/IFB kernel modules are a separate, rarer gap - see the backlog.)
    if ! require_cmd tc tc-tiny "traffic control (tc)"; then
        print_warning "Traffic control (tc) isn't available - limits can't be applied until it's installed."
        press_any_key
    fi
    while true; do
        clear
        print_centered_header "Network Bandwidth Limiter"
        # HW acceleration is a router-wide GATE for shaping, auto-managed by netlimit_offload_sync
        # (offload follows limits). Report it HEALTH-aware, not by literal on/off: green = nominal
        # (nothing bypassed), yellow ONLY when it is ENABLED while a limit exists (that limit is then
        # BYPASSED - a state reachable only via a manual [H] override). Status word ENABLED/DISABLED
        # matches the [H] control verb; only the yellow (exception) state carries a side note.
        local hw; hw=$(offload_state)
        if [ "$hw" != on ]; then
            printf " %bHW Acceleration:%b %bDISABLED%b\n" "$CYAN" "$RESET" "$GREEN" "$RESET"
        elif netlimit_any_limited; then
            printf " %bHW Acceleration:%b %bENABLED%b  %blimits are BYPASSED - [H] to enforce them%b\n" "$CYAN" "$RESET" "$YELLOW" "$RESET" "$GREY" "$RESET"
        else
            printf " %bHW Acceleration:%b %bENABLED%b\n" "$CYAN" "$RESET" "$GREEN" "$RESET"
        fi
        printf "\n"
        printf "       %-14s %-13s %-8s %-9s %-9s %-8s %-8s %s\n" "Network" "Interface" "If-State" "Download" "Upload" "Router" "Persist" "Status"
        printf " %s\n" "$_div"
        while IFS='|' read -r idx name iface type zone dl ul wb ps st ifstate; do
            local rdot pbl stc stu ifc ifv nmc
            case "$wb" in
                open|full) rdot="$_S_RLA_AC" ;;
                partial)   rdot="$_S_RLA_RO" ;;
                blocked)   rdot="$_S_RLA_IA" ;;
                *)         rdot=$(printf '   %b—%b    ' "$GREY" "$RESET") ;;
            esac
            # Persist is a LIMIT attribute (firmware-upgrade survival); it's meaningless/confusing on
            # a down network, so show "-" there - matching the edit screen, which hides it entirely.
            if [ "$ifstate" = down ]; then pbl="-"; elif [ "$ps" = 1 ]; then pbl="YES"; else pbl="NO"; fi
            case "$st" in active) stc="$GREEN"; stu="ACTIVE" ;; bypassed) stc="$YELLOW"; stu="BYPASSED" ;; *) stc="$GREY"; stu="INACTIVE" ;; esac
            # If-State: UP for live networks, DOWN (dimmed row) for configured-but-disabled ones.
            if [ "$ifstate" = down ]; then ifc="$GREY"; ifv="DOWN"; nmc="$GREY"; else ifc="$GREEN"; ifv="UP"; nmc="$RESET"; fi
            printf " %-5s %b%-14s %-13s%b %b%-8s%b %-9s %-9s %s %-8s %b%s%b\n" "$idx." "$nmc" "$name" "$iface" "$RESET" "$ifc" "$ifv" "$RESET" "$(_nl_rate "$dl")" "$(_nl_rate "$ul")" "$rdot" "$pbl" "$stc" "$stu" "$RESET"
        done < "$NL_MAP"
        printf "\n"
        printf " Legend: %s reachable (all ports)  %s partial (some ports)  %s blocked (no access)\n" "$(_nl_dot reachable)" "$(_nl_dot partial)" "$(_nl_dot blocked)"
        printf " %s\n" "$_div"
        # [H] label states what pressing does NOW (toggle-label standard), not "Toggle".
        local hact; [ "$hw" = on ] && hact="Disable HW Acceleration" || hact="Enable HW Acceleration"
        printf " [#] Edit a network   [H] %s   [R] Reset   [0] Back   [?] Help\n" "$hact"
        local n; n=$(wc -l < "$NL_MAP" 2>/dev/null | tr -dc '0-9')
        printf "\nChoose [1-%s/H/R/0/?]: " "${n:-0}"
        read -r cmd; printf "\n"
        case "$cmd" in
            0) rm -f "$NL_MAP"; return ;;
            [1-9]*) local ln; ln=$(grep "^$cmd|" "$NL_MAP"); [ -n "$ln" ] && { _netlimit_edit "$ln"; _netlimit_build_map; } || { print_error "Invalid option"; sleep 1; } ;;
            h|H)
                if [ "$(offload_state)" = on ]; then
                    spin_run "Disabling HW acceleration" set_hw_accel 0; _netlimit_build_map
                elif netlimit_any_limited; then
                    print_warning "Active limits will stop working with HW acceleration on (offload bypasses the shaper)."
                    printf "Enable anyway? [y/N]: "; read -r a; printf '\n'
                    case "$a" in y|Y) spin_run "Enabling HW acceleration" set_hw_accel 1; _netlimit_build_map ;; esac
                else
                    spin_run "Enabling HW acceleration" set_hw_accel 1; _netlimit_build_map
                fi ;;
            r|R)
                print_warning "This removes every limit and router rule, re-enables HW acceleration, and stops the background service."
                printf "Revert to defaults? [y/N]: "; read -r a; printf '\n'
                case "$a" in y|Y) spin_run "Reverting to defaults" netlimit_reset_all; _netlimit_build_map ;; esac ;;
            \?|help) show_netlimit_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# --- Web-UI Terminal Manager ---
show_terminal_help() {
    show_paged "Web Terminal Management - Help" << 'HELPEOF'
Web Terminal (ttyd) Management – Quick Help

What is the Web Terminal?
───────────────────────────
This tool embeds a fully functional Linux terminal directly into your 
GL.iNet Admin Panel. It allows you to execute commands, edit configs, 
and manage your router without needing an external SSH client.

Main Benefits:
• Zero Config: Access your shell from any browser (Safari/Chrome/Edge).
• Secure: Uses '/bin/login' to require your root password.
• Integrated: Adds a custom icon ( >_ ) to the top navigation bar.

How it Works (The Technical Bit):
────────────────────────────────
• Backend (ttyd): A lightweight C-based terminal-to-web server that 
  runs as a Procd service (Start Priority: 99).
• Frontend (JS Injection): Patches the 'app.*.js.gz' file in /www/js/ 
  to inject a draggable, minimizable terminal modal.
• The "Fast-UI" Label: The window header automatically pulls your 
  router's model (e.g., gl-be3600) from the browser's LocalStorage 
  to match a native macOS/Linux terminal feel.

Usage in this Menu:
───────────────────
1. Install & Deploy: Automatically installs the 'ttyd' package, 
   configures the black-background theme via UCI, starts the service, 
   and injects the Web UI button.
2. Disable Service & UI: Stops the background process and reverts the 
   Admin Panel JS to its original ROM state. The 'ttyd' package 
   remains installed for quick re-activation.
3. Completely Uninstall: Stops the service, uninstalls the 'ttyd' 
   binary, deletes its config, and restores the factory UI.

Important UX Notes:
────────────────────
• Hard Refresh: After deploying or disabling, you MUST perform a 
  "Hard Refresh" (Chrome/Edge/Firefox: Ctrl+F5 or Ctrl/Cmd + Shift + R; Safari:
  Cmd + Option + R) in your browser. This
  clears the Nginx cache ( /var/lib/nginx ) and forces the new UI.
• Security: The service is bound to the 'LAN' interface by default. 
  It is not accessible from the WAN (Internet) unless you manually 
  open Port 7681 in the firewall.
• Persistence: Configuration is handled via UCI (/etc/config/ttyd), 
  ensuring your terminal settings survive a reboot.

Note: If the icon does not appear after a refresh, ensure "Network 
Acceleration" isn't preventing the UI from updating, though the 
script attempts to force this by clearing the Nginx cache.
HELPEOF
}

# _inject_terminal_into <app.js.gz> [proto] [from_rom]
# Appends the Web-UI terminal button to the app bundle. Guarded against a
# double injection, so it is safe to call unconditionally.
#
# from_rom=1 starts from a pristine ROM copy - the enable path wants a clean
# base. from_rom=0 appends to the CURRENT file, so the button can be restored
# on top of another feature's edits to the SAME bundle. That matters because
# the fan feature also rewrites app.*.js.gz; restoring it from ROM (which both
# a fan reset and every fan setpoint change do) would otherwise silently wipe
# this button while the toolkit still reports the terminal as enabled.
_inject_terminal_into() {
    _iti_gz="$1"; _iti_proto="${2:-http}"; _iti_fromrom="${3:-0}"
    [ -n "$_iti_gz" ] || return 1
    if [ "$_iti_fromrom" = 1 ] && [ -f "/rom$_iti_gz" ]; then
        cp -f "/rom$_iti_gz" "$_iti_gz"
    fi
    zcat "$_iti_gz" 2>/dev/null | grep -q "term-wrapper" && return 0
    _iti_js="${_iti_gz%.gz}"
    zcat "$_iti_gz" > "$_iti_js"
    cat << 'EOF' >> "$_iti_js"
;(function(){
  // Anchor candidates, most to least specific. GL's admin panel markup differs
  // between firmware builds, so binding to a single class means the button
  // silently never appears on a build that renames or drops it.
  const ANCHORS = ['.icon-reboot','.icon-question-circle','.icon-logout',
                   '[class*="icon-reboot"]','[class*="icon-power"]'];
  const findAnchor = () => {
    for (const sel of ANCHORS) {
      const el = document.querySelector(sel);
      if (el) return el;
    }
    return null;
  };
  const inject = () => {
    if (document.getElementById('term-wrapper')) return;
    const anchor = findAnchor();
    if (!anchor) return;
    const rs = window.getComputedStyle(anchor);
    const rml = parseInt(rs.marginLeft)||0, rmr = parseInt(rs.marginRight)||0;
    const wML = rml > 0 ? rml+'px' : '0px';
    const wMR = rml > 0 ? '0px' : rmr+'px';
    const wrapper = document.createElement('span');
    wrapper.id = 'term-wrapper';
    wrapper.className = 'btn-icon';
    wrapper.style.cssText = 'margin-left:'+wML+'; margin-right:'+wMR+'; display:inline-flex; align-items:center; cursor:pointer; color:#606266; font-size:18px;';
    wrapper.innerHTML = ' >_ ';
    wrapper.onclick = () => {
      if(document.getElementById('term-modal')) return;
      const host = window.location.hostname;
      const aliasEl = document.querySelector('.alias span');
      const hostLabel = (aliasEl && aliasEl.innerText.trim())
                        ? aliasEl.innerText.trim().toLowerCase()
                        : host;
      const modal = document.createElement('div');
      modal.id = 'term-modal';
      // Sized to the toolkit's standard 110x33.
      //
      // Calibrated from measured sessions, not estimated - three estimates in a
      // row were wrong, including a linear scaling that assumed cell size tracks
      // fontSize proportionally. It does not.
      //
      //   default font, 1095x700 box -> 142x43  => cell 7.7  x 15.4
      //   fontSize=14,   800x520 box -> 96x29   => cell 8.33 x 16.6
      //
      // At fontSize=12 the cell measures about 7.14 x 14.25, so this 800x520 box
      // should land near 112x33. Trim the width to ~785px if exactly 110 matters.
      //
      // FIXED PIXELS, not percentages - a percentage yields a different
      // cols x rows on every window size, which is what produced 134x38.
      //
      // max() inside min() rather than the min-width/min-height PROPERTIES:
      // those are a permanent floor, and minimise sets the modal to 250x38, so a
      // floor silently stops it collapsing (the old min-width:300px did that).
      modal.style.cssText = 'position:fixed; top:8%; left:10%; width:min(96vw, 800px); height:min(90vh, 520px); background:#000 !important; z-index:9999; border-radius:10px; box-shadow:0 20px 50px rgba(0,0,0,0.9); overflow:hidden; border:1px solid #444;';
      const head = document.createElement('div');
      head.id = 'term-header';
      head.style.cssText = 'background:#1a1a1a; padding:10px 15px; display:flex; justify-content:space-between; align-items:center; cursor:move; user-select:none; border-bottom:1px solid #333;';
      const popOutSvg = '<svg width="14" height="14" viewBox="0 0 512 512" fill="#00a8ff" style="cursor:pointer;"><path d="M432 320H400a16 16 0 0 0-16 16v112H64V128h112a16 16 0 0 0 16-16V80a16 16 0 0 0-16-16H48a48 48 0 0 0-48 48v400a48 48 0 0 0 48 48h352a48 48 0 0 0 48-48V336a16 16 0 0 0-16-16zM488 0H360c-21.37 0-32.05 25.91-17 41l35.73 35.73L135 320.37a24 24 0 0 0 0 34L157.67 377a24 24 0 0 0 34 0l243.61-243.68L471 169c15 15 41 4.47 41-17V24a24 24 0 0 0-24-24z"/></svg>';
      head.innerHTML = '<div style="display:flex; gap:8px;"><div id="t-cls" style="width:12px;height:12px;background:#ff5f56;border-radius:50%;cursor:pointer;"></div><div id="t-min" style="width:12px;height:12px;background:#ffbd2e;border-radius:50%;cursor:pointer;"></div><div id="t-max" style="width:12px;height:12px;background:#27c93f;border-radius:50%;cursor:pointer;"></div></div><span style="color:#888;font-family:monospace;font-size:11px;pointer-events:none;">root@'+hostLabel+': ~</span><div id="t-pop">'+popOutSvg+'</div>';
      const ifrm = document.createElement('iframe');
      const termUrl = 'http://' + host + ':7681/';
      ifrm.src = termUrl;
      ifrm.style.cssText = 'width:100%; height:calc(100% - 38px); border:none; background:#000;';
      modal.appendChild(head); modal.appendChild(ifrm); document.body.appendChild(modal);
      const setTrans = (on) => modal.style.transition = on ? 'all 0.3s ease-in-out' : 'none';
      document.getElementById('t-pop').onclick = (e) => { e.stopPropagation(); window.open(termUrl,'_blank'); modal.remove(); };
      document.getElementById('t-cls').onclick = () => modal.remove();
      let isMin = false, minOldStyle = {};
      document.getElementById('t-min').onclick = () => {
        setTrans(true);
        if (!isMin) {
          minOldStyle = { top:modal.style.top, left:modal.style.left, width:modal.style.width, height:modal.style.height, bottom:modal.style.bottom, right:modal.style.right };
          Object.assign(modal.style, { top:'auto', left:'auto', bottom:'20px', right:'20px', width:'250px', height:'38px' });
          ifrm.style.display = 'none';
          resizeHandle.style.display = 'none';
        } else {
          ifrm.style.display = 'block';
          resizeHandle.style.display = '';
          setTrans(false);
          Object.assign(modal.style, { top:'auto', left:'auto', bottom:'20px', right:'20px', width:minOldStyle.width, height:minOldStyle.height });
          requestAnimationFrame(() => requestAnimationFrame(() => {
            setTrans(true);
            Object.assign(modal.style, { top:minOldStyle.top||'10%', left:minOldStyle.left||'10%', bottom:minOldStyle.bottom||'auto', right:minOldStyle.right||'auto', width:minOldStyle.width, height:minOldStyle.height });
          }));
        }
        isMin = !isMin;
      };
      let isMax = false, maxOldPos = {};
      document.getElementById('t-max').onclick = () => {
        setTrans(true);
        if (!isMax) {
          maxOldPos = { t:modal.style.top, l:modal.style.left, w:modal.style.width, h:modal.style.height, b:modal.style.bottom, r:modal.style.right };
          Object.assign(modal.style, { top:'0', left:'0', width:'100%', height:'100%', borderRadius:'0', bottom:'auto', right:'auto' });
        } else {
          Object.assign(modal.style, { top:maxOldPos.t, left:maxOldPos.l, width:maxOldPos.w, height:maxOldPos.h, bottom:maxOldPos.b, right:maxOldPos.r, borderRadius:'10px' });
        }
        isMax = !isMax;
      };
      head.onmousedown = (e) => {
        if (e.target.id.startsWith('t-')) return;
        const rect = modal.getBoundingClientRect();
        setTrans(false);
        modal.style.top = rect.top + 'px';
        modal.style.left = rect.left + 'px';
        modal.style.bottom = 'auto';
        modal.style.right = 'auto';
        let ox = e.clientX - rect.left, oy = e.clientY - rect.top;
        document.onmousemove = (e) => { modal.style.left=(e.clientX-ox)+'px'; modal.style.top=(e.clientY-oy)+'px'; };
        document.onmouseup = () => { document.onmousemove = null; };
      };
      const resizeHandle = document.createElement('div');
      resizeHandle.style.cssText = 'position:absolute; bottom:0; right:0; width:12px; height:12px; cursor:se-resize; z-index:10001; background:linear-gradient(135deg, transparent 50%, #888 50%);';
      modal.appendChild(resizeHandle);
      resizeHandle.onmousedown = (e) => {
        e.preventDefault();
        e.stopPropagation();
        const startX = e.clientX, startY = e.clientY;
        const startW = modal.offsetWidth, startH = modal.offsetHeight;
        ifrm.style.pointerEvents = 'none';
        document.onmousemove = (e) => {
          modal.style.width  = Math.max(300, startW + e.clientX - startX) + 'px';
          modal.style.height = Math.max(100, startH + e.clientY - startY) + 'px';
        };
        document.onmouseup = () => { document.onmousemove = null; ifrm.style.pointerEvents = ''; };
      };
    };
    // Placement: land immediately to the LEFT of the reboot icon, in whatever
    // row actually holds it. Verified identical on every firmware checked -
    // .hd-right > .switch > [ ...icons..., reboot ] on 4.3.25 through op25.
    //
    // Climb only through wrappers that contain nothing but us (an <el-tooltip>
    // may or may not materialise as its own element depending on the Element-UI
    // build), then insert as a sibling. Bounded by .hd-right so we can never
    // escape the header.
    //
    // Do NOT compute this from a neighbouring icon. The previous version derived
    // the insertion parent from .icon-question-circle, and that is precisely
    // what broke: on 4.3.25 the help icon is a plain sibling, but from 4.8.6 it
    // moved inside a support dropdown, so the derived parent resolved outside
    // the toolbar and the button was inserted where nobody could see it.
    // Equally, do not insert relative to .hd-right itself - that would place the
    // button before the whole .switch group and MOVE it on firmwares where it
    // currently renders correctly.
    try {
      const box = anchor.closest('.hd-right');
      let node = anchor, guard = 0;
      while (node.parentElement && node.parentElement !== box
             && node.parentElement.children.length === 1 && ++guard < 20) {
        node = node.parentElement;
      }
      node.parentNode.insertBefore(wrapper, node);
    } catch(e) {
      try { anchor.parentNode.insertBefore(wrapper, anchor); } catch(e2) {}
    }
  };
  // Retry forever: the panel is a single-page app, so the toolbar is rebuilt on
  // navigation and the button has to be re-added each time. Errors are contained
  // per tick so one bad frame cannot stop later attempts.
  setInterval(() => { try { inject(); } catch(e) {} },1000);
})();
EOF
    [ "$_iti_proto" = "https" ] && sed -i 's|http://|https://|g' "$_iti_js"
    gzip -c "$_iti_js" > "$_iti_gz"
    rm -f "$_iti_js"
    rm -rf /var/lib/nginx/*
}

manage_web_terminal() {
    while true; do
        clear
        print_centered_header "Web-UI Terminal Interface"
        
        TARGET_GZ=$(ls /www/js/app.*.js.gz | head -n 1)
        if [ -z "$TARGET_GZ" ]; then
            print_error "Cannot find target JS file for patching. Exiting"
            press_any_key
            return
        fi
        
        # Check Service Status via Procd
        if pgrep ttyd >/dev/null; then
            if grep -q "option ssl '1'" /etc/config/ttyd 2>/dev/null; then
                svc_status="${GREEN}RUNNING (HTTPS)${RESET}"
            else
                svc_status="${GREEN}RUNNING (HTTP)${RESET}"
            fi
        else
            svc_status="${RED}STOPPED${RESET}"
        fi
        
        zcat "$TARGET_GZ" 2>/dev/null | grep -q "term-wrapper" && inj_status="${GREEN}ENABLED${RESET}" || inj_status="${YELLOW}DISABLED${RESET}"

        # Read the port from config rather than assuming 7681 - it is a uci
        # option and a user may well have changed it.
        ttyd_port=$(uci -q get ttyd.@ttyd[0].port 2>/dev/null); : "${ttyd_port:=7681}"
        grep -q "option ssl '1'" /etc/config/ttyd 2>/dev/null && ttyd_url_proto="https" || ttyd_url_proto="http"
        ttyd_lan_ip=$(get_lan_ip 2>/dev/null)

        printf " %b\n" "${CYAN}STATUS${RESET}"
        printf "   ttyd Service:   %b\n" "$svc_status"
        printf "   Web UI Button:  %b\n" "$inj_status"
        # The button depends on the admin panel's markup, which differs between
        # firmware builds; the direct URL always works when the service is up, so
        # show it rather than leaving the terminal unreachable if the button is
        # missing.
        if pgrep ttyd >/dev/null 2>&1 && [ -n "$ttyd_lan_ip" ]; then
            printf "   Direct URL:     %b\n\n" "${CYAN}${ttyd_url_proto}://${ttyd_lan_ip}:${ttyd_port}${RESET}"
        else
            printf "   Direct URL:     %b\n\n" "${GREY}(service not running)${RESET}"
        fi
        
        printf "%s%sEnable Web-UI Terminal\n" "$N1" "$NSEP"
        printf "%s%sDisable Web-UI Terminal\n" "$N2" "$NSEP"
        printf "%s%sCompletely Uninstall\n" "$N3" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-3/0/?]: "
        read -r term_choice
        printf "\n"
        
        case $term_choice in
            1)
                ttyd_proto="http"
                hash -r
                if pgrep ttyd >/dev/null; then
                    if [ "$inj_status" = "${GREEN}ENABLED${RESET}" ]; then
                         print_warning "Web-UI Terminal is already running and patched."
                         press_any_key
                         continue
                    else
                         grep -q "option ssl '1'" /etc/config/ttyd 2>/dev/null && ttyd_proto="https"
                         print_warning "Web-UI Terminal service is running but UI is not patched. Re-patching"
                    fi
                else
                    if ! command -v ttyd >/dev/null 2>&1; then
                        install_package ttyd
                    fi

                    print_info "Configuring ttyd service"
                    printf "\n"

                    # Detect HTTPS mode and prompt for connection mode
                    redirect_https=$(uci -q get uhttpd.main.redirect_https 2>/dev/null)
                    if [ "$redirect_https" = "1" ]; then
                        print_warning "The GL Admin Panel is set to force HTTPS. ttyd will be installed in HTTPS mode so the\nembedded terminal loads correctly in your browser."
                        ttyd_proto="https"
                    else
                        print_info "ttyd runs over HTTP by default and will not work when accessing the Admin Panel via HTTPS.\nttyd over HTTPS works when accessing the Admin Panel via HTTP or HTTPS but requires a\none-time browser cert acceptance."
                        printf "   Use HTTPS? [y/N]: "
                        read -r proto_choice
                        printf "\n"
                        [ "$proto_choice" = "y" ] || [ "$proto_choice" = "Y" ] && ttyd_proto="https"
                    fi

                    # Generate cert if HTTPS chosen
                    if [ "$ttyd_proto" = "https" ]; then
                        if [ ! -f /etc/ttyd.crt ] || [ ! -f /etc/ttyd.key ]; then
                            if ! require_cmd openssl openssl-util "OpenSSL command-line tools"; then
                                print_error "OpenSSL isn't available, so an HTTPS certificate can't be generated."
                                print_info "Using HTTP for the Web-UI Terminal instead."
                                printf "\n"
                                ttyd_proto="http"
                            else
                                print_info "Generating self-signed certificate for ttyd"
                                printf "\n"
                                if openssl req -x509 -nodes -newkey rsa:2048 \
                                        -keyout /etc/ttyd.key -out /etc/ttyd.crt -days 3650 \
                                        -subj "/CN=gl-router" >/dev/null 2>&1 && [ -s /etc/ttyd.crt ] && [ -s /etc/ttyd.key ]; then
                                    print_success "Generated /etc/ttyd.crt and /etc/ttyd.key"
                                    printf "\n"
                                else
                                    rm -f /etc/ttyd.crt /etc/ttyd.key
                                    print_error "Certificate generation failed; using HTTP for the Web-UI Terminal instead."
                                    printf "\n"
                                    ttyd_proto="http"
                                fi
                            fi
                        else
                            print_info "SSL certificates already exist, reusing."
                            printf "\n"
                        fi
                    fi

                    # Write UCI config
                    if [ "$ttyd_proto" = "https" ]; then
                        cat << 'UCIEOF' > /etc/config/ttyd
config ttyd
	option enable '1'
	option port '7681'
	option interface '@lan'
	option command '/bin/login'
	option ssl '1'
	option ssl_cert '/etc/ttyd.crt'
	option ssl_key '/etc/ttyd.key'
	list client_option 'scrollback=10000'
	list client_option 'theme={"background":"#000000"}'
	list client_option 'titleFixed="Terminal"'
	# Pinned so the modal's pixel size maps predictably onto columns x rows.
	# Without it the cell size follows the browser's default monospace font
	# and the same window yields a different terminal geometry per machine.
	# This does NOT stop the user resizing: xterm.js refits on every container
	# change, so drag-resize, maximise and minimise all still work.
	list client_option 'fontSize=12'
UCIEOF
                        lan_ip=$(get_lan_ip)
                        print_warning "Before using the terminal, open a new tab and visit: ${CYAN}https://${lan_ip}:7681${RESET}"
                        print_warning "You must accept the certificate warning, then return to the Admin Panel."
                        print_warning "The terminal will not load until this is done!"
                        printf "\n"
                    else
                        cat << 'UCIEOF' > /etc/config/ttyd
config ttyd
	option enable '1'
	option port '7681'
	option interface '@lan'
	option command '/bin/login'
	list client_option 'scrollback=10000'
	list client_option 'theme={"background":"#000000"}'
	list client_option 'titleFixed="Terminal"'
	# Pinned so the modal's pixel size maps predictably onto columns x rows.
	# Without it the cell size follows the browser's default monospace font
	# and the same window yields a different terminal geometry per machine.
	# This does NOT stop the user resizing: xterm.js refits on every container
	# change, so drag-resize, maximise and minimise all still work.
	list client_option 'fontSize=12'
UCIEOF
                    fi

                    /etc/init.d/ttyd enable
                    /etc/init.d/ttyd restart >/dev/null 2>&1

                    # Verify ttyd actually came up before patching the UI + claiming success. The restart
                    # can fail SILENTLY (a bad/invalid SSL cert, a wrong system clock, or the port already
                    # in use), which otherwise leaves a "Web-UI Terminal Installed" message + a dead page.
                    _ttyd_port=$(uci -q get ttyd.@ttyd[0].port 2>/dev/null); : "${_ttyd_port:=7681}"
                    _ttyd_up=0
                    for _i in 1 2 3 4 5; do
                        if { netstat -ltn 2>/dev/null || ss -ltn 2>/dev/null; } | grep -q ":${_ttyd_port} "; then _ttyd_up=1; break; fi
                        sleep 1
                    done
                    if [ "$_ttyd_up" -ne 1 ]; then
                        printf "\n"
                        print_error "ttyd did not start - nothing is listening on port ${_ttyd_port}."
                        _why=$(logread 2>/dev/null | grep -i ttyd | tail -3)
                        [ -n "$_why" ] && { print_info "Last ttyd log lines:"; printf '%s\n' "$_why" | sed 's/^/   /'; printf "\n"; }
                        print_info "Common causes: an invalid certificate, a wrong system clock, or port ${_ttyd_port} already in use."
                        print_info "Run ${GREY}/etc/init.d/ttyd restart${RESET} to see the error, and check ${GREY}date${RESET} against the certificate."
                        print_warning "The Web-UI was not patched (the terminal button would lead to a dead page)."
                        press_any_key
                        continue
                    fi

                fi

                # UI Injection
                print_info "Patching Web-UI"
                printf "\n"
                _inject_terminal_into "$TARGET_GZ" "$ttyd_proto" 1
                print_success "Web-UI Terminal installed."
                printf "\n"
                _hard_refresh_hint
                press_any_key
                ;;

            2)
                print_info "Disabling Web Terminal"
                printf "\n"
                
                # Only attempt to stop/disable if the service script exists
                
                if [ -f "/etc/init.d/ttyd" ]; then
                    if pgrep ttyd >/dev/null; then
                        print_info "Stopping ttyd service"
                        printf "\n"
                        /etc/init.d/ttyd stop 2>/dev/null
                        /etc/init.d/ttyd disable 2>/dev/null
                        killall ttyd >/dev/null 2>&1
                        print_success "Service stopped."
                        printf "\n"
                    else
                        print_warning "ttyd service is not running."
                        printf "\n"
                    fi
                else
                    print_warning "ttyd service not found; skipping service stop."
                    printf "\n"
                fi

                # Restore UI to stock regardless of service status
                if [ -f "/rom$TARGET_GZ" ]; then
                    cp -f "/rom$TARGET_GZ" "$TARGET_GZ"
                    rm -rf /var/lib/nginx/*
                    print_success "Web UI button removed and cache cleared."
                    # Restoring app.*.js.gz from ROM also drops any fan-slider
                    # range patch, since both features edit the same file. The
                    # fan's actual behaviour (uci glfan) is untouched; only the
                    # web-UI slider range reverts. Tell the user rather than
                    # silently reverting it.
                    # Only on devices that actually have a fan - /etc/config/glfan
                    # is absent on fanless models (e.g. MT1300), so this stays
                    # quiet there.
                    if [ -f /etc/config/glfan ]; then
                        print_info "If you customised Fan settings, re-apply them - the panel was reset to stock here."
                    fi
                    printf "\n"
                    _hard_refresh_hint
                else
                    print_error "ROM backup not found. Manual UI restoration required."
                fi
                press_any_key
                ;;

            3)
                print_warning "Completely Uninstalling ttyd"
                printf "\n"
                
                # Stop service before removal if it exists
                if command -v ttyd >/dev/null 2>&1 || [ -f "/etc/init.d/ttyd" ]; then
                    if pgrep ttyd >/dev/null; then
                        print_info "Stopping ttyd service"
                        printf "\n"
                        /etc/init.d/ttyd stop 2>/dev/null
                        killall ttyd >/dev/null 2>&1
                        print_success "Service stopped."
                        printf "\n"
                    else
                        print_warning "ttyd service is not running."
                        printf "\n"
                    fi
                    pkg_remove ttyd >/dev/null 2>&1
                    rm -f /etc/config/ttyd
                    if [ -f /etc/ttyd.crt ] || [ -f /etc/ttyd.key ]; then
                        print_info "Removing ttyd SSL certificates"
                        printf "\n"
                        rm -f /etc/ttyd.crt /etc/ttyd.key
                        print_success "SSL certificates removed."
                        printf "\n"
                    fi
                    print_success "ttyd package uninstalled."
                    printf "\n"
                fi

                # Always ensure the UI is restored
                if [ -f "/rom$TARGET_GZ" ]; then
                    cp -f "/rom$TARGET_GZ" "$TARGET_GZ"
                    rm -rf /var/lib/nginx/*
                    print_success "Web UI button removed and cache cleared."
                    # Restoring app.*.js.gz from ROM also drops any fan-slider
                    # range patch, since both features edit the same file. The
                    # fan's actual behaviour (uci glfan) is untouched; only the
                    # web-UI slider range reverts. Tell the user rather than
                    # silently reverting it.
                    # Only on devices that actually have a fan - /etc/config/glfan
                    # is absent on fanless models (e.g. MT1300), so this stays
                    # quiet there.
                    if [ -f /etc/config/glfan ]; then
                        print_info "If you customised Fan settings, re-apply them - the panel was reset to stock here."
                    fi
                else
                    print_error "ROM backup not found. Manual UI restoration required."
                fi
                press_any_key
                ;;
            0) return ;;
            \?|h|H|❓) show_terminal_help ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# --- Manage Packages ---

get_action_text() {
    local t_i=$1 local t_p=$2 local o_i=$3 local o_p=$4
    
    if [ "$t_i" -eq "$o_i" ] && [ "$t_p" -eq "$o_p" ]; then
        echo "No Change"
    elif [ "$t_i" -eq 1 ] && [ "$o_i" -eq 0 ]; then
        [ "$t_p" -eq 1 ] && echo "> Install + Persist" || echo "> Install Package"
    elif [ "$t_i" -eq 1 ] && [ "$o_i" -eq 1 ] && [ "$t_p" -ne "$o_p" ]; then
        [ "$t_p" -eq 1 ] && echo "> Enable Persistence" || echo "> Disable Persistence"
    elif [ "$t_i" -eq 0 ] && [ "$o_i" -eq 1 ]; then
        [ "$o_p" -eq 1 ] && echo "> Remove + Unpersist" || echo "> Remove Package"
    else
        echo "No Change"
    fi
}

create_lazarus_hook() {
    local hook="/etc/uci-defaults/99-lazarus"
    cat << 'EOF' > "$hook"
#!/bin/sh
# Lazarus Survival Engine - Post-Upgrade Package Restoration Hook
#
# This runs standalone from /etc/uci-defaults after a sysupgrade, with NONE of
# the toolkit's helpers loaded - so the apk/opkg choice is inlined rather than
# calling pkg_update/pkg_install, which do not exist in this context.
if [ -f /etc/lazarus.list ]; then
    if command -v apk >/dev/null 2>&1; then
        apk update
        for _lz in $(cat /etc/lazarus.list 2>/dev/null); do apk add "$_lz"; done
    else
        opkg update
        for _lz in $(cat /etc/lazarus.list 2>/dev/null); do opkg install "$_lz"; done
    fi
fi
# Re-persist the healer list itself
grep -qFx "/etc/lazarus.list" /etc/sysupgrade.conf || echo "/etc/lazarus.list" >> /etc/sysupgrade.conf
exit 0
EOF
    chmod +x "$hook"
}

manage_packages() {
    # Define the Utility Database (Package|Binary|Config/Service Files)
    # Types: R = Reinstall (Complex), B = Binary (Simple)
    # Ookla ships no MIPS build, so on MIPS the internet speed test is speedtest-go (a GitHub
    # binary, not an opkg package) - offer THAT as the installable entry there instead. Both
    # install/remove via the special-cases in the apply loop below.
    local _st_line="speedtest|/usr/bin/speedtest|B|/usr/bin/speedtest /root/.config/ookla/speedtest-cli.json"
    case "$(uname -m)" in mips*) _st_line="speedtest-go|/usr/bin/speedtest-go|B|/usr/bin/speedtest-go" ;; esac
    # stress-ng can crash routers on kernels < 6.6 - withhold it there (empty entry -> skipped by the
    # init loop's blank-name guard); offered normally on 6.6+ where the kernel bug is fixed.
    local _stressng_line="stress-ng|/usr/bin/stress-ng|B|/usr/bin/stress-ng"
    _stressng_unsafe && _stressng_line=""
    local UTILITY_DB="zram-swap|/etc/init.d/zram|R|/etc/init.d/zram /etc/config/system
librespeed-go|/usr/bin/librespeed-go|R|/usr/bin/librespeed-go /etc/config/librespeed-go /etc/init.d/librespeed-go
stress|/usr/bin/stress|B|/usr/bin/stress
$_stressng_line
lscpu|/usr/bin/lscpu|B|/usr/bin/lscpu
apache|/usr/bin/htpasswd|R|/usr/bin/htpasswd
openssl-util|/usr/bin/openssl|B|/usr/bin/openssl
htop|/usr/bin/htop|B|/usr/bin/htop
rsync|/usr/bin/rsync|B|/usr/bin/rsync
diffutils|/usr/bin/diff|B|/usr/bin/diff
vim-fuller|/usr/bin/vim|R|/usr/bin/vim
$_st_line
iperf3|/usr/bin/iperf3|B|/usr/bin/iperf3
tailscale|/usr/sbin/tailscale|R|/etc/config/tailscale /etc/tailscale
iputils-ping|/usr/bin/ping|B|/usr/bin/ping"

    local map_file="/tmp/pkg_manage_map"
    local sys_conf="/etc/sysupgrade.conf"
    local laz_list="/etc/lazarus.list"
    local sort_mode="size"                    # size | name; toggled by [S]
    local sizes_file="/tmp/pkg_manage_sizes"  # name|sizeKB, computed once per entry
    local idx_sizes="/tmp/pkg_manage_idx"     # name|bytes from ONE batched 'opkg info' (see init)
    local _pkg_opts="[A] All   [N] None   [#] Toggle   [S] Sort   [C] Confirm   [0] Cancel   [?] Help"
    local _pkg_div; _pkg_div=$(awk -v n="${#_pkg_opts}" 'BEGIN{s="";for(i=0;i<n;i++)s=s"─";print s}')
    # Overlay filesystem: ubifs/jffs2 compress transparently (uncompressed sizes overstate real
    # flash use), f2fs/ext4 do not. Drives whether the storage projection is exact or an "≈"
    # floor - see _pkg_storage_line.
    local overlay_fs; overlay_fs=$(awk '$2=="/overlay"{print $3; exit}' /proc/mounts 2>/dev/null)
    local fs_comp=0; case "$overlay_fs" in ubifs|jffs2) fs_comp=1 ;; esac

    # Size (KB) for a package: an installed one's actual on-disk footprint (its own files,
    # rom or overlay), or a not-installed one's download size from the index.
    # Binaries installed from GitHub/Ookla, absent from every opkg/apk feed - best-effort INSTALL
    # size (the extracted binary, measured) so their column isn't blank. Estimates; arch varies a bit.
    _nonindex_bytes() {
        case "$1" in
            speedtest-go) echo 8782007 ;;   # ~8.4M GitHub binary (MIPS)
            speedtest)    echo 2541880 ;;   # ~2.5M Ookla CLI (measured aarch64; other arches similar)
            *)            echo 0 ;;
        esac
    }
    _pkg_size() {
        local name="$1" bin="$2" paths="$3" list="/usr/lib/opkg/info/$1.list" kb=0 files="" bytes
        if [ "$(pkg_mgr)" = apk ]; then
            # apk-tools (OpenWrt 24.10+/25, newer GL firmware) has no opkg feeds to parse. `apk info -s`
            # reports the installed size for BOTH installed and available (index) packages in one fast
            # local call ("<pkg>-<ver> installed size:\n284 KiB"), so it fills the whole column. Fall
            # back to du only for a toolkit-made symlink apk doesn't know (e.g. stress -> stress-ng).
            kb=$(apk info -s "$name" 2>/dev/null | awk '
                $2=="B"   {printf "%d",($1+1023)/1024; exit}
                $2=="KiB" {printf "%d",$1;             exit}
                $2=="MiB" {printf "%d",$1*1024;        exit}
                $2=="GiB" {printf "%d",$1*1048576;     exit}')
            case "$kb" in ''|*[!0-9]*) kb=0 ;; esac
            # non-index binaries (Ookla speedtest, speedtest-go) aren't in apk either - use the estimate
            if [ "$kb" -le 0 ]; then bytes=$(_nonindex_bytes "$name"); [ "$bytes" -gt 0 ] && kb=$(( (bytes + 1023) / 1024 )); fi
            if [ "$kb" -le 0 ] && [ -e "$bin" ]; then
                files=$(for f in $bin $paths; do [ -f "$f" ] && echo "$f"; done | sort -u)
                [ -n "$files" ] && kb=$(du -sk $files 2>/dev/null | awk '{s+=$1} END{print s+0}')
            fi
            printf '%s' "${kb:-0}"; return
        fi
        if [ -e "$bin" ]; then
            # installed: actual on-disk size of its files, measured at their real paths. This
            # covers firmware/rom-provided packages too - they can still be removed from the
            # active partition (they only return on a firmware reset/upgrade), so they have a
            # real size worth showing, not a blank. For overlay-installed packages the active
            # file IS the overlay copy, so this is the same number as before.
            if [ -f "$list" ]; then
                files=$(while read -r f; do [ -f "$f" ] && echo "$f"; done < "$list")
            fi
            # dedupe: $bin is often also listed in $paths (busybox 'du -s a a' double-counts).
            [ -z "$files" ] && files=$(for f in $bin $paths; do [ -f "$f" ] && echo "$f"; done | sort -u)
            [ -n "$files" ] && kb=$(du -sk $files 2>/dev/null | awk '{s+=$1} END{print s+0}')
        else
            # not installed: estimated INSTALL size (index Installed-Size), from the pre-built
            # map (init_system_state parses it once - see there for why we don't loop opkg).
            bytes=$(_nonindex_bytes "$name")   # GitHub/Ookla binaries: fixed estimate, not in the index
            [ "$bytes" -eq 0 ] && bytes=$(grep -m1 "^$name|" "$idx_sizes" 2>/dev/null | cut -d'|' -f2)
            case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
            [ "$bytes" -gt 0 ] && kb=$(( (bytes + 1023) / 1024 ))
        fi
        printf '%s' "${kb:-0}"
    }
    _fmt_kb() {
        local k="${1:-0}"; case "$k" in ''|*[!0-9]*) k=0 ;; esac
        [ "$k" -le 0 ] && { printf -- '-'; return; }
        if [ "$k" -ge 1024 ]; then awk -v k="$k" 'BEGIN{printf "%.1fM", k/1024}'; else printf '%dK' "$k"; fi
    }
    # Like _fmt_kb but for free/total space: adds a G tier and never prints "-" (0 is a real
    # value here, not "unknown").
    _fmt_space() {
        local k="${1:-0}"; case "$k" in ''|*[!0-9]*) k=0 ;; esac
        if   [ "$k" -ge 1048576 ]; then awk -v k="$k" 'BEGIN{printf "%.2fG", k/1048576}'
        elif [ "$k" -ge 1024 ];    then awk -v k="$k" 'BEGIN{printf "%.1fM", k/1024}'
        else printf '%dK' "$k"; fi
    }
    # Overlay storage line: current free/total, plus a live projection of free space after the
    # staged install/remove changes. On a compressing overlay (ubifs/jffs2) the uncompressed
    # sizes overstate real flash use, so the projection is a conservative floor, marked "≈";
    # on f2fs/ext4 it is exact. Amber when the projected free would get low. Persist toggles
    # don't touch overlay space (sysupgrade.conf is tiny), so only install-state changes count.
    _pkg_storage_line() {
        local free tot
        read -r free tot <<EOF
$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4, $2}')
EOF
        case "$free" in ''|*[!0-9]*) free=0 ;; esac
        case "$tot"  in ''|*[!0-9]*) tot=0 ;; esac
        local delta=0 nm ti tp oi s
        while IFS='|' read -r _ nm ti tp _ _ _ oi _; do
            [ -z "$nm" ] && continue
            [ "$ti" = "$oi" ] && continue        # install state unchanged -> no overlay delta
            s=$(grep -m1 "^$nm|" "$sizes_file" 2>/dev/null | cut -d'|' -f2)
            case "$s" in ''|*[!0-9]*) s=0 ;; esac
            if [ "$ti" -eq 1 ]; then delta=$((delta - s)); else delta=$((delta + s)); fi
        done < "$map_file"
        printf " %bStorage:%b  %s free of %s" "$CYAN" "$RESET" "$(_fmt_space "$free")" "$(_fmt_space "$tot")"
        if [ "$delta" -ne 0 ]; then
            local proj=$((free + delta)); [ "$proj" -lt 0 ] && proj=0
            local approx="" col="$GREEN"
            [ "$fs_comp" -eq 1 ] && approx="≈ "
            [ "$proj" -lt 10240 ] && col="$YELLOW"      # < 10M projected free -> flag amber
            printf "   %b→%b  %b%s%s%b after changes" "$GREY" "$RESET" "$col" "$approx" "$(_fmt_space "$proj")" "$RESET"
            [ "$proj" -lt 10240 ] && printf "  %b(low)%b" "$YELLOW" "$RESET"
        fi
        printf "\n"
    }
    # Re-sort the map by $sort_mode and renumber the visible index (field 1).
    _pkg_resort() {
        # busybox sort can't sort by a mid-line -k field reliably (sort -t'|' -k2,2 is
        # a no-op there), so annotate each row with its sort key (name, or size KB) in a
        # leading tab-delimited field, sort on that, then strip it back off.
        local tmp="${map_file}.rs"
        {
            while IFS= read -r _l; do
                _n=$(printf '%s' "$_l" | cut -d'|' -f2)
                if [ "$sort_mode" = name ]; then
                    printf '%s\t%s\n' "$_n" "$_l"
                else
                    _k=$(grep -m1 "^$_n|" "$sizes_file" 2>/dev/null | cut -d'|' -f2); : "${_k:=0}"
                    printf '%s\t%s\n' "$_k" "$_l"
                fi
            done < "$map_file"
        } | if [ "$sort_mode" = name ]; then sort; else sort -rn; fi | cut -f2- > "$tmp"
        awk -F'|' -v OFS='|' '{$1=NR; print}' "$tmp" > "$map_file"
        rm -f "$tmp"
    }
    
    # Initialization: Scan current system state
    init_system_state(){
    rm -f "$map_file" "$sizes_file" "$idx_sizes"
    # Not-installed sizes come from the package index; refresh it when empty (opkg keeps
    # the lists under /tmp, so they vanish on reboot). Runs behind the caller's spinner.
    # Refresh only when the index is empty AND the internet is actually up (a quick ping,
    # so an offline entry doesn't wait out the timeout). Bound the update at 60s - a full
    # refresh is ~30s on a slow MIPS box - so a stalled feed can't hang. Anything still
    # unknown afterwards falls back to "-".
    if [ "$(pkg_mgr)" = opkg ] && [ -z "$(find /var/opkg-lists /tmp/opkg-lists -type f 2>/dev/null)" ] \
       && ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then timeout 60 opkg update >/dev/null 2>&1
        else opkg update >/dev/null 2>&1; fi
    fi
    # Cache every not-installed INSTALL size in ONE pass. We show install size (not download)
    # for every package, so parse the index's Installed-Size field, not Size (the .ipk
    # download). 'opkg info <pkg>' cold-parses the whole index on every call (~3s on MIPS) and
    # only ever reports its FIRST argument, so a call per package made this loop ~3s*N; one awk
    # over the feeds builds name|bytes for the whole feed in well under a second. The feeds are
    # usually gzip-compressed on disk (zcat), but plain on some boxes (cat fallback - busybox
    # 'zcat -f' does NOT pass plain text through). NB: some feeds under-report Installed-Size
    # for compressible binaries (e.g. librespeed-go), so a not-installed size is a best-effort
    # estimate; the storage projection treats it as such. Absent names -> "-".
    : > "$idx_sizes"
    if [ "$(pkg_mgr)" = opkg ]; then
        local _files _f
        # /var is a symlink to /tmp on OpenWrt, so both globs hit the same feeds - dedupe by
        # basename (keep the first path per feed) so we decompress each feed once, not twice.
        _files=$(find /var/opkg-lists /tmp/opkg-lists -type f 2>/dev/null | awk -F/ '!seen[$NF]++')
        for _f in $_files; do
            zcat "$_f" 2>/dev/null || cat "$_f" 2>/dev/null
        done | awk '/^Package: /{n=$2} /^Installed-Size: /{if(n!=""){print n"|"$2; n=""}}' > "$idx_sizes"
    fi
    local i=1
    echo "$UTILITY_DB" | while IFS='|' read -r name bin type paths; do
        [ -z "$name" ] && continue
        local inst=0; [ -f "$bin" ] && inst=1
        local pers=0
        # Persistence is only meaningful for an INSTALLED package (there is no persist-without-install);
        # only reflect it when installed, so the Persist column can never show a checked box for a
        # package that isn't there.
        if [ "$inst" -eq 1 ]; then
            for p in $paths; do
                if grep -qFx "$p" "$sys_conf" 2>/dev/null; then pers=1; break; fi
            done
        fi
        # Format: Index|Name|Target_I|Target_P|Action|Type|Paths|Orig_I|Orig_P
        echo "$i|$name|$inst|$pers|No Change|$type|$paths|$inst|$pers" >> "$map_file"
        printf '%s|%s\n' "$name" "$(_pkg_size "$name" "$bin" "$paths")" >> "$sizes_file"
        i=$((i+1))
    done
    _pkg_resort
    }

    # Standard setup-screen flow: show the header, then a spinner while sizes are
    # gathered (and the opkg index is refreshed if empty), then the loop clears and
    # renders the full menu. Sizes that can't be determined fall back to "-".
    clear
    print_centered_header "Package & Persistence Manager"
    spin_run "Collecting package sizes" init_system_state

    while true; do
        clear
        print_centered_header "Package & Persistence Manager"
        _pkg_storage_line          # print_centered_header already leaves one blank line above
        printf "\n"
        # ↓ marks the sorted column; pre-padded to the same display width as the data
        # columns (%-19s / %-7s) so the arrow's byte width doesn't shift the layout.
        if [ "$sort_mode" = name ]; then _hn="Package Name ↓     "; _hs="Size   "
        else                             _hn="Package Name       "; _hs="Size ↓ "; fi
        printf "       %-7s %-7s %s %s %s\n" "Install" "Persist" "$_hn" "$_hs" "Planned Action"
        printf " %s\n" "$_pkg_div"

        while IFS='|' read -r idx name i_t p_t action type paths o_i o_p; do
            local i_box="  [ ]  "; [ "$i_t" -eq 1 ] && i_box="  [✓]  "
            local p_box="  [ ]  "; [ "$p_t" -eq 1 ] && p_box="  [✓]  "
            local sz; sz=$(grep -m1 "^$name|" "$sizes_file" 2>/dev/null | cut -d'|' -f2)
            # Semantic action colour, matching the confirm screen (green = install/persist,
            # red = remove/unpersist); "No Change" stays dim so staged rows stand out. Check
            # the destructive words first ("Disable Persistence" contains "Persist").
            local _ac
            case "$action" in
                "No Change")                    _ac="$GREY" ;;
                *Remove*|*Disable*|*Unpersist*) _ac="$RED" ;;
                *Install*|*Enable*)             _ac="$GREEN" ;;
                *)                              _ac="$CYAN" ;;
            esac
            printf " %-5s %s %s %-19s %-7s %b%s%b\n" "$idx." "$i_box" "$p_box" "$name" "$(_fmt_kb "${sz:-0}")" "$_ac" "$action" "${RESET}"
        done < "$map_file"

        printf " %s\n" "$_pkg_div"
        printf " %s\n" "$_pkg_opts"
        pkg_count=$(wc -l < "$map_file" 2>/dev/null | tr -dc '0-9')
        printf "\n Choose [%s/A/N/S/C/0/?]: " "$(picker_range "$pkg_count")"
        read -r cmd
        cmd=$(echo "$cmd" | tr 'A-Z' 'a-z')

        case "$cmd" in
            a|A) 
                # Step 1: Force targets to 1|1 for all rows
                awk -F'|' -v OFS='|' '{$3=1; $4=1; print}' "$map_file" > "${map_file}.tmp"
                
                # Step 2: Re-calculate the "Smart" action text for all 9 columns
                while IFS='|' read -r idx name ti tp act type paths oi op; do
                    new_act=$(get_action_text 1 1 "$oi" "$op")
                    echo "$idx|$name|1|1|$new_act|$type|$paths|$oi|$op"
                done < "${map_file}.tmp" > "$map_file"
                rm -f "${map_file}.tmp"
                ;;
            n|N)
                # Step 1: Force targets to 0|0 for all rows
                awk -F'|' -v OFS='|' '{$3=0; $4=0; print}' "$map_file" > "${map_file}.tmp"
                
                # Step 2: Re-calculate the "Smart" action text for all 9 columns
                while IFS='|' read -r idx name ti tp act type paths oi op; do
                    new_act=$(get_action_text 0 0 "$oi" "$op")
                    echo "$idx|$name|0|0|$new_act|$type|$paths|$oi|$op"
                done < "${map_file}.tmp" > "$map_file"
                rm -f "${map_file}.tmp"
                ;;
            [1-9]*)
                if grep -q "^$cmd|" "$map_file"; then
                    local line=$(grep "^$cmd|" "$map_file")
                    # Extract columns (Note the new positions for Orig_I and Orig_P)
                    local name=$(echo "$line" | cut -d'|' -f2)
                    local cur_i=$(echo "$line" | cut -d'|' -f3)
                    local cur_p=$(echo "$line" | cut -d'|' -f4)
                    local type=$(echo "$line" | cut -d'|' -f6)
                    local paths=$(echo "$line" | cut -d'|' -f7)
                    local o_i=$(echo "$line" | cut -d'|' -f8)
                    local o_p=$(echo "$line" | cut -d'|' -f9)
                    
                    # 3-Way Cycle: (0,0) -> (1,0) -> (1,1) -> Back to (0,0)
                    local next_i=0; local next_p=0
                    if [ "$cur_i" -eq 0 ] && [ "$cur_p" -eq 0 ]; then
                        next_i=1; next_p=0
                    elif [ "$cur_i" -eq 1 ] && [ "$cur_p" -eq 0 ]; then
                        next_i=1; next_p=1
                    else
                        next_i=0; next_p=0
                    fi
                    
                    # Get the smart action text based on the NEW targets vs ORIGINAL live state
                    local next_act=$(get_action_text "$next_i" "$next_p" "$o_i" "$o_p")
                    
                    # Update the map file
                    grep -v "^$cmd|" "$map_file" > "${map_file}.tmp"
                    echo "$cmd|$name|$next_i|$next_p|$next_act|$type|$paths|$o_i|$o_p" >> "${map_file}.tmp"
                    sort -n "${map_file}.tmp" > "$map_file" && rm -f "${map_file}.tmp"
                fi
                ;;
            c)
                # 1. Build Confirmation Lists
                local to_add=""; local to_rem=""
                while IFS='|' read -r idx name t_i t_p action type paths o_i o_p; do
                    # Skip if no change
                    [ "$action" == "No Change" ] && continue

                    # Match specific strings for Additions
                    case "$action" in
                        "> Install Package")
                            to_add="${to_add}\n  + $name (Install)"
                            ;;
                        "> Install + Persist")
                            to_add="${to_add}\n  + $name (Install + Persist)"
                            ;;
                        "> Enable Persistence")
                            to_add="${to_add}\n  + $name (Persist)"
                            ;;
                    esac

                    # Match specific strings for Removals
                    case "$action" in
                        "> Remove Package")
                            to_rem="${to_rem}\n  - $name (Remove)"
                            ;;
                        "> Remove + Unpersist")
                            to_rem="${to_rem}\n  - $name (Remove + Unpersist)"
                            ;;
                        "> Disable Persistence")
                            to_rem="${to_rem}\n  - $name (Unpersist)"
                            ;;
                    esac
                done < "$map_file"

                if [ -z "$to_add" ] && [ -z "$to_rem" ]; then
                    print_error "No changes planned."; sleep 2; continue
                fi

                clear
                print_centered_header "Confirm System Changes"
                [ -n "$to_add" ] && { printf "${GREEN}TO BE INSTALLED or PERSISTED:${RESET}"; printf "$to_add\n\n"; }
                [ -n "$to_rem" ] && { printf "${RED}TO BE REMOVED or UNPERSISTED:${RESET}"; printf "$to_rem\n\n"; }
                
                printf "Proceed with changes? [y/N]: "; read -r confirm; printf "\n"
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    install_fail=0; rem_kept=""; rem_fail=""; rem_forced=""
                    # map_file columns: idx|name|i_t|p_t|action|type|paths|o_i|o_p
                    while IFS='|' read -r idx name i_t p_t action type paths o_i o_p; do
                        [ "$action" == "No Change" ] && continue
                        
                        # EXECUTE REMOVALS
                        if [[ "$action" == *"> Remove"* ]] || [[ "$action" == *"> Unpersist"* ]]; then
                            if [ "$i_t" -eq 0 ]; then
                                if pkg_is_installed "$name"; then
                                    # Tailscale: remove the GL wrapper (the dependent) FIRST so the base
                                    # package then removes cleanly and frees its ~6.4M, instead of hitting
                                    # a 'depended upon' wall and force-breaking gl-sdk4-tailscale.
                                    [ "$name" = tailscale ] && pkg_is_installed gl-sdk4-tailscale && pkg_remove gl-sdk4-tailscale >/dev/null 2>&1
                                    # opkg-managed: let opkg remove the package (and all its files).
                                    _rout=$(pkg_remove "$name" 2>&1)
                                    if pkg_is_installed "$name"; then
                                        if printf '%s' "$_rout" | grep -qi 'depended upon'; then
                                            # Required by other packages. Default = keep it; offer a
                                            # typed-YES forced removal with a clear warning.
                                            printf "\n"
                                            print_warning "'$name' is required by other installed packages:"
                                            # Pull just the dependent package NAMES out of opkg's noisy
                                            # "print_dependents_warning: <pkg>" lines (skip the header + the
                                            # "Collected errors:" / "No packages removed." chatter).
                                            _deps=$(printf '%s\n' "$_rout" | grep 'dependents_warning' \
                                                | grep -vi 'depended upon\|circular' \
                                                | sed 's/.*dependents_warning:[[:space:]]*//' \
                                                | grep -E '^[A-Za-z0-9._+-]+$' | head -12)
                                            if [ -n "$_deps" ]; then printf '%s\n' "$_deps" | sed 's/^/     - /'
                                            else printf "     (other installed packages depend on it)\n"; fi
                                            printf "   Forcing removal leaves those packages with a broken dependency.\n"
                                            printf "   Type %bYES%b to force-remove '%s' anyway, anything else to keep it: " "$BOLD" "$RESET" "$name"
                                            read -r _force </dev/tty; printf "\n"
                                            case "$_force" in
                                                [Yy][Ee][Ss])
                                                    opkg remove --force-depends --autoremove "$name" >/dev/null 2>&1
                                                    if pkg_is_installed "$name"; then
                                                        rem_fail="${rem_fail}\n     - $name (force-remove failed)"
                                                    else
                                                        rem_forced="${rem_forced}\n     - $name (force-removed; dependents may be broken)"
                                                    fi ;;
                                                *) rem_kept="${rem_kept}\n     - $name (kept - required by other packages)" ;;
                                            esac
                                        else
                                            rem_fail="${rem_fail}\n     - $name (could not be removed)"
                                        fi
                                    fi
                                else
                                    # Not an opkg package (raw binary / util) - remove everything it owns
                                    # so nothing is left behind, but never a shared core config file.
                                    for p in $paths; do
                                        case "$p" in
                                            /etc/config/system|/etc/config/network|/etc/config/wireless|/etc/config/firewall|/etc/config/dhcp|/etc/config/dropbear|/etc/config/uhttpd) : ;;
                                            *) rm -rf "$p" 2>/dev/null ;;
                                        esac
                                    done
                                fi
                            fi

                            # Standard cleanup for paths and survival lists
                            for p in $paths; do sed -i "\|$p|d" "$sys_conf" 2>/dev/null; done
                            [ -f "$laz_list" ] && sed -i "\|$name|d" "$laz_list" 2>/dev/null
                        fi

                        # EXECUTE INSTALLS
                        if [[ "$action" == *"Install"* ]] || [[ "$action" == *"Persist"* ]]; then
                            if [ "$i_t" -eq 1 ]; then
                                if [ "$name" == "speedtest" ]; then
                                    install_ookla_speedtest
                                elif [ "$name" == "speedtest-go" ]; then
                                    install_speedtest_go /usr/bin || install_fail=$((install_fail + 1))
                                elif [ "$name" == "tailscale" ]; then
                                    # Tailscale = base binaries (tailscale, ~6.4M) + GL integration
                                    # (gl-sdk4-tailscale: service, /etc/config, admin-panel UI, firewall
                                    # killswitch). Install both so the feature actually works; the wrapper
                                    # is best-effort (absent on the oldest firmware) and only the base
                                    # counts toward install_fail.
                                    install_package tailscale || install_fail=$((install_fail + 1))
                                    pkg_is_installed tailscale && install_package gl-sdk4-tailscale >/dev/null 2>&1
                                else
                                    install_package "$name" || install_fail=$((install_fail + 1))
                                fi
                            fi

                            if [ "$p_t" -eq 1 ]; then
                                for p in $paths; do grep -qFx "$p" "$sys_conf" || echo "$p" >> "$sys_conf"; done
                                if [ "$type" == "R" ]; then
                                    grep -qFx "$name" "$laz_list" 2>/dev/null || echo "$name" >> "$laz_list"
                                    create_lazarus_hook
                                fi
                            elif [ "$o_p" -eq 1 ]; then
                                # Persistence turned OFF while the package stays installed ("Disable
                                # Persistence") - actually strip its sysupgrade + boot-restore entries
                                # (this path used to do nothing, so persistence never got removed).
                                for p in $paths; do sed -i "\|$p|d" "$sys_conf" 2>/dev/null; done
                                [ -f "$laz_list" ] && sed -i "\|$name|d" "$laz_list" 2>/dev/null
                            fi
                        fi
                    done < "$map_file"
                    if [ "$install_fail" -eq 0 ] && [ -z "$rem_fail" ] && [ -z "$rem_kept" ] && [ -z "$rem_forced" ]; then
                        print_success "System changes applied."
                    else
                        print_warning "Changes applied, with exceptions:"
                        [ "$install_fail" -gt 0 ] && printf "   %d package(s) failed to install.\n" "$install_fail"
                        [ -n "$rem_kept" ]   && { printf "   %bKept - required by other installed packages:%b" "$YELLOW" "$RESET"; printf "$rem_kept\n"; }
                        [ -n "$rem_fail" ]   && { printf "   %bCould not be removed:%b" "$RED" "$RESET"; printf "$rem_fail\n"; }
                        [ -n "$rem_forced" ] && { printf "   %bForce-removed (dependent packages may now be broken):%b" "$YELLOW" "$RESET"; printf "$rem_forced\n"; }
                    fi
                    press_any_key
                    clear
                    print_centered_header "Package & Persistence Manager"
                    spin_run "Refreshing package list" init_system_state
                    continue
                fi
                ;;
            s) [ "$sort_mode" = size ] && sort_mode=name || sort_mode=size; _pkg_resort ;;
            0) rm -f "$map_file" "$sizes_file" "$idx_sizes" 2>/dev/null; return ;;
            \?|h|H|❓) show_package_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# --- Manage SSH ---

show_ssh_help() {
    show_paged "SSH Key Management - Help" << 'HELPEOF'
SSH Key Management – Quick Help

What is an SSH Key?
───────────────────
An SSH key is a "digital passport" that allows you to log into your router
securely without typing your password every time. It consists of a 
Public Key (which stays on the router) and a Private Key (which stays on 
your computer). 

Main Benefits:
• Security: Keys are virtually impossible to brute-force compared to passwords.
• Convenience: Log in instantly from your terminal or script.
• Persistence: This script can ensure your keys survive firmware updates.

How to find or generate your Public Key:
────────────────────────────────────────
Your Public Key usually ends in .pub. DO NOT paste your Private Key.

• macOS / Linux:
  1. Open Terminal.
  2. Check for existing keys: cat ~/.ssh/id_rsa.pub (or id_ed25519.pub)
  3. To generate new: ssh-keygen -t ed25519
  4. Copy the output of: cat ~/.ssh/id_ed25519.pub

• Windows (PowerShell/CMD):
  1. Open PowerShell.
  2. Check for existing keys: cat $HOME\.ssh\id_rsa.pub
  3. To generate new: ssh-keygen -t ed25519
  4. Copy the text starting with "ssh-ed25519..."

• Windows (PuTTY):
  1. Open 'PuTTYgen'.
  2. Click 'Load' (for existing) or 'Generate' (for new).
  3. Copy the text from the box labeled: 
     "Public key for pasting into OpenSSH authorized_keys file"

Usage in this Menu:
───────────────────
1. Add Key: Paste the entire line (starts with ssh-rsa, ssh-ed25519, etc.).
2. Manage: View existing keys. Use [✓] to mark keys for deletion.
3. Persistence: Adds /etc/dropbear/authorized_keys to the
   sysupgrade list so you don't lose access after a firmware update.

Security Warning:
─────────────────
Never share your PRIVATE key with anyone. Only the PUBLIC key belongs
on the router.
HELPEOF
}

manage_ssh_keys() {
    local auth_file="/etc/dropbear/authorized_keys"
    local up_conf="/etc/sysupgrade.conf"
    local ssh_data="/tmp/ssh_mgr.data"

    while true; do
        # 1. Status Calculations
        local key_count=0
        [ -f "$auth_file" ] && key_count=$(grep -c "^ssh-" "$auth_file")
        
        local persistence="${YELLOW}DISABLED${RESET}"
        grep -qFx "$auth_file" "$up_conf" 2>/dev/null && persistence="${GREEN}ENABLED${RESET}"

        clear
        print_centered_header "SSH Key Management"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        printf "   Authorized Keys:  %d\n" "$key_count"
        printf "   Persistence:      %b\n\n" "$persistence"

        local ssh_persist_label="Enable Persistence"
        [ "$persistence" = "${GREEN}ENABLED${RESET}" ] && ssh_persist_label="Disable Persistence"
        printf "%s%sAdd a New SSH Key\n" "$N1" "$NSEP"
        printf "%s%sManage / Delete Keys\n" "$N2" "$NSEP"
        printf "%s%s%s\n" "$N3" "$NSEP" "$ssh_persist_label"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        
        printf "\nChoose [1-3/0/?]: "
        read -r ssh_choice
        
        case "$ssh_choice" in
            1) # ADD KEY
                printf "\n${CYAN}Paste your public key (starts with ssh-rsa, etc.):${RESET}\n"
                read -r new_key
                printf "\n"
                if echo "$new_key" | grep -qE "^ssh-(rsa|ed25519|dss|ecdsa) "; then
                    # Extract base64 part for duplicate check
                    local key_base64=$(echo "$new_key" | awk '{print $2}')
                    if [ -f "$auth_file" ] && grep -q "$key_base64" "$auth_file"; then
                        print_warning "Key already exists in authorized_keys."
                    else
                        mkdir -p /etc/dropbear
                        echo "$new_key" >> "$auth_file"
                        chmod 0700 /etc/dropbear && chmod 0600 "$auth_file"
                        print_success "Key added successfully."
                    fi
                else
                    print_error "Invalid key format."
                fi
                press_any_key ;;

            2) # MANAGE / DELETE UI
                if [ ! -s "$auth_file" ]; then
                    print_error "No keys found to manage."
                    sleep 1; continue
                fi

                while true; do
                    # Generate fresh temp data: Index | Type | Identity | Selected(0/1)
                    # Use awk to handle keys with no comments by truncating the key string itself
                    awk '{
                        type=$1; 
                        # If comment (field 3) exists, use it. Otherwise, truncate field 2.
                        if ($3 != "") { 
                            id=$3; for(i=4;i<=NF;i++) id=id" "$i 
                        } else { 
                            id="(No comment) " substr($2,1,15)"..." 
                        }
                        print NR "|" type "|" id "|0"
                    }' "$auth_file" > "$ssh_data"

                    while true; do
                        clear
                        print_centered_header "SSH Authorized Keys Manager"
                        printf "\n"
                        printf " %-5s %-4s %-12s %-40s\n" "Sel" "Idx" "Key Type" "Identity / Comment"
                        printf " ────────────────────────────────────────────────────────────────\n"
                        while IFS='|' read -r idx type id sel; do
                            s_box=" [ ] "; [ "$sel" -eq 1 ] && s_box=" [✓] "
                            printf " %s %-4s %-12s %-40s\n" "$s_box" "$idx." "$type" "$id"
                        done < "$ssh_data"
                        printf " ────────────────────────────────────────────────────────────────\n"
                        printf " [A] All   [N] None   [#] Toggle   [D] Delete   [0] Cancel\n"
                        key_count=$(wc -l < "$ssh_data" 2>/dev/null | tr -dc '0-9')
                        printf "\n Choose [%s/A/N/D/0]: " "$(picker_range "$key_count")"
                        read -r cmd

                        case "$cmd" in
                            a|A) sed -i 's/|0$/|1/' "$ssh_data" ;;
                            n|N) sed -i 's/|1$/|0/' "$ssh_data" ;;
                            [0-9]*)
                                [ "$cmd" -eq 0 ] && break 2
                                awk -F'|' -v t="$cmd" 'BEGIN{OFS="|"} {if($1==t) $4=($4==1?0:1); print}' "$ssh_data" > "$ssh_data.tmp" && mv "$ssh_data.tmp" "$ssh_data" ;;
                            d|D)
                                local to_del=$(awk -F'|' '$4==1' "$ssh_data")
                                if [ -z "$to_del" ]; then
                                    print_warning "No keys selected."; sleep 2; continue
                                fi
                                
                                clear
                                print_centered_header "Confirm Deletion"
                                echo "$to_del" | awk -F'|' '{print "  - " $2 " (" $3 ")"}'
                                printf "\nDelete selected keys? [y/N]: "; read -r confirm
                                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                                    # Create a keep-list of line numbers
                                    local lines_to_keep=$(awk -F'|' '$4==0 {print $1}' "$ssh_data")
                                    if [ -z "$lines_to_keep" ]; then
                                        > "$auth_file" # Wipe if all deleted
                                    else
                                        # Use awk to reconstruct the file from original line numbers
                                        local tmp_auth="/tmp/auth.keep"
                                        for l in $lines_to_keep; do
                                            sed -n "${l}p" "$auth_file" >> "$tmp_auth"
                                        done
                                        mv "$tmp_auth" "$auth_file"
                                    fi
                                    chmod 0600 "$auth_file"
                                    print_success "Keys updated."
                                    break 2
                                fi ;;
                            0) break 2 ;;
                        esac
                    done
                done
                rm -f "$ssh_data" ;;

            3) # TOGGLE PERSISTENCE
                printf "\n"
                if grep -qFx "$auth_file" "$up_conf" 2>/dev/null; then
                    sed -i "\|$auth_file|d" "$up_conf"
                    print_warning "Persistence disabled. Keys will be lost on firmware upgrade."
                else
                    echo "$auth_file" >> "$up_conf"
                    print_success "Persistence enabled. Keys will survive firmware upgrades."
                fi
                press_any_key ;;
                
            0) return ;;
            \?|h|H|❓) show_ssh_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

show_system_tweaks_help() {
    show_paged "System Tweaks - Help" << 'HELPEOF'
System Tweaks – Quick Help

Overview
────────
This menu groups configuration and management tools for common GL.iNet
router customizations. Each option targets a specific subsystem.

Options
───────
1. Device Fan Settings
   Adjust fan speed thresholds, min/max RPM, and thermal warning temps.
   Only available on hardware with controllable fans (e.g. Flint 3).

2. Manage Zram Swap
   Install and configure compressed RAM swap. Essential on low-RAM
   devices running AdGuardHome + VPN simultaneously.

3. Web-UI Terminal Interface
   Embed a draggable terminal (powered by ttyd) into the GL.iNet
   Admin Panel as a ">_" icon in the navigation bar.

4. Package and Persistence Manager
   Install useful CLI tools (htop, tcpdump, etc.) and configure them
   to survive firmware upgrades via the sysupgrade keep-list.

5. Package System Repair
   Fix a corrupted package system (the "Missing new line character at
   end of file" opkg error) by rebuilding the feed cache and/or
   repairing the installed database, with backups.

6. Toolkit Management
   Install this script to /usr/sbin/glinet_utils so it can be run
   from anywhere. Manage sysupgrade persistence and updates.

Moved: the Bandwidth Limiter (now any network, not just guest) and SSH Key
Management now live under Network and VPN Tools on the main menu.
HELPEOF
}

# -----------------------------
# Toolkit Management
# -----------------------------

toolkit_is_installed() {
    [ -f "$INSTALL_PATH" ]
}

toolkit_persistence_enabled() {
    grep -qFx "$INSTALL_PATH" /etc/sysupgrade.conf 2>/dev/null
}

set_toolkit_persistence() {
    local enable="$1"
    local keep_conf="/etc/sysupgrade.conf"
    if [ "$enable" -eq 1 ]; then
        if ! grep -qFx "$INSTALL_PATH" "$keep_conf" 2>/dev/null; then
            printf "%s\n" "$INSTALL_PATH" >> "$keep_conf"
            print_success "Added to $keep_conf — will survive firmware upgrades."
        else
            print_info "Already persisted in $keep_conf — no change."
        fi
    else
        if grep -qFx "$INSTALL_PATH" "$keep_conf" 2>/dev/null; then
            sed -i "\|^${INSTALL_PATH}$|d" "$keep_conf" 2>/dev/null
            print_success "Removed from $keep_conf — will not survive firmware upgrades."
        else
            print_info "Not in $keep_conf — no change."
        fi
    fi
}

show_toolkit_help() {
    show_paged "Toolkit Management - Help" << 'HELPEOF'
Toolkit Management – Quick Help

Install to /usr/sbin/glinet_utils
──────────────────────────────────
Copies this script to /usr/sbin/glinet_utils (no .sh extension) so
you can run it from any directory by typing just: glinet_utils

Once installed, the self-updater always targets the installed copy,
keeping a single up-to-date version on your router.

Sysupgrade Persistence
──────────────────────
By default, files added to /usr/sbin via the overlay filesystem are
lost when you perform a firmware upgrade (sysupgrade). Enabling
persistence adds /usr/sbin/glinet_utils to /etc/sysupgrade.conf so
the file is preserved across upgrades.

After a firmware upgrade, the preserved copy will check GitHub for
updates on its first run and self-update if a newer version exists.

View Change Log & Update
────────────────────────
Browse the full change log, newest first. When you are behind, a
line marks your installed version (everything above it is new to
you) and [U] updates in place and restarts. The heading reads
"View Change Log" when you are already up to date.

Uninstall
─────────
Removes /usr/sbin/glinet_utils and its sysupgrade.conf entry.
The script you are currently running is not affected.
HELPEOF
}

# True only if $1 is a readable copy of THIS toolkit (shebang + the "# Version:" marker). Guards
# the installer against copying a mis-resolved SCRIPT_PATH: when the script is piped into a shell
# ($0 = "sh"/"ash"), SCRIPT_PATH resolves via `command -v` to /bin/sh -> a symlink to busybox, and
# a blind `cp "$SCRIPT_PATH" /usr/sbin/glinet_utils` would replace the command with busybox (which
# then answers "glinet_utils: applet not found"). Verify before we ever copy.
_is_toolkit_file() {
    [ -r "$1" ] || return 1
    head -1 "$1" 2>/dev/null | grep -q '^#!' || return 1
    grep -q '^# Version:' "$1" 2>/dev/null
}

check_install_prompt() {
    local ip_ans
    [ "$SCRIPT_PATH" = "$INSTALL_PATH" ] && return
    [ "$INSTALL_PROMPTED" -eq 1 ] && return
    _is_toolkit_file "$SCRIPT_PATH" || return   # piped/stdin run: no real file to install, don't offer

    print_info "Installing to $INSTALL_PATH lets you run this program from anywhere as a system command."
    printf "Install as a system command? [Y/n]: "
    read -r ip_ans
    printf "\n"
    case "$ip_ans" in
        n|N)
            sed -i 's/^INSTALL_PROMPTED=0$/INSTALL_PROMPTED=1/' "$SCRIPT_PATH"
            print_info "Skipping. You can install later via System Tweaks → Toolkit Management."
            STARTUP_NOTICE=1
            ;;
        *)
            do_install_to_sbin "$@"
            ;;
    esac
}

do_install_to_sbin() {
    local persist_ans
    # Never copy anything that isn't this toolkit (see _is_toolkit_file). A piped run mis-resolves
    # SCRIPT_PATH to /bin/sh -> busybox; copying that would brick the installed command.
    if ! _is_toolkit_file "$SCRIPT_PATH"; then
        print_error "Can't install: couldn't locate the running script."
        print_info "This happens when the toolkit is piped into a shell. Save it to a file and run that:"
        print_info "  sh glinet_utils.sh"
        press_any_key
        return 1
    fi
    print_action "Installing to $INSTALL_PATH"
    if ! cp "$SCRIPT_PATH" "$INSTALL_PATH" || ! chmod +x "$INSTALL_PATH"; then
        print_error "Install failed. Check write permissions on /usr/sbin."
        press_any_key
        return 1
    fi
    print_success "Installed to $INSTALL_PATH"

    if ! toolkit_persistence_enabled; then
        printf "\n   Persist across firmware upgrades? [Y/n]: "
        read -r persist_ans
        printf "\n"
        case "$persist_ans" in
            n|N) print_warning "Not persisted — will be lost on next sysupgrade." ;;
            *)   set_toolkit_persistence 1 ;;
        esac
    fi

    printf "\n"
    print_action "Switching to installed copy"
    sleep 2
    exec "$INSTALL_PATH" "$@"
}

manage_display_settings() {
    # Per-mode preview screen. Uses hardcoded escapes so each sample renders
    # truthfully regardless of the currently active OUTPUT_MODE.
    _display_settings_screen() {
        local page="$1" detected="$2"
        local _R="\033[0m" _G="\033[32m" _Y="\033[33m" _B="\033[38;5;153m" _C="\033[36m" _RD="\033[31m"
        # The Full-mode samples below must be padded for the CURRENT TERMINAL,
        # not the current OUTPUT_MODE - which is why they cannot simply use
        # $_S_OK/$_S_ERR (those follow the active mode, so previewing Full mode
        # from Compatible mode would show the wrong glyphs entirely).
        #
        # On Termius ✅ and ❌ advance one cell but PAINT two, so the single
        # trailing space used everywhere else lands on top of the glyph and the
        # sample renders short. Mirror the padding detect_output_mode applies.
        # ❓ is the same kind of glyph and needs the same treatment. The real
        # menus print it as "$NQ" plus ONE space at the call site, and the
        # termius profile sets NQ="❓ " so the total is two - matching the two
        # spaces the keycap rows use. Hardcoding one space here left Help sitting
        # a column left of the numbered items.
        #
        # _pPAD is a sacrificial trailing space, and it is load-bearing.
        #
        # Measured in Termius: when a line carries a glyph that paints wider than
        # it advances (✅ ❌ advance 1, paint 2), the LAST CELL OF EACH COLOUR RUN
        # on that line is clipped. Not the last cell of the line - the run. That
        # distinction was established by testing two lines differing only in
        # whether a trailing space sat inside or outside the reset: inside, the
        # space was eaten and the text survived; outside, the text lost its final
        # character instead. It is also why the Status row lost a character in
        # BOTH halves - two runs, two clipped cells.
        #
        # So each run ends with a space for the terminal to eat. Splitting the
        # runs (glyph in one, text in another) does NOT help on its own - that
        # was tried and the text run still lost its last character.
        #
        # Termius only: everywhere else the space is NOT consumed, and the Status
        # row's second column would sit a space further right than the first.
        # Glyphs carrying VS16 (⚠️ ℹ️ ⚙️) advance 2 and paint 2, so they never
        # overflow and those rows need none of this.
        local _pOK="✅ " _pERR="❌ " _pQ="❓ " _pPAD=""
        # ttyd renders these exactly as Termius does - ✅ ❌ ❓ advance one
        # cell but paint two - so both need the wider pad. This was keyed on
        # termius alone, which is why the samples still looked wrong in the
        # web terminal after the ttyd PROFILE symbols were corrected: this
        # page does not use _S_OK/NQ, it has its own copies.
        case "$_TERM_PROFILE" in
            termius|ttyd) _pOK="✅  "; _pERR="❌  "; _pQ="❓  " ;;
        esac
        # _pPAD is the sacrificial trailing space for Termius's colour-run
        # clipping. ttyd does NOT clip - "successfully" renders complete there
        # - so it stays empty, or every row would gain a stray space.
        [ "$_TERM_PROFILE" = termius ] && _pPAD=" "
        case "$page" in
            1)
                printf " %bPage 1 of 3 — Full mode%b (emoji symbols + color)\n\n" "${BOLD}${CYAN}" "$_R"
                printf "   %bMessages%b\n" "$_C" "$_R"
                printf "     %b%s%b%bOperation completed successfully%s%b\n" "$_G" "$_pOK" "$_R" "$_G" "$_pPAD" "$_R"
                printf "     %b%s%b%bOperation failed%s%b\n" "$_RD" "$_pERR" "$_R" "$_RD" "$_pPAD" "$_R"
                printf "     %b⚠️  Something needs attention%s%b\n" "$_Y" "$_pPAD" "$_R"
                printf "     %bℹ️  Informational message%s%b\n" "$_B" "$_pPAD" "$_R"
                printf "     %b⚙️  Action in progress%s%b\n\n" "$_C" "$_pPAD" "$_R"
                printf "   %bStatus%b\n" "$_C" "$_R"
                printf "     %b%s%b%bOn / enabled / running%s%b      %b%s%b%bOff / disabled / stopped%s%b\n\n" "$_G" "$_pOK" "$_R" "$_G" "$_pPAD" "$_R" "$_RD" "$_pERR" "$_R" "$_RD" "$_pPAD" "$_R"
                printf "   %bA menu looks like%b\n" "$_C" "$_R"
                printf "     1️⃣  Show Hardware Information\n"
                printf "     2️⃣  AdGuardHome Control Center\n"
                printf "     3️⃣  System Tweaks\n"
                printf "     0️⃣  Exit\n"
                printf "     %sHelp\n" "$_pQ"
                ;;
            2)
                printf " %bPage 2 of 3 — Compatible mode%b (Unicode symbols + color, PuTTY-safe)\n\n" "${BOLD}${CYAN}" "$_R"
                printf "   %bMessages%b\n" "$_C" "$_R"
                printf "     %b✓  Operation completed successfully%b\n" "$_G" "$_R"
                printf "     %b✗  Operation failed%b\n" "$_RD" "$_R"
                printf "     %b⚠  Something needs attention%b\n" "$_Y" "$_R"
                printf "     %bℹ  Informational message%b\n" "$_B" "$_R"
                printf "     %b⚙  Action in progress%b\n\n" "$_C" "$_R"
                printf "   %bStatus%b\n" "$_C" "$_R"
                printf "     %b✓ On / enabled / running%b      %b✗ Off / disabled / stopped%b\n\n" "$_G" "$_R" "$_RD" "$_R"
                printf "   %bA menu looks like%b\n" "$_C" "$_R"
                printf "     [1]  Show Hardware Information\n"
                printf "     [2]  AdGuardHome Control Center\n"
                printf "     [3]  System Tweaks\n"
                printf "     [0]  Exit\n"
                printf "     [?]  Help\n"
                ;;
            3)
                printf " %bPage 3 of 3 — Auto%b (detect terminal on each launch)\n\n" "${BOLD}${CYAN}" "$_R"
                printf "   Re-detects your terminal every time the toolkit\n"
                printf "   starts and selects Full or Compatible automatically.\n\n"
                printf "   Right now it would use:\n"
                printf "     %b%s%b\n" "$_G" "$detected" "$_R"
                ;;
        esac
    }

    local page_num=1 total=3
    while true; do
        clear
        print_centered_header "Display Settings"
        printf " ──────────────────────────────────────────────────────────────────────────────\n"

        local pref_display
        case "$OUTPUT_PREF" in
            full)   pref_display="${GREEN}Full${RESET}"                  ;;
            compat) pref_display="${YELLOW}Compatible${RESET}"           ;;
            *)      pref_display="${CYAN}Auto (detect each run)${RESET}" ;;
        esac
        printf "   Saved default: %b\n\n" "$pref_display"
        # Auto page needs to show what auto would currently resolve to.
        local detected_desc
        case "$OUTPUT_MODE" in
            full)
                case "$_TERM_PROFILE" in
                    ttyd)    detected_desc="ttyd (browser) → Full mode" ;;
                    wt)      detected_desc="Windows Terminal → Full mode" ;;
                    termius) detected_desc="Termius → Full mode" ;;
                    *)       detected_desc="macOS/Linux Terminal → Full mode" ;;
                esac
                ;;
            *)
                case "$_TERM_PROFILE" in
                    putty) detected_desc="PuTTY / xterm → Compatible (colour glyphs)" ;;
                    *)     detected_desc="Basic terminal → Compatible mode" ;;
                esac
                ;;
        esac

        _display_settings_screen "$page_num" "$detected_desc"

        # Footer / navigation (mirrors the Hardware Info pager)
        printf "\n ──────────────────────────────────────────────────────────────────────────────\n"
        printf " [P] Prev   "
        local i=1
        while [ "$i" -le "$total" ]; do
            if [ "$i" -eq "$page_num" ]; then
                printf "%b[%d]%b " "${BOLD}" "$i" "${RESET}"
            else
                printf "%b[%d]%b " "${GREY}" "$i" "${RESET}"
            fi
            i=$((i + 1))
        done
        printf "  [N] Next   [C] Confirm   [0] Back  "

        local nav_choice
        nav_choice=$(read_single_char)
        printf "\n"

        case "$nav_choice" in
            p|P|b|B) [ "$page_num" -gt 1 ] && page_num=$((page_num - 1)) ;;
            n|N)     [ "$page_num" -lt "$total" ] && page_num=$((page_num + 1)) ;;
            1|2|3)   page_num="$nav_choice" ;;
            c|C)
                local new_pref
                case "$page_num" in
                    1) new_pref="full"   ;;
                    2) new_pref="compat" ;;
                    3) new_pref="auto"   ;;
                esac
                local pref_label
                case "$new_pref" in
                    full)   pref_label="Full"       ;;
                    compat) pref_label="Compatible" ;;
                    auto)   pref_label="Auto"        ;;
                    *)      pref_label="$new_pref"   ;;
                esac
                printf "\n"
                print_info "Set display mode to $pref_label."
                printf "   Save as default? [Y/n]: "
                read -r ds_save
                printf "\n"
                case "$ds_save" in
                    n|N)
                        OUTPUT_PREF="$new_pref"
                        detect_output_mode
                        print_info "Applied for this session only (not saved)."
                        ;;
                    *)
                        sed -i "s/^OUTPUT_PREF=\"[^\"]*\"/OUTPUT_PREF=\"$new_pref\"/" "$SCRIPT_PATH"
                        OUTPUT_PREF="$new_pref"
                        detect_output_mode
                        print_success "Saved as default: $pref_label"
                        ;;
                esac
                press_any_key
                ;;
            0) return ;;
        esac
    done
}

manage_toolkit() {
    while true; do
        clear
        print_centered_header "Toolkit Management"

        local installed_status persistence_status running_from install_label persist_label
        if toolkit_is_installed; then
            installed_status="${GREEN}INSTALLED${RESET}"
            install_label="Uninstall"
        else
            installed_status="${RED}NOT INSTALLED${RESET}"
            install_label="Install"
        fi
        if toolkit_persistence_enabled; then
            persistence_status="${GREEN}ENABLED${RESET}"
            persist_label="Disable Persistence"
        else
            persistence_status="${YELLOW}DISABLED${RESET}"
            persist_label="Enable Persistence"
        fi
        if [ "$SCRIPT_PATH" = "$INSTALL_PATH" ]; then
            running_from="${GREEN}$INSTALL_PATH${RESET}"
        else
            running_from="${YELLOW}$SCRIPT_PATH${RESET} (local)"
        fi
        local mode_display
        case "$OUTPUT_MODE" in
            full)   mode_display="${GREEN}Full${RESET}"        ;;
            compat) mode_display="${YELLOW}Compatible${RESET}" ;;
            *)      mode_display="$OUTPUT_MODE"                ;;
        esac
        if [ "$OUTPUT_PREF" = "auto" ]; then
            case "$OUTPUT_MODE" in
                full)
                    case "$_TERM_PROFILE" in
                        ttyd)    mode_display="$mode_display  [auto: ttyd]" ;;
                        wt)      mode_display="$mode_display  [auto: Windows Terminal]" ;;
                        termius) mode_display="$mode_display  [auto: Termius]" ;;
                        *)       mode_display="$mode_display  [auto: macOS/Linux]" ;;
                    esac
                    ;;
                *) mode_display="$mode_display  [auto]" ;;
            esac
        fi

        local update_display update_label local_ver
        local_ver="$(grep -m1 '^# Version:' "$SCRIPT_PATH" | awk '{print $3}' | tr -d '\r')"
        [ -z "$local_ver" ] && local_ver="unknown"
        case "${UPDATE_STATUS:-unknown}" in
            available) update_display="${YELLOW}${REMOTE_VERSION} available${RESET}"; update_label="View Change Log & Update" ;;
            current)   update_display="${GREEN}Up to date${RESET}";                   update_label="View Change Log" ;;
            *)         update_display="${GREY}Unknown (offline)${RESET}";              update_label="View Change Log" ;;
        esac

        printf " %b\n" "${CYAN}STATUS${RESET}"
        printf "   Display mode: %b\n"   "$mode_display"
        printf "   Terminal:     %b\n"   "${GREEN}${TERM:-unknown}${RESET}"
        printf "   Installation: %b\n"   "$installed_status"
        printf "   Persistence:  %b\n"   "$persistence_status"
        printf "   Running from: %b\n"   "$running_from"
        printf "   Version:      %b\n"   "${GREEN}${local_ver}${RESET}"
        printf "   Update:       %b\n\n" "$update_display"

        printf "%s%s%s\n" "$N1" "$NSEP" "$install_label"
        printf "%s%s%s\n" "$N2" "$NSEP" "$persist_label"
        printf "%s%sDisplay Settings\n"          "$N3" "$NSEP"
        printf "%s%s%s\n"                        "$N4" "$NSEP" "$update_label"
        printf "%s%sBack\n"                      "$N0" "$NSEP"
        printf "%s Help\n"                       "$NQ"
        printf "\nChoose [1-4/0/?]: "
        read -r tk_choice
        printf "\n"

        case "$tk_choice" in
            1)
                if toolkit_is_installed; then
                    # Uninstall path
                    print_warning "This will remove $INSTALL_PATH from the system."
                    if [ "$SCRIPT_PATH" = "$INSTALL_PATH" ]; then
                        print_warning "You are currently running the installed copy."
                        printf "   After removal, run the script directly from its local path.\n"
                    fi
                    printf "   Remove the toolkit? [y/N]: "; read -r c; printf "\n"
                    case "$c" in
                        y|Y)
                            rm -f "$INSTALL_PATH"
                            set_toolkit_persistence 0
                            print_success "Uninstalled."
                            press_any_key
                            ;;
                        *) print_info "No change."; press_any_key ;;
                    esac
                else
                    # Install path
                if [ "$SCRIPT_PATH" = "$INSTALL_PATH" ]; then
                    print_info "Already running from the installed location."
                    press_any_key
                else
                        do_install_to_sbin "$@"
                    fi
                fi
                ;;
            2)
                if ! toolkit_is_installed; then
                    print_error "Not installed — install first (option 1)."
                    sleep 2; continue
                fi
                if toolkit_persistence_enabled; then
                    printf "   Disable sysupgrade persistence? [y/N]: "; read -r c; printf "\n"
                    case "$c" in y|Y) set_toolkit_persistence 0 ;; *) print_info "No change." ;; esac
                else
                    printf "   Enable sysupgrade persistence? [y/N]: "; read -r c; printf "\n"
                    case "$c" in y|Y) set_toolkit_persistence 1 ;; *) print_info "No change." ;; esac
                fi
                press_any_key
                ;;
            3) manage_display_settings ;;
            4)
                CL_EXIT_LABEL="Back"
                if ! show_changelog "$@"; then
                    print_warning "Unable to fetch the change log (network or GitHub issue)."
                    press_any_key
                fi
                CL_EXIT_LABEL=""
                ;;
            \?|h|H|❓) show_toolkit_help ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# =============================================================================
# VPN MTU Optimizer
# =============================================================================
# Recommended tunnel MTU = (MTU of the interface that routes to the peer's
# endpoint) - protocol overhead. WireGuard overhead is exact (60 IPv4 / 80 IPv6);
# OpenVPN is a conservative estimate. Everything is derived at runtime from
# `wg show` / `ip` — no interface names or subnets are hardcoded.
# Derive OpenVPN data-channel overhead from the running configuration rather than
# assuming a worst case.  Measured against a live tunnel with tcpdump: UDP +
# AES-256-GCM + tun + peer-id = 52 bytes on IPv4, versus the 69 previously assumed.
#   IPv4 20 + UDP 8 + opcode/peer-id 4 + GCM packet-id 4 + auth tag 16 = 52
mtu_ovpn_overhead() {                     # iface -> bytes, or empty if undecidable
    _oif="$1"; _ocfg=""; _ocipher=""; _oauth=""; _oproto=""; _ocomp=0; _ofam=IPv4
    case "$_oif" in
        ovpnserver) _ocipher=$(uci -q get ovpnserver.vpn.cipher)
                    _oauth=$(uci -q get ovpnserver.vpn.auth)
                    _oproto=$(uci -q get ovpnserver.vpn.proto) ;;
        *)          _ocfg=$(uci -q get network."$_oif".config)
                    [ -n "$_ocfg" ] && {
                        _ocipher=$(uci -q get ovpnclient."$_ocfg".cipher)
                        _oauth=$(uci -q get ovpnclient."$_ocfg".hmac)
                        _oproto=$(uci -q get ovpnclient."$_ocfg".proto); } ;;
    esac
    # the negotiated cipher wins over the configured one - NCP may pick another
    _oneg=$(logread 2>/dev/null | grep -i "Data Channel: Cipher" | tail -1 \
            | sed -n "s/.*Cipher '\([^']*\)'.*/\1/p")
    [ -n "$_oneg" ] && _ocipher="$_oneg"
    [ -z "$_ocipher" ] && return 1
    # compression adds a byte only when a directive is actually emitted
    grep -qE '^(comp-lzo|compress)' "/tmp/${_oif}/${_oif}" 2>/dev/null && _ocomp=1
    case "$_oproto" in *tcp*) _otr=20 ;; *) _otr=8 ;; esac
    # The family that matters is the UNDERLAY - the address OpenVPN's socket talks
    # to - not what routes into the tunnel.  A full-tunnel client carries the IPv6
    # default route while its own transport is still IPv4; testing the route table
    # reports IPv6 there and inflates the overhead by 20 bytes.
    _orem=$(sed -n 's/^remote  *\([^ ]*\).*/\1/p' "/tmp/${_oif}/${_oif}" 2>/dev/null | head -1)
    [ -z "$_orem" ] && [ -n "$_ocfg" ] && _orem=$(uci -q get ovpnclient."$_ocfg".remote)
    case "$_orem" in
        *:*:*) _ofam=IPv6 ;;
    esac
    [ "$_ofam" = IPv6 ] && _oip=40 || _oip=20
    case "$_ocipher" in
        *GCM*|*CHACHA20*|*gcm*|*chacha20*) _ocrypt=$((4 + 16)) ;;   # pktid 4 + tag 16
        *CBC*|*cbc*)
            case "$_oauth" in
                *SHA512*|*sha512*) _ohmac=64 ;; *SHA256*|*sha256*) _ohmac=32 ;;
                *MD5*|*md5*)       _ohmac=16 ;; *)                 _ohmac=20 ;;
            esac
            _ocrypt=$((8 + _ohmac + 16 + 16)) ;;                    # pktid+hmac+IV+pad
        *) return 1 ;;
    esac
    echo $(( _oip + _otr + 4 + _ocrypt + _ocomp ))
}

mtu_get() { ip link show "$1" 2>/dev/null | sed -n 's/.* mtu \([0-9]*\).*/\1/p' | head -1; }

# One line per active tunnel: type|role|iface|endpoint|overhead|underlay_family
mtu_detect() {
    local iface endpoint role overhead family _pid _cl _cfg
    iface=""; endpoint=""; role=""; overhead=""; family=""; _pid=""; _cl=""; _cfg=""
    if command -v wg >/dev/null 2>&1; then
        for iface in $(wg show interfaces 2>/dev/null); do
            endpoint=$(wg show "$iface" endpoints 2>/dev/null | awk 'NF>1{print $2; exit}')
            # A peer that has never connected reports the literal string "(none)"
            # - passing that through would have the probe DF-ping a hostname
            # called "(none)". Treat it as no endpoint.
            [ "$endpoint" = "(none)" ] && endpoint=""
            endpoint=$(printf '%s' "$endpoint" | sed 's/^\[//; s/\]:[0-9]*$//; s/:[0-9]*$//')
            case "$iface" in
                *server*) role=Server ;;
                *client*) role=Client ;;
                *) case "$(wg show "$iface" allowed-ips 2>/dev/null)" in *0.0.0.0/0*) role=Client ;; *) role=Server ;; esac ;;
            esac
            case "$endpoint" in *:*) overhead=80; family=IPv6 ;; *) overhead=60; family=IPv4 ;; esac
            printf 'WireGuard|%s|%s|%s|%s|%s\n' "$role" "$iface" "$endpoint" "$overhead" "$family"
        done
    fi
    for iface in $(ls /sys/class/net 2>/dev/null | grep -E '^(tun|ovpn)'); do
        [ "$(ip -4 addr show dev "$iface" 2>/dev/null | grep -c 'inet ')" -eq 0 ] && continue
        endpoint=$(ip -4 addr show dev "$iface" 2>/dev/null | sed -n 's#.*peer \([0-9.]*\).*#\1#p' | head -1)
        # GL uses `topology subnet`, so there is normally NO kernel peer field
        # and endpoint comes up empty. Read the `remote` line from the running
        # instance's config instead - that is the server's public address, which
        # the active probe wants. The right process is matched to THIS interface
        # by the --dev argument GL always passes (verified live on 4.3.25).
        if [ -z "$endpoint" ]; then
            for _pid in $(pgrep openvpn 2>/dev/null); do
                _cl=$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)
                case " $_cl" in *" --dev $iface "*) ;; *) continue ;; esac
                _cfg=$(printf '%s' "$_cl" | sed -n 's/.*--config  *\([^ ]*\).*/\1/p')
                [ -n "$_cfg" ] && [ -f "$_cfg" ] && \
                    endpoint=$(sed -n 's/^remote[ \t][ \t]*\([^ \t]*\).*/\1/p' "$_cfg" | head -1)
                break
            done
        fi
        case "$iface" in *server*) role=Server ;; *) role=Client ;; esac
        overhead=$(mtu_ovpn_overhead "$iface" 2>/dev/null)
        [ -z "$overhead" ] && overhead=69          # undecidable: keep the safe estimate
        case "$overhead" in 72|92) family=IPv6 ;; *) family=IPv4 ;; esac
        printf 'OpenVPN|%s|%s|%s|%s|%s\n' "$role" "$iface" "$endpoint" "$overhead" "$family"
    done
}

# List the config sections whose .mtu governs this tunnel — one per line, the
# functional (proto-handler) key first. Derived from GL's own netifd proto
# handlers and web UI, not guessed:
#
#   WG server   -> wireguard_server.<servers-section>          [verified 4.3/4.9]
#   OVPN server -> ovpnserver.<general-section>                [verified 4.3/4.9]
#   client 4.9  -> network.<iface>   (wg/ovpnclient.sh reads this first on ifup)
#              +  route_policy.@rule[via==iface]   (the value the web UI shows)
#   client 4.3  -> package section via network.<iface>.config pointer
#                 (ovpnclient.<cfg> / wireguard.<cfg>; no route_policy on 4.3)
#
# The 4.9-vs-4.3 split is decided structurally (does a route_policy rule name
# this interface?), never by firmware version. Prints nothing for an unmapped
# tunnel, so callers fall back to a live-only apply and say so.
mtu_gl_targets() {
    local iface type cfg proto rule
    iface="$1"; type="$2"; cfg=""; proto=""; rule=""
    case "$iface" in
        *server*)
            case "$type" in
                WireGuard) uci show wireguard_server 2>/dev/null | grep '=servers$' | head -1 | cut -d= -f1 ;;
                OpenVPN)   uci show ovpnserver 2>/dev/null | grep '=general$' | head -1 | cut -d= -f1 ;;
            esac
            return 0 ;;
    esac
    # --- client ---
    rule=$(uci show route_policy 2>/dev/null | grep "\.via='$iface'\$" | grep '@rule' | head -1 | cut -d. -f1-2)
    [ -n "$rule" ] && [ "$(uci -q get "$rule" 2>/dev/null)" != rule ] && rule=""
    if [ -n "$rule" ]; then
        # 4.9.x policy-routed model: interface MTU (functional) + rule MTU (UI).
        uci -q get network."$iface" >/dev/null 2>&1 && printf 'network.%s\n' "$iface"
        printf '%s\n' "$rule"
    else
        # 4.3.x package model: MTU lives in the section the interface points at.
        proto=$(uci -q get network."$iface".proto 2>/dev/null)
        cfg=$(uci -q get network."$iface".config 2>/dev/null)
        case "$proto" in
            ovpnclient) [ -n "$cfg" ] && printf 'ovpnclient.%s\n' "$cfg" ;;
            wgclient)   [ -n "$cfg" ] && printf 'wireguard.%s\n' "$cfg" ;;
        esac
    fi
}

# Delete any stale network.<iface>.mtu this toolkit wrote before we knew GL's
# keys — but never when network.<iface> is itself a live target (4.9.x clients).
mtu_drop_legacy() {
    rm -f "/etc/hotplug.d/iface/99-glutils-mtu-$1" 2>/dev/null
    printf '%s\n' "$2" | grep -Fqx "network.$1" && return 0
    if uci -q get network."$1".mtu >/dev/null 2>&1; then
        uci -q delete network."$1".mtu 2>/dev/null && uci -q commit network 2>/dev/null
    fi
}

# Write the MTU to every governing section, commit, and apply it live.
mtu_apply() {
    local iface val type targets primary pkgs wrote sec pkg oldifs
    iface="$1"; val="$2"; type="$3"
    targets=$(mtu_gl_targets "$iface" "$type")
    primary=""; pkgs=""; wrote=""; sec=""; pkg=""
    oldifs=$IFS; IFS='
'; set -f
    for sec in $targets; do
        [ -z "$sec" ] && continue
        uci -q set "$sec.mtu=$val" 2>/dev/null
        [ -z "$primary" ] && primary="$sec"
        case " $pkgs " in *" ${sec%%.*} "*) ;; *) pkgs="$pkgs ${sec%%.*}" ;; esac
    done
    set +f; IFS=$oldifs
    for pkg in $pkgs; do uci -q commit "$pkg" 2>/dev/null; done
    [ -n "$primary" ] && [ "$(uci -q get "$primary.mtu")" = "$val" ] && wrote=1
    mtu_drop_legacy "$iface" "$targets"
    if ip link set "$iface" mtu "$val" 2>/dev/null; then
        sleep 1
        if [ -n "$wrote" ]; then
            print_success "MTU on $iface is now $(mtu_get "$iface") (saved to the router's VPN config)."
            print_info "Shows in the GL web UI under this tunnel's Options and survives a reboot."
        elif [ -n "$primary" ]; then
            print_success "MTU on $iface is now $(mtu_get "$iface")."
            print_warning "Config write to $primary.mtu did not stick — applied live only, may not survive a reboot."
        else
            print_success "MTU on $iface is now $(mtu_get "$iface")."
            print_warning "Applied live only — this firmware's config layout isn't mapped, so it may not survive a reboot."
        fi
    else
        print_error "Failed to set MTU on $iface to $val."
    fi
}

# ---- probe persistence ------------------------------------------------------
# A credible probe result is worth keeping: the menu can then say VERIFIED
# rather than calculated, and Optimize applies the measured value. Stored beside
# Remote LAN Access's keys in /etc/config/glutils. The base link MTU and the
# target ride along so staleness is detectable - if either changes, the stored
# number no longer describes this path and mtu_v_get reports it STALE.
mtu_v_store() { # iface value kind(public|tunnel) target base-underlay-mtu
    uci -q get glutils >/dev/null 2>&1 || touch /etc/config/glutils
    uci -q get "glutils.vpn_$1" >/dev/null 2>&1 || uci set "glutils.vpn_$1=vpn"
    uci set "glutils.vpn_$1.mtu_probe=$2"
    uci set "glutils.vpn_$1.mtu_probe_kind=$3"
    uci set "glutils.vpn_$1.mtu_probe_target=$4"
    uci set "glutils.vpn_$1.mtu_probe_base=$5"
    uci set "glutils.vpn_$1.mtu_probe_date=$(date '+%Y-%m-%d')"
    uci commit glutils
}

# Forget any stored probe result so the status drops back to Calculated. Used when
# a fresh probe comes back inconclusive (frag/noreply): a prior "Verified" badge
# would otherwise linger even though the path can no longer confirm it - which is
# itself a change in VPN behaviour the status should reflect.
mtu_v_clear() {
    uci -q delete "glutils.vpn_$1.mtu_probe"        2>/dev/null
    uci -q delete "glutils.vpn_$1.mtu_probe_kind"   2>/dev/null
    uci -q delete "glutils.vpn_$1.mtu_probe_target" 2>/dev/null
    uci -q delete "glutils.vpn_$1.mtu_probe_base"   2>/dev/null
    uci -q delete "glutils.vpn_$1.mtu_probe_date"   2>/dev/null
    uci -q commit glutils 2>/dev/null
}

# iface current-underlay-mtu current-endpoint ->
#   "OK|value|kind|target|date"     fresh - outranks the calculation
#   "STALE|value|kind|target|date"  link or endpoint changed since the probe
#   nothing (rc 1)                  never probed
mtu_v_get() {
    _mv=$(uci -q get "glutils.vpn_$1.mtu_probe")
    [ -z "$_mv" ] && return 1
    _mk=$(uci -q get "glutils.vpn_$1.mtu_probe_kind")
    _mt=$(uci -q get "glutils.vpn_$1.mtu_probe_target")
    _mb=$(uci -q get "glutils.vpn_$1.mtu_probe_base")
    _md=$(uci -q get "glutils.vpn_$1.mtu_probe_date")
    if [ -n "$2" ] && [ -n "$_mb" ] && [ "$_mb" != "$2" ]; then
        echo "STALE|$_mv|$_mk|$_mt|$_md"; return 0
    fi
    if [ "$_mk" = public ] && [ -n "$3" ] && [ -n "$_mt" ] && [ "$_mt" != "$3" ]; then
        echo "STALE|$_mv|$_mk|$_mt|$_md"; return 0
    fi
    echo "OK|$_mv|$_mk|$_mt|$_md"
}

# Render the probe's Test result block + verdict + follow-up, so the public and
# through-tunnel paths word the outcome identically. Everything shown maps to a
# page-1 field (Current MTU / Recommended / Basis). outcome is one of:
#   confirm - probe agrees with the Calculated value (recorded)
#   revise  - probe found a lower real limit (recorded)
#   frag    - DF ignored, reading unusable (nothing recorded)
#   noreply - no answer, inconclusive (nothing recorded)
mtu_probe_render() {
    local ttype trole tiface cur old_rec new_rec outcome vinfo basis_was applyval
    ttype="$1"; trole="$2"; tiface="$3"; cur="$4"; old_rec="$5"; new_rec="$6"
    outcome="$7"; vinfo="$8"; basis_was="$9"
    printf " %bTest result%b\n" "$CYAN" "$RESET"
    printf "   %-18s %b%s%b\n" "Current MTU:" "$GREEN" "${cur:-N/A}" "$RESET"
    printf "   %-18s %b%s%b\n" "Calculated MTU:" "$GREEN" "${old_rec:-N/A}" "$RESET"
    case "$outcome" in
        confirm|revise) printf "   %-18s %b%s%b\n" "Verified MTU:" "$GREEN" "$new_rec" "$RESET" ;;
        *)              printf "   %-18s %bunknown%b\n" "Verified MTU:" "$GREY" "$RESET" ;;
    esac
    # The rows above are a reviewable data block (design-note 1: its own region),
    # so one blank separates them from the verdict + follow-up status lines, which
    # are grouped together below.
    printf "\n"
    case "$outcome" in
        confirm) if [ -n "$old_rec" ]; then print_success "The probe confirmed the Calculated $new_rec is optimal."
                 else print_success "The probe verified an MTU of $new_rec."; fi ;;
        revise)  print_warning "The probe verified the optimal MTU is $new_rec, not $old_rec." ;;
        frag)    print_info "Verification was inconclusive: the DF flag was ignored, so oversized packets slipped through." ;;
        noreply) print_info "Verification was inconclusive: no reply from the target, so there is nothing to measure." ;;
    esac
    case "$outcome" in
        confirm|revise) applyval="$new_rec"; print_info "Basis is now: $vinfo ($basis_was)." ;;
        *)              applyval="$old_rec"; print_info "Falling back to the Calculated ${old_rec:-N/A}; this value was not actively verified." ;;
    esac
    if [ -n "$applyval" ] && [ -n "$cur" ] && [ "$cur" != "$applyval" ]; then
        print_info "To apply $applyval, choose [1] Optimize tunnel."
    elif [ -n "$applyval" ] && [ "$cur" = "$applyval" ] && { [ "$outcome" = confirm ] || [ "$outcome" = revise ]; }; then
        print_info "Current MTU already matches — nothing to change."
    fi
}

# Binary-search the largest DF-safe packet between 1280..1500. Echoes the best size
# (0 = no reply). Split out so the search can run under spin_run - a probe takes a
# few seconds, and the spinner shows it is live rather than frozen.
mtu_bsearch() {   # pinger hdr target [iface]
    local pinger="$1" hdr="$2" target="$3" ifc="$4" lo=1280 hi=1500 best=0 mid
    while [ "$lo" -le "$hi" ]; do
        mid=$(( (lo + hi) / 2 ))
        if [ -n "$ifc" ]; then
            "$pinger" -M do -s $((mid - hdr)) -c1 -W1 -I "$ifc" "$target" >/dev/null 2>&1
        else
            "$pinger" -M do -s $((mid - hdr)) -c1 -W1 "$target" >/dev/null 2>&1
        fi
        if [ $? -eq 0 ]; then best=$mid; lo=$((mid + 1)); else hi=$((mid - 1)); fi
    done
    echo "$best"
}

# Active probe. Public endpoint FIRST: a don't-fragment search straight to the
# server's public address rides the same wire as the tunnel but outside it, so
# nothing depends on the DF flag surviving encapsulation - and the tunnel is
# never touched. The through-tunnel probe to the peer's internal IP is the
# fallback (typical for servers, whose "endpoint" is a NATed client that will
# not answer from the internet). Credible results are persisted via mtu_v_store.
mtu_probe() {
    local type iface endpoint overhead role underlay_mtu
    local own_ip peer_ip lo hi best mid computed answer pinger hdr npeers hs cur prior basis_was outcome new_rec vinfo orig
    type="$1"; iface="$2"; endpoint="$3"; overhead="$4"; role="$5"; underlay_mtu="$6"
    own_ip=""; peer_ip=""; lo=1280; hi=1500; best=0; mid=0; computed=""
    answer=""; pinger=""; hdr=28; npeers=""; hs=""; cur=""; prior=""; basis_was=""; outcome=""; new_rec=""; vinfo=""; orig=""
    clear
    print_centered_header "MTU Active Probe"
    [ -n "$underlay_mtu" ] && computed=$((underlay_mtu - overhead))

    # Tunnel-internal fallback target.
    own_ip=$(ip -4 addr show dev "$iface" 2>/dev/null | sed -n 's#.*inet \([0-9.]*\)/.*#\1#p' | head -1)
    case "$type" in
        OpenVPN)
            # The kernel peer field is ground truth when present - p2p/net30
            # topologies put the far end at .5/.9/..., NOT .1, and custom servers
            # need not sit at .1 either. But GL uses `topology subnet`, where the
            # interface has NO peer field at all (live 4.3.25: ovpnclient came up
            # as 10.8.0.2/32 and the old code declared a working tunnel
            # unprobeable). Guess the conventional gateway .1 only then.
            peer_ip=$(ip -4 addr show dev "$iface" 2>/dev/null | sed -n 's#.*peer \([0-9.]*\).*#\1#p' | head -1)
            [ -z "$peer_ip" ] && [ "$role" = Client ] && [ -n "$own_ip" ] && peer_ip="${own_ip%.*}.1"
            ;;
        *)  if [ "$role" = Client ]; then
                peer_ip="${own_ip%.*}.1"
            else
                # Only target a peer that has actually completed a handshake. A
                # configured-but-never-connected peer just eats packets and the
                # whole probe reads "inconclusive" (live: wgserver with one dead
                # peer, latest-handshake 0).
                hs=$(wg show "$iface" latest-handshakes 2>/dev/null | awk '$2>0{print $1; exit}')
                if [ -n "$hs" ]; then
                    peer_ip=$(wg show "$iface" allowed-ips 2>/dev/null | awk -v k="$hs" '$1==k{for(i=2;i<=NF;i++) if($i~/^[0-9.]+\/32$/){print $i; exit}}')
                    peer_ip=${peer_ip%/*}
                fi
            fi ;;
    esac

    if [ -z "$endpoint" ] && [ -z "$peer_ip" ]; then
        printf "\n"
        print_warning "Active probe isn't available for this tunnel."
        if [ "$type" = WireGuard ] && [ "$role" = Server ]; then
            npeers=$(wg show "$iface" allowed-ips 2>/dev/null | grep -c .)
            if [ "${npeers:-0}" -gt 0 ]; then
                print_info "$npeers peer(s) configured, but none has connected - nothing live to probe."
            else
                print_info "No peers are configured on this server."
            fi
        else
            print_info "No public endpoint or peer tunnel IP could be determined."
        fi
        press_any_key; return
    fi

    printf "\n %bWhat this does%b\n" "$CYAN" "$RESET"
    printf "   Sends test packets to find the biggest size this connection really carries,\n"
    printf "   then confirms or lowers the Recommended MTU and marks its Basis \"Verified\".\n"
    printf "   Your Current MTU is not changed. If the probe measured size is bigger, it\n"
    printf "   means the don't-fragment (DF) flag is being ignored on the path, resulting\n"
    printf "   in an oversized packet being split into two or more pieces, forwarded, and\n"
    printf "   reassembled at the receiving end, so it looks like it fit. The probe will\n"
    printf "   detect this and ignore the probed value, keeping the original Calculated\n"
    printf "   value as the Recommended value.\n"
    printf "\nRun the probe? [y/N]: "; read -r answer
    case "$answer" in y|Y) ;; *) print_info "Cancelled."; press_any_key; return ;; esac

    # Find a don't-fragment-capable pinger. Busybox ping lacks -M do and shadows
    # iputils on PATH, so when the PATH ping can't do it, install iputils via the
    # standard helper (a no-op if already present) and call /usr/bin/ping directly.
    pinger="ping"
    if ! ping -M do -c1 -W1 127.0.0.1 >/dev/null 2>&1; then
        install_package "iputils-ping" || { press_any_key; return; }
        pinger="/usr/bin/ping"
    fi
    if ! "$pinger" -M do -c1 -W1 127.0.0.1 >/dev/null 2>&1; then
        print_warning "Couldn't get a don't-fragment pinger; skipping probe."; press_any_key; return
    fi

    # old_rec (shown as "Calculated MTU") is always the Calculated value (link
    # MTU - overhead); new_rec (shown as "Verified MTU") is what this probe finds.
    # basis_was distinguishes a first verification from a refresh of an
    # already-verified tunnel.
    cur=$(mtu_get "$iface")
    prior=$(mtu_v_get "$iface" "$underlay_mtu" "$endpoint")
    case "$prior" in "OK|"*) basis_was="re-verified today" ;; *) basis_was="was: Calculated" ;; esac

    # ---- Phase 1: the native path, straight to the public endpoint ----------
    if [ -n "$endpoint" ]; then
        # 28 = IPv4 20 + ICMP 8; 48 = IPv6 40 + ICMPv6 8. A DNS-name endpoint is
        # sized as IPv4; if it resolves to IPv6 the search still converges and
        # the figure is merely conservative by the 20-byte difference.
        case "$endpoint" in *:*) hdr=48 ;; *) hdr=28 ;; esac
        printf "\n"
        spin_run "Probing the connection to $endpoint" mtu_bsearch "$pinger" "$hdr" "$endpoint"
        best=$(tr -dc '0-9' < "$SPIN_LOG" 2>/dev/null); [ -z "$best" ] && best=0
        if [ "$best" -gt 0 ]; then
            new_rec=$((best - overhead))
            if [ -n "$computed" ] && [ "$new_rec" -lt "$computed" ] 2>/dev/null; then outcome=revise; else outcome=confirm; fi
            mtu_v_store "$iface" "$new_rec" public "$endpoint" "${underlay_mtu:-}"
            vinfo="Verified $(date '+%Y-%m-%d') - public probe to $endpoint"
            printf "\n"
            mtu_probe_render "$type" "$role" "$iface" "$cur" "$computed" "$new_rec" "$outcome" "$vinfo" "$basis_was"
            press_any_key; return
        fi
        printf "\n"
        print_warning "No reply from the public endpoint (it may drop ICMP)."
        if [ -z "$peer_ip" ]; then
            mtu_v_clear "$iface"   # inconclusive: drop any stale Verified -> Basis returns to Calculated
            print_info "No tunnel peer available to fall back to - probe inconclusive."
            press_any_key; return
        fi
        print_info "Falling back to the through-tunnel probe."
        lo=1280; hi=1500; best=0
    fi

    # ---- Phase 2: through the tunnel to the internal peer -------------------
    orig=$(mtu_get "$iface")
    printf "\n"
    [ "${orig:-0}" -lt 1500 ] && ip link set "$iface" mtu 1500 2>/dev/null
    spin_run "Probing through the tunnel to $peer_ip" mtu_bsearch "$pinger" 28 "$peer_ip" "$iface"
    best=$(tr -dc '0-9' < "$SPIN_LOG" 2>/dev/null); [ -z "$best" ] && best=0
    [ -n "$orig" ] && ip link set "$iface" mtu "$orig" 2>/dev/null
    printf "\n"
    if [ "$best" -eq 0 ]; then
        outcome=noreply; new_rec=""
    elif [ -n "$computed" ] && [ "$best" -gt "$computed" ] 2>/dev/null; then
        outcome=frag; new_rec=""
    elif [ -n "$computed" ] && [ "$best" -lt "$computed" ] 2>/dev/null; then
        outcome=revise; new_rec="$best"
    else
        outcome=confirm; new_rec="$best"
    fi
    case "$outcome" in
        confirm|revise)
            mtu_v_store "$iface" "$best" tunnel "$peer_ip" "${underlay_mtu:-}"
            vinfo="Verified $(date '+%Y-%m-%d') - tunnel probe to $peer_ip" ;;
        frag|noreply)
            mtu_v_clear "$iface" ;;   # inconclusive: drop any stale Verified -> Basis returns to Calculated
    esac
    mtu_probe_render "$type" "$role" "$iface" "$cur" "$computed" "$new_rec" "$outcome" "$vinfo" "$basis_was"
    press_any_key
}
# Remove the toolkit's MTU override from every governing section so the router's
# own VPN default governs again (and the web UI field returns to Optional).
mtu_reset() {
    local iface type targets pkgs cleared sec pkg oldifs
    iface="$1"; type="$2"
    targets=$(mtu_gl_targets "$iface" "$type")
    pkgs=""; cleared=""; sec=""; pkg=""
    oldifs=$IFS; IFS='
'; set -f
    for sec in $targets; do
        [ -z "$sec" ] && continue
        uci -q get "$sec.mtu" >/dev/null 2>&1 && cleared=1
        uci -q delete "$sec.mtu" 2>/dev/null
        case " $pkgs " in *" ${sec%%.*} "*) ;; *) pkgs="$pkgs ${sec%%.*}" ;; esac
    done
    set +f; IFS=$oldifs
    for pkg in $pkgs; do uci -q commit "$pkg" 2>/dev/null; done
    mtu_drop_legacy "$iface" ""
    # Report the actual delta — only say "cleared" when something was cleared.
    if [ -n "$cleared" ]; then
        print_success "Cleared the MTU override on $iface."
        print_info "The web UI MTU field is back to Optional; restart the tunnel to pick up the default."
    else
        print_info "$iface had no MTU override — already at the router's default."
    fi
}


# Paginated per-tunnel MTU screen, matching Remote LAN Access: one tunnel per page,
# [P]/[N] to move between them, and the four actions apply to the tunnel on screen -
# no "which tunnel?" picker, no all-tunnels batch. After any action the loop
# re-detects and re-renders, so an applied MTU or a freshly cleared Basis shows at
# once. Uses literal [n]/[P]/[N] brackets like RLA so the two screens read alike.
manage_mtu() {
    local tf count pg pv nx line oldifs type role iface endpoint overhead family
    local cur underlay underlay_mtu rec rec_display source_label sec vline vplain v vkind vtgt vdate
    local _st stcol _idp _navp _w pick val answer hr
    tf="/tmp/.gl-mtu.$$"; pg=1
    while true; do
        mtu_detect > "$tf"
        if [ ! -s "$tf" ]; then
            clear; print_centered_header "VPN MTU Optimizer"; printf "\n"
            print_warning "No active WireGuard or OpenVPN tunnels found."
            printf "\n"; rm -f "$tf"; press_any_key; return
        fi
        count=$(wc -l < "$tf" | tr -dc '0-9')
        [ "$pg" -gt "$count" ] && pg=1
        [ "$pg" -lt 1 ] && pg="$count"
        pv=$(( (pg - 2 + count) % count + 1 )); nx=$(( pg % count + 1 ))

        # The tunnel on this page.
        line=$(sed -n "${pg}p" "$tf")
        oldifs=$IFS; IFS='|'; set -- $line; IFS=$oldifs
        type="$1"; role="$2"; iface="$3"; endpoint="$4"; overhead="$5"; family="$6"

        cur=$(mtu_get "$iface")
        underlay=$(ip route get "$endpoint" 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
        [ -z "$underlay" ] && underlay=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')
        underlay_mtu=$(mtu_get "$underlay")
        if [ -n "$underlay_mtu" ]; then rec=$((underlay_mtu - overhead)); else rec=""; fi
        # A fresh probe-verified value outranks the calculation - it measured the
        # actual path. mtu_v_get reports STALE when the link or endpoint changed
        # since the probe, and the display drops back to Calculated.
        vline=""; v=$(mtu_v_get "$iface" "$underlay_mtu" "$endpoint")
        case "$v" in
            "OK|"*)
                rec=$(printf '%s' "$v" | cut -d'|' -f2)
                vkind=$(printf '%s' "$v" | cut -d'|' -f3)
                vtgt=$(printf '%s' "$v" | cut -d'|' -f4)
                vdate=$(printf '%s' "$v" | cut -d'|' -f5)
                vline="${GREEN}Verified ${vdate} - ${vkind} probe to ${vtgt}${RESET}"; vplain="Verified ${vdate} - ${vkind} probe to ${vtgt}" ;;
            "STALE|"*)
                vline="${YELLOW}Calculated - earlier probe is stale (link changed); re-verify: opt 3${RESET}"; vplain="Calculated - earlier probe is stale (link changed); re-verify: opt 3" ;;
            *)
                vline="${GREY}Calculated from link MTU - verify with an active probe: opt 3${RESET}"; vplain="Calculated from link MTU - verify with an active probe: opt 3" ;;
        esac
        if [ -n "$rec" ] && [ "$cur" = "$rec" ]; then
            rec_display="${GREEN}${rec}${RESET}   (optimal)"
        elif [ -n "$rec" ]; then
            if [ "${cur:-0}" -lt "$rec" ] 2>/dev/null; then rec_display="${YELLOW}${rec}${RESET}   (can raise)"; else rec_display="${YELLOW}${rec}${RESET}   (should lower)"; fi
        else
            rec_display="${YELLOW}unknown (endpoint not resolved)${RESET}"
        fi
        sec=$(mtu_gl_targets "$iface" "$type" | head -1); source_label=""
        if [ -n "$sec" ]; then
            if uci -q get "$sec.mtu" >/dev/null 2>&1; then source_label="   (override)"; else source_label="   (default)"; fi
        fi
        # Role-aware interface state: connected/disconnected for a client, up/down
        # for a server, with the WireGuard handshake age carried through.
        _st=$(vpn_state_label "$iface" "$type" "$role")
        case "$_st" in CONNECTED*|UP*) stcol="$GREEN" ;; *) stcol="$RED" ;; esac
        # Divider is drawn to the WIDEST rendered line (identity / Basis / nav footer),
        # measured from each line's plain text so colour codes don't count.
        _idp="$type $role: $iface     Status: $_st"
        _navp="[P] Previous   Page $pg of $count   [N] Next   [1/2/3/4]   [0] Back   [?] Help"
        _w=$(( 17 + ${#vplain} ))
        [ $(( ${#_idp} + 1 )) -gt "$_w" ] && _w=$(( ${#_idp} + 1 ))
        [ $(( ${#_navp} + 1 )) -gt "$_w" ] && _w=$(( ${#_navp} + 1 ))
        if [ "$OUTPUT_MODE" = compat ]; then hr=$(rla_rep "-" "$_w"); else hr=$(rla_rep "─" "$_w"); fi

        clear
        print_centered_header "VPN MTU Optimizer"
        printf "\n"
        printf " %b%s %s: %s%b     Status: %b%s%b\n" "$CYAN" "$type" "$role" "$iface" "$RESET" "$stcol" "$_st" "$RESET"
        printf "   Current MTU:  %b%s%b%s\n" "$GREEN" "${cur:-N/A}" "$RESET" "$source_label"
        printf "   Underlay:     %b%s (MTU %s)%b\n" "$GREEN" "${underlay:-N/A}" "${underlay_mtu:-N/A}" "$RESET"
        printf "   Overhead:     %b-%s (%s / %s)%b\n" "$GREEN" "$overhead" "$type" "$family" "$RESET"
        printf "   Recommended:  %b\n" "$rec_display"
        printf "   Basis:        %b\n" "$vline"
        printf " %s\n" "$hr"
        printf " [1] Optimize tunnel (apply recommended)\n"
        printf " [2] Set MTU manually\n"
        printf " [3] Verify with an active probe\n"
        printf " [4] Reset MTU (remove override)\n"
        # Realtime nav footer, no Choose prompt (matches the other paginated screens):
        # every valid key is advertised here and read_single_char dispatches at once.
        # Shown even for a single page (Page 1 of 1) for consistency. No trailing
        # newline so the cursor rests at the END of the line (UX std for char input).
        printf "\n [P] Previous   Page %s of %s   [N] Next   [1/2/3/4]   [0] Back   [?] Help  " "$pg" "$count"
        pick=$(read_single_char); printf "\n\n"
        case "$pick" in
            p|P) pg=$pv ;;   # single page: pv==pg, so this just refreshes
            n|N) pg=$nx ;;
            0) rm -f "$tf"; return ;;
            \?|h|H|❓) show_mtu_help ;;
            1)
                if [ -z "$rec" ]; then print_error "No recommendation (underlay unresolved)."; sleep 2
                elif [ "$cur" = "$rec" ]; then print_info "$iface is already at the recommended $rec."; press_any_key
                else mtu_apply "$iface" "$rec" "$type"; press_any_key; fi ;;
            2)
                printf "Enter MTU for %s (1280-1500, 0 to cancel): " "$iface"; read -r val; printf "\n"
                case "$val" in
                    ''|0) : ;;
                    *[!0-9]*) print_error "Invalid MTU"; sleep 1 ;;
                    *) if [ "$val" -ge 1280 ] && [ "$val" -le 1500 ]; then mtu_apply "$iface" "$val" "$type"; press_any_key
                       else print_error "MTU must be 1280-1500"; sleep 1; fi ;;
                esac ;;
            3) mtu_probe "$type" "$iface" "$endpoint" "$overhead" "$role" "$underlay_mtu" ;;
            4)
                printf "Remove the toolkit's MTU override on %s? [y/N]: " "$iface"; read -r answer; printf "\n"
                case "$answer" in y|Y) mtu_reset "$iface" "$type"; press_any_key ;; *) print_info "No change."; sleep 1 ;; esac ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# =============================================================================
#  Remote LAN Access  -  read / guard / write / detect / authorise / probe
#  Drives GL's own uci keys and apply helpers so the fw3/fw4 split never
#  reaches us.  See CHANGELOG 2026-07-26.
# =============================================================================

# ============================================================================
# Remote LAN Access - read layer.  Candidate code for glinet_utils.sh.
# Pure reads: no uci writes, no firewall changes.  Runs ON a router.
#
#   sh rla_lib.sh dump     print everything this layer resolves
# ============================================================================

# ---- detect active VPN instances -------------------------------------------
# one line per instance: type|role|iface
rla_detect() {
    local i
    for i in $(wg show interfaces 2>/dev/null); do
        [ -n "$(ip -4 addr show "$i" 2>/dev/null | grep inet)" ] || continue
        case "$i" in
            *server*) printf 'WireGuard|server|%s\n' "$i" ;;
            *)        printf 'WireGuard|client|%s\n' "$i" ;;
        esac
    done
    for i in $(ls /sys/class/net 2>/dev/null | grep -E '^(tun|ovpn)'); do
        [ -n "$(ip -4 addr show "$i" 2>/dev/null | grep inet)" ] || continue
        case "$i" in
            *server*) printf 'OpenVPN|server|%s\n' "$i" ;;
            *)        printf 'OpenVPN|client|%s\n' "$i" ;;
        esac
    done
}

# ---- GL's UI/source section for a tunnel's toggles --------------------------
rla_src_section() {
    local iface="$1" type="$2" role="$3" rule cfg proto
    if [ "$role" = server ]; then
        case "$type" in
            WireGuard) uci show wireguard_server 2>/dev/null | grep '=servers$' | head -1 | cut -d= -f1 ;;
            OpenVPN)   uci show ovpnserver 2>/dev/null | grep '=general$' | head -1 | cut -d= -f1 ;;
        esac
        return 0
    fi
    rule=$(uci show route_policy 2>/dev/null | grep "\.via='$iface'\$" | grep '@rule' | head -1 | cut -d. -f1-2)
    if [ -n "$rule" ] && [ "$(uci -q get "$rule" 2>/dev/null)" = rule ]; then
        printf '%s' "$rule"; return 0
    fi
    cfg=$(uci -q get network."$iface".config 2>/dev/null)
    proto=$(uci -q get network."$iface".proto 2>/dev/null)
    [ -n "$cfg" ] || return 0
    case "$proto" in
        wgclient)   printf 'wireguard.%s' "$cfg" ;;
        ovpnclient) printf 'ovpnclient.%s' "$cfg" ;;
    esac
}

# ---- firewall zone name for an interface (NOT assumed = iface) -------------
rla_zone() {
    local iface="$1" z n nets
    for z in $(uci show firewall 2>/dev/null | grep '=zone$' | cut -d= -f1); do
        n=$(uci -q get "$z.name" 2>/dev/null)
        nets=" $(uci -q get "$z.network" 2>/dev/null) "
        case "$nets" in *" $iface "*) printf '%s' "${n:-$iface}"; return 0 ;; esac
        [ "$n" = "$iface" ] && { printf '%s' "$n"; return 0; }
    done
    printf '%s' "$iface"
}

# ---- toggle state: read the FIREWALL key (what actually governs behaviour) --
# masq: absent = ON (GL default).  access: absent/ACCEPT = ON.
rla_masq() {
    local zone="$1" v
    v=$(uci -q get firewall."$zone".masq 2>/dev/null)
    case "$v" in 0) echo off ;; 1) echo on ;; '') echo on ;; *) echo "?" ;; esac
}
rla_access() {
    local zone="$1" v
    v=$(uci -q get firewall."$zone".input 2>/dev/null)
    case "$v" in ACCEPT) echo on ;; REJECT|DROP) echo off ;; '') echo "?" ;; *) echo "?" ;; esac
}

# ---- addresses --------------------------------------------------------------
rla_tunnel_ip()  { ip -4 addr show "$1" 2>/dev/null | sed -n 's#.*inet \([0-9.]*\)/.*#\1#p' | head -1; }
rla_lan_ip()     { uci -q get network.lan.ipaddr 2>/dev/null; }
rla_lan_cidr()   { local ip; ip=$(rla_lan_ip); [ -n "$ip" ] && printf '%s.0/24' "${ip%.*}"; }

# peer's tunnel IP (the far router's tunnel address)
rla_peer_tunnel_ip() {
    local iface="$1" type="$2" role="$3" own peer
    own=$(rla_tunnel_ip "$iface")
    [ -n "$own" ] || return 0
    # point-to-point tunnels expose a peer address; GL's OpenVPN uses
    # "topology subnet" which does not, so fall back to .1 of the subnet.
    peer=$(ip -4 addr show "$iface" 2>/dev/null | sed -n 's#.*peer \([0-9.]*\).*#\1#p' | head -1)
    [ -n "$peer" ] && { printf '%s' "$peer"; return 0; }
    if [ "$role" = client ]; then
        printf '%s.1' "${own%.*}"
        return 0
    fi
    # server: first connected peer (see rla_peers for the full list)
    case "$type" in
        WireGuard)
            peer=$(wg show "$iface" allowed-ips 2>/dev/null | grep -oE '[0-9.]+/32' \
                   | grep -v "^${own}/" | head -1)
            printf '%s' "${peer%/*}" ;;
        OpenVPN)
            # GL configures no status file, so use the daemon's own log
            peer=$(logread 2>/dev/null | grep "MULTI: Learn:" | tail -1 \
                   | sed -n 's/.*MULTI: Learn: \([0-9.]*\) .*/\1/p')
            printf '%s' "$peer" ;;
    esac
}

# ---- connected peers on a SERVER: one line per peer  ident|tunnel_ip -------
# WireGuard: from the kernel.  OpenVPN: needs a status file, which GL does not
# configure, so clients are not enumerable - callers must degrade gracefully.
rla_peers() {
    local iface="$1" type="$2" own
    own=$(rla_tunnel_ip "$iface")
    case "$type" in
        WireGuard)
            wg show "$iface" dump 2>/dev/null | tail -n +2 | while IFS="$(printf '\t')" read -r pk psk ep aips hs rx tx ka; do
                [ -z "$aips" ] && continue
                printf '%s|%s\n' "$(printf '%s' "$pk" | cut -c1-8)" "$(printf '%s' "$aips" | tr ',' '\n' | grep '/32$' | head -1 | cut -d/ -f1)"
            done ;;
        OpenVPN) return 0 ;;
    esac
}

# ---- remote LAN: stored -> specific AllowedIPs -> pushed route -> unset -----
rla_remote_lan() {
    local iface="$1" type="$2" v ai r own ownnet
    v=$(uci -q get glutils."vpn_$iface".remote_lan 2>/dev/null)
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    own=$(rla_tunnel_ip "$iface")
    ownnet="${own%.*}."          # exclude the tunnel's own subnet
    if [ "$type" = WireGuard ]; then
        ai=$(wg show "$iface" allowed-ips 2>/dev/null | tr '\t' '\n' | tr ',' '\n' \
             | grep -E '^[0-9.]+/[0-9]+$' | grep -v '^0\.0\.0\.0/0$' | grep -v '/32$' \
             | grep -v "^${ownnet}" | head -1)
        [ -n "$ai" ] && { printf '%s' "$ai"; return 0; }
    else
        r=$(ip route show dev "$iface" 2>/dev/null | awk '{print $1}' \
            | grep -E '^(10|172|192)\.' | grep '/' | grep -v "^${ownnet}" | head -1)
        [ -n "$r" ] && { printf '%s' "$r"; return 0; }
    fi
}

# ---- does traffic to <dest> actually leave via <iface>? ---------------------
# Uses the kernel's own decision (ip route get), which accounts for policy
# routing. Grepping the main table is WRONG: OpenVPN clients use table 8000 and
# WireGuard clients table 1001, so a main-table check misses both.
rla_routes_via() {
    local dest="$1" iface="$2" probe out
    [ -z "$dest" ] || [ -z "$iface" ] && return 1
    probe="${dest%%/*}"
    case "$dest" in */*) probe="${probe%.*}.1" ;; esac
    out=$(ip route get "$probe" 2>/dev/null | head -1)
    case "$out" in *" dev $iface "*) return 0 ;; esac
    return 1
}

# ---- subnet overlap guard ---------------------------------------------------
# 0 = overlap (unsafe), 1 = distinct.  /24 granularity, matches GL defaults.
rla_overlap() {
    local a="$1" b="$2"
    [ -z "$a" ] || [ -z "$b" ] && return 1
    [ "${a%%/*}" = "${b%%/*}" ] && return 0
    return 1
}


# ---- flow table -------------------------------------------------------------
# Emits one line per flow:  dir|from_label|from_addr|as|to|status|lever
#   status: active | blocked | unknown
#   lever : masq | route | access | remote | tunnel   (UI maps these to options)
#
# Status is COMPUTED from config, not probed - "Test reachability" is what
# probes. Reachability of a destination uses the kernel's own decision
# (rla_routes_via), which accounts for policy routing on both protocols.
rla_flows() {
    local iface="$1" type="$2" role="$3"
    local zone tun peer lan lanip rlan masq acc lo hi rgw asrc st rr fwd
    zone=$(rla_zone "$iface")
    tun=$(rla_tunnel_ip "$iface")
    peer=$(rla_peer_tunnel_ip "$iface" "$type" "$role")
    lanip=$(rla_lan_ip); lan=$(rla_lan_cidr)
    rlan=$(rla_remote_lan "$iface" "$type")
    masq=$(rla_masq "$zone"); acc=$(rla_access "$zone")
    lo="${lanip%.*}.2-254"
    [ -z "$peer" ] && peer="not set"
    if [ -n "$rlan" ]; then hi="${rlan%.*}.2-254"; rgw="${rlan%.*}.1"
    else rlan="not set"; hi="not set"; rgw="not set"; fi
    if [ "$masq" = on ]; then asrc="$tun"; else asrc="source IP"; fi

    # far side accepts our un-NATed source? WireGuard filters by AllowedIPs
    # (needs the remote config -> unknown); OpenVPN does no source filtering.
    _acc() { if [ "$masq" = on ]; then echo active
             elif [ "$type" = OpenVPN ]; then echo active
             else echo unknown; fi; }

    # ---- OUTBOUND: static 6 rows -------------------------------------------
    # to the peer tunnel address (up whenever the tunnel is up)
    printf 'out|ld|LAN devices|%s|%s|%s|%s|masq\n'   "$lo"    "$asrc" "$peer" "$(_acc)"
    printf 'out|rt|this router|%s|%s|%s|unknown|remote\n' "$tun" "$tun" "$peer"
    printf 'out|rl|this router|%s|%s|%s|%s|masq\n'   "$lanip" "$asrc" "$peer" "$(_acc)"
    # to the remote LAN
    if [ "$rlan" = "not set" ]; then
        printf 'out|ld|LAN devices|%s|%s|not set|unknown|identify\n'   "$lo"    "$asrc"
        printf 'out|rt|this router|%s|%s|not set|unknown|identify\n'   "$tun"   "$tun"
        printf 'out|rl|this router|%s|%s|not set|unknown|identify\n'   "$lanip" "$asrc"
    else
        rla_routes_via "$rlan" "$iface" && rr=yes || rr=no
        printf 'out|ld|LAN devices|%s|%s|%s|%s|masq\n' "$lo" "$asrc" "$rlan" "$(_acc)"
        [ "$rr" = yes ] && st=active || st=blocked
        printf 'out|rt|this router|%s|%s|%s|%s|route\n' "$tun" "$tun" "$rlan" "$st"
        [ "$rr" = yes ] && st=$(_acc) || st=blocked
        printf 'out|rl|this router|%s|%s|%s|%s|route\n' "$lanip" "$asrc" "$rlan" "$st"
    fi

    # ---- INBOUND: static 6 rows --------------------------------------------
    # MEASURED: the access toggle gates traffic to our tunnel address too.
    # (An earlier reading said otherwise, but that harness wrote only the uci
    # SOURCE key, which does not change the firewall - so access was never
    # actually off in that test.)
    fwd=$(rla_fwd_to_lan "$zone" && echo yes || echo no)
    [ "$acc" = on ] && st=active || st=blocked
    printf 'in|ld|remote LAN|%s|?|%s|%s|access\n'    "$hi"   "$tun" "$st"
    printf 'in|rt|remote router|%s|?|%s|%s|access\n' "$peer" "$tun" "$st"
    printf 'in|rl|remote router|%s|?|%s|%s|access\n' "$rgw"  "$tun" "$st"
    if [ "$acc" != on ] || [ "$fwd" != yes ]; then st=blocked; else st=unknown; fi
    printf 'in|ld|remote LAN|%s|?|%s|%s|access\n'    "$hi"   "$lan" "$st"
    printf 'in|rt|remote router|%s|?|%s|%s|access\n' "$peer" "$lan" "$st"
    printf 'in|rl|remote router|%s|?|%s|%s|remote\n' "$rgw" "$lan" "$st"
}

# does this protocol accept un-NATed LAN sources from us?
# WireGuard filters by AllowedIPs (needs remote config -> unknown here).
# OpenVPN does no source filtering -> always accepts.
rla_far_accepts() { [ "$1" = OpenVPN ]; }

# is tunnel -> lan forwarding configured for this zone?
rla_fwd_to_lan() {
    local zone="$1" f
    for f in $(uci show firewall 2>/dev/null | grep "\.src='$zone'\$" | cut -d. -f1-2); do
        [ "$(uci -q get "$f.dest")" = lan ] || continue
        [ "$(uci -q get "$f.enabled")" = 0 ] && continue
        return 0
    done
    return 1
}

# ============================================================================
case "${1:-}" in
dump)
  printf 'host          %s  fw %s\n' "$(uname -n)" "$(cat /etc/glversion 2>/dev/null)"
  printf 'lan           %s (%s)\n' "$(rla_lan_cidr)" "$(rla_lan_ip)"
  printf 'backend       %s\n' "$(nft list tables 2>/dev/null | grep -q 'inet fw4' && echo nftables || echo iptables)"
  rla_detect | while IFS='|' read -r type role iface; do
    [ -z "$iface" ] && continue
    src=$(rla_src_section "$iface" "$type" "$role")
    zone=$(rla_zone "$iface")
    tun=$(rla_tunnel_ip "$iface")
    peer=$(rla_peer_tunnel_ip "$iface" "$type" "$role")
    rlan=$(rla_remote_lan "$iface" "$type")
    printf '\n%s %s: %s\n' "$type" "$role" "$iface"
    printf '  src section   %s\n' "${src:-UNRESOLVED}"
    printf '  fw zone       %s\n' "$zone"
    printf '  tunnel ip     %s\n' "${tun:-?}"
    printf '  peer tun ip   %s\n' "${peer:-?}"
    printf '  remote lan    %s\n' "${rlan:-<not set>}"
    [ "$role" = server ] && printf '  peers         %s\n' "$(rla_peers "$iface" "$type" | tr '\n' ' ')"
    printf '  masq          %s   (fw key=%s, src key=%s)\n' "$(rla_masq "$zone")" \
           "$(uci -q get firewall.$zone.masq)" "$(uci -q get $src.masq 2>/dev/null)"
    printf '  access        %s   (fw key=%s)\n' "$(rla_access "$zone")" \
           "$(uci -q get firewall.$zone.input)"
    printf '  rlan via tun  %s\n' "$(rla_routes_via "$rlan" "$iface" && echo yes || echo no)"
    printf '  peer via tun  %s\n' "$(rla_routes_via "$peer" "$iface" && echo yes || echo no)"
    printf '  lan overlap   %s\n' "$(rla_overlap "$(rla_lan_cidr)" "$rlan" && echo COLLISION || echo ok)"
  done
  ;;
flows)
  rla_detect | while IFS='|' read -r type role iface; do
    [ -z "$iface" ] && continue
    printf '\n%s %s: %s\n' "$type" "$role" "$iface"
    printf '  %-4s %-13s %-17s %-11s %-17s %-8s %s\n' dir from addr as to status lever
    rla_flows "$iface" "$type" "$role" | while IFS='|' read -r d fl fa as to st lv; do
      printf '  %-4s %-13s %-17s %-11s %-17s %-8s %s\n' "$d" "$fl" "$fa" "$as" "$to" "$st" "$lv"
    done
  done ;;
*) : ;;   # silent when sourced
esac

# Remote LAN Access - guardrail layer.  See rla-guardrail-spec.md.
# Pure busybox ash; no bashisms, no external deps beyond ip/netstat/uci.

# ---- G4: CIDR arithmetic -----------------------------------------------------
guard_ip2int() { # a.b.c.d -> integer, or empty on garbage
    case "$1" in
        *[!0-9.]*|"") return 1 ;;
    esac
    IFS=. read -r a b c d <<EOF
$1
EOF
    [ -z "$d" ] && return 1
    for o in "$a" "$b" "$c" "$d"; do
        [ -z "$o" ] && return 1
        [ "$o" -gt 255 ] 2>/dev/null && return 1
    done
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

guard_cidr_contains() { # <cidr|ip> <ip> -> 0 if ip falls inside
    cidr="$1"; probe="$2"
    [ -z "$cidr" ] || [ -z "$probe" ] && return 1
    case "$cidr" in
        */*) net="${cidr%%/*}"; bits="${cidr##*/}" ;;
        *)   net="$cidr";       bits=32 ;;
    esac
    case "$bits" in *[!0-9]*|"") return 1 ;; esac
    [ "$bits" -gt 32 ] && return 1
    ni=$(guard_ip2int "$net") || return 1
    pi=$(guard_ip2int "$probe") || return 1
    [ -z "$ni" ] || [ -z "$pi" ] && return 1
    if [ "$bits" -eq 0 ]; then return 0; fi
    mask=$(( 0xFFFFFFFF ^ ((1 << (32 - bits)) - 1) ))
    [ $(( ni & mask )) -eq $(( pi & mask )) ]
}

guard_overlap() { # <cidr_a> <cidr_b> -> 0 if the ranges intersect
    a="$1"; b="$2"
    case "$a" in */*) an="${a%%/*}"; ab="${a##*/}" ;; *) an="$a"; ab=32 ;; esac
    case "$b" in */*) bn="${b%%/*}"; bb="${b##*/}" ;; *) bn="$b"; bb=32 ;; esac
    case "$ab$bb" in *[!0-9]*) return 1 ;; esac
    ai=$(guard_ip2int "$an") || return 1
    bi=$(guard_ip2int "$bn") || return 1
    [ -z "$ai" ] || [ -z "$bi" ] && return 1
    # the shorter prefix is the coarser net; they overlap iff one contains the other's base
    if [ "$ab" -le "$bb" ]; then bits="$ab"; else bits="$bb"; fi
    [ "$bits" -eq 0 ] && return 0
    mask=$(( 0xFFFFFFFF ^ ((1 << (32 - bits)) - 1) ))
    [ $(( ai & mask )) -eq $(( bi & mask )) ]
}

# ---- G1: session discovery ---------------------------------------------------
guard_my_source() { # source IP of the session running this script
    if [ -n "$SSH_CLIENT" ]; then
        echo "${SSH_CLIENT%% *}"
    elif [ -n "$SSH_CONNECTION" ]; then
        echo "${SSH_CONNECTION%% *}"
    else
        echo "127.0.0.1"          # web terminal / console - never assume safe
    fi
}

guard_sessions() { # -> ip|svc  for every live management session
    netstat -tn 2>/dev/null | awk '
        /ESTABLISHED/ {
            lport = $4; sub(/.*:/, "", lport)          # local port
            rip   = $5; sub(/:[^:]*$/, "", rip)        # foreign ip, strip :port
            svc = ""
            if (lport == "22") svc = "ssh"
            else if (lport == "80" || lport == "443") svc = "http"
            if (svc != "" && rip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print rip "|" svc
        }' | sort -u
}

guard_lan_cidr() { # local LAN as a.b.c.0/nn
    ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2; exit}' | while read -r a; do
        i="${a%%/*}"; b="${a##*/}"
        IFS=. read -r w x y z <<EOF
$i
EOF
        [ "$b" = 24 ] && echo "$w.$x.$y.0/24" || echo "$w.$x.$y.0/$b"
    done
}

guard_tunnel_cidr() { # tunnel subnet for an iface
    ip -4 addr show "$1" 2>/dev/null | awk '/inet /{print $2; exit}' | while read -r a; do
        i="${a%%/*}"; b="${a##*/}"
        [ "$b" = 32 ] && b=24
        IFS=. read -r w x y z <<EOF
$i
EOF
        echo "$w.$x.$y.0/$b"
    done
}

guard_classify() { # <ip> <iface> -> lan|tunnel|remote|local|other
    gip="$1"; gif="$2"
    case "$gip" in 127.*) echo local; return ;; esac
    l=$(guard_lan_cidr)
    [ -n "$l" ] && guard_cidr_contains "$l" "$gip" && { echo lan; return; }
    t=$(guard_tunnel_cidr "$gif")
    [ -n "$t" ] && guard_cidr_contains "$t" "$gip" && { echo tunnel; return; }
    r=$(uci -q get glutils."vpn_$gif".remote_lan 2>/dev/null)
    [ -n "$r" ] && guard_cidr_contains "$r" "$gip" && { echo remote; return; }
    echo other
}

guard_at_risk() { # <iface> -> sessions whose path traverses this tunnel
    gif="$1"
    guard_sessions | while IFS='|' read -r ip svc; do
        c=$(guard_classify "$ip" "$gif")
        case "$c" in tunnel|remote) echo "$ip|$svc|$c" ;; esac
    done
}

# ---- G2: alternate transports ------------------------------------------------
guard_alternates() { # <affected-iface> -> live interfaces that could carry mgmt traffic
    gif="$1"
    for i in br-lan wgserver ovpnserver $(ls /sys/class/net 2>/dev/null | grep -E '^(wg|ovpn)client'); do
        [ "$i" = "$gif" ] && continue
        a=$(ip -4 addr show "$i" 2>/dev/null | awk '/inet /{print $2; exit}')
        [ -n "$a" ] && echo "$i|$a"
    done
}

# ---- G3: detached commit-confirm ---------------------------------------------
# The reverter must outlive this shell: if the session dies the revert must still fire.
guard_confirm_spawn() { # <name> <revert-cmd> <timeout-sec>
    gname="$1"; grev="$2"; gto="${3:-30}"
    rm -f "/tmp/guard_${gname}.token"
    cat > "/tmp/guard_${gname}.rev" <<EOF
#!/bin/sh
i=0
while [ \$i -lt $gto ]; do
    [ -f "/tmp/guard_${gname}.token" ] && exit 0
    sleep 1; i=\$((i+1))
done
[ -f "/tmp/guard_${gname}.token" ] && exit 0
$grev
logger -t glutils-rla "commit-confirm timed out; reverted ${gname}"
EOF
    chmod +x "/tmp/guard_${gname}.rev"
    # setsid/nohup do not exist on GL busybox, and a bare `&` child dies with the
    # parent script - verified on GL firmware 4.9.1.  start-stop-daemon -b survives.
    if command -v start-stop-daemon >/dev/null 2>&1; then
        start-stop-daemon -S -b -x "/tmp/guard_${gname}.rev" >/dev/null 2>&1
    else
        sh -c "(/tmp/guard_${gname}.rev) >/dev/null 2>&1 &" &
    fi
    return 0
}

guard_confirm_ok() { # <name> - cancel the pending revert
    touch "/tmp/guard_$1.token"
}

# Remote LAN Access - write layer.  Drives GL's own uci keys and apply helpers so
# the fw3/fw4 split never reaches us.  See rla-guardrail-spec.md.

# ---- protocol abstraction ----------------------------------------------------
w_pkg() { # iface -> uci package holding the levers
    case "$1" in
        ovpnserver)  echo ovpnserver ;;
        wgserver)    echo wireguard_server ;;
        ovpnclient*) echo ovpnclient ;;
        wgclient*)   echo wireguard ;;
        *) return 1 ;;
    esac
}

w_sect() { # iface -> section holding masq/access
    case "$1" in
        ovpnserver) echo global ;;
        wgserver)   echo main_server ;;
        *) uci -q get network."$1".config ;;   # clients point at their own section
    esac
}

w_func() { # iface -> GL's firewall apply helper, ONLY if it actually exists
    # 4.9.x ships ovpnserver_func.sh / wgserver_func.sh which sync the package option
    # into the firewall zone.  4.3.25 ships NEITHER - its RPC handler writes
    # firewall.<iface>.masq directly and calls /etc/init.d/firewall reload.
    # So this must gate on file existence, not on the interface name, or servers on
    # 4.3.25 silently take the 4.9 path and nothing applies.
    case "$1" in
        ovpnserver) f=/etc/openvpn/scripts/ovpnserver_func.sh ;;
        wgserver)   f=/etc/wireguard/scripts/wgserver_func.sh ;;
        *) return 1 ;;
    esac
    [ -x "$f" ] || return 1
    echo "$f"
}

# ---- levers ------------------------------------------------------------------
w_akey() { # iface -> name of the access option (servers: access, clients: local_access)
    case "$1" in ovpnserver|wgserver) echo access ;; *) echo local_access ;; esac
}
w_get_masq()   { p=$(w_pkg "$1") && s=$(w_sect "$1") && uci -q get "$p.$s.masq"; }
w_get_access() { p=$(w_pkg "$1") && s=$(w_sect "$1") && uci -q get "$p.$s.$(w_akey "$1")"; }

w_apply_firewall() { # iface -> run GL's own helper; backend-agnostic by construction
    # Clients ship no *_func.sh (verified on MT1300 4.3.25 and MT3600BE 4.9.0),
    # so they fall back to a plain firewall reload.
    if ! f=$(w_func "$1"); then
        /etc/init.d/firewall reload >/dev/null 2>&1
        return 0
    fi
    [ -x "$f" ] || { /etc/init.d/firewall reload >/dev/null 2>&1; return 0; }
    # GL's helper ends in `exit $?` picking up reload_modified_service, so it returns 1
    # even on success - verified on 4.9.1.  Never gate on its rc; assert behaviour instead.
    "$f" "$1" set_firewall >/dev/null 2>&1
    return 0
}

# ---- zone state --------------------------------------------------------------
w_zone_enabled() { # iface -> 0 if the firewall zone exists AND is enabled
    # A disabled zone makes masq/access writes silent no-ops: the backend never
    # emits rules for it.  Callers must report this rather than claim success.
    uci -q get "firewall.$1" >/dev/null 2>&1 || return 1
    # namespaced: a bare `e` here clobbered a caller's variable of the same name
    # (POSIX sh has no `local` in these helpers, so every temp is global)
    _wze=$(uci -q get "firewall.$1.enabled")
    [ "$_wze" = "0" ] && return 1
    return 0
}

# ---- behavioural observables (H3) - backend aware ----------------------------
w_masq_active() { # iface -> 0 if the kernel is really masquerading this zone (IPv4)
    # IPv4-specific on purpose: fw4/fw3 emit a separate IPv6 masquerade rule for the
    # same iface (firewall.<z>.masq6) which w_set_masq does not touch - a loose match
    # reads the v6 rule and never appears to change.
    # No `grep -A<n>` context fallback: it bleeds into the adjacent chain and picks up
    # srcnat_wan's masquerade.  Verified on MT1300 4.3.25.
    # Backend detection must test for the fw4 TABLE, not for the nft binary: nft is
    # installed on fw3 boxes too (4.9.0), where `nft list ruleset` succeeds but returns
    # nothing relevant - so a binary-presence check silently always reports "not masqueraded".
    if nft list table inet fw4 >/dev/null 2>&1; then
        nft list ruleset 2>/dev/null | grep -q "masquerade.*IPv4 $1 traffic"
        return $?
    fi
    iptables -t nat -S "zone_$1_postrouting" 2>/dev/null | grep -q MASQUERADE
}

w_wait_masq() { # iface expected(0|1) [tries] -> 0 when the kernel agrees
    n=0; lim="${3:-8}"
    while [ "$n" -lt "$lim" ]; do
        if w_masq_active "$1"; then a=1; else a=0; fi
        [ "$a" = "$2" ] && return 0
        n=$((n+1)); sleep 1
    done
    return 1
}

w_set_masq() { # iface 0|1   -> rc 3 = zone disabled, the write would do nothing
    p=$(w_pkg "$1") || return 1; s=$(w_sect "$1") || return 1
    case "$2" in 0|1) ;; *) return 1 ;; esac
    # Guard here, not at one UI entry point: a disabled zone makes the backend
    # skip it entirely, so uci writes and reads back correctly while producing
    # no kernel rules. Every caller needs this - including lv_apply's detached
    # revert, which would otherwise report a successful revert that never
    # happened. Observed on MT1300 with the wgserver zone left disabled.
    if ! w_zone_enabled "$1"; then
        echo "refused: firewall zone for $1 is disabled - this would have no effect" >&2
        return 3
    fi
    uci set "$p.$s.masq=$2" && uci commit "$p" || return 1
    # Two-key model: GL's package option is only the UI mirror.  Servers have a
    # set_firewall helper that syncs it; clients do NOT, so the firewall zone -
    # the key the backend actually reads - must be written directly.
    # Verified on MT1300 4.3.25: writing only ovpnclient.<sect>.masq changed nothing.
    if ! w_func "$1" >/dev/null 2>&1; then
        if uci -q get "firewall.$1" >/dev/null 2>&1; then
            uci set "firewall.$1.masq=$2" && uci commit firewall
        fi
    fi
    w_apply_firewall "$1"
}

w_set_access() { # iface ACCEPT|DROP|REJECT (servers) | 0|1 (clients)
                 # rc 3 = zone disabled, the write would do nothing
    p=$(w_pkg "$1") || return 1; s=$(w_sect "$1") || return 1; k=$(w_akey "$1")
    if ! w_zone_enabled "$1"; then
        echo "refused: firewall zone for $1 is disabled - this would have no effect" >&2
        return 3
    fi
    if [ "$k" = access ]; then
        case "$2" in ACCEPT|DROP|REJECT) ;; *) return 1 ;; esac
    else
        case "$2" in 0|1) ;; *) return 1 ;; esac
    fi
    uci set "$p.$s.$k=$2" && uci commit "$p" || return 1
    # No helper (clients anywhere, servers on 4.3.25) -> write the zone ourselves.
    if ! w_func "$1" >/dev/null 2>&1 && uci -q get "firewall.$1" >/dev/null 2>&1; then
        case "$2" in
            1|ACCEPT) uci set "firewall.$1.input=ACCEPT" ;;
            *)        uci set "firewall.$1.input=DROP" ;;
        esac
        uci commit firewall
    fi
    w_apply_firewall "$1"
}

# ---- route rules (GL's own storage) -----------------------------------------
# GL's proto handlers read dest and mask as SEPARATE options and build
#   wgserver:   AllowedIPs=${dest}/${mask}      and  ip route add ${dest}/${mask}
#   ovpnserver: iroute $(ipcalc_network $dest $mask)   -> the ccd file
# so a rule written as dest="a.b.c.0/24" yields "a.b.c.0/24/" and breaks on ifup.
# Writing them split is also what makes [3] work: GL derives the per-peer
# authorisation (AllowedIPs / iroute) from these same sections, gated on the
# gateway matching the peer's tunnel address.
w_route_list() { # iface -> dest/mask|gateway|metric
    p=$(w_pkg "$1") || return 1
    i=0
    while :; do
        d=$(uci -q get "$p.@route_rules[$i].dest") || break
        [ -z "$d" ] && break
        m=$(uci -q get "$p.@route_rules[$i].mask")
        printf '%s/%s|%s|%s\n' "$d" "${m:-32}" \
            "$(uci -q get "$p.@route_rules[$i].gateway")" \
            "$(uci -q get "$p.@route_rules[$i].metric")"
        i=$((i+1))
    done
}

w_route_idx() { # iface dest-cidr -> index of the matching rule
    p=$(w_pkg "$1") || return 1
    want_d="${2%%/*}"; want_m="${2##*/}"; [ "$want_m" = "$2" ] && want_m=32
    i=0
    while :; do
        d=$(uci -q get "$p.@route_rules[$i].dest") || return 1
        [ -z "$d" ] && return 1
        m=$(uci -q get "$p.@route_rules[$i].mask")
        [ "$d" = "$want_d" ] && [ "${m:-32}" = "$want_m" ] && { echo "$i"; return 0; }
        i=$((i+1))
    done
}

w_route_add() { # iface dest-cidr gateway [metric]
    ifc="$1"; dest="$2"; gw="$3"; met="${4:-100}"
    p=$(w_pkg "$ifc") || return 1
    lan=$(guard_lan_cidr)
    if [ -n "$lan" ] && guard_overlap "$lan" "$dest"; then
        echo "refused: $dest overlaps local LAN $lan" >&2
        return 2
    fi
    w_route_idx "$ifc" "$dest" >/dev/null 2>&1 && return 0   # idempotent
    dnet="${dest%%/*}"; dmask="${dest##*/}"; [ "$dmask" = "$dest" ] && dmask=32
    uci add "$p" route_rules >/dev/null 2>&1 || return 1
    uci set "$p.@route_rules[-1].dest=$dnet"
    uci set "$p.@route_rules[-1].mask=$dmask"
    uci set "$p.@route_rules[-1].gateway=$gw"
    uci set "$p.@route_rules[-1].metric=$met"
    uci set "$p.@route_rules[-1].route_flag=4"
    uci commit "$p" || return 1
    ip route replace "$dnet/$dmask" via "$gw" dev "$ifc" metric "$met" 2>/dev/null
    ip route replace table 9910 "$dnet/$dmask" via "$gw" dev "$ifc" metric "$met" 2>/dev/null
    return 0
}

w_route_del() { # iface dest-cidr
    ifc="$1"; dest="$2"
    p=$(w_pkg "$ifc") || return 1
    dnet="${dest%%/*}"; dmask="${dest##*/}"; [ "$dmask" = "$dest" ] && dmask=32
    idx=$(w_route_idx "$ifc" "$dest") || { ip route del "$dnet/$dmask" dev "$ifc" 2>/dev/null; return 0; }
    uci delete "$p.@route_rules[$idx]" && uci commit "$p"
    ip route del "$dnet/$dmask" dev "$ifc" 2>/dev/null
    ip route del table 9910 "$dnet/$dmask" dev "$ifc" 2>/dev/null
    return 0
}

# ---- behaviour verification (H3) ---------------------------------------------
w_route_active() { # iface dest -> 0 if the kernel actually has it
    ip route show dev "$2" 2>/dev/null | grep -q "^${1%%/*}" || \
    ip route show 2>/dev/null | grep -q "^$1 .*dev $2"
}

# Remote LAN Access - option [4] detection cascade.
#   config -> ssh -> probe -> manual        first three definitive-to-inferred in order.
# Every rung reports what it tried and why it failed; nothing is silent.

D_TRACE=/tmp/rla_detect_trace.$$
d_trace_reset() { : > "$D_TRACE"; }
d_trace()       { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$D_TRACE"; }   # rung|result|detail
d_trace_show()  { [ -f "$D_TRACE" ] && cat "$D_TRACE"; }

# ---- helpers -----------------------------------------------------------------
d_mask2bits() { # 255.255.255.0 -> 24
    case "$1" in *.*.*.*) ;; *) return 1 ;; esac
    IFS=. read -r m1 m2 m3 m4 <<EOF
$1
EOF
    b=0
    for o in "$m1" "$m2" "$m3" "$m4"; do
        case "$o" in
            255) b=$((b+8)) ;; 254) b=$((b+7)) ;; 252) b=$((b+6)) ;; 248) b=$((b+5)) ;;
            240) b=$((b+4)) ;; 224) b=$((b+3)) ;; 192) b=$((b+2)) ;; 128) b=$((b+1)) ;;
            0)   ;;
            *) return 1 ;;
        esac
    done
    echo "$b"
}

d_netof() { # ip bits -> network cidr
    ni=$(guard_ip2int "$1") || return 1
    [ "$2" -ge 0 ] 2>/dev/null || return 1
    [ "$2" -eq 0 ] && { echo "0.0.0.0/0"; return 0; }
    mask=$(( 0xFFFFFFFF ^ ((1 << (32 - $2)) - 1) ))
    n=$(( ni & mask ))
    echo "$(( (n >> 24) & 255 )).$(( (n >> 16) & 255 )).$(( (n >> 8) & 255 )).$(( n & 255 ))/$2"
}

# ---- provenance --------------------------------------------------------------
d_store() { # iface cidr src   -> persist value + how we learned it
    ifc="$1"; cidr="$2"; src="$3"
    lan=$(guard_lan_cidr)
    if [ -n "$lan" ] && guard_overlap "$lan" "$cidr"; then
        echo "refused: $cidr overlaps local LAN $lan" >&2
        return 2
    fi
    uci -q get glutils >/dev/null 2>&1 || touch /etc/config/glutils
    uci -q get "glutils.vpn_$ifc" >/dev/null 2>&1 || uci set "glutils.vpn_$ifc=vpn"
    uci set "glutils.vpn_$ifc.remote_lan=$cidr"
    uci set "glutils.vpn_$ifc.remote_lan_src=$src"
    uci commit glutils
}

d_get()     { uci -q get "glutils.vpn_$1.remote_lan"; }
d_get_src() { uci -q get "glutils.vpn_$1.remote_lan_src"; }
d_clear()   { uci -q delete "glutils.vpn_$1.remote_lan" 2>/dev/null
              uci -q delete "glutils.vpn_$1.remote_lan_src" 2>/dev/null; uci commit glutils; }

# ---- rung 1: config (definitive, free, always runs) --------------------------
d_config() { # iface type -> cidr from AllowedIPs / pushed routes
    ifc="$1"; typ="$2"
    own=$(ip -4 addr show "$ifc" 2>/dev/null | awk '/inet /{print $2; exit}')
    ownnet="${own%%/*}"; ownnet="${ownnet%.*}."
    if [ "$typ" = WireGuard ]; then
        v=$(wg show "$ifc" allowed-ips 2>/dev/null | tr '\t' '\n' | tr ',' '\n' \
            | grep -E '^[0-9.]+/[0-9]+$' | grep -v '^0\.0\.0\.0/0$' | grep -v '/32$' \
            | grep -v "^${ownnet}" | head -1)
    else
        v=$(ip route show dev "$ifc" 2>/dev/null | awk '{print $1}' \
            | grep -E '^(10|172|192)\.' | grep '/' | grep -v "^${ownnet}" | head -1)
    fi
    if [ -n "$v" ]; then d_trace config found "$v"; echo "$v"; return 0; fi
    if [ "$typ" = WireGuard ]; then
        d_trace config none "AllowedIPs declares no specific remote subnet"
    else
        d_trace config none "no pushed route names a remote subnet"
    fi
    return 1
}

# ---- rung 2: ssh (definitive, exact mask, needs credentials) -----------------
d_ssh_reachable() { # peer-ip -> 0 if pingable AND sshd answers
    p="$1"
    [ -z "$p" ] && { d_trace ssh skip "no peer tunnel address known"; return 1; }
    # Reject addresses that resolve to ourselves.  0.0.0.0 pings as localhost and
    # `nc 0.0.0.0 22` reaches our OWN sshd - without this we would ssh to ourselves
    # and store our own LAN as the remote one.  Caught by test, not by reasoning.
    case "$p" in
        0.0.0.0|0.*|127.*|255.255.255.255)
            d_trace ssh invalid "$p is not a routable peer address"; return 1 ;;
    esac
    if ip -4 addr show 2>/dev/null | grep -qE "inet $p/"; then
        d_trace ssh invalid "$p is one of this router's own addresses"; return 1
    fi
    if ! ping -c1 -W2 "$p" >/dev/null 2>&1; then
        d_trace ssh unreachable "$p does not answer - the far side blocks it"
        return 1
    fi
    # busybox nc has no -z; a real connect + banner grep is the portable check
    if echo | timeout 4 nc "$p" 22 2>/dev/null | head -c 32 | grep -qi ssh; then
        d_trace ssh reachable "$p:22 answering"
        return 0
    fi
    d_trace ssh noport "$p reachable but nothing answers on :22"
    return 1
}

d_ssh_query() { # peer-ip [user] -> cidr
    # If router-to-router key trust already exists this runs with NO prompt at all.
    # Otherwise ssh prompts once; credentials are never stored or logged.
    # dropbear ignores OpenSSH -o options, so -y is the host-key flag, not -o Strict...
    p="$1"; u="${2:-root}"
    q='echo "$(uci -q get network.lan.ipaddr) $(uci -q get network.lan.netmask)"'
    if command -v k_can_auth >/dev/null 2>&1 && k_can_auth "$p" "$u"; then
        kf=$(k_key_path 2>/dev/null)
        out=$(timeout 15 ssh -y -i "$kf" "$u@$p" "$q" </dev/null 2>/dev/null)
        d_trace ssh keyauth "logged in to $p with an existing key - no password needed"
    else
        out=$(timeout 60 ssh -y "$u@$p" "$q" 2>/dev/null)
    fi
    ipa="${out%% *}"; msk="${out##* }"
    [ -z "$ipa" ] || [ -z "$msk" ] && { d_trace ssh failed "no answer from uci on $p"; return 1; }
    b=$(d_mask2bits "$msk") || { d_trace ssh failed "unparsable netmask '$msk'"; return 1; }
    c=$(d_netof "$ipa" "$b") || return 1
    d_trace ssh found "$c (exact mask from the remote router)"
    echo "$c"
}

# ---- rung 3: probe (inferred - guessed candidate, assumed /24) ---------------
d_can_probe() { # iface -> 0 if we can send -I-bound probes into this tunnel
    # The scan binds probes to the interface (ping -I / fping -I), which reaches
    # THROUGH any up tunnel regardless of the routing table - a default route is
    # NOT required. An OpenVPN client with no pushed LAN route (e.g. a test box's
    # ovpnclient1) still carries bound probes, and the scan then finds its remote
    # LAN. So the only requirement is that the tunnel is up. tun/tap/ovpn/wg
    # interfaces report operstate "unknown" (no carrier concept) when up, "down"
    # when down.
    case "$(cat "/sys/class/net/$1/operstate" 2>/dev/null)" in
        up|unknown) return 0 ;;
    esac
    return 1
}

# ---- tiered remote-LAN scan --------------------------------------------------
# Find the remote LAN by sweeping candidate gateways THROUGH the tunnel and
# keeping only those that still answer a TTL-1 ICMP echo - a subnet directly
# across the tunnel (the peer answers for itself), not one a hop upstream (the
# peer forwards it and the TTL expires). The old probe pinged ~9
# gateways and gave up on "several answered", with no hop test to tell a real
# remote LAN from an upstream one (both answer). Validated on the fleet: fping
# (tuned, -i0) sweeps the standard tier (~8.7k) in ~1s and all of RFC1918
# (139,776) in ~25s chunked; shell-parallel is the zero-dependency fallback.
d_gen() {   # tier(standard|full) -> candidate gateway IPs (.1 and .254)
    case "$1" in
        standard)
            for s in 192.168.0 192.168.1 192.168.2 192.168.8 192.168.10 192.168.11 \
                     192.168.50 192.168.100 192.168.178 192.168.254 10.0.0 10.0.1 \
                     10.1.0 10.8.0 10.10.0 10.10.10 172.16.0; do echo "$s.1"; echo "$s.254"; done ;;
        full)
            awk 'BEGIN{
                for(y=0;y<256;y++){print "192.168."y".1";print "192.168."y".254"}
                for(x=16;x<32;x++)for(y=0;y<256;y++){print "172."x"."y".1";print "172."x"."y".254"}
                for(x=0;x<256;x++)for(y=0;y<256;y++){print "10."x"."y".1";print "10."x"."y".254"}}' ;;
    esac
}

d_sweep() { # iface  (candidates on stdin) -> alive IPs. fping if present, else shell.
    _if="$1"
    if command -v fping >/dev/null 2>&1; then
        # chunk so fping RSS stays low (~0.43KB/target) even on tight-RAM devices
        _cp="/tmp/.dsw.$$"; rm -f "$_cp".*
        split -l 20000 - "$_cp." 2>/dev/null || cat > "$_cp.aa"
        for _f in "$_cp".*; do [ -f "$_f" ] && fping -a -q -I "$_if" -r0 -t400 -i0 < "$_f" 2>/dev/null; done
        rm -f "$_cp".*
    else
        _i=0
        while read -r _g; do
            ping -c1 -W1 -I "$_if" "$_g" >/dev/null 2>&1 && echo "$_g" &
            _i=$((_i+1)); [ $((_i%128)) -eq 0 ] && wait
        done
        wait
    fi
}

d_0hop() {  # iface  (alive IPs on stdin) -> remote-LAN /24s, minus ALL our own subnets
    _if="$1"
    # Exclude every /24 THIS router already owns - not just the current tunnel and
    # the LAN, but every other tunnel too, INCLUDING ones that are configured but
    # down. A router often terminates several VPNs on overlapping ranges: one test box
    # has its own WireGuard at 10.1.0.x (down) whose subnet is ALSO reachable
    # across the OpenVPN client we are scanning, so without this it would offer
    # 10.1.0.0/24 - a VPN transit subnet, not a real remote LAN. Sources: live
    # interface addresses + the WireGuard address_v4 keys from UCI (the down
    # tunnels). Prefixes are wrapped in '|' for a fast substring match below.
    _own=$({ ip -4 addr show 2>/dev/null | awk '/inet /{print $2}'
             uci show 2>/dev/null | sed -n "s/.*address_v4='\\([0-9.]*\\).*/\\1/p"
           } | awk -F/ '{n=$1; sub(/\.[0-9]+$/,"",n); print n}' | sort -u | tr '\n' '|')
    _own="|$_own"
    # 0-hop test = a TTL-1 ICMP echo the far side still ANSWERS. The remote LAN
    # gateway is the tunnel peer's own address (delivered to self -> it replies),
    # whereas an upstream gateway is forwarded (TTL expires, no echo). Same echo
    # semantics as the sweep, so it stays reliable where UDP traceroute is flaky,
    # and it is fast (<=1s each) and parallel-safe. Responders are few.
    _of="/tmp/.d0h.$$"; : > "$_of"
    while read -r _ip; do
        _n=${_ip%.*}
        case "$_own" in *"|$_n|"*) continue ;; esac
        # Keep a subnet only if it is 0-hop THROUGH THE TUNNEL *and* NOT reachable
        # by the normal (default) route. A genuine remote LAN lives only on the far
        # side of the tunnel; a subnet reachable BOTH ways is a shared/routable
        # network - e.g. a VPN subnet that is one of the peer's own interfaces
        # (0-hop across the tunnel) but is also reached upstream over the WAN.
        ( ping -c1 -W1 -t1 -I "$_if" "$_ip" >/dev/null 2>&1 &&
          ! ping -c1 -W1 "$_ip" >/dev/null 2>&1 &&
          echo "${_n}.0/24" >> "$_of" ) &
    done
    wait
    sort -u "$_of" 2>/dev/null; rm -f "$_of"
}

d_scan() { d_gen "$2" | d_sweep "$1" | d_0hop "$1"; }   # iface tier -> 0-hop cidr(s)

d_probe() { # iface -> first directly-attached remote LAN via the fast standard tier
    ifc="$1"                                            # (full is user-driven in rla_do_detect)
    if ! d_can_probe "$ifc"; then
        d_trace probe skip "no route sends arbitrary traffic into $ifc - a probe cannot leave"
        return 1
    fi
    _r=$(d_scan "$ifc" standard)
    if [ -n "$_r" ]; then
        d_trace probe found "standard scan, hop-0 through $ifc: $(echo $_r | tr '\n' ' ')"
        echo "$_r" | head -1; return 0
    fi
    d_trace probe none "no directly-attached subnet in the standard tier answered through $ifc"
    return 1
}

# ---- the cascade -------------------------------------------------------------
# Returns the subnet and echoes provenance on stderr-free stdout as "cidr|src".
# Rung 2 is opt-in because it prompts for a password; callers pass want_ssh=1.
d_cascade() { # iface type role [want_ssh] [peer-ip]
    ifc="$1"; typ="$2"; rol="$3"; want_ssh="${4:-0}"; peer="$5"
    d_trace_reset

    v=$(d_get "$ifc")
    if [ -n "$v" ]; then
        s=$(d_get_src "$ifc"); d_trace stored found "$v (set earlier by: ${s:-unknown})"
        echo "$v|${s:-manual}"; return 0
    fi

    if v=$(d_config "$ifc" "$typ"); then echo "$v|config"; return 0; fi

    if [ "$want_ssh" = 1 ]; then
        if d_ssh_reachable "$peer"; then
            if v=$(d_ssh_query "$peer"); then d_store "$ifc" "$v" ssh >/dev/null 2>&1
                                              echo "$v|ssh"; return 0; fi
        fi
    else
        d_trace ssh skip "not requested (prompts for the remote router's password)"
    fi

    if v=$(d_probe "$ifc"); then
        d_store "$ifc" "$v" probe >/dev/null 2>&1
        echo "$v|probe"; return 0
    fi

    d_trace manual required "no automatic rung succeeded - enter the subnet yourself"
    return 1
}

# Remote LAN Access - option [3]: per-peer authorisation.
#
# A kernel route alone is not enough.  Each protocol needs to be told WHICH peer
# owns the remote subnet:
#   OpenVPN   ccd file named after the client's CN, containing `iroute`
#   WireGuard the subnet present in that peer's AllowedIPs
#
# GL derives both from wireguard_server/ovpnserver @route_rules, but writes the
# OpenVPN iroute into ccd/DEFAULT - which applies to EVERY client and therefore
# cannot bind a subnet to one peer.  A per-CN ccd file overrides DEFAULT and is
# never regenerated by GL (its proto handler only removes DEFAULT), so that is
# what we write.  Requires client_auth 2 or 3 so the CN is the username.

AZ_CCD=/etc/openvpn/ccd
AZ_USERS=/etc/openvpn/cert/user_passwd.txt

# ---- capability gate ---------------------------------------------------------
az_unique_cn() { # ovpnserver -> 0 if each client gets its own CN
    a=$(uci -q get ovpnserver.vpn.client_auth)
    [ "$a" = 2 ] || [ "$a" = 3 ]
}

az_blocker() { # iface -> empty if [3] can proceed, else the reason
    case "$1" in
        ovpnserver)
            az_unique_cn && return 0
            echo "every client shares the certificate CN, so a subnet cannot be bound to one peer - set Authentication Mode to include a username first"
            return 1 ;;
        wgserver) return 0 ;;
        *) echo "per-peer authorisation applies to VPN servers only"; return 1 ;;
    esac
}

# ---- peer enumeration --------------------------------------------------------
az_peers() { # iface -> name|id   the identities a subnet can be bound to
    case "$1" in
        ovpnserver)
            [ -f "$AZ_USERS" ] || return 1
            awk '{ if ($1 != "") print $1 "|" $1 }' "$AZ_USERS" ;;
        wgserver)
            i=0
            while :; do
                pid=$(uci -q get "wireguard_server.@peers[$i].peer_id") || break
                [ -z "$pid" ] && break
                n=$(uci -q get "wireguard_server.@peers[$i].name")
                printf '%s|%s\n' "${n:-peer_$pid}" "$pid"
                i=$((i+1))
            done ;;
        *) return 1 ;;
    esac
}

az_peer_tunnel_ip() { # iface peer-id -> that peer's address inside the tunnel
    case "$1" in
        wgserver)
            c=$(uci -q get "wireguard_server.peer_$2.client_ip")
            echo "${c%%/*}" ;;
        ovpnserver)
            # OpenVPN assigns from the pool; read what the peer actually holds
            logread 2>/dev/null | grep "MULTI: Learn:" | grep "> $2/" \
                | tail -1 | awk '{print $(NF-2)}' ;;
    esac
}

# ---- grant / revoke ----------------------------------------------------------
az_granted() { # iface peer -> subnets currently bound to that peer
    case "$1" in
        ovpnserver)
            f="$AZ_CCD/$2"
            [ -f "$f" ] || return 1
            # the ccd stores a dotted netmask; callers speak CIDR
            awk '/^iroute /{print $2, $3}' "$f" | while read -r n m; do
                b=$(az_mask2bits "$m") || continue
                echo "$n/$b"
            done ;;
        wgserver)
            uci -q get "wireguard_server.peer_$2.allowed_ips" | tr ',' '\n' \
                | grep -E '^[0-9]' | grep -v '/32$' ;;
    esac
}

az_grant() { # iface peer cidr
    ifc="$1"; peer="$2"; cidr="$3"
    az_blocker "$ifc" >/dev/null || return 3
    lan=$(guard_lan_cidr)
    [ -n "$lan" ] && guard_overlap "$lan" "$cidr" && {
        echo "refused: $cidr overlaps local LAN $lan" >&2; return 2; }
    net="${cidr%%/*}"; bits="${cidr##*/}"
    case "$ifc" in
        ovpnserver)
            mkdir -p "$AZ_CCD" || return 1
            nm=$(az_bits2mask "$bits") || return 1
            f="$AZ_CCD/$peer"
            touch "$f"
            grep -qE "^iroute $net $nm\$" "$f" 2>/dev/null || echo "iroute $net $nm" >> "$f"
            ;;
        wgserver)
            cur=$(uci -q get "wireguard_server.peer_$peer.allowed_ips")
            case ",$cur," in *",$cidr,"*) ;; *)
                uci set "wireguard_server.peer_$peer.allowed_ips=${cur:+$cur,}$cidr" ;;
            esac
            uci commit wireguard_server
            tip=$(az_peer_tunnel_ip "$ifc" "$peer")
            [ -n "$tip" ] && w_route_add "$ifc" "$cidr" "$tip" >/dev/null 2>&1
            az_wg_sync "$peer"
            ;;
        *) return 1 ;;
    esac
}

az_revoke() { # iface peer cidr
    ifc="$1"; peer="$2"; cidr="$3"
    net="${cidr%%/*}"; bits="${cidr##*/}"
    case "$ifc" in
        ovpnserver)
            f="$AZ_CCD/$peer"; [ -f "$f" ] || return 0
            nm=$(az_bits2mask "$bits") || return 1
            sed -i "\\|^iroute $net $nm\$|d" "$f"
            [ -s "$f" ] || rm -f "$f"
            ;;
        wgserver)
            cur=$(uci -q get "wireguard_server.peer_$peer.allowed_ips")
            new=$(echo "$cur" | tr ',' '\n' | grep -vxF "$cidr" | tr '\n' ',' | sed 's/,*$//')
            uci set "wireguard_server.peer_$peer.allowed_ips=$new"
            uci commit wireguard_server
            w_route_del "$ifc" "$cidr" >/dev/null 2>&1
            az_wg_sync "$peer"
            ;;
    esac
}

az_mask2bits() { # 255.255.255.0 -> 24
    case "$1" in *.*.*.*) ;; *) return 1 ;; esac
    IFS=. read -r q1 q2 q3 q4 <<EOF
$1
EOF
    b=0
    for o in "$q1" "$q2" "$q3" "$q4"; do
        case "$o" in
            255) b=$((b+8)) ;; 254) b=$((b+7)) ;; 252) b=$((b+6)) ;; 248) b=$((b+5)) ;;
            240) b=$((b+4)) ;; 224) b=$((b+3)) ;; 192) b=$((b+2)) ;; 128) b=$((b+1)) ;;
            0) ;; *) return 1 ;;
        esac
    done
    echo "$b"
}

az_bits2mask() { # 24 -> 255.255.255.0
    case "$1" in *[!0-9]*|"") return 1 ;; esac
    [ "$1" -gt 32 ] && return 1
    m=$(( 0xFFFFFFFF ^ ((1 << (32 - $1)) - 1) ))
    [ "$1" -eq 0 ] && m=0
    echo "$(( (m>>24)&255 )).$(( (m>>16)&255 )).$(( (m>>8)&255 )).$(( m&255 ))"
}

# push AllowedIPs to the live interface without bouncing it (gl_wg is a symlink to
# wg or awg on 4.9; 4.3.25 has plain wg only)
az_wg_sync() { # peer-id
    pk=$(uci -q get "wireguard_server.peer_$1.public_key"); [ -z "$pk" ] && return 1
    cip=$(uci -q get "wireguard_server.peer_$1.client_ip"); cip="${cip%%/*}"
    aips=$(uci -q get "wireguard_server.peer_$1.allowed_ips" | tr ',' '\n' \
           | grep -E '^[0-9]' | grep -v '^0\.0\.0\.0/0$' | tr '\n' ',' | sed 's/,*$//')
    full="${cip}/32${aips:+,$aips}"
    W=$(command -v gl_wg || command -v wg) || return 1
    "$W" set wgserver peer "$pk" allowed-ips "$full" 2>/dev/null
}

# ---- behavioural verification (H3) -------------------------------------------
az_active() { # iface peer cidr -> 0 if the DATA PLANE really authorises it
    case "$1" in
        ovpnserver)
            grep -qE "^iroute ${3%%/*} " "$AZ_CCD/$2" 2>/dev/null ;;
        wgserver)
            pk=$(uci -q get "wireguard_server.peer_$2.public_key")
            wg show wgserver allowed-ips 2>/dev/null | grep -F "$pk" | grep -qF "$3" ;;
    esac
}

# Remote LAN Access - guarded lever application.
# Composes guard + write: nothing that can sever the management path is applied
# without capturing the prior value and arming a detached revert first.

LV_STATE=/tmp/rla_lever_prior

lv_risky() { # iface lever -> 0 if this change can cut a live management session
    case "$2" in access|masq) ;; *) return 1 ;; esac
    [ -n "$(guard_at_risk "$1")" ]
}

lv_risk_report() { # iface -> human-readable list of endangered sessions
    guard_at_risk "$1" | while IFS='|' read -r ip svc via; do
        printf '   %s (%s) reaches this router via the %s\n' "$ip" "$svc" "$via"
    done
}

lv_alternates_report() { # iface
    guard_alternates "$1" | while IFS='|' read -r i a; do
        printf '   %-12s %s\n' "$i" "$a"
    done
}

# Apply a lever under commit-confirm.  Returns 0 applied, 1 failed, 3 nothing to do.
lv_apply() { # iface lever value [timeout]
    ifc="$1"; lev="$2"; val="$3"; to="${4:-30}"
    case "$lev" in
        masq)   cur=$(w_get_masq "$ifc") ;;
        access) cur=$(w_get_access "$ifc") ;;
        *) return 1 ;;
    esac
    [ "$cur" = "$val" ] && return 3
    # prior value on DISK, not in a shell variable - the reverter outlives this shell
    printf '%s|%s|%s\n' "$ifc" "$lev" "$cur" > "$LV_STATE.$ifc.$lev"
    guard_confirm_spawn "$ifc$lev" \
        "sh -c '. /tmp/rla_guard.sh; . /tmp/rla_write.sh; w_set_$lev $ifc $cur'" "$to"
    case "$lev" in
        masq)   w_set_masq   "$ifc" "$val" ;;
        access) w_set_access "$ifc" "$val" ;;
    esac || return 1
    return 0
}

lv_confirm() { guard_confirm_ok "$1$2"; rm -f "$LV_STATE.$1.$2"; }

lv_pending() { [ -f "/tmp/guard_$1$2.rev" ] && [ ! -f "/tmp/guard_$1$2.token" ]; }

# Did the kernel actually follow?  Used to decide confirm vs report-failure.
lv_verify() { # iface lever value
    case "$2" in
        masq)   w_wait_masq "$1" "$3" 8 ;;
        access) [ "$(w_get_access "$1")" = "$3" ] ;;
    esac
}

# Remote LAN Access - option [1]: reachability testing.
# Outbound is testable locally.  Inbound genuinely requires the far side, so it is
# only truthfully reportable when router-to-router key trust exists; otherwise we
# say so rather than inferring it from local config.

pr_ping() { # dest [source-ip] -> 0 reachable
    [ -z "$1" ] && return 1
    case "$1" in unknown|*[!0-9./]*) return 1 ;; esac
    if [ -n "$2" ]; then ping -c1 -W2 -I "$2" "$1" >/dev/null 2>&1
    else                 ping -c1 -W2 "$1" >/dev/null 2>&1; fi
}

pr_gw_of() { echo "${1%%/*}" | awk -F. '{print $1"."$2"."$3".1"}'; }

# Router-to-router SSH trust (OUTBOUND: lets THIS router log in to another).
# Distinct from the existing SSH Authorized Keys Manager, which governs who may
# log in TO this router.  Keys are dropbear-format; authorized_keys lives in
# /etc/dropbear/, not /root/.ssh/ - verified on 4.9.1, 4.9.0 and 4.3.25.

K_DIR=/root/.ssh
K_AUTH=/etc/dropbear/authorized_keys
K_TAG="glinet_utils-rla"          # comment marker so we can find/revoke only ours

k_key_path() { # prefer a key that already exists; else our own
    for k in "$K_DIR/id_dropbear" "$K_DIR/id_ed25519" "$K_DIR/id_rsa"; do
        [ -s "$k" ] && { echo "$k"; return 0; }
    done
    echo "$K_DIR/id_dropbear"; return 1
}

# ---- remote auth -------------------------------------------------------------
# dropbear's client IGNORES OpenSSH -o options (it prints "Ignoring unknown
# configuration option"), so BatchMode cannot be used to suppress the password
# prompt.  Redirecting stdin from /dev/null makes a prompt fail immediately
# instead of hanging, which is what makes this safe to call non-interactively.
k_can_auth() { # host [user] -> 0 if keyless login already works
    h="$1"; u="${2:-root}"
    [ -z "$h" ] && return 1
    case "$h" in 0.0.0.0|0.*|127.*) return 1 ;; esac
    k=$(k_key_path 2>/dev/null) || return 1
    out=$(timeout 10 ssh -y -i "$k" "$u@$h" 'echo __RLA_OK__' </dev/null 2>/dev/null)
    case "$out" in *__RLA_OK__*) return 0 ;; *) return 1 ;; esac
}

# ---- local inbound view (what the existing keys menu governs) -----------------
k_local_authorized() { # -> count|tagged-count  of keys allowed INTO this router
    t=0; g=0
    [ -f "$K_AUTH" ] && { t=$(grep -c . "$K_AUTH" 2>/dev/null); g=$(grep -c "$K_TAG" "$K_AUTH" 2>/dev/null); }
    echo "${t:-0}|${g:-0}"
}

rla_link_state() {              # iface type [role] -> what we can actually measure
    # WireGuard exposes a real handshake timestamp, so age is reported precisely.
    # OpenVPN exposes none (GL enables no status file and sets no `status` directive),
    # so no time is claimed for it - only whether a peer is known.
    # ASCII only: busybox printf pads by BYTES, so a multi-byte separator here
    # would under-pad the topology column by one display position.
    _lsif="$1"; _lsty="$2"; _lsro="$3"
    ip -4 addr show "$_lsif" 2>/dev/null | grep -q "inet " || { echo "down"; return; }
    if [ "$_lsty" = WireGuard ]; then
        _hs=$(wg show "$_lsif" latest-handshakes 2>/dev/null | awk '{print $2}' | sort -rn | head -1)
        [ -z "$_hs" ] && { echo "up"; return; }
        [ "$_hs" = 0 ] && { echo "up  no peer"; return; }
        _age=$(( $(date +%s) - _hs ))
        [ "$_age" -lt 0 ] && _age=0
        if [ "$_age" -lt 60 ]; then echo "up  ${_age}s ago"
        elif [ "$_age" -lt 3600 ]; then echo "up  $((_age/60))m ago"
        elif [ "$_age" -lt 86400 ]; then echo "up  $((_age/3600))h ago"
        else echo "up  $((_age/86400))d ago"; fi
    else
        _lsp=$(rla_peer_tunnel_ip "$_lsif" "$_lsty" "$_lsro")
        [ -n "$_lsp" ] && echo "up" || echo "up  no peer"
    fi
}

# Role-aware status label, shared by the MTU and Remote LAN Access screens. A client
# CONNECTS to a server, so it reads connected/disconnected; a server reports up/down.
# The WireGuard handshake age (e.g. "58s ago") carries through on either.
vpn_state_label() {   # iface type role -> label (status values are ALL CAPS per UX std)
    _vs=$(rla_link_state "$1" "$2" "$3")
    case "$3" in
        [Cc]lient)
            case "$_vs" in
                down|*"no peer"*) echo "DISCONNECTED" ;;
                "up  "*)          echo "CONNECTED  ${_vs#up  }" ;;
                up*)              echo "CONNECTED" ;;
                *)                echo "$_vs" ;;
            esac ;;
        *)  case "$_vs" in
                up*)   echo "UP${_vs#up}" ;;
                down*) echo "DOWN${_vs#down}" ;;
                *)     echo "$_vs" ;;
            esac ;;
    esac
}

# display columns of a flow-table value: everything is ascii (1 byte = 1 cell) EXCEPT a
# trailing † (U+2020) which is 3 BYTES but DAG_CELLS display cells - so ${#} over-counts it.
rla_dispw() { _b="${1%†}"; if [ "$_b" != "$1" ]; then printf '%d' $(( ${#_b} + DAG_CELLS )); else printf '%d' "${#1}"; fi; }
# left-justify $1 to a field of $2 DISPLAY columns (dagger-aware; replaces byte-based %-Ns).
rla_padr() { _d=$(rla_dispw "$1"); printf '%s' "$1"; [ "$2" -gt "$_d" ] && rla_rep ' ' "$(( $2 - _d ))"; return 0; }
rla_ctr() {                     # text width -> text centred in a field of width
    _t="$1"; _w="$2"; _l=$(rla_dispw "$_t")
    if [ "$_l" -ge "$_w" ]; then printf '%s' "$_t"; return; fi
    _p=$(( (_w - _l) / 2 ))
    rla_rep ' ' "$_p"; printf '%s' "$_t"; rla_rep ' ' "$(( _w - _l - _p ))"
}

rla_rep() { _i=0; while [ "$_i" -lt "$2" ]; do printf '%s' "$1"; _i=$((_i+1)); done; }

rla_ctx() {                              # shared lookups for the action handlers
    A_IF="$1"; A_TY="$2"; A_RO="$3"
    A_TUN=$(rla_tunnel_ip "$A_IF")
    A_PEER=$(rla_peer_tunnel_ip "$A_IF" "$A_TY" "$A_RO")
    A_LAN=$(rla_lan_cidr)
    A_RLAN=$(d_get "$A_IF"); [ -z "$A_RLAN" ] && A_RLAN=$(rla_remote_lan "$A_IF" "$A_TY")
    [ -z "$A_RLAN" ] && A_RLAN="unknown"
}

# ---- [2] outbound: route+authorise | inbound: access -------------------------
rla_do_lever2() {
    rla_ctx "$1" "$2" "$3"; _dir="$4"
    if [ "$_dir" = out ]; then
        if [ "$A_RLAN" = unknown ]; then
            print_warning "The remote LAN subnet is not known yet."
            print_info "Use option 2 first - a route needs a destination."
            press_any_key; return
        fi
        if guard_overlap "$A_LAN" "$A_RLAN"; then
            print_error "Refused: $A_RLAN overlaps this router's LAN $A_LAN."
            print_info "Two identical subnets cannot be routed between. Change one of them."
            press_any_key; return
        fi
        if rla_routes_via "$A_RLAN" "$A_IF" 2>/dev/null; then
            spin_run "Removing the route to $A_RLAN" w_route_del "$A_IF" "$A_RLAN"
            print_success "This router no longer routes $A_RLAN over $A_IF."
        else
            _blk=$(az_blocker "$A_IF" 2>&1)
            if [ -n "$_blk" ]; then
                print_warning "Route added, but per-peer authorisation is not possible:"
                print_info "$_blk"
            fi
            spin_run "Routing $A_RLAN via $A_PEER" w_route_add "$A_IF" "$A_RLAN" "$A_PEER"
            if [ -z "$_blk" ]; then
                _pid=$(az_peers "$A_IF" 2>/dev/null | head -1 | cut -d'|' -f2)
                [ -n "$_pid" ] && az_grant "$A_IF" "$_pid" "$A_RLAN" >/dev/null 2>&1
            fi
            print_success "This router now routes $A_RLAN over $A_IF."
            print_info "The status table re-checks reachability automatically."
        fi
    else
        _cur=$(w_get_access "$A_IF")
        case "$_cur" in ACCEPT|1) _new=$( [ "$_cur" = 1 ] && echo 0 || echo DROP ) ;;
                        *)        _new=$( [ "$_cur" = 0 ] && echo 1 || echo ACCEPT ) ;; esac
        _risk=$(guard_at_risk "$A_IF")
        if [ -n "$_risk" ]; then
            print_warning "This change can cut live management sessions:"
            lv_risk_report "$A_IF"
            printf '\n'; print_info "Other ways in that are currently up:"
            lv_alternates_report "$A_IF"
            printf '\n'
            printf ' Apply anyway? It reverts automatically in 30s unless confirmed [y/N]: '
            read -r _yn; printf '\n'
            case "$_yn" in y|Y) ;; *) print_info "Cancelled - nothing changed."; press_any_key; return ;; esac
        fi
        lv_apply "$A_IF" access "$_new" 30
        if lv_verify "$A_IF" access "$_new"; then
            if [ -n "$_risk" ]; then
                print_warning "Applied. Confirm within 30 seconds or it reverts."
                printf ' Still connected? Press y to keep it [y/N]: '
                read -r _yn
                case "$_yn" in y|Y) lv_confirm "$A_IF" access; print_success "Kept." ;;
                               *) print_info "Not confirmed - it will revert." ;; esac
            else
                lv_confirm "$A_IF" access
                print_success "Remote access is now $_new."
            fi
        else
            print_error "The firewall did not follow the setting - reverting."
        fi
    fi
    press_any_key
}

# ---- [3] outbound only: masquerade toggle ------------------------------------
# Inbound has no remote-side action - the remote router's route/masquerade can
# only be set on the remote router itself (that guidance now lives in the Help),
# so [3] is outbound-only and this is only ever called with _dir=out.
rla_do_lever3() {
    rla_ctx "$1" "$2" "$3"; _dir="$4"
    [ "$_dir" = out ] || return
    _cur=$(w_get_masq "$A_IF"); _new=$( [ "$_cur" = 1 ] && echo 0 || echo 1 )
    if ! w_zone_enabled "$A_IF"; then
        # w_set_masq refuses this too (rc 3); checked here as well so the
        # user gets an explanation instead of a silently skipped action.
        print_error "The firewall zone for $A_IF is disabled."
        print_info "This setting would have no effect until the VPN is enabled properly."
        press_any_key; return
    fi
    _risk=$(guard_at_risk "$A_IF")
    if [ -n "$_risk" ]; then
        print_warning "This changes how traffic is addressed and can interrupt sessions:"
        lv_risk_report "$A_IF"
        printf '\n Apply anyway? It reverts automatically in 30s unless confirmed [y/N]: '
        read -r _yn; printf '\n'
        case "$_yn" in y|Y) ;; *) print_info "Cancelled - nothing changed."; press_any_key; return ;; esac
    fi
    lv_apply "$A_IF" masq "$_new" 30
    if lv_verify "$A_IF" masq "$_new"; then
        lv_confirm "$A_IF" masq
        if [ "$_new" = 0 ]; then print_success "Your devices now show their real addresses to the remote side."
        else print_success "Your devices are now hidden behind $A_TUN."; fi
    else
        print_error "The firewall did not follow the setting - it will revert."
    fi
    press_any_key
}

# Quiet auto-detect, run once when ENTERING the feature (never from the menu).
# Tries the authoritative source (the tunnel's own AllowedIPs), else a standard
# tunnel scan, and sets the remote LAN ONLY when the answer is a single eligible
# subnet. No countdown, no prompts, no "press any key" - it just flows into the
# screen. The ambiguous, multi-result and manual cases are left for the explicit
# [2] "Detect or set the remote LAN subnet" action, which stays interactive.
rla_autodetect() {
    rla_ctx "$1" "$2" "$3"; _ad_if="$A_IF"
    _ad_v=$(d_config "$_ad_if" "$A_TY" 2>/dev/null)
    [ -n "$_ad_v" ] && { d_store "$_ad_if" "$_ad_v" config >/dev/null 2>&1; return; }
    d_can_probe "$_ad_if" || return
    # Show a spinner so entry doesn't look frozen during the scan - the duration is
    # network-dependent, so a countdown estimate only drifts out of sync. No "press
    # any key" afterwards; it flows straight in.
    spin_run "Scanning $_ad_if for the remote LAN" d_scan "$_ad_if" standard
    _ad_hits=$(grep '/' "$SPIN_LOG" 2>/dev/null)
    [ "$(printf '%s\n' "$_ad_hits" | grep -c '/')" = 1 ] && {
        d_store "$_ad_if" "$_ad_hits" probe >/dev/null 2>&1
        print_success "Remote LAN on $_ad_if set to $_ad_hits."
    }
}

# ---- [2] detect or set the remote LAN subnet ---------------------------------
# SSH probe for the remote LAN, echoed (not returned in a var) so it can run under
# a spinner - spin_run backgrounds its command, where a var assignment would be
# lost. Emits "RLASRC|<cidr>" only when keyless SSH to the peer answers.
rla_ssh_lookup() {   # peer -> "RLASRC|cidr" | (nothing)
    _slp="$1"; [ -z "$_slp" ] && return 1
    if k_can_auth "$_slp" 2>/dev/null && _slv=$(d_ssh_query "$_slp" 2>/dev/null) && [ -n "$_slv" ]; then
        printf 'RLASRC|%s\n' "$_slv"
    fi
}

rla_do_detect() {
    rla_ctx "$1" "$2" "$3"
    ifc="$A_IF"; d_trace_reset 2>/dev/null

    # 1) Authoritative sources first: an earlier manual set, the tunnel's own
    #    AllowedIPs, or (only if key-login already works) the remote router.
    _known=""; _kdisp=""; _ktok=""
    v=$(d_get "$ifc"); [ -n "$v" ] && { _known="$v"; _kdisp="set earlier"; _ktok=""; }
    if [ -z "$_known" ] && v=$(d_config "$ifc" "$A_TY" 2>/dev/null) && [ -n "$v" ]; then
        _known="$v"; _kdisp="the tunnel's AllowedIPs"; _ktok="config"; fi
    # The SSH probe (k_can_auth) can block up to its 10s timeout when the peer runs
    # no SSH; run it under a spinner so [2] doesn't sit on a frozen screen. spin_run
    # backgrounds its command, so the answer comes back via stdout, not a variable.
    if [ -z "$_known" ] && [ -n "$A_PEER" ]; then
        spin_run "Checking the tunnel peer over SSH" rla_ssh_lookup "$A_PEER"
        v=$(grep '^RLASRC|' "$SPIN_LOG" 2>/dev/null | head -1); v=${v#RLASRC|}
        [ -n "$v" ] && { _known="$v"; _kdisp="the remote router over SSH"; _ktok="ssh"; }
    fi
    if [ -n "$_known" ]; then
        print_success "Remote LAN is $_known  (from $_kdisp)."
        printf 'Keep this? [Y/n]: '; read -r _a; printf '\n'
        case "$_a" in
            n|N) _known="" ;;
            *)   [ -n "$_ktok" ] && d_store "$ifc" "$_known" "$_ktok" >/dev/null 2>&1
                 print_success "Remote LAN set to $_known."; press_any_key; return ;;
        esac
    fi

    # 2) Two-tier scan through the tunnel. Each tier keeps only subnets that are
    #    0-hop (directly across the tunnel), so an upstream subnet can never be
    #    mistaken for the remote LAN. Several can be directly attached, so results
    #    are a pick-list, not a guess.
    _hits=""; _scanned=0
    if [ -z "$_known" ] && d_can_probe "$ifc"; then
        _scanned=1
        # Standard: ping the common gateways (~2s, NO dependency - works on a plane).
        # Full is offered only if Standard finds nothing; it installs fping and sweeps
        # every private /24 in seconds. Scan duration is network-dependent, so a
        # spinner (not a countdown) tracks the real work.
        spin_run "Scanning common subnets" d_scan "$ifc" standard
        _hits=$(grep '/' "$SPIN_LOG" 2>/dev/null)
        if [ -z "$_hits" ]; then
            print_warning "No remote LAN answered on the common subnets."
            printf 'Run a full scan (every private /24, ~30s)? [y/N]: '
            read -r _a; printf '\n'
            case "$_a" in
                y|Y)
                    command -v fping >/dev/null 2>&1 || spin_run "Installing fping" install_package fping
                    if command -v fping >/dev/null 2>&1; then
                        spin_run "Scanning all private subnets" d_scan "$ifc" full
                        _hits=$(grep '/' "$SPIN_LOG" 2>/dev/null)
                    else
                        print_warning "fping is unavailable and the shell fallback would take ~18 minutes - skipped."
                    fi ;;
            esac
        fi
    elif [ -z "$_known" ]; then
        print_info "This tunnel isn't up, so a scan can't run - enter the subnet by hand."
    fi

    # 3) Present scan results: one -> store; several -> pick-list.
    if [ -n "$_hits" ]; then
        _n=$(printf '%s\n' "$_hits" | grep -c .)
        if [ "$_n" -eq 1 ]; then
            if d_store "$ifc" "$_hits" probe >/dev/null 2>&1; then print_success "Remote LAN set to $_hits."
            else print_error "Could not store $_hits."; fi
            press_any_key; return
        fi
        print_success "Found $_n subnets directly across the tunnel:"
        printf '\n'
        printf '%s\n' "$_hits" | awk '{printf "   [%d] %s\n", NR, $0}'
        printf '\nWhich is the remote LAN? [1-%s], or Enter to type one instead: ' "$_n"
        read -r _pick; printf '\n'
        case "$_pick" in
            [1-9]|[1-9][0-9])
                _sel=$(printf '%s\n' "$_hits" | sed -n "${_pick}p")
                if [ -n "$_sel" ]; then
                    if d_store "$ifc" "$_sel" probe >/dev/null 2>&1; then print_success "Remote LAN set to $_sel."
                    else print_error "Could not store $_sel."; fi
                    press_any_key; return
                fi ;;
        esac
    fi

    # 4) Manual entry - also the path when the user chose to type one above. When we
    #    just scanned and came up empty, say so first, so the manual prompt has a
    #    reason (the pick-list "type one" path has hits, so it stays silent).
    [ "$_scanned" = 1 ] && [ -z "$_hits" ] && print_warning "No remote LAN found automatically."
    printf 'Enter the remote LAN subnet manually (e.g. 192.168.2.0/24), or press Enter to leave it unknown: '
    read -r _in; printf '\n'
    if [ -n "$_in" ]; then
        case "$_in" in */*) ;; *) print_error "Needs a prefix length, e.g. 192.168.2.0/24"; press_any_key; return ;; esac
        if guard_overlap "$A_LAN" "$_in"; then
            print_error "Refused: $_in overlaps this router's LAN $A_LAN."
            print_info "Remote LAN access cannot work between two identical subnets."
            press_any_key; return
        fi
        if d_store "$ifc" "$_in" manual; then print_success "Remote LAN set to $_in."
        else print_error "Could not store that subnet."; fi
    else
        print_info "Left unknown - routing to the remote LAN needs a subnet first."
    fi
    press_any_key
}

# ---- Remote LAN Access screen ------------------------------------------------
rla_pages_build() {                     # flat page list: tunnel x direction
    : > /tmp/rla_pages.$$
    rla_detect | while IFS='|' read -r t r i; do
        [ -z "$i" ] && continue
        printf '%s|%s|%s|out\n%s|%s|%s|in\n' "$t" "$r" "$i" "$t" "$r" "$i" >> /tmp/rla_pages.$$
    done
}

rla_stat() { case "$1" in reachable) echo REACH ;; unreach) echo BLOCK ;; *) echo UNKNOWN ;; esac; }

rla_measure() {   # tun-ip lan-ip peer rgw -> "tp=..; lp=..; tr=..; lr=.." (parallel)
    _rt="$1"; _rl="$2"; _rp="$3"; _rg="$4"; _b="/tmp/.rlm.$$"
    ( pr_ping "$_rp" "$_rt" && echo tp=reachable || echo tp=unreach ) >"$_b.1" 2>/dev/null &
    ( pr_ping "$_rp" "$_rl" && echo lp=reachable || echo lp=unreach ) >"$_b.2" 2>/dev/null &
    if [ -n "$_rg" ]; then
        ( pr_ping "$_rg" "$_rt" && echo tr=reachable || echo tr=unreach ) >"$_b.3" 2>/dev/null &
        ( pr_ping "$_rg" "$_rl" && echo lr=reachable || echo lr=unreach ) >"$_b.4" 2>/dev/null &
    else printf 'tr=na\n' >"$_b.3"; printf 'lr=na\n' >"$_b.4"; fi
    wait; cat "$_b".1 "$_b".2 "$_b".3 "$_b".4 2>/dev/null; rm -f "$_b".*
}

rla_cache_measure() {   # iface type role -> cache this tunnel's OUTBOUND measurement
    _ci="$1"
    _ct=$(rla_tunnel_ip "$_ci"); _cp=$(rla_peer_tunnel_ip "$_ci" "$2" "$3")
    _cl=$(rla_lan_ip); _cr=$(d_get "$_ci"); [ -z "$_cr" ] && _cr=$(rla_remote_lan "$_ci" "$2")
    _cr="${_cr%†}"; _cg=""; [ -n "$_cr" ] && [ "$_cr" != unknown ] && _cg=$(pr_gw_of "$_cr")
    rla_measure "$_ct" "$_cl" "$_cp" "$_cg" > "$RLA_MCACHE.$_ci" 2>/dev/null
}

rla_reverify() {   # iface type role -> a config change happened; drop the stale
    rm -f "$RLA_MCACHE.$1"                # cache and re-measure THIS tunnel with
    print_action "Re-checking reachability on $1"   # honest feedback, so the
    rla_cache_measure "$1" "$2" "$3"     # redraw shows truth instead of hanging.
}

# Status is MEASURED, never inferred. OUTBOUND rows show a live ping from each
# source identity (masqueraded = the tunnel IP; real = the LAN IP) to the
# destination. INBOUND cannot be pinged from here (the remote must initiate), so
# it shows our firewall's real accept/block policy, and flags the parts that only
# the remote side controls. Re-runs on every render, so it is fresh after a change.
rla_rows() {                            # status|from|as|to|change
    _if="$1"; _ty="$2"; _ro="$3"; _dir="$4"
    _zone=$(rla_zone "$_if"); _tun=$(rla_tunnel_ip "$_if")
    _peer=$(rla_peer_tunnel_ip "$_if" "$_ty" "$_ro")
    _lanip=$(rla_lan_ip); _lan=$(rla_lan_cidr)
    _rlan=$(d_get "$_if"); [ -z "$_rlan" ] && _rlan=$(rla_remote_lan "$_if" "$_ty")
    [ -z "$_rlan" ] && _rlan="unknown"
    [ "$(d_get_src "$_if")" = probe ] && [ "$_rlan" != unknown ] && _rlan="$_rlan†"
    _rbase="${_rlan%†}"; _sfx=""; [ "$_rbase" != "$_rlan" ] && _sfx="†"
    _masq=$(rla_masq "$_zone"); _acc=$(rla_access "$_zone")
    [ -z "$_peer" ] && { [ "$_ro" = server ] && _peer="no clients" || _peer="no peer"; }
    _lo="${_lanip%.*}.2-254"
    if [ "$_dir" = out ]; then
        # Change column keeps the ORIGINAL wording; only the STATUS is now measured
        # and the opt numbers are renumbered (masq 3->2, route 2->1, detect 4->3).
        _rgw=""; [ "$_rbase" != unknown ] && _rgw=$(pr_gw_of "$_rbase")
        tp=na; lp=na; tr=na; lr=na
        if [ -n "$RLA_MCACHE" ] && [ -f "$RLA_MCACHE.$_if" ]; then eval "$(cat "$RLA_MCACHE.$_if")"
        else _mm=$(rla_measure "$_tun" "$_lanip" "$_peer" "$_rgw")
             [ -n "$RLA_MCACHE" ] && echo "$_mm" > "$RLA_MCACHE.$_if"; eval "$_mm"; fi
        for _d in peer rlan; do
            if [ "$_d" = peer ]; then _to="$_peer"; _sm="$tp"; _sr="$lp"
            elif [ "$_rbase" = unknown ]; then
                echo "UNKNOWN|$_lo|$_tun|unknown|Subnet not known yet - opt 2"
                echo "UNKNOWN|$_lanip|$_tun|unknown|Subnet not known yet - opt 2"
                echo "UNKNOWN|$_lo|$_lo|unknown|Subnet not known yet - opt 2"
                echo "UNKNOWN|$_lanip|$_lanip|unknown|Subnet not known yet - opt 2"
                continue
            else _to="$_rlan"; _sm="$tr"; _sr="$lr"; fi
            if [ "$_masq" = on ]; then
                echo "$(rla_stat "$_sm")|$_lo|$_tun|$_to|Opt 3 stops masquerading"
                echo "$(rla_stat "$_sm")|$_lanip|$_tun|$_to|Opt 3 stops masquerading"
                echo "$(rla_stat "$_sr")|$_lo|$_lo|$_to|Masquerading is on - opt 3"
                echo "$(rla_stat "$_sr")|$_lanip|$_lanip|$_to|Masquerading is on - opt 3"
            else
                echo "$(rla_stat "$_sm")|$_lo|$_tun|$_to|Masquerading is off - opt 3"
                echo "$(rla_stat "$_sm")|$_lanip|$_tun|$_to|Masquerading is off - opt 3"
                echo "$(rla_stat "$_sr")|$_lo|$_lo|$_to|Opt 2 hides devices behind $_tun"
                echo "$(rla_stat "$_sr")|$_lanip|$_lanip|$_to|Opt 2 hides devices behind $_tun"
            fi
        done
        echo "$(rla_stat "$tp")|$_tun|$_tun|$_peer|this router to the tunnel peer"
        if [ "$_rbase" = unknown ]; then
            echo "UNKNOWN|$_tun|$_tun|unknown|Subnet not known yet - opt 2"
        elif rla_routes_via "$_rbase" "$_if" 2>/dev/null; then
            echo "$(rla_stat "$tr")|$_tun|$_tun|$_rlan|Opt 1 removes this route"
        else
            echo "$(rla_stat "$tr")|$_tun|$_tun|$_rlan|Opt 1 adds the route"
        fi
    else
        # INBOUND: not pingable from here. Status is our firewall's accept policy;
        # remote-controlled flows keep the original wording, renumbered.
        if [ "$_acc" = on ]; then _ai=REACH; _ah="Opt 1 blocks the remote side"
        else _ai=BLOCK; _ah="Remote access is off - opt 1"; fi
        if [ "$_rbase" = unknown ]; then
            echo "UNKNOWN|unknown|$_peer|$_tun|Subnet not known yet - opt 2"
            echo "UNKNOWN|unknown|$_peer|$_lan|Subnet not known yet - opt 2"
            echo "UNKNOWN|unknown|unknown|$_tun|Subnet not known yet - opt 2"
            echo "UNKNOWN|unknown|unknown|$_lan|Subnet not known yet - opt 2"
        else
            for _s in "${_rbase%.*}.2-254$_sfx" "${_rbase%.*}.1$_sfx"; do
                echo "$_ai|$_s|$_peer|$_tun|$_ah"
                echo "$_ai|$_s|$_peer|$_lan|$_ah"
                echo "REMOTE|$_s|$_s|$_tun|Remote must stop masquerading"
                echo "REMOTE|$_s|$_s|$_lan|Remote must route your LAN"
            done
        fi
        echo "$_ai|$_peer|$_peer|$_tun|$_ah"
        echo "$_ai|$_peer|$_peer|$_lan|$_ah"
    fi
}

manage_remote_lan_access() {
    local pg=1
    rla_pages_build
    local np; np=$(wc -l < /tmp/rla_pages.$$ | tr -dc '0-9')
    if [ "${np:-0}" -lt 1 ]; then
        clear; print_centered_header "Remote LAN Access"
        print_warning "No VPN tunnel is up on this router."
        print_info "Start a WireGuard or OpenVPN client or server first."
        press_any_key; rm -f /tmp/rla_pages.$$; return
    fi
    # Collect ALL data up front, on ENTERING the feature, before any page is drawn:
    # detect the remote LAN for every scannable tunnel, then measure each tunnel's
    # reachability into a per-tunnel cache. Page navigation then reads the cache and
    # is instant; a change action re-measures only the affected tunnel. The tunnel
    # list is read on FD 3 to keep the loop's own stdin isolated. Entry-time detect
    # is now the quiet rla_autodetect (no prompts, no "press any key") - the verbose
    # interactive detect only runs from the [2] menu action.
    RLA_MCACHE="/tmp/.rlam.$$"; rm -f "$RLA_MCACHE".*
    awk -F'|' '{print $1"|"$2"|"$3}' /tmp/rla_pages.$$ | sort -u > /tmp/rla_tuns.$$
    clear; print_centered_header "Remote LAN Access"
    while IFS='|' read -r _t _r _i <&3; do
        [ -z "$(d_get "$_i")" ] && rla_autodetect "$_i" "$_t" "$_r"
        spin_run "Checking reachability on $_i" rla_cache_measure "$_i" "$_t" "$_r"
    done 3< /tmp/rla_tuns.$$
    rm -f /tmp/rla_tuns.$$
    # Use the profile-aware cells computed by detect_output_mode - they are padded
    # to exactly 8 columns for THIS terminal's measured glyph widths. Hardcoding
    # the pad here is what made the column ragged on terminals where emoji
    # advance 1 instead of 2.
    S_AC="$_S_RLA_AC"; S_IA="$_S_RLA_IA"; S_RO="$_S_RLA_RO"
    # Status is measured now: reachable / blocked, plus a WARN cell for rows that
    # cannot be measured from here - inbound flows the remote must initiate, or a
    # not-yet-known subnet.
    case "$S_AC" in
        \[*) DEC="Legend: [AC] reachable  [IA] blocked  [!] unknown  † inferred subnet" ;;
            # Painted so PuTTY's monochrome circles stay distinguishable. (Measured with
            # glyph-test.sh across mac/termius/ttyd/wt/putty: the circles are NOT clipped by the
            # trailing † on any of them, so no sacrificial space is needed here.)
        *)  DEC=$(printf 'Legend: %b🟢%b reachable  %b🔴%b blocked  %b🟡%b unknown  † inferred subnet' "$GREEN" "$RESET" "$RED" "$RESET" "$YELLOW" "$RESET") ;;
    esac
    if [ "$OUTPUT_MODE" = "compat" ]; then
        RULE="-"; BAR="|"; TL="|"; TR="|"; LK="===="; WR="--"
    else
        RULE="─"; BAR="│"; TL="┤"; TR="├"; LK="════"; WR="──"
    fi
    local W=100
    while true; do
        [ "$pg" -gt "$np" ] && pg=1
        [ "$pg" -lt 1 ] && pg="$np"
        local cur; cur=$(sed -n "${pg}p" /tmp/rla_pages.$$)
        local type role iface dir
        type=${cur%%|*}; local rest=${cur#*|}
        role=${rest%%|*}; rest=${rest#*|}
        iface=${rest%%|*}; dir=${rest#*|}
        local rt; case "$role" in server) rt=Server ;; *) rt=Client ;; esac
        local nx=$(( pg % np + 1 )) pv=$(( (pg - 2 + np) % np + 1 ))
        local tun peer lan lanip rlan rgw
        tun=$(rla_tunnel_ip "$iface"); peer=$(rla_peer_tunnel_ip "$iface" "$type" "$role")
        lan=$(rla_lan_cidr); lanip=$(rla_lan_ip)
        rlan=$(d_get "$iface"); [ -z "$rlan" ] && rlan=$(rla_remote_lan "$iface" "$type")
        [ -z "$rlan" ] && rlan="unknown"
        [ "$(d_get_src "$iface")" = probe ] && [ "$rlan" != unknown ] && rlan="$rlan†"
        if [ "$rlan" = unknown ]; then rgw="unknown"; else rgw="${rlan%†}"; rgw="${rgw%.*}.1"; fi
        [ -z "$peer" ] && { [ "$role" = server ] && peer="no clients" || peer="no peer"; }

        clear
        print_centered_header "Remote LAN Access"
        # Identity line (cyan): the tunnel and its role-aware state, promoted out of
        # the topology's first column so the diagram reads cleanly below it. Status
        # is ALL CAPS (UX std); client=CONNECTED/DISCONNECTED, server=UP/DOWN.
        _rst=$(vpn_state_label "$iface" "$type" "$role")
        case "$_rst" in CONNECTED*|UP*) _rsc="$GREEN" ;; *) _rsc="$RED" ;; esac
        printf ' %b%s %s: %s%b     Status: %b%s%b\n\n' "$CYAN" "$type" "$rt" "$iface" "$RESET" "$_rsc" "$_rst" "$RESET"
        # Topology diagram (no left rail - the leftmost value left-aligns with the
        # Status column of the flow table below). Values are centred under their own
        # label so each column reads as a unit.
        printf ' %s%s%s%s%s%s%s%s\n' \
            "$(rla_ctr 'this LAN' 18)" "$WR$TL" "$(rla_ctr 'this router' 15)" \
            "$TR$LK$TL" "$(rla_ctr 'remote router' 15)" "$TR$WR" \
            "$(rla_ctr 'remote LAN' 13)" ""
        printf ' %s%s%s%s%s%s%s\n' \
            "$(rla_ctr "$lan" 18)" "   " "$(rla_ctr "$tun" 15)" \
            "      " "$(rla_ctr "$peer" 15)" "   " "$(rla_ctr "$rlan" 13)"
        printf ' %s%s%s%s%s\n' \
            "$(rla_ctr '' 18)" "   " "$(rla_ctr "$lanip" 15)" \
            "      " "$(rla_ctr "$rgw" 15)"
        printf '\n'
        if [ "$dir" = out ]; then printf ' %bOUTBOUND%b   From here to the remote side\n' "$CYAN" "$RESET"
        else printf ' %bINBOUND%b    From the remote side to here\n' "$CYAN" "$RESET"; fi
        printf '   %-8s%-18s%-18s%-18s%s\n' Status From As To Change
        # Emit in GENERATION order, not sorted by status. The rows are a fixed
        # enumeration whose position never changes - only their Status does - so
        # a toggle updates the row you were looking at instead of moving it
        # somewhere else. Sorting made sense while the sections had visible
        # headers to explain the reordering; with the Status column carrying that
        # information, sorting only costs spatial stability.
        rla_rows "$iface" "$type" "$role" "$dir" | while IFS='|' read -r k a b c d; do
            case "$k" in REACH) g="$S_AC";; BLOCK) g="$S_IA";; *) g="$S_RO";; esac
            # dagger-aware padding: %-18s counts the 3-byte † as 3, so a daggered value would
            # slide the next column left. rla_padr pads by DISPLAY width instead.
            printf '   %s%s%s%s%s\n' "$g" "$(rla_padr "$a" 18)" "$(rla_padr "$b" 18)" "$(rla_padr "$c" 18)" "$d"
        done
        printf '\n %s\n' "$DEC"
        printf ' %s\n' "$(rla_rep "$RULE" $W)"
        # Density-divider rule: this dense page earns a divider between the legend
        # and the actions. Navigation is a realtime footer BELOW the actions (no
        # Choose prompt, cursor rests at line end), matching the MTU / Hardware Info
        # screens; the identity line + topology header name the page.
        # Toggle labels state what pressing WILL DO from the current state, using
        # the app-wide Enable/Disable convention (see ui-toggle-label-standard).
        # [1] reach and [2] detect mean the same on both directions; [3] masquerade
        # is outbound-only.
        if [ "$dir" = out ]; then
            if [ "$rlan" != unknown ] && rla_routes_via "${rlan%†}" "$iface" 2>/dev/null
            then _o1="[1] Disable routing to the remote LAN"
            else _o1="[1] Enable routing to the remote LAN"; fi
            if [ "$(rla_masq "$(rla_zone "$iface")")" = on ]
            then _o3="[3] Disable masquerade (show my devices' real addresses)"
            else _o3="[3] Enable masquerade (hide my devices behind $tun)"; fi
            printf ' %s\n' "$_o1"
            printf ' %s\n' "[2] Detect or set the remote LAN subnet"
            printf ' %s\n' "$_o3"
            _opts="1-3"
        else
            if [ "$(rla_access "$(rla_zone "$iface")")" = on ]
            then _o1="[1] Disable inbound access from the remote LAN"
            else _o1="[1] Enable inbound access from the remote LAN"; fi
            printf ' %s\n' "$_o1"
            printf ' %s\n' "[2] Detect or set the remote LAN subnet"
            _opts="1-2"
        fi
        case "$_opts" in 1-3) _keys="1/2/3" ;; *) _keys="1/2" ;; esac
        printf '\n [P] Previous   Page %s of %s   [N] Next   [%s]   [0] Back   [?] Help  ' "$pg" "$np" "$_keys"
        c=$(read_single_char); printf '\n\n'
        case "$c" in
            1) rla_do_lever2 "$iface" "$type" "$role" "$dir"
               [ "$dir" = out ] && rla_reverify "$iface" "$type" "$role" ;;
            2) _pre=$(d_get "$iface"); rla_do_detect "$iface" "$type" "$role"
               [ "$(d_get "$iface")" != "$_pre" ] && rla_reverify "$iface" "$type" "$role" ;;
            3) if [ "$dir" = out ]; then
                   rla_do_lever3 "$iface" "$type" "$role" "$dir"
                   rla_reverify "$iface" "$type" "$role"
               else print_error "Invalid option"; sleep 1; fi ;;
            p|P) pg=$pv ;;
            n|N) pg=$nx ;;
            0) rm -f /tmp/rla_pages.$$ "$RLA_MCACHE".*; return ;;
            \?|h|H|❓) show_rla_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

show_vpntools_help() {
    show_paged "VPN Tools - Help" << 'HELPEOF'

VPN Tools - Quick Help

What it does
────────────
A hub for the toolkit's VPN utilities:

  • VPN MTU Optimizer - tune each tunnel's packet size so tunnelled traffic
    stops fragmenting and silently losing throughput.
  • Remote LAN Access - reach the LAN behind the far end of a tunnel (which
    GL.iNet's own "Allow Remote Access to LAN" toggle does not fully set up).

Getting around
──────────────
Type the number beside an item and press Enter. [0] goes back; [?] shows the
help for whichever screen you are on.

HELPEOF
}

show_mtu_help() {
    show_paged "VPN MTU Optimizer - Help" << 'HELPEOF'

VPN MTU Optimizer - Quick Help

What it does
────────────
Finds each active WireGuard/OpenVPN tunnel and works out the best MTU - the
largest packet that fits without fragmenting - so tunnelled traffic stops
silently losing throughput.

The status block
────────────────
One tunnel per page; [P]/[N] move between tunnels. For the tunnel on screen:
  • Status       - Active (carrying traffic) or Inactive (down)
  • Current MTU  - what is set now
  • Underlay     - the link the tunnel rides on, and its MTU
  • Overhead     - the protocol's per-packet cost
  • Recommended  - the best MTU (Underlay minus Overhead)
  • Basis        - whether Recommended is Calculated from the link, or Verified
                   by an active probe (with the date and target)

The actions
───────────
Each action applies to the tunnel currently on screen:
  • Optimize tunnel     - apply the recommended MTU
  • Set MTU manually    - enter a value by hand
  • Verify with a probe - test the real path and mark the Basis "Verified"
  • Reset MTU           - remove the toolkit's override; the router default
                          governs again

About Verify (the active probe)
───────────────────────────────
Verify sends don't-fragment test packets to find the largest that survives - but
it can be inconclusive without meaning anything is wrong:
  • A failed ICMP reply does NOT mean the endpoint is down. Many servers (and the
    WireGuard/OpenVPN UDP port itself) simply don't answer ICMP, even while the
    tunnel is up and passing traffic.
  • If something on the path ignores the don't-fragment flag, oversized packets
    get through anyway and the measured size reads too high to trust.
Either way the probe result is discarded and the safe Calculated value is kept.
If the tunnel had a prior Verified value, an inconclusive probe also clears it, so
the Basis returns to Calculated - the path can no longer confirm it. On the result
screen this reads "Verified MTU: unknown" and "Falling back to the Calculated <n>;
this value was not actively verified" - it means "couldn't verify", not "broken".

Notes
─────
  • The value is written where GL.iNet expects it, so it appears in the Admin
    Panel under the tunnel's Options and survives a reboot.

HELPEOF
}

show_rla_help() {
    show_paged "Remote LAN Access - Help" << 'HELPEOF'

Remote LAN Access - Quick Help

What it does
────────────
Lets a device at one end of a VPN reach the LAN behind the other end - which
GL.iNet's "Allow Remote Access to LAN" toggle does not fully route on its own.

The table
─────────
Each row is a traffic flow (outbound or inbound) with its status: whether the
route, the firewall masquerade and per-peer access are in place. Use [P]/[N] to
page between tunnels and directions.

The actions
───────────
Status is measured live on entry and re-checked after any change, so there is no
separate "test" step. The toggles state what pressing them will do right now:
  • Enable / Disable routing to the remote LAN    - outbound.
  • Enable / Disable masquerade                    - outbound; hide your devices
                        behind the tunnel address, or show their real addresses.
  • Enable / Disable inbound access                - let the remote LAN reach you.
  • Detect or set the remote LAN subnet            - refuses one that overlaps
                        your own LAN.

Notes
─────
  • Changes are applied through GL.iNet's own VPN firewall helpers, so they
    persist and stay consistent with the Admin Panel.
  • Inbound access also needs the REMOTE router to route its LAN over the tunnel
    and to not masquerade traffic toward you. That side can only be configured on
    the remote router itself - this tool cannot set it for you.

HELPEOF
}

show_package_help() {
    show_paged "Package & Persistence Manager - Help" << 'HELPEOF'

Package & Persistence Manager - Quick Help

What it does
────────────
Installs the optional tools the toolkit can use (speed tests, benchmarks and
other utilities) and manages whether they survive a reboot.

Install / remove
────────────────
  • Toggle a package to mark it for install (or an installed one for removal),
    then Confirm. The right package manager for your firmware (opkg or apk) is
    used automatically.
  • Removals are verified: if a package you are removing is required by other
    installed packages it is kept and reported (you may type YES to force it,
    though that can break the packages that depend on it). A non-package tool
    has all of its files removed, leaving nothing behind.

Size & storage
──────────────
  • Size is the INSTALL size for every package - what it occupies once on disk, not the
    download. Installed rows are measured directly (a firmware-provided package counts too:
    it can be removed from the active partition, returning on a firmware reset); not-installed
    rows are the package index's declared install size, so they are an estimate. "-" means the
    size could not be determined (e.g. a package the index doesn't list).
  • The Storage line shows the overlay's free space and, once you stage changes, the projected
    free space after them. On a compressing overlay (ubifs/jffs2) that projection is a
    conservative "≈" floor - real free space is usually a little higher - and it turns amber
    when it would get low; on f2fs/ext4 it is exact.
  • [S] Sort toggles largest-first (the default) and alphabetical.

Persistence
───────────
Many models wipe added packages on reboot. Persistence re-installs your marked
tools automatically at boot so they are always there; turn it off to save space
and install on demand instead. Persistence applies only to installed packages -
uninstalling a tool also clears its persistence.

Notes
─────
  • A package with no build for your CPU (e.g. the Ookla speed test on MIPS) is
    called out up front, with an alternative suggested.
  • Tailscale installs both the daemon and GL's integration (admin-panel toggle,
    kill-switch), and removing it takes both so the full space is freed. It's on
    current firmware; the oldest builds may not offer it.

HELPEOF
}

manage_vpn_tools() {
    while true; do
        clear
        print_centered_header "Network and VPN Tools"
        printf "%s%sVPN MTU Optimizer\n" "$N1" "$NSEP"
        printf "%s%sRemote LAN Access\n" "$N2" "$NSEP"
        printf "%s%sNetwork Bandwidth Limiter\n" "$N3" "$NSEP"
        printf "%s%sSSH Key Management\n" "$N4" "$NSEP"
        printf "%s%sMain menu\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-4/0/?]: "
        read -r vpn_choice
        printf "\n"
        case "$vpn_choice" in
            1) manage_mtu ;;
            2) manage_remote_lan_access ;;
            3) manage_netlimit ;;
            4) manage_ssh_keys ;;
            0) return ;;
            \?|h|H|❓) show_vpntools_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Package System Repair (System Tweaks)
# ─────────────────────────────────────────────────────────────────────────────
# Diagnoses and repairs the two ways a Packages-format file gets corrupted (see the
# pkg_* primitives near the top of the script): a truncated, re-fetchable feed cache,
# and a truncated installed database /usr/lib/opkg/status. Database backups live in the
# central store (bk_* namespace "opkg"). apk devices use apk's own update / fix, since
# the newline corruption is opkg-specific.

pkg_db_restore() {
    local _db _ns _base; _db="$(pkg_db_path)"; _ns="$(pkg_db_ns)"; _base="$(basename "$_db")"
    local list; list=$(bk_list "$_ns" "$_base")
    if [ -z "$list" ]; then printf "\n"; print_info "No database backups saved yet."; press_any_key; return; fi
    clear
    print_centered_header "Restore Package Database"
    printf " %-3s  %-18s  %s\n" "#" "Date / Time" "Size"
    printf " ────────────────────────────────────────────\n"
    local map="/tmp/pkg_bk_map.$$"; : > "$map"
    local i=1 ts
    for ts in $list; do
        printf " %-3s  %-18s  %sK\n" "$i." "$(bk_date "$ts")" "$(bk_size_kb "$_ns" "$ts")"
        printf "%s|%s\n" "$i" "$ts" >> "$map"; i=$((i+1))
    done
    printf " ────────────────────────────────────────────\n"
    printf " [#] To Restore   [0] Cancel\n"
    printf "\n Choose [%s/0]: " "$(picker_range $((i-1)))"
    read -r c; printf "\n"
    if [ -z "$c" ] || [ "$c" = "0" ]; then rm -f "$map"; return; fi
    local ts_sel; ts_sel=$(grep "^$c|" "$map" | cut -d'|' -f2); rm -f "$map"
    if [ -z "$ts_sel" ]; then print_error "Invalid selection"; sleep 1; return; fi
    print_warning "This overwrites the current installed database with the backup from $(bk_date "$ts_sel")."
    printf "Restore this backup? [y/N]: "; read -r yn; printf "\n"
    case "$yn" in y|Y) ;; *) print_info "Restore cancelled."; press_any_key; return ;; esac
    if bk_restore "$_ns" "$ts_sel" "$_db"; then
        spin_run "Verifying the package index" pkg_update
        if tail -n 80 "$SPIN_LOG" 2>/dev/null | pkg_parse_sig; then
            print_warning "Restored, but opkg still reports parse errors - the backup may predate the corruption; try 'Rebuild the package index cache'."
        else
            print_success "Database restored from $(bk_date "$ts_sel")."
        fi
        rm -f "$SPIN_LOG" 2>/dev/null
    else
        print_error "Could not restore the selected backup."
    fi
    press_any_key
}

# Multi-select cleanup, mirroring the AdGuardHome Backup Cleanup (delete_agh_backups): a persistent
# selection map with [A] All / [N] None / [#] Toggle / [C] Confirm / [0] Cancel, so several backups
# can be purged at once. Single-component (the installed DB), so no Conf/Bin/Init columns.
pkg_db_delete() {
    local _ns _base _bkd; _ns="$(pkg_db_ns)"; _base="$(basename "$(pkg_db_path)")"; _bkd="$(bk_dir "$_ns")"
    local map_file="/tmp/pkg_del_map"
    [ -f "$map_file" ] && rm -f "$map_file"
    while true; do
        local backups; backups=$(bk_list "$_ns" "$_base")
        [ -z "$backups" ] && { printf "\n"; print_info "No database backups saved yet."; press_any_key; rm -f "$map_file"; return; }

        # Selection map (Index|Timestamp|Selected), built once and updated in place across redraws.
        if [ ! -f "$map_file" ]; then
            local i=1
            for ts in $backups; do echo "$i|$ts|0" >> "$map_file"; i=$((i+1)); done
        fi

        clear
        print_centered_header "Package Database Cleanup"
        printf " %-3s  %-4s  %-18s  %s\n" "Sel" "Idx" "Date / Time" "Size"
        printf " ────────────────────────────────────────────\n"
        while IFS='|' read -r idx ts sel; do
            local p_date; p_date="$(bk_date "$ts")"
            local s_box="[ ]"; [ "$sel" -eq 1 ] && s_box="[✓]"
            local ts_bytes=0
            [ -f "$_bkd/$_base.$ts" ] && ts_bytes=$(ls -nl "$_bkd/$_base.$ts" | awk '{print $5}')
            local p_size="0B"
            if [ "$ts_bytes" -ge 1048576 ]; then p_size=$(awk "BEGIN {printf \"%.1fM\", $ts_bytes/1048576}")
            elif [ "$ts_bytes" -ge 1024 ]; then p_size=$(awk "BEGIN {printf \"%.1fK\", $ts_bytes/1024}")
            else p_size="${ts_bytes}B"; fi
            printf " %s  %-4s  %-18s  %-6s\n" "$s_box" "$idx." "$p_date" "$p_size"
        done < "$map_file"
        printf " ────────────────────────────────────────────\n"
        printf " [A] All   [N] None   [#] Toggle   [C] Confirm   [0] Cancel\n"
        local bk_count; bk_count=$(wc -l < "$map_file" 2>/dev/null | tr -dc '0-9')
        printf "\n Choose [%s/A/N/C/0]: " "$(picker_range "$bk_count")"
        read -r input
        local cmd; cmd=$(echo "$input" | tr 'A-Z' 'a-z')
        case "$cmd" in
            a) sed -i 's/|0$/|1/' "$map_file" ;;
            n) sed -i 's/|1$/|0/' "$map_file" ;;
            [1-9]*)
                if grep -q "^$cmd|" "$map_file"; then
                    local current_state new_state
                    current_state=$(grep "^$cmd|" "$map_file" | cut -d'|' -f3)
                    new_state=$((1 - current_state))
                    sed -i "s/^\($cmd|[^|]*|\).*/\1$new_state/" "$map_file"
                else
                    print_error "Index $cmd not found"; sleep 1
                fi ;;
            c)
                if ! grep -q "|1$" "$map_file"; then
                    printf "\n"; print_error "No backups selected."; sleep 2; continue
                fi
                printf "\n"
                print_warning "WARNING: You are about to permanently delete selected backups."
                printf "Delete selected backups? [y/N]: "; read -r confirm
                case "$confirm" in
                    y|Y)
                        while IFS='|' read -r idx ts sel; do
                            [ "$sel" -eq 1 ] && bk_delete "$_ns" "$ts"
                        done < "$map_file"
                        printf "\n"
                        print_success "Selected backups purged."
                        press_any_key; rm -f "$map_file"; return ;;
                    *) print_error "Deletion cancelled."; sleep 2; continue ;;
                esac ;;
            0) rm -f "$map_file"; return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

pkg_backup_restore() {
    local _db _ns _base; _db="$(pkg_db_path)"; _ns="$(pkg_db_ns)"; _base="$(basename "$_db")"
    while true; do
        clear
        print_centered_header "Package Database Backups"
        local n; n=$(bk_list "$_ns" "$_base" | grep -c .); case "$n" in ''|*[!0-9]*) n=0 ;; esac
        printf " ${CYAN}STATUS${RESET}\n"
        printf "   %-16s %b%s%b\n" "Database file:" "$GREY" "$_db" "$RESET"
        printf "   %-16s %s\n" "Saved backups:" "$n"
        printf " ────────────────────────────────────────────────\n\n"
        printf "%s%sSave a backup now\n" "$N1" "$NSEP"
        printf "%s%sRestore from a backup\n" "$N2" "$NSEP"
        printf "%s%sDelete a backup\n" "$N3" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "\nChoose [1-3/0]: "
        read -r b
        case "$b" in
            1) printf "\n"
               if [ ! -f "$_db" ]; then print_error "No installed database found at $_db."
               elif bk_save "$_ns" "$(bk_ts)" "$_db"; then print_success "Backup saved."
               else print_error "Could not save a backup."; fi
               press_any_key ;;
            2) pkg_db_restore ;;
            3) pkg_db_delete ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

pkg_repair_measure() {   # measure live -> PR_MGR/PR_NET/PR_BK/PR_DB/PR_CACHE (spinner while probing online)
    PR_MGR=$(pkg_mgr)
    ping -c1 -W3 8.8.8.8 >/dev/null 2>&1 && PR_NET="UP" || PR_NET="DOWN"
    PR_BK=$(bk_list "$(pkg_db_ns)" "$(basename "$(pkg_db_path)")" | grep -c .); case "$PR_BK" in ''|*[!0-9]*) PR_BK=0 ;; esac
    if [ "$PR_MGR" = apk ]; then PR_DB="HEALTHY"; PR_CACHE="HEALTHY"; return 0; fi
    local files broke=0
    if [ "$PR_NET" = "UP" ]; then
        spin_run "Checking package system" pkg_update
        tail -n 80 "$SPIN_LOG" 2>/dev/null | pkg_parse_sig && broke=1
        rm -f "$SPIN_LOG" 2>/dev/null
    fi
    files=$(find /var/opkg-lists /tmp/opkg-lists -type f 2>/dev/null | grep -c .)
    case "$files" in ''|*[!0-9]*) files=0 ;; esac
    if pkg_db_broken; then PR_DB="CORRUPT"; else PR_DB="HEALTHY"; fi
    if [ "$files" -eq 0 ]; then PR_CACHE="EMPTY"
    elif [ "$broke" = "1" ] && [ "$PR_DB" = "HEALTHY" ]; then PR_CACHE="CORRUPT"
    else PR_CACHE="HEALTHY"; fi
}

# Shared installed-database repair escalation - the ONE place the repair tiers + their messages live, so
# "Repair now" and "Repair the installed database" behave and read identically. Tiers, stopping at the
# first that makes opkg parse clean: (1) safe end-of-file repair (append the missing EOF newline);
# (2) rebuild from on-disk per-package metadata (keeps the real installed set - high fidelity, runs
# automatically); (3) as a LAST RESORT before re-flash, restore the factory database from read-only /rom
# (lossy - opkg forgets post-factory package records; files stay - so this one is confirmed). No pre-repair
# copy is kept (see pkg_db_repair). Prints its own success/failure + guidance; the caller already confirmed
# the safe repair. Returns 0 iff opkg parses clean afterwards.
_pkg_db_repair_flow() {
    local _db _ns _base; _db="$(pkg_db_path)"; _ns="$(pkg_db_ns)"; _base="$(basename "$_db")"

    # Tier 1: safe end-of-file repair.
    spin_run "Repairing the installed database" pkg_db_repair
    spin_run "Verifying the package index" pkg_update
    if ! tail -n 80 "$SPIN_LOG" 2>/dev/null | pkg_parse_sig; then
        rm -f "$SPIN_LOG" 2>/dev/null; print_success "Installed database repaired."; return 0
    fi
    rm -f "$SPIN_LOG" 2>/dev/null

    # Tier 2: rebuild from the on-disk per-package metadata (opkg only). High fidelity - it keeps the
    # ACTUAL installed set (only the user/auto + hold flags are lost, which is safe), so it runs as part
    # of the repair the user already confirmed rather than behind its own prompt.
    if [ "$(pkg_mgr)" = opkg ] && ls "$(pkg_db_info_dir)"/*.control >/dev/null 2>&1; then
        printf "\n"
        print_info "Rebuilding the database from installed-package metadata (this keeps your installed packages)."
        spin_run "Rebuilding the installed database" pkg_db_reconstruct
        spin_run "Verifying the package index" pkg_update
        if ! tail -n 80 "$SPIN_LOG" 2>/dev/null | pkg_parse_sig; then
            rm -f "$SPIN_LOG" 2>/dev/null
            print_success "Installed database rebuilt from package metadata - opkg is working again."
            return 0
        fi
        rm -f "$SPIN_LOG" 2>/dev/null
    fi

    # Tier 3: factory database from /rom (opkg only, lossy) - the last resort before re-flash.
    if [ "$(pkg_mgr)" = opkg ] && [ -f "$(pkg_db_rom)" ]; then
        printf "\n"
        print_warning "Neither repair could fix it. As a last resort, the FACTORY package database can be"
        printf "   restored from read-only firmware. This gets opkg working again, but resets its record of\n"
        printf "   installed packages to the factory set - anything you added stays on disk, but opkg no longer\n"
        printf "   tracks it (reinstall to re-register). Your data, settings and configs are untouched.\n\n"
        printf "Restore the factory package database now? [y/N]: "; local _r; read -r _r; printf "\n"
        case "$_r" in
            y|Y) cp "$(pkg_db_rom)" "$_db" 2>/dev/null
                 spin_run "Verifying the package index" pkg_update
                 if ! tail -n 80 "$SPIN_LOG" 2>/dev/null | pkg_parse_sig; then
                     rm -f "$SPIN_LOG" 2>/dev/null
                     print_success "Factory package database restored - opkg is working again."
                     print_info "Packages you had installed remain on disk; reinstall any you want opkg to track again."
                     return 0
                 fi
                 rm -f "$SPIN_LOG" 2>/dev/null ;;
            *) : ;;
        esac
    fi

    # Exhausted - honest, consistent guidance (offer a restore only if the user actually has backups).
    print_error "The database could not be repaired automatically."
    if [ "$(bk_list "$_ns" "$_base" | grep -c .)" -gt 0 ]; then
        print_info "Restore an earlier backup (from before the corruption) via 'Backup & Restore', or re-flash the firmware."
    else
        print_info "No earlier package-database backup exists to restore - re-flash the firmware to recover."
    fi
    return 1
}

# apk installed-database repair (the apk analog of _pkg_db_repair_flow, kept separate because apk's world
# differs: apk-tools is tolerant of a partly-corrupt DB - `apk info` stays exit-0 - so there is no clean
# "still broken" signal to gate on, and apk keeps NO per-package metadata to reconstruct from. So: run
# apk's own `apk fix`, then OFFER the factory /rom copy as a lossy last resort (the user judges whether
# the DB is still misbehaving). Shared by "Repair now" and "Repair the installed database".
_pkg_db_repair_apk() {
    spin_run "Repairing the package database (apk fix)" apk fix
    rm -f "$SPIN_LOG" 2>/dev/null
    print_success "Ran apk fix."
    [ -f "$(pkg_db_rom)" ] || return 0
    printf "\n"
    print_info "If the package database is still misbehaving, the factory copy can be restored from"
    printf "   read-only firmware - lossy: apk forgets post-factory package records, but the files stay.\n\n"
    printf "Restore the factory package database from /rom now? [y/N]: "; local _r; read -r _r; printf "\n"
    case "$_r" in
        y|Y) cp "$(pkg_db_rom)" "$(pkg_db_path)" 2>/dev/null
             spin_run "Refreshing the package index" pkg_update
             rm -f "$SPIN_LOG" 2>/dev/null
             print_success "Factory package database restored."
             print_info "Packages you had installed remain on disk; reinstall any you want apk to track again." ;;
        *) print_info "Left as-is (apk fix applied)." ;;
    esac
}

pkg_repair_now() {
    printf "\n"
    if [ "$PR_DB" != "CORRUPT" ] && [ "$PR_CACHE" != "CORRUPT" ] && [ "$PR_CACHE" != "EMPTY" ]; then
        print_success "The package system looks healthy - nothing to repair."
        press_any_key; return
    fi
    spin_run "Rebuilding the package index cache" pkg_cache_rebuild
    if ! tail -n 80 "$SPIN_LOG" 2>/dev/null | pkg_parse_sig; then
        rm -f "$SPIN_LOG" 2>/dev/null
        print_success "Package index cache rebuilt - the package system now parses cleanly."
        press_any_key; return
    fi
    rm -f "$SPIN_LOG" 2>/dev/null
    if [ "$(pkg_mgr)" = apk ]; then
        _pkg_db_repair_apk
        press_any_key; return
    fi
    printf "\n"
    print_warning "The cache was rebuilt but the installed database still can't be parsed."
    printf "   A safe end-of-file repair is tried first, before anything drastic.\n\n"
    printf "Repair the installed database now? [y/N]: "; read -r yn; printf "\n"
    case "$yn" in
        y|Y) _pkg_db_repair_flow ;;
        *) print_info "Database left unchanged." ;;
    esac
    press_any_key
}

pkg_cache_rebuild_action() {
    printf "\n"
    spin_run "Rebuilding the package index cache" pkg_cache_rebuild
    if tail -n 80 "$SPIN_LOG" 2>/dev/null | pkg_parse_sig; then
        print_warning "The index was refreshed but opkg still reports parse errors - the installed database may be corrupted (try 'Repair the installed database')."
    else
        print_success "Package index cache rebuilt."
    fi
    rm -f "$SPIN_LOG" 2>/dev/null
    press_any_key
}

pkg_db_repair_action() {
    printf "\n"
    if [ "$(pkg_mgr)" = apk ]; then
        _pkg_db_repair_apk
        press_any_key; return
    fi
    local _db; _db="$(pkg_db_path)"
    if [ ! -f "$_db" ]; then print_error "No installed database found at $_db."; press_any_key; return; fi
    print_warning "This repairs the installed package database ($_db)."
    printf "   A safe end-of-file repair is tried first, before anything drastic.\n\n"
    printf "Repair the installed database now? [y/N]: "; read -r yn; printf "\n"
    case "$yn" in
        y|Y) _pkg_db_repair_flow ;;
        *) print_info "Database left unchanged." ;;
    esac
    press_any_key
}

show_pkg_repair_help() {
    show_paged "Package System Repair - Help" << 'HELPEOF'
Package System Repair - Quick Help

What it does
────────────
Detects and fixes the two ways OpenWrt's package system gets corrupted. Both
show up as "parse_from_stream_nomalloc: Missing new line character at end of
file" and make installs and removals fail (or silently do nothing).

What can go wrong
─────────────────
  • Index cache - the downloaded feed lists under /var/opkg-lists. Fully
    re-fetchable, so rebuilding it is safe and loses nothing.
  • Installed database - /usr/lib/opkg/status, the record of what is installed.
    Repaired in place and NEVER deleted; a backup is saved first.

The status block
────────────────
Installed database and Index cache read HEALTHY, CORRUPT or EMPTY. When online,
the check runs a real package-index refresh so the reading is measured, not
guessed; offline it falls back to a structural check of the database.

Actions
───────
  • Repair now - rebuilds the cache first (non-destructive); if the database is
    still unparseable it asks before repairing it (backup first).
  • Rebuild the package index cache - forces a fresh download of the feed lists.
  • Repair the installed database - backs up, then applies a safe end-of-file
    repair. Deeper damage is left for a backup restore rather than risking the
    file.
  • Backup & Restore - save, restore or delete timestamped copies of the
    installed database, kept under /etc/glinet_utils/backups.

Note: apk-based firmware keeps its own database; there the repair uses apk's own
update and fix.
HELPEOF
}

repair_package_system() {
    clear; print_centered_header "Package System Repair"; pkg_repair_measure
    while true; do
        clear
        print_centered_header "Package System Repair"
        printf " ${CYAN}STATUS${RESET}\n"
        printf "   %-20s %s\n" "Package manager:" "$(printf '%s' "$PR_MGR" | tr 'a-z' 'A-Z')"
        local dbc cac netc
        case "$PR_DB" in HEALTHY) dbc="$GREEN";; CORRUPT) dbc="$RED";; *) dbc="$YELLOW";; esac
        case "$PR_CACHE" in HEALTHY) cac="$GREEN";; CORRUPT) cac="$RED";; *) cac="$YELLOW";; esac
        [ "$PR_NET" = "UP" ] && netc="$GREEN" || netc="$RED"
        printf "   %-20s %b%s%b\n" "Installed database:" "$dbc" "$PR_DB" "$RESET"
        printf "   %-20s %b%s%b\n" "Index cache:" "$cac" "$PR_CACHE" "$RESET"
        printf "   %-20s %b%s%b\n" "Internet:" "$netc" "$PR_NET" "$RESET"
        if [ "${PR_BK:-0}" -gt 0 ]; then
            printf "   %-20s %b%s AVAILABLE%b\n" "Database backups:" "$GREEN" "$PR_BK" "$RESET"
        else
            printf "   %-20s %b%s%b\n" "Database backups:" "$YELLOW" "NONE" "$RESET"
        fi
        printf " ────────────────────────────────────────────────\n\n"
        printf "%s%sRepair now (auto-detect and fix)\n" "$N1" "$NSEP"
        printf "%s%sRebuild the package index cache\n" "$N2" "$NSEP"
        printf "%s%sRepair the installed database\n" "$N3" "$NSEP"
        printf "%s%sBackup & Restore the database\n" "$N4" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-4/0/?]: "
        read -r opt
        case "$opt" in
            1) pkg_repair_now ;;
            2) pkg_cache_rebuild_action ;;
            3) pkg_db_repair_action ;;
            4) pkg_backup_restore ;;
            \?|h|H|❓) show_pkg_repair_help; continue ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1; continue ;;
        esac
        clear; print_centered_header "Package System Repair"; pkg_repair_measure
    done
}

system_tweaks() {
    while true; do
        clear
        print_centered_header "System Tweaks"
        printf "%s%sDevice Fan Settings\n" "$N1" "$NSEP"
        printf "%s%sManage Zram Swap\n" "$N2" "$NSEP"
        printf "%s%sWeb-UI Terminal Interface\n" "$N3" "$NSEP"
        printf "%s%sPackage and Persistence Manager\n" "$N4" "$NSEP"
        printf "%s%sPackage System Repair\n" "$N5" "$NSEP"
        printf "%s%sToolkit Management\n" "$N6" "$NSEP"
        printf "%s%sMain menu\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-6/0/?]: "
        read -r st_choice
        printf "\n"
        case $st_choice in
            1) manage_fan_settings ;;
            2) manage_zram ;;
            3) manage_web_terminal ;;
            4) manage_packages ;;
            5) repair_package_system ;;
            6) manage_toolkit ;;
            \?|h|H|❓) show_system_tweaks_help ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# System Benchmarks
# -----------------------------

show_benchmarks_help() {
    show_paged "System Benchmarks - Help" << 'HELPEOF'
System Benchmarks – Quick Help

Overview
────────
This menu provides a suite of tools to validate hardware performance, thermal 
stability, and network throughput. These tests help identify if your router 
is throttling due to heat or if your storage/RAM is underperforming.

Benchmark Categories:
─────────────────────
• CPU & Thermal: Options 1 and 2 test the processor. The Stress Test pushes
  all cores/threads to 100% to test heat soak, while the VPN & Crypto Benchmark ranks
  this device against saved routers for WireGuard, OpenVPN and RSA throughput.
• Storage & Memory: Options 3 and 4 measure I/O speeds. Use these to test 
  the performance of the internal NAND vs. attached USB 3.0 drives or to 
  check if RAM bandwidth is saturated.
• Connectivity: Options 5 and 6 measure latency and external WAN speeds. 
  Essential for troubleshooting "slow internet" vs. "slow DNS." Option 6 (Ookla)
  runs on every router - on MIPS, where Ookla ships no binary, it uses speedtest-go
  against the same speedtest.net servers.
• Local Servers: Options 7, 8, and 9 turn the router into a speedtest target. 
  These are used to test Wi-Fi/LAN limits without ISP interference.

Technical Details:
──────────────────
• Stress Testing: The script uses 'stress' primarily. If it is missing, it falls
  back to 'stress-ng' ONLY on kernel 6.6+; on older kernels stress-ng is withheld
  because a memory-pressure kernel bug can hard-crash the router there.
• Baselines: The VPN & Crypto Benchmark is a leaderboard - its "vs yours"
  column compares saved devices to the one you are on. Disk and Memory tests
  use a fixed Beryl 7 (0.0%) reference point.
• Timing: Disk and Memory tests use /proc/uptime millisecond offsets for 
  precise Speed (MB/s) calculations rather than relying on 'dd' output.

Note on Local Servers:
──────────────────────
iPerf3 is the industry standard for CLI testing. LibreSpeed and OpenSpeedTest 
provide a browser-based UI for testing from phones and tablets without apps.
HELPEOF
}

show_librespeed_help() {
    show_paged "LibreSpeed Speed Test - Help" << 'HELPEOF'
LibreSpeed Speed Test Server – Quick Help

What is LibreSpeed?
───────────────────
LibreSpeed is a lightweight, open-source speed test server written in Go. Unlike 
traditional speed tests that rely on external servers, this runs locally on your 
router. This allows you to test the actual throughput of your LAN and Wi-Fi 
without being limited by your ISP's internet speed.

Main features on GL.iNet routers:
• Zero Dependencies: Standalone Go binary; does not require Nginx or PHP.
• Lightweight: Extremely low CPU and RAM footprint, ideal for travel routers.
• Privacy Focused: No telemetry, no ads, and no data collection.
• Local Benchmarking: Perfect for testing Wi-Fi 6/7 performance and signal dead zones.

LibreSpeed vs. OpenSpeedTest:
─────────────────────────────
• LibreSpeed: Best for background monitoring and 1Gbps wireless audits. 
  It is much lighter on system resources (RAM/CPU).
• OpenSpeedTest: Better for high-stress 2.5G/10G throughput testing on 
  powerful hardware (like the Flint 2/3) due to its multi-threaded nature.
• Better Together: Both can run simultaneously on different ports (e.g., 8989 
  and 8888) to allow A/B testing of your wireless environment.

When should you use it?
Yes → To find Wi-Fi dead zones or verify the max speed of your local network.
Yes → To check if your VPN or SQM settings are bottlenecking your local speeds.
No  → If you only care about your ISP's "Internet" speed (use Ookla for that).

Important notes:
• Listen Port: Defaults to :8989. Access via http://<router-ip>:8989
• Persistence: Enabling persistence ensures the binary and settings survive 
  firmware updates, preventing manual re-installation.
• Procd Jail: Runs in a secure sandbox for improved router security.
HELPEOF
}

manage_librespeed() {
    while true; do
        clear
        print_centered_header "LibreSpeed Speed Test Management"
        
        LAN_IP=$(get_lan_ip)
        LISTEN_PORT=":8989"
        UP_CONF="/etc/sysupgrade.conf"
        
        # Determine installation status once for the whole loop
		hash -r 
        if command -v librespeed-go >/dev/null 2>&1; then
            IS_INSTALLED=1
        else
            IS_INSTALLED=0
        fi

        printf " %b\n" "${CYAN}STATUS${RESET}"
        if [ "$IS_INSTALLED" -eq 1 ]; then
            if [ "$(uci -q get librespeed-go.config.enabled)" = "1" ]; then
                printf "   Service: %bENABLED%b\n" "${GREEN}" "${RESET}"
                if netstat -ltn 2>/dev/null | grep -q "${LISTEN_PORT#:}"; then
                    printf "   Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                    printf "   URL: %bhttp://$LAN_IP${LISTEN_PORT}%b\n" "${CYAN}" "${RESET}"
                else
                    printf "   Status: %bSTARTING/ERROR%b\n" "${YELLOW}" "${RESET}"
                fi
            else
                printf "   Service: %bDISABLED%b\n" "${YELLOW}" "${RESET}"
            fi
            
            # Check Persistence Status
            persist_ok="1"
            for entry in "/usr/bin/librespeed-go" "/etc/init.d/librespeed-go" "/etc/config/librespeed-go"; do
                if ! grep -qFx "$entry" "$UP_CONF" 2>/dev/null; then
                    persist_ok="0"
                    break
                fi
            done
            
            if [ "$persist_ok" -eq "1" ]; then
                printf "   Persistence: %bENABLED%b\n" "${GREEN}" "${RESET}"
            else
                printf "   Persistence: %bDISABLED%b\n" "${RED}" "${RESET}"
            fi
        else
            printf "   Service: %bNOT INSTALLED%b\n" "${RED}" "${RESET}"
        fi
        
        local ls_persist_label="Enable Persistence"
        [ "$IS_INSTALLED" -eq 1 ] && [ "$persist_ok" -eq 1 ] && ls_persist_label="Disable Persistence"
        printf "\n%s%sInstall and Enable\n" "$N1" "$NSEP"
        printf "%s%sDisable Service\n" "$N2" "$NSEP"
        printf "%s%s%s\n" "$N3" "$NSEP" "$ls_persist_label"
        printf "%s%sUninstall Package\n" "$N4" "$NSEP"
        printf "%s%sBack\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-4/0/?]: "
        read -r ls_choice
        printf "\n"
        
        case $ls_choice in
            1)
                if [ "$IS_INSTALLED" -eq 0 ]; then
                    install_package librespeed-go "LibreSpeed" || { press_any_key; continue; }
                    grep -q "librespeed" /etc/passwd || echo "librespeed:x:500:500:librespeed:/var/run/librespeed-go:/bin/false" >> /etc/passwd
                    IS_INSTALLED=1
                fi

                if [ ! -f "/etc/config/librespeed-go" ]; then
                    touch /etc/config/librespeed-go
                fi
                
                if ! uci -q get librespeed-go.config >/dev/null; then
                    uci set librespeed-go.config=librespeed-go
                fi

                uci set librespeed-go.config.listen_addr="$LISTEN_PORT"
                uci set librespeed-go.config.enabled='1'
                uci commit librespeed-go
                
                /etc/init.d/librespeed-go restart >/dev/null 2>&1
                print_success "LibreSpeed enabled at http://$LAN_IP${LISTEN_PORT}"
                press_any_key
                ;;
            2)
                if [ "$IS_INSTALLED" -eq 1 ]; then
                    uci set librespeed-go.config.enabled='0'
                    uci commit librespeed-go
                    /etc/init.d/librespeed-go stop >/dev/null 2>&1
                    print_success "LibreSpeed disabled"
                else
                    print_error "Nothing to disable: LibreSpeed is not installed."
                fi
                press_any_key
                ;;
            3)
                if [ "$IS_INSTALLED" -eq 1 ]; then
                    if [ "$persist_ok" -eq "0" ]; then
                        for entry in "/usr/bin/librespeed-go" "/etc/init.d/librespeed-go" "/etc/config/librespeed-go"; do
                            grep -qFx "$entry" "$UP_CONF" || echo "$entry" >> "$UP_CONF"
                        done
                        print_success "Persistence enabled in $UP_CONF"
                    else
                        sed -i "\|/usr/bin/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/init.d/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/config/librespeed-go|d" "$UP_CONF"
                        print_success "Persistence disabled"
                    fi
                else
                    print_error "Nothing to persist: LibreSpeed is not installed."
                fi
                press_any_key
                ;;
            4)
                if [ "$IS_INSTALLED" -eq 1 ]; then
                    printf "Remove LibreSpeed package? [y/N]: "; read -r confirm
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        /etc/init.d/librespeed-go stop >/dev/null 2>&1
                        pkg_remove librespeed-go >/dev/null 2>&1
                        # Always clean up persistence entries on uninstall
                        sed -i "\|/usr/bin/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/init.d/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/config/librespeed-go|d" "$UP_CONF"
                        print_success "LibreSpeed removed"
                    fi
                else
                    print_error "Nothing to remove: LibreSpeed is not installed."
                fi
                press_any_key
                ;;
            0) return ;;
            \?|h|H|❓) show_librespeed_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

install_ookla_speedtest() {
    if ! command -v speedtest >/dev/null 2>&1 || ! speedtest --version 2>&1 | grep -qi "ookla"; then
        arch=$(uname -m)
        case "$arch" in
            aarch64) suffix="aarch64" ;;
            armv7*)  suffix="armhf"   ;;
            armv8*)  suffix="aarch64" ;;
            x86_64)  suffix="x86_64"  ;;
            mips*)
                # Reached only from the package-install flow now - the Ookla Internet
                # Speedtest menu routes MIPS to speedtest-go (see install_speedtest_go).
                # Ookla publishes no MIPS binary, and it couldn't be persisted to the
                # tiny flash here anyway, so explain that and point at the path that works.
                print_error "Ookla Speedtest can't be installed as a package here."
                print_info "Ookla ships no MIPS build ($arch), so there's no binary to"
                print_info "persist to this router's flash."
                printf "\n"
                print_info "System Benchmarks -> \"Ookla Internet Speedtest\" still runs it on"
                print_info "MIPS: the same speedtest.net test, via speedtest-go, on demand."
                press_any_key
                return 1
                ;;
            *) print_error "Unsupported Arch: $arch"; press_any_key; return 1 ;;
        esac

        _ookla_fetch() {
            local ver url
            ver=$(wget -qO- https://www.speedtest.net/apps/cli | grep -oE "ookla-speedtest-[0-9.]+-linux-$suffix.tgz" | head -n1)
            [ -z "$ver" ] && ver="ookla-speedtest-1.2.0-linux-$suffix.tgz"
            url="https://install.speedtest.net/app/cli/$ver"
            wget -qO- "$url" | tar xz -C /usr/bin speedtest
            chmod +x /usr/bin/speedtest
        }

        spin_run "Installing Ookla Speedtest" _ookla_fetch
        rm -f "$SPIN_LOG" 2>/dev/null

        if command -v speedtest >/dev/null 2>&1; then
            print_success "Installed: $(speedtest --version | head -n1)"
        else
            print_error "Failed to install Ookla Speedtest."
            check_connectivity
            press_any_key
            return 1
        fi
    fi
}

STGO_BIN="/tmp/speedtest-go"

# speedtest-go is a maintained, statically-linked Go client that measures against the same
# speedtest.net servers as Ookla but - unlike Ookla - ships MIPS builds. We use it on MIPS
# routers, where the official Ookla binary doesn't exist. By default it fetches to /tmp (the
# binary is ~8.4 MB and MIPS boards have little flash, so a per-session re-fetch keeps the
# overlay free). But it can also be installed persistently to /usr/bin via the Package
# Manager - the Size column + storage line let the user judge the flash cost first - and a
# persistent copy is always preferred here (survives reboots, no re-download). Sets STGO_BIN
# to whichever copy it ended up with.
install_speedtest_go() {   # [target_dir]  default /tmp (scratch); pass /usr/bin to persist
    local _dir="${1:-/tmp}"
    # A persistent /usr/bin copy always wins - survives reboots, no re-download.
    if [ -x /usr/bin/speedtest-go ] && /usr/bin/speedtest-go --version >/dev/null 2>&1; then
        STGO_BIN=/usr/bin/speedtest-go
        [ "$_dir" = /usr/bin ] && print_success "speedtest-go already installed."
        return 0
    fi
    STGO_BIN="$_dir/speedtest-go"
    # Cached and runnable at the target? (--version also proves the download matched this CPU.)
    if [ -x "$STGO_BIN" ] && "$STGO_BIN" --version >/dev/null 2>&1; then
        return 0
    fi
    # GL's MIPS routers are all little-endian; take 32- vs 64-bit from uname (busybox od
    # can't reliably read the ELF header). softfloat runs with or without an FPU, and a
    # wrong guess just fails the --version check below and soft-fails cleanly.
    case "$(uname -m)" in
        mips64*) _stgo_arch="mips64le" ;;
        *)       _stgo_arch="mipsle"   ;;
    esac
    _stgo_asset="Linux_${_stgo_arch}_softfloat.tar.gz"

    _stgo_fetch() {
        local url
        url=$(wget -qO- "https://api.github.com/repos/showwin/speedtest-go/releases/latest" 2>/dev/null \
                | grep -oE "https://[^\"]*speedtest-go_[0-9.]+_${_stgo_asset}" | head -n1)
        [ -z "$url" ] && url="https://github.com/showwin/speedtest-go/releases/download/v1.7.11/speedtest-go_1.7.11_${_stgo_asset}"
        wget -qO- "$url" | tar xz -C "$_dir" speedtest-go
        chmod +x "$STGO_BIN"
    }

    spin_run "Fetching speedtest-go (Ookla ships no MIPS build)" _stgo_fetch
    rm -f "$SPIN_LOG" 2>/dev/null

    if [ -x "$STGO_BIN" ] && "$STGO_BIN" --version >/dev/null 2>&1; then
        print_success "Ready: $("$STGO_BIN" --version 2>&1 | head -n1)"
    else
        print_error "Couldn't fetch speedtest-go."
        check_connectivity
        press_any_key
        return 1
    fi
}

# --- VPN & Crypto Benchmark helpers ---
# Throughput data is OpenSSL's "1000s of bytes per second" (KB/s); rsa in ops/s.

# Measure one EVP cipher at one block size into BENCH_RESULT (numeric, no
# trailing 'k'). Sets a global rather than echoing because spin_run animates on
# stdout - capturing it in $(...) would swallow the spinner. Name/case-agnostic
# so it works across OpenSSL 1.1.x and 3.x; empty on failure -> caller uses 0.
bench_measure() {   # cipher size -> BENCH_RESULT
    spin_run "Measuring $1 @ ${2}B" openssl speed -evp "$1" -bytes "$2"
    BENCH_RESULT=$(awk '/[0-9]k$/{v=$NF} END{sub(/k$/,"",v); print v}' "$SPIN_LOG")
}

# Render one cipher leaderboard table: rows sorted by throughput (1420 B)
# descending, this device highlighted. Args: title small_col tput_col ceil_col
# datafile my_id. Columns in datafile are 1=id 2=label 3=cpu 4..9=cipher sizes.
bench_render_cipher() {
    local title="$1" sc="$2" tc="$3" cc="$4" df="$5" id="$6" base
    base=$(awk -F'|' -v id="$id" -v c="$tc" '$1==id{print $c; exit}' "$df")
    printf '\n %b%s%b\n' "$CYAN" "$title" "$RESET"
    printf '  %-10s %-7s %-10s  %-10s  %-10s %-8s  %-10s\n' "Device" "CPU" "64 B" "1420 B" "vs yours" "" "16 K"
    printf ' %s\n' "───────────────────────────────────────────────────────────────────────────"
    awk -F'|' -v c="$tc" '{print $c"\t"$0}' "$df" | sort -rn | cut -f2- | awk -F'|' \
        -v id="$id" -v sc="$sc" -v tc="$tc" -v cc="$cc" -v base="$base" \
        -v cur="${BOLD}${GREEN}" -v res="$RESET" '
        function unit(k,  v,u){ v=k*8; u="Kb/s"; if(v>=10000){v/=1000;u="Mb/s"} if(v>=10000){v/=1000;u="Gb/s"}
            if(v>=1000)return sprintf("%.0f %s",v,u); if(v>=100)return sprintf("%.1f %s",v,u);
            if(v>=10)return sprintf("%.2f %s",v,u); return sprintf("%.3f %s",v,u) }
        function bar(v,mx,  n,i,s){ if(mx<=0)return "          "; n=int(v/mx*10+0.5); if(n>10)n=10; if(n<0)n=0;
            s=""; for(i=0;i<n;i++)s=s"█"; for(i=n;i<10;i++)s=s"░"; return s }
        NR==1{mx=$tc}
        { if($1==id)d="  ---   "; else if(base>0)d=sprintf("%+6.1f%%",($tc-base)/base*100); else d="";
          mark=($1==id)?"> ":"  ";
          line=sprintf("%s%-10.10s %-7.7s %-10s  %-10s  %-10s %-8s  %-10s",mark,$2,$3,unit($sc),unit($tc),bar($tc,mx),d,unit($cc));
          if($1==id)printf "%s%s%s\n",cur,line,res; else print line }'
}

# Render the RSA connection-setup table (sorted by sign/s). Args: datafile my_id.
bench_render_rsa() {
    local df="$1" id="$2" base
    base=$(awk -F'|' -v id="$id" '$1==id{print $10; exit}' "$df")
    printf '\n %b%s%b\n' "$CYAN" "Connection setup · RSA-2048" "$RESET"
    printf '  %-10s %-7s %-10s  %-10s %-8s  %-10s\n' "Device" "CPU" "sign/s" "vs yours" "" "verify/s"
    printf ' %s\n' "───────────────────────────────────────────────────────────────"
    awk -F'|' '{print $10"\t"$0}' "$df" | sort -rn | cut -f2- | awk -F'|' -v id="$id" -v base="$base" \
        -v cur="${BOLD}${GREEN}" -v res="$RESET" '
        function bar(v,mx,  n,i,s){ if(mx<=0)return "          "; n=int(v/mx*10+0.5); if(n>10)n=10; if(n<0)n=0;
            s=""; for(i=0;i<n;i++)s=s"█"; for(i=n;i<10;i++)s=s"░"; return s }
        NR==1{mx=$10}
        { if($1==id)d="  ---   "; else if(base>0)d=sprintf("%+6.1f%%",($10-base)/base*100); else d="";
          mark=($1==id)?"> ":"  ";
          line=sprintf("%s%-10.10s %-7.7s %-10.1f  %-10s %-8s  %-10.1f",mark,$2,$3,$10,bar($10,mx),d,$11);
          if($1==id)printf "%s%s%s\n",cur,line,res; else print line }'
}

# Render the Disk I/O leaderboard, sorted by Write (the cross-device-reliable
# metric - Read may reflect a storage controller's own cache, see caller's
# footnote). Args: datafile my_id. Columns: 1=id 2=label 3=cpu 4=write 5=read.
bench_render_disk() {
    local df="$1" id="$2" base
    base=$(awk -F'|' -v id="$id" '$1==id{print $4; exit}' "$df")
    printf '\n %b%s%b\n' "$CYAN" "Disk I/O (Sequential)" "$RESET"
    printf '  %-10s %-7s %-10s  %-10s  %-10s %-8s\n' "Device" "CPU" "Write" "Read" "vs yours" ""
    printf ' %s\n' "───────────────────────────────────────────────────────────────"
    awk -F'|' '{print $4"\t"$0}' "$df" | sort -rn | cut -f2- | awk -F'|' \
        -v id="$id" -v base="$base" -v cur="${BOLD}${GREEN}" -v res="$RESET" '
        function unit(v,  u){ u="MB/s"; if(v>=10000){v/=1000;u="GB/s"}
            if(v>=1000)return sprintf("%.0f %s",v,u); if(v>=100)return sprintf("%.1f %s",v,u);
            if(v>=10)return sprintf("%.2f %s",v,u); return sprintf("%.3f %s",v,u) }
        function bar(v,mx,  n,i,s){ if(mx<=0)return "          "; n=int(v/mx*10+0.5); if(n>10)n=10; if(n<0)n=0;
            s=""; for(i=0;i<n;i++)s=s"█"; for(i=n;i<10;i++)s=s"░"; return s }
        NR==1{mx=$4}
        { if($1==id)d="  ---   "; else if(base>0)d=sprintf("%+6.1f%%",($4-base)/base*100); else d="";
          mark=($1==id)?"> ":"  ";
          line=sprintf("%s%-10.10s %-7.7s %-10s  %-10s  %-10s %-8s",mark,$2,$3,unit($4),unit($5),bar($4,mx),d);
          if($1==id)printf "%s%s%s\n",cur,line,res; else print line }'
}

# Render the Memory I/O leaderboard (single Read/Write throughput metric).
# Args: datafile my_id. Columns: 1=id 2=label 3=cpu 4=mem_mbs.
bench_render_mem() {
    local df="$1" id="$2" base
    base=$(awk -F'|' -v id="$id" '$1==id{print $4; exit}' "$df")
    printf '\n %b%s%b\n' "$CYAN" "Memory I/O (Read/Write)" "$RESET"
    printf '  %-10s %-7s %-10s  %-10s %-8s\n' "Device" "CPU" "Speed" "vs yours" ""
    printf ' %s\n' "───────────────────────────────────────────────────"
    awk -F'|' '{print $4"\t"$0}' "$df" | sort -rn | cut -f2- | awk -F'|' \
        -v id="$id" -v base="$base" -v cur="${BOLD}${GREEN}" -v res="$RESET" '
        function unit(v,  u){ u="MB/s"; if(v>=10000){v/=1000;u="GB/s"}
            if(v>=1000)return sprintf("%.0f %s",v,u); if(v>=100)return sprintf("%.1f %s",v,u);
            if(v>=10)return sprintf("%.2f %s",v,u); return sprintf("%.3f %s",v,u) }
        function bar(v,mx,  n,i,s){ if(mx<=0)return "          "; n=int(v/mx*10+0.5); if(n>10)n=10; if(n<0)n=0;
            s=""; for(i=0;i<n;i++)s=s"█"; for(i=n;i<10;i++)s=s"░"; return s }
        NR==1{mx=$4}
        { if($1==id)d="  ---   "; else if(base>0)d=sprintf("%+6.1f%%",($4-base)/base*100); else d="";
          mark=($1==id)?"> ":"  ";
          line=sprintf("%s%-10.10s %-7.7s %-10s  %-10s %-8s",mark,$2,$3,unit($4),bar($4,mx),d);
          if($1==id)printf "%s%s%s\n",cur,line,res; else print line }'
}

benchmark_system() {
    while true; do
        clear
        print_centered_header "System Benchmarks"
        printf "%s%sCPU Thermal Stress Test\n" "$N1" "$NSEP"
        printf "%s%sVPN & Crypto Benchmark\n" "$N2" "$NSEP"
        printf "%s%sDisk I/O Benchmark\n" "$N3" "$NSEP"
        printf "%s%sMemory I/O Benchmark\n" "$N4" "$NSEP"
        printf "%s%sDNS Latency Benchmark\n" "$N5" "$NSEP"
        printf "%s%sOokla Internet Speedtest\n" "$N6" "$NSEP"
        printf "%s%sLibreSpeed Speed Test Server\n" "$N7" "$NSEP"
        printf "%s%siPerf3 Network Speed Test Server\n" "$N8" "$NSEP"
        printf "%s%sOpenSpeedTest Server\n" "$N9" "$NSEP"
        printf "%s%sMain menu\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-9/0/?]: "
        read -r bench_choice
        printf "\n"
        
        case $bench_choice in
            1)
                clear
                print_centered_header "CPU Thermal Stress Test"
                
                if ! command -v stress >/dev/null 2>&1; then
                    install_package stress
                    if ! command -v stress >/dev/null 2>&1; then
                        # stress-ng can hard-crash routers on kernels < 6.6 - never fall back to it there.
                        if _stressng_unsafe; then
                            print_error "Could not install 'stress', and 'stress-ng' can crash this router's kernel (a pre-6.6 kernel bug), so it isn't used here."
                            press_any_key
                            continue
                        fi
                        install_package stress-ng
                        if ! command -v stress-ng >/dev/null 2>&1; then
                            print_error "Could not install a CPU stress tool."
                            press_any_key
                            continue
                        else
                            ln -s "$(which stress-ng)" /usr/bin/stress
                        fi
                    fi
                fi

                get_temp() {
                    local raw_temp
                    raw_temp=$(get_cpu_temp)
                    if [ "$raw_temp" != "unknown" ]; then
                        local celsius=$(awk "BEGIN {printf \"%.2f\", $raw_temp}")
                        local fahrenheit=$(awk "BEGIN {printf \"%.2f\", ($raw_temp * 1.8) + 32}")
                        printf "%s°C (%s°F)" "$celsius" "$fahrenheit"
                    else
                        printf "N/A"
                    fi
                }
                
                # stress loads every logical CPU; the label names cores vs threads so a
                # multithreaded chip (MT7621: 2 cores / 4 threads) reads honestly.
                _cc=$(cpu_counts); cpu_logical=${_cc% *}; cpu_phys=${_cc#* }
                [ "$cpu_phys" -eq 1 ] && _cw=core || _cw=cores
                if [ "$cpu_phys" -lt "$cpu_logical" ]; then
                    stress_what="$cpu_logical threads ($cpu_phys $_cw)"
                else
                    [ "$cpu_logical" -eq 1 ] && _cw=core || _cw=cores
                    stress_what="$cpu_logical $_cw"
                fi
                
                printf "\nHow many seconds to run stress test? [default: 60]: "
                read -r duration
                [ -z "$duration" ] && duration=60
                
                case "$duration" in
                    ''|*[!0-9]*) duration=60 ;;
                esac

                raw_start=$(get_cpu_temp)
                start_temp_str=$(get_temp)
                start_fan_str=$(get_fan_speed)
                
                printf "\n"
                countdown_run "Stress testing $stress_what" "$duration" stress --cpu "$cpu_logical" --timeout "${duration}s"

                raw_end=$(get_cpu_temp)
                end_temp_str=$(get_temp)
                end_fan_str=$(get_fan_speed)
                # Settle before the "after cooling" reading. Same fallback as the
                # other usleep call sites - sleep 3, not 1, so the cooldown is
                # still 3s on a build without the applet; a shorter pause would
                # silently change what this measures.
                usleep 3000000 2>/dev/null || sleep 3
                raw_post=$(get_cpu_temp)
                post_temp_str=$(get_temp)
                post_fan_str=$(get_fan_speed)
                
                printf "\n"
                print_success "Stress test completed"
                printf "\n"
                if [ "$raw_start" != "unknown" ] && [ "$raw_end" != "unknown" ]; then
                    diff_c=$(awk "BEGIN {printf \"%+.2f\", $raw_end - $raw_start}")
                    diff_f=$(awk "BEGIN {printf \"%+.1f\", ($raw_end - $raw_start) * 1.8}")
                    post_diff_c=$(awk "BEGIN {printf \"%+.2f\", $raw_post - $raw_start}")
                    post_diff_f=$(awk "BEGIN {printf \"%+.1f\", ($raw_post - $raw_start) * 1.8}")
                    
                    # Fan % Changes
                    if [ "$start_fan_str" = "N/A" ] || [ "$start_fan_str" -eq 0 ] 2>/dev/null; then
                        fan_p="+0.0"
                        fan_post_p="+0.0"
                    else
                        fan_p=$(awk "BEGIN {printf \"%+.1f\", (($end_fan_str - $start_fan_str) / $start_fan_str) * 100}")
                        fan_post_p=$(awk "BEGIN {printf \"%+.1f\", (($post_fan_str - $start_fan_str) / $start_fan_str) * 100}")
                    fi

                    # --- TABLE RENDER ---
                    # Left-justified: exactly 3 fixed rows about ONE test run
                    # (a status report, not an open-ended comparison list), so
                    # this fails the "genuinely comparing many values" test -
                    # same category as the leaderboards, not DNS Benchmark.
                    # printf's %Ns counts UTF-8 BYTES, not characters, on this
                    # platform (confirmed: ${#}/wc -m/wc -c/awk length() ALL
                    # miscount multi-byte glyphs like ° identically - there is
                    # no reliable char-counting tool here). ljust() sidesteps
                    # this: it never measures a string containing a multi-byte
                    # char - the caller supplies the true length, computed from
                    # ASCII-only numeric substrings + a known-constant offset
                    # for the fixed °C/°F skeleton around them.
                    ljust() {
                        local width="$1" s="$2" true_len="$3" pad="" i=0
                        while [ "$i" -lt "$((width - true_len))" ]; do pad="${pad} "; i=$((i + 1)); done
                        printf '%s%s' "$s" "$pad"
                    }

                    c_start=$(awk "BEGIN {printf \"%.2f\", $raw_start}")
                    f_start=$(awk "BEGIN {printf \"%.2f\", ($raw_start * 1.8) + 32}")
                    c_end=$(awk "BEGIN {printf \"%.2f\", $raw_end}")
                    f_end=$(awk "BEGIN {printf \"%.2f\", ($raw_end * 1.8) + 32}")
                    c_post=$(awk "BEGIN {printf \"%.2f\", $raw_post}")
                    f_post=$(awk "BEGIN {printf \"%.2f\", ($raw_post * 1.8) + 32}")
                    # "°C (°F)" skeleton = 7 real characters around the two ASCII numbers
                    temp_len_start=$((${#c_start} + ${#f_start} + 7))
                    temp_len_end=$((${#c_end} + ${#f_end} + 7))
                    temp_len_post=$((${#c_post} + ${#f_post} + 7))

                    delta_end="${diff_c}°C (${diff_f}°F)"
                    delta_post="${post_diff_c}°C (${post_diff_f}°F)"
                    delta_len_end=$((${#diff_c} + ${#diff_f} + 7))
                    delta_len_post=$((${#post_diff_c} + ${#post_diff_f} + 7))

                    fan_start="${start_fan_str} RPM"
                    fan_end="${end_fan_str} RPM (${fan_p}%)"
                    fan_post="${post_fan_str} RPM (${fan_post_p}%)"

                    printf "%-10s %s %s %s\n" "PHASE" "$(ljust 22 "TEMPERATURE" 11)" "$(ljust 18 "Δ CHANGE" 8)" "$(ljust 18 "FAN SPEED (Δ%)" 14)"
                    printf "%s\n" "───────────────────────────────────────────────────────────────────────"
                    printf "%-10s %s %s %-18s\n" "Start" "$(ljust 22 "$start_temp_str" "$temp_len_start")" "       ---        " "$fan_start"
                    printf "%-10s %s %s %-18s\n" "End" "$(ljust 22 "$end_temp_str" "$temp_len_end")" "$(ljust 18 "$delta_end" "$delta_len_end")" "$fan_end"
                    printf "%-10s %s %s %-18s\n" "End + 3s" "$(ljust 22 "$post_temp_str" "$temp_len_post")" "$(ljust 18 "$delta_post" "$delta_len_post")" "$fan_post"
                fi         
                press_any_key
                ;;
            2)
                clear
                print_centered_header "VPN & Crypto Benchmark"

                if ! require_cmd openssl openssl-util "OpenSSL command-line tools"; then
                    print_error "OpenSSL is required for the crypto benchmark and could not be installed."
                    press_any_key
                    continue
                fi

                # Reference results, keyed on /proc/gl-hw-info/model. Add a tested
                # device by appending one line in the same column order:
                # id|label|cpu|aes64|aes1420|aes16k|cha64|cha1420|cha16k|rsa_sign|rsa_verify
                bench_ref='be14000|Flint 4|MT7988a|342047|662912|715487|116011|214298|259237|163.5|6140.7
mt3600be|Beryl 7|MT7987a|267728|621208|721917|126357|258082|323188|182.9|6850.8
be3600|Slate 7|IPQ5332|148704|390262|469676|68462|158269|185704|103.4|3908.5
mt6000|Flint 2|MT7986a|35969|403625|784938|128188|285938|336125|186.4|6906.5
mt3000|Beryl AX|MT7981|174738|403199|465470|84051|166484|209360|118.7|4446.3
mt5000|Brume 3|MT7987a|268078|621323|723411|126278|257233|323477|181.8|6816.4
be9300|Flint 3|IPQ5332|186703|533571|639020|84930|216067|250916|139.7|5180.6
mt1300|Beryl|MT7621|5522|5944|5759|21915|27148|27613|10.4|397.6'

                my_id=$(cat /proc/gl-hw-info/model 2>/dev/null)
                [ -z "$my_id" ] && my_id="thisdevice"
                my_label=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $2; exit}')
                my_cpu=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $3; exit}')
                [ -z "$my_label" ] && my_label="$my_id"
                [ -z "$my_cpu" ] && my_cpu=$(get_cpu_vendor_model | awk '{print $NF}')

                print_info "Measuring this device - stop VPN, SQM and heavy traffic for accurate, comparable numbers."
                printf "\n"

                bench_measure aes-256-gcm 64;          a64=$BENCH_RESULT
                bench_measure aes-256-gcm 1420;        a1420=$BENCH_RESULT
                bench_measure aes-256-gcm 16384;       a16k=$BENCH_RESULT
                bench_measure chacha20-poly1305 64;    c64=$BENCH_RESULT
                bench_measure chacha20-poly1305 1420;  c1420=$BENCH_RESULT
                bench_measure chacha20-poly1305 16384; c16k=$BENCH_RESULT
                spin_run "Measuring RSA-2048 (connection setup)" openssl speed rsa2048
                rs=$(awk '/^rsa 2048 bits/{print $6; exit}' "$SPIN_LOG")
                rv=$(awk '/^rsa 2048 bits/{print $7; exit}' "$SPIN_LOG")
                rm -f "$SPIN_LOG" 2>/dev/null

                bench_data="/tmp/.glnet-bench.$$"
                {
                    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$my_id" "$my_label" "$my_cpu" \
                        "${a64:-0}" "${a1420:-0}" "${a16k:-0}" "${c64:-0}" "${c1420:-0}" "${c16k:-0}" "${rs:-0}" "${rv:-0}"
                    printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" 'NF>=11 && $1!=id'
                } > "$bench_data"

                bench_page=1
                while true; do
                    clear
                    print_centered_header "VPN & Crypto Benchmark"
                    case "$bench_page" in
                        1)
                            bench_render_cipher "WireGuard · ChaCha20-Poly1305" 7 8 9 "$bench_data" "$my_id"
                            printf '\n %b64 B = small packets (VoIP/gaming/DNS)      1420 B = VPN throughput (downloads/streaming)%b\n' "$GREY" "$RESET"
                            printf ' %b16 K = raw cipher ceiling, larger than any VPN packet%b\n' "$GREY" "$RESET"
                            printf '\n %bNote: each device uses its own OpenSSL build. WireGuard runs kernel ChaCha20, so that%b\n' "$GREY" "$RESET"
                            printf ' %bcolumn is a proxy; OpenVPN/IPsec uses OpenSSL directly.%b\n' "$GREY" "$RESET"
                            ;;
                        2)
                            bench_render_cipher "OpenVPN / IPsec · AES-256-GCM" 4 5 6 "$bench_data" "$my_id"
                            printf '\n %b64 B = small packets (VoIP/gaming/DNS)      1420 B = VPN throughput (downloads/streaming)%b\n' "$GREY" "$RESET"
                            printf ' %b16 K = raw cipher ceiling, larger than any VPN packet%b\n' "$GREY" "$RESET"
                            ;;
                        3)
                            bench_render_rsa "$bench_data" "$my_id"
                            ;;
                    esac
                    printf " ──────────────────────────────────────────────────────────────────────────────\n"
                    printf " [P] Previous   "
                    bpi=1
                    while [ $bpi -le 3 ]; do
                        if [ $bpi -eq $bench_page ]; then
                            printf "%b[%d]%b " "${BOLD}" "$bpi" "${RESET}"
                        else
                            printf "%b[%d]%b " "${GREY}" "$bpi" "${RESET}"
                        fi
                        bpi=$((bpi + 1))
                    done
                    printf "  [N] Next   [0] Back  "
                    bp=$(read_single_char)
                    printf '\n'
                    case "$bp" in
                        p|P|b|B) [ "$bench_page" -gt 1 ] && bench_page=$((bench_page - 1)) ;;
                        n|N) [ "$bench_page" -lt 3 ] && bench_page=$((bench_page + 1)) ;;
                        1|2|3) bench_page="$bp" ;;
                        0) break ;;
                    esac
                done
                rm -f "$bench_data"
                ;;
            3)
                clear
                print_centered_header "Disk I/O Benchmark"

                available_kb=$(df -Pk . | awk 'NR==2 {print $4}')

                if [ "$available_kb" -ge 1024000 ]; then test_size=1000; test_name="1GB"
                elif [ "$available_kb" -ge 512000 ]; then test_size=500; test_name="500MB"
                elif [ "$available_kb" -ge 256000 ]; then test_size=250; test_name="250MB"
                elif [ "$available_kb" -ge 128000 ]; then test_size=125; test_name="125MB"
                elif [ "$available_kb" -ge 64000 ]; then test_size=64; test_name="64MB"
                elif [ "$available_kb" -ge 32000 ]; then test_size=32; test_name="32MB"
                else test_size=16; test_name="16MB"; fi

                printf "Test size: %b%s%b\n\n" "${GREEN}" "$test_name" "${RESET}"

                get_ms() { read ut _ < /proc/uptime; awk -v t="$ut" 'BEGIN {print int(t * 1000)}'; }

                sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
                w_start=$(get_ms)
                spin_run "Running write test ($test_name)" dd if=/dev/zero of=./testfile bs=1M count=$test_size conv=fsync
                w_end=$(get_ms)

                sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
                r_start=$(get_ms)
                spin_run "Running read test ($test_name)" dd if=./testfile of=/dev/null bs=1M
                r_end=$(get_ms)
                rm -f ./testfile

                w_ms=$((w_end - w_start)); [ "$w_ms" -le 0 ] && w_ms=1
                r_ms=$((r_end - r_start)); [ "$r_ms" -le 0 ] && r_ms=1
                write_speed=$(awk -v sz="$test_size" -v ms="$w_ms" 'BEGIN{printf "%.2f", (sz*1000)/ms}')
                read_speed=$(awk -v sz="$test_size" -v ms="$r_ms" 'BEGIN{printf "%.2f", (sz*1000)/ms}')

                # Reference results, keyed on /proc/gl-hw-info/model. Add a tested
                # device by appending one line: id|label|cpu|write_mbs|read_mbs
                bench_ref='be14000|Flint 4|MT7988a|149.48|165.29
mt3600be|Beryl 7|MT7987a|124.70|11.00
be3600|Slate 7|IPQ5332|75.72|51.50
mt6000|Flint 2|MT7986a|52.72|154.00
mt3000|Beryl AX|MT7981|82.78|16.21
mt5000|Brume 3|MT7987a|38.93|42.32
be9300|Flint 3|IPQ5332|13.72|81.70
mt1300|Beryl|MT7621|0.24|12.54'

                my_id=$(cat /proc/gl-hw-info/model 2>/dev/null)
                [ -z "$my_id" ] && my_id="thisdevice"
                my_label=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $2; exit}')
                my_cpu=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $3; exit}')
                [ -z "$my_label" ] && my_label="$my_id"
                [ -z "$my_cpu" ] && my_cpu=$(get_cpu_vendor_model | awk '{print $NF}')

                bench_data="/tmp/.glnet-bench.$$"
                {
                    printf '%s|%s|%s|%s|%s\n' "$my_id" "$my_label" "$my_cpu" "$write_speed" "$read_speed"
                    printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" 'NF>=5 && $1!=id'
                } > "$bench_data"

                bench_render_disk "$bench_data" "$my_id"
                printf "\n %bWrite is the reliable cross-device metric. Read may reflect the storage%b\n" "$GREY" "$RESET"
                printf " %bcontroller's own onboard cache (notably on eMMC), which OS cache-drop can't%b\n" "$GREY" "$RESET"
                printf " %breach - treat Read as indicative, not absolute. Test size scales with free%b\n" "$GREY" "$RESET"
                printf " %bdisk space, so it can differ between devices.%b\n" "$GREY" "$RESET"
                rm -f "$bench_data"

                printf "\n"
                print_success "Disk benchmark completed"
                press_any_key
                ;;
            4)
                clear
                print_centered_header "Memory I/O Benchmark"

                # Use the SAME RAM figure as Hardware Info screen 1 (get_mem_stats -> mem_rounded),
                # never a second calc. A 128 MB device reads MemTotal ~124 MB; the old inline
                # "est = MemTotal+30, then ceil-to-128" over-rounded that to 256. get_mem_stats
                # buckets MemTotal to the nearest common size (124 -> 128), matching the GL UI.
                get_mem_stats
                total_mem=$mem_rounded
                [ "${mem_total:-0}" -gt 0 ] || total_mem=512   # /proc/meminfo unreadable: old default

                # Determine test size (100k blocks of 1M = 100GB of throughput)
                # We want a large enough test to bypass L1/L2 cache saturation
                if [ "$total_mem" -ge 960 ]; then test_size=100000; test_name="100GB"
                elif [ "$total_mem" -ge 460 ]; then test_size=50000; test_name="50GB"
                else test_size=4000; test_name="4GB"; fi

                printf "System RAM: %b%s MB%b\n" "${GREEN}" "$total_mem" "${RESET}"
                printf "Test throughput: %b%s%b\n\n" "${GREEN}" "$test_name" "${RESET}"

                get_ms() { read ut _ < /proc/uptime; awk -v t="$ut" 'BEGIN {print int(t * 1000)}'; }

                m_start=$(get_ms)
                spin_run "Measuring memory controller throughput" dd if=/dev/zero of=/dev/null bs=1M count=$test_size
                m_end=$(get_ms)

                m_ms=$((m_end - m_start)); [ "$m_ms" -le 0 ] && m_ms=1
                mem_speed=$(awk -v sz="$test_size" -v ms="$m_ms" 'BEGIN{printf "%.2f", (sz*1000)/ms}')

                # Reference results, keyed on /proc/gl-hw-info/model. Add a tested
                # device by appending one line: id|label|cpu|mem_mbs
                bench_ref='be14000|Flint 4|MT7988a|5271.48
mt3600be|Beryl 7|MT7987a|4361.12
be3600|Slate 7|IPQ5332|3006.13
mt6000|Flint 2|MT7986a|5401.50
mt3000|Beryl AX|MT7981|2983.29
mt5000|Brume 3|MT7987a|4492.36
be9300|Flint 3|IPQ5332|4277.16
mt1300|Beryl|MT7621|179.39'

                my_id=$(cat /proc/gl-hw-info/model 2>/dev/null)
                [ -z "$my_id" ] && my_id="thisdevice"
                my_label=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $2; exit}')
                my_cpu=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $3; exit}')
                [ -z "$my_label" ] && my_label="$my_id"
                [ -z "$my_cpu" ] && my_cpu=$(get_cpu_vendor_model | awk '{print $NF}')

                bench_data="/tmp/.glnet-bench.$$"
                {
                    printf '%s|%s|%s|%s\n' "$my_id" "$my_label" "$my_cpu" "$mem_speed"
                    printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" 'NF>=4 && $1!=id'
                } > "$bench_data"

                bench_render_mem "$bench_data" "$my_id"
                printf "\n %bMeasures raw memcpy-style throughput via dd, not a full memory-latency%b\n" "$GREY" "$RESET"
                printf " %bbenchmark; test size scales with device RAM to avoid cache saturation.%b\n" "$GREY" "$RESET"
                rm -f "$bench_data"

                printf "\n"
                print_success "Memory benchmark completed"
                press_any_key
                ;;
            5)
                clear
                print_centered_header "DNS Benchmark"

                print_info "Starting Comprehensive DNS Benchmark"
                printf "\n"
                
                # Pre-check: Can we resolve anything at all?
                if ! nslookup google.com >/dev/null 2>&1; then
                    print_error "DNS is not responding. Check your internet connection or DNS settings."
                    press_any_key
                    continue
                fi

                # Check for Hijacking
                is_proxied=0
                if nslookup "detect${RANDOM}.com" 1.2.3.4 >/dev/null 2>&1; then
                    is_proxied=1
                    print_warning "DNS Interception Active: Traffic is being redirected locally."
                    printf "\n"
                fi
                
                # Servers to test
                SERVERS="127.0.0.1 1.1.1.1 8.8.8.8 9.9.9.9"
                SAMPLES=20  # Number of tests per server
                
                printf " %-22s %8s %8s %8s\n" "DNS Server" "Min" "Avg" "Max"
                printf " ────────────────────────────────────────────────────\n"

                for server in $SERVERS; do
                    case $server in
                        "127.0.0.1") label="Local (AdGuard/Cache)" ;;
                        "1.1.1.1")   label="Cloudflare" ;;
                        "8.8.8.8")   label="Google" ;;
                        "9.9.9.9")   label="Quad9" ;;
                    esac

                    total=0; min=9999; max=0; BURST=5

                    for i in $(seq 1 10); do
                        test_domain="bench${RANDOM}.net"

                        read ut _ < /proc/uptime
                        start_t=$ut
                        
                        # Execute a burst of lookups to exceed the 10ms clock tick
                        for b in $(seq 1 $BURST); do
                            nslookup "$test_domain" "$server" >/dev/null 2>&1
                        done
                        
                        read ut _ < /proc/uptime
                        end_t=$ut
                        
                        # Calculate per-query msec: ((end - start) * 1000) / BURST
                        msec=$(awk -v s="$start_t" -v e="$end_t" -v b="$BURST" \
                              'BEGIN { printf "%.2f", ((e - s) * 1000) / b }')

                        # Update stats
                        min=$(awk -v m="$msec" -v cur="$min" 'BEGIN { print (m < cur ? m : cur) }')
                        max=$(awk -v m="$msec" -v cur="$max" 'BEGIN { print (m > cur ? m : cur) }')
                        total=$(awk -v m="$msec" -v t="$total" 'BEGIN { print t + m }')
                    done

                    avg=$(awk -v t="$total" 'BEGIN { printf "%.2f", t / 10 }')

                    COLOR=$CYAN
                    if [ $(awk -v a="$avg" 'BEGIN {print (a < 15.0 ? 1 : 0)}') -eq 1 ]; then 
                        COLOR=$GREEN
                    fi
                        
                    printf " %-22s %b%8s %8s %8s%b ms\n" "$label" "$COLOR" "$min" "$avg" "$max" "$RESET"
                done
                
                printf "\n"
                print_success "DNS Benchmark completed"
                press_any_key
                ;;
            6)
                clear
                print_centered_header "Ookla Network Speedtest"
                # Ookla ships no MIPS binary, so MIPS routers run speedtest-go instead:
                # same speedtest.net servers, a real WAN-to-internet measurement. Both
                # installers explain, wait, then return non-zero if the binary can't be
                # had (no build, or no internet), so "|| continue" goes back to the menu
                # instead of "running" a missing binary that no-ops and claims success.
                _stdiv="──────────────────────────────────────────────────────────────────────────────────────────"
                case "$(uname -m)" in
                    mips*)
                        install_speedtest_go || continue
                        printf "\n%b\n" "${YELLOW}⏳ Running Internet Speedtest (speedtest.net) ${RESET}"
                        printf "%s\n" "$_stdiv"
                        if "$STGO_BIN"; then
                            printf "\n%s\n" "$_stdiv"
                            print_success "Speedtest completed"
                        else
                            printf "\n%s\n" "$_stdiv"
                            print_error "Speedtest didn't complete - check your internet connection."
                        fi
                        press_any_key
                        ;;
                    *)
                        install_ookla_speedtest || continue
                        printf "\n%b\n" "${YELLOW}⏳ Running Ookla Speedtest ${RESET}"
                        printf "%s\n" "$_stdiv"
                        speedtest -a --accept-license --accept-gdpr 2>/dev/null
                        printf "\n%s\n" "$_stdiv"
                        print_success "Ookla Speedtest completed"
                        press_any_key
                        ;;
                esac
                ;;
            7)  manage_librespeed ;;
            8)  
                lan_ipaddr=$(get_lan_ip)
                clear
                print_centered_header "iperf3 Network Speed Test Server"
                
                if ! command -v iperf3 >/dev/null 2>&1; then
                    install_package iperf3 || { press_any_key; continue; }
                fi
                
                printf "%b\n\n" "${YELLOW}⏳ Starting iperf3 Server on port 5201... ${RESET}"
                print_info "Client usage:"
                printf "   Download:  %biperf3 -c %s -P 6 -R -t 60%b\n" "${CYAN}" "$lan_ipaddr" "${RESET}"
                printf "   Upload:    %biperf3 -c %s -P 4 -t 60%b\n" "${CYAN}" "$lan_ipaddr" "${RESET}"
                
                printf "\n%bPress Ctrl+C to stop the server and return to menu.%b\n" "${YELLOW}" "${RESET}"
                trap 'printf "\n%s\n" "──────────────────────────────────────────────────────────────────────"' INT
                iperf3 -s
                trap - INT
                print_success "iperf3 Server stopped"
                press_any_key
                ;;
            9)  install_openspeedtest ;;
            0)
                return
                ;;
            \?|h|H|❓) show_benchmarks_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# UCI Configuration Viewer
# -----------------------------
show_uci_help() {
    show_paged "System Configuration Viewer - Help" << 'HELPEOF'
System Configuration Viewer - Quick Help

What it does
────────────
A READ-ONLY viewer for the router's UCI configuration - the unified config
behind wireless, network, firewall, VPN and more. Pick a category to print its
current settings.

Read-only, on purpose
─────────────────────
Nothing is changed, saved or committed from this screen. It's for inspecting
what the router is actually running - safe to browse, and handy for
troubleshooting or comparing against the Admin Panel.
HELPEOF
}

view_uci_config() {
    while true; do
        clear
        print_centered_header "System Configuration Viewer"
        printf "%s%sWireless Networks\n" "$N1" "$NSEP"
        printf "%s%sNetwork Configuration\n" "$N2" "$NSEP"
        printf "%s%sVPN Configuration\n" "$N3" "$NSEP"
        printf "%s%sSystem Settings\n" "$N4" "$NSEP"
        printf "%s%sCloud Services\n" "$N5" "$NSEP"
        printf "%s%sMain menu\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-5/0/?]: "
        read -r config_choice
        printf "\n"
        
        case $config_choice in
            \?|h|H|❓) show_uci_help ;;
            1)
                clear
                print_centered_header "Wireless Networks"
                
                all_ifaces=""
                for iface in $(uci show wireless 2>/dev/null | grep "wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1 | sort -u); do
                    ssid=$(uci get wireless.${iface}.ssid 2>/dev/null)
                    [ -n "$ssid" ] && all_ifaces="$all_ifaces $iface"
                done
                
                mlo_ifaces=""
                five_ifaces=""
                two_ifaces=""
                
                for iface in $all_ifaces; do
                    device=$(uci get wireless.${iface}.device 2>/dev/null)
                    band=$(uci get wireless.${device}.band 2>/dev/null)
                    
                    if uci get wireless.${iface}.mlo 2>/dev/null | grep -q "1"; then
                        mlo_ifaces="$mlo_ifaces $iface"
                    elif [ "$band" = "5g" ] || [ "$band" = "6g" ]; then
                        five_ifaces="$five_ifaces $iface"
                    elif [ "$band" = "2g" ]; then
                        two_ifaces="$two_ifaces $iface"
                    else
                        two_ifaces="$two_ifaces $iface"
                    fi
                done
                
                count=0
                for iface in $mlo_ifaces $five_ifaces $two_ifaces; do

                    if [ $((count % 2)) -eq 0 ] && [ $count -gt 0 ]; then
                       press_any_key
                       clear
                       print_centered_header "Wireless Networks"
                    fi
                    
                    ssid=$(uci get wireless.${iface}.ssid 2>/dev/null)
                    key=$(uci get wireless.${iface}.key 2>/dev/null)
                    encryption=$(uci get wireless.${iface}.encryption 2>/dev/null)
                    disabled=$(uci get wireless.${iface}.disabled 2>/dev/null)
                    hidden=$(uci get wireless.${iface}.hidden 2>/dev/null)
                    device=$(uci get wireless.${iface}.device 2>/dev/null)
                    mode=$(uci get wireless.${iface}.mode 2>/dev/null)
                    
                    band=$(uci get wireless.${device}.band 2>/dev/null)
                    htmode=$(uci get wireless.${device}.htmode 2>/dev/null)
                    channel=$(uci get wireless.${device}.channel 2>/dev/null)
                    
                    case "$band" in
                        2g) band_name="2.4GHz" ;;
                        5g) band_name="5GHz" ;;
                        6g) band_name="6GHz" ;;
                        *) band_name="Unknown" ;;
                    esac
                    
                    if uci get wireless.${iface}.mlo 2>/dev/null | grep -q "1"; then
                        band_name="MLO (Multi-Link)"
                    fi
                    
                    printf "%b\n" "${CYAN}Interface: $iface ($band_name)${RESET}"
                    printf "  SSID: %b%s%b\n" "${GREEN}" "$ssid" "${RESET}"
                    [ -n "$key" ] && printf "  Password: %b%s%b\n" "${YELLOW}" "$key" "${RESET}"
                    [ -n "$encryption" ] && printf "  Encryption: %s\n" "$encryption"
                    
                    if [ "$hidden" = "1" ]; then
                        printf "  Visibility: %bHidden%b\n" "${YELLOW}" "${RESET}"
                    else
                        printf "  Visibility: %bVisible%b\n" "${GREEN}" "${RESET}"
                    fi
                    
                    [ -n "$mode" ] && printf "  Mode: %s\n" "$mode"
                    [ -n "$htmode" ] && printf "  Bandwidth: %s\n" "$htmode"
                    [ -n "$channel" ] && printf "  Channel: %s\n" "$channel"
                    
                    if [ "$disabled" = "1" ]; then
                        printf "  Status: %bDisabled%b\n" "${RED}" "${RESET}"
                    else
                        printf "  Status: %bEnabled%b\n" "${GREEN}" "${RESET}"
                    fi
                    printf "\n"
                    count=$((count + 1))
                done
                
                press_any_key
                ;;
            2)
                clear
                print_centered_header "Network Configuration"
                
                printf "%b\n" "${CYAN}WAN Configuration:${RESET}"
                wan_proto=$(uci get network.wan.proto 2>/dev/null)
                wan_ipaddr=$(uci get network.wan.ipaddr 2>/dev/null)
                wan_netmask=$(uci get network.wan.netmask 2>/dev/null)
                wan_gateway=$(uci get network.wan.gateway 2>/dev/null)
                wan_dns=$(uci get network.wan.dns 2>/dev/null)
                
                [ -n "$wan_proto" ] && printf "  Protocol: %s\n" "$wan_proto"
                [ -n "$wan_ipaddr" ] && printf "  IP Address: %b%s%b\n" "${GREEN}" "$wan_ipaddr" "${RESET}"
                [ -n "$wan_netmask" ] && printf "  Netmask: %s\n" "$wan_netmask"
                [ -n "$wan_gateway" ] && printf "  Gateway: %s\n" "$wan_gateway"
                [ -n "$wan_dns" ] && printf "  DNS: %s\n" "$wan_dns"
                
                printf "\n%b\n" "${CYAN}LAN Configuration:${RESET}"
                lan_ipaddr=$(get_lan_ip)
                lan_netmask=$(uci get network.lan.netmask 2>/dev/null)
                lan_proto=$(uci get network.lan.proto 2>/dev/null)
                
                [ -n "$lan_proto" ] && printf "  Protocol: %s\n" "$lan_proto"
                [ -n "$lan_ipaddr" ] && printf "  IP Address: %b%s%b\n" "${GREEN}" "$lan_ipaddr" "${RESET}"
                [ -n "$lan_netmask" ] && printf "  Netmask: %s\n" "$lan_netmask"
                
                printf "\n%b\n" "${CYAN}DHCP Server:${RESET}"
                dhcp_start=$(uci get dhcp.lan.start 2>/dev/null)
                dhcp_limit=$(uci get dhcp.lan.limit 2>/dev/null)
                dhcp_leasetime=$(uci get dhcp.lan.leasetime 2>/dev/null)
                
                [ -n "$dhcp_start" ] && printf "  Start: %s\n" "$dhcp_start"
                [ -n "$dhcp_limit" ] && printf "  Limit: %s\n" "$dhcp_limit"
                [ -n "$dhcp_leasetime" ] && printf "  Lease Time: %s\n" "$dhcp_leasetime"
                printf "\n"
                
                press_any_key
                ;;
            3)
                clear
                print_centered_header "VPN Configuration"
                
                found_vpn=0

                # GL.iNet keeps VPN config in its own packages, not the stock
                # OpenWrt ones — read wireguard_server / ovpnserver (servers) and
                # the wireguard / ovpnclient peer sections (clients).
                if uci show wireguard_server 2>/dev/null | grep -q "=servers"; then
                    printf "%b\n" "${CYAN}WireGuard Server:${RESET}"
                    for iface in $(uci show wireguard_server 2>/dev/null | grep "=servers" | cut -d'.' -f2 | cut -d'=' -f1); do
                        listen_port=$(uci get wireguard_server.${iface}.port 2>/dev/null)
                        addr_v4=$(uci get wireguard_server.${iface}.address_v4 2>/dev/null)
                        mtu=$(uci get wireguard_server.${iface}.mtu 2>/dev/null)
                        printf "  Interface: %b%s%b\n" "${GREEN}" "$iface" "${RESET}"
                        [ -n "$listen_port" ] && printf "    Listen Port: %s\n" "$listen_port"
                        [ -n "$addr_v4" ] && printf "    Address: %s\n" "$addr_v4"
                        [ -n "$mtu" ] && printf "    MTU: %s\n" "$mtu"
                        printf "\n"
                        found_vpn=1
                    done
                fi

                if uci show ovpnserver 2>/dev/null | grep -q "=general"; then
                    printf "%b\n" "${CYAN}OpenVPN Server:${RESET}"
                    proto=$(uci get ovpnserver.vpn.proto 2>/dev/null)
                    port=$(uci get ovpnserver.vpn.port 2>/dev/null)
                    subnet=$(uci get ovpnserver.vpn.subnetv4 2>/dev/null)
                    mtu=$(uci get ovpnserver.global.mtu 2>/dev/null)
                    [ -n "$proto" ] && printf "    Protocol: %s\n" "$proto"
                    [ -n "$port" ] && printf "    Port: %s\n" "$port"
                    [ -n "$subnet" ] && printf "    Subnet: %s\n" "$subnet"
                    [ -n "$mtu" ] && printf "    MTU: %s\n" "$mtu"
                    printf "\n"
                    found_vpn=1
                fi

                if uci show wireguard 2>/dev/null | grep -q "=peers"; then
                    printf "%b\n" "${CYAN}WireGuard Clients:${RESET}"
                    for peer in $(uci show wireguard 2>/dev/null | grep "=peers" | cut -d'.' -f2 | cut -d'=' -f1); do
                        name=$(uci get wireguard.${peer}.name 2>/dev/null)
                        endpoint=$(uci get wireguard.${peer}.end_point 2>/dev/null)
                        addr_v4=$(uci get wireguard.${peer}.address_v4 2>/dev/null)
                        allowed=$(uci get wireguard.${peer}.allowed_ips 2>/dev/null)
                        keepalive=$(uci get wireguard.${peer}.persistent_keepalive 2>/dev/null)

                        printf "  Peer: %b%s%b\n" "${GREEN}" "${name:-$peer}" "${RESET}"
                        [ -n "$endpoint" ] && printf "    Endpoint: %s\n" "$endpoint"
                        [ -n "$addr_v4" ] && printf "    Address: %s\n" "$addr_v4"
                        [ -n "$allowed" ] && printf "    Allowed IPs: %s\n" "$allowed"
                        [ -n "$keepalive" ] && printf "    Keepalive: %s sec\n" "$keepalive"
                        printf "\n"
                        found_vpn=1
                    done
                fi

                if uci show ovpnclient 2>/dev/null | grep -q "=clients"; then
                    printf "%b\n" "${CYAN}OpenVPN Clients:${RESET}"
                    for client in $(uci show ovpnclient 2>/dev/null | grep "=clients" | cut -d'.' -f2 | cut -d'=' -f1); do
                        name=$(uci get ovpnclient.${client}.name 2>/dev/null)
                        remote=$(uci get ovpnclient.${client}.remote 2>/dev/null)
                        proto=$(uci get ovpnclient.${client}.proto 2>/dev/null)
                        printf "  Client: %b%s%b\n" "${GREEN}" "${name:-$client}" "${RESET}"
                        [ -n "$remote" ] && printf "    Remote: %s\n" "$remote"
                        [ -n "$proto" ] && printf "    Protocol: %s\n" "$proto"
                        printf "\n"
                        found_vpn=1
                    done
                fi

                if [ "$found_vpn" -eq 0 ]; then
                    print_warning "No active VPN configurations found"
                    printf "\n"
                fi
                
                press_any_key
                ;;
            4)
                clear
                print_centered_header "System Settings"
                
                printf "%b\n" "${CYAN}System Information:${RESET}"
                hostname=$(uci get system.@system[0].hostname 2>/dev/null)
                timezone=$(uci get system.@system[0].timezone 2>/dev/null)
                zonename=$(uci get system.@system[0].zonename 2>/dev/null)
                
                [ -n "$hostname" ] && printf "  Hostname: %b%s%b\n" "${GREEN}" "$hostname" "${RESET}"
                [ -n "$zonename" ] && printf "  Timezone: %s\n" "$zonename"
                [ -n "$timezone" ] && printf "  TZ String: %s\n" "$timezone"
                
                printf "\n%b\n" "${CYAN}Root Access:${RESET}"
                if grep -q "^root:[^\*!]" /etc/shadow 2>/dev/null; then
                    printf "  Root Password: %b%s%b\n" "${GREEN}" "Set" "${RESET}"
                else
                    printf "  Root Password: %b%s%b\n" "${RED}" "Not Set" "${RESET}"
                fi
                
                ssh_port=$(uci get dropbear.@dropbear[0].Port 2>/dev/null)
                ssh_interface=$(uci get dropbear.@dropbear[0].Interface 2>/dev/null)
                ssh_pass=$(uci get dropbear.@dropbear[0].PasswordAuth 2>/dev/null)
                ssh_root=$(uci get dropbear.@dropbear[0].RootPasswordAuth 2>/dev/null)
                
                printf "\n%b\n" "${CYAN}SSH Configuration:${RESET}"
                [ -n "$ssh_port" ] && printf "  Port: %s\n" "$ssh_port" || printf "  Port: 22 (default)\n"
                [ -n "$ssh_interface" ] && printf "  Interface: %s\n" "$ssh_interface"
                
                if [ "$ssh_pass" = "0" ]; then
                    printf "  Password Auth: %b%s%b\n" "${RED}" "Disabled" "${RESET}"
                else
                    printf "  Password Auth: %b%s%b\n" "${GREEN}" "Enabled" "${RESET}"
                fi
                
                if [ "$ssh_root" = "0" ]; then
                    printf "  Root Login: %b%s%b\n" "${RED}" "Disabled" "${RESET}"
                else
                    printf "  Root Login: %b%s%b\n" "${GREEN}" "Enabled" "${RESET}"
                fi
                printf "\n"
                
                press_any_key
                ;;
            5)
                clear
                print_centered_header "Cloud Services"
                
                printf "%b\n" "${CYAN}GoodCloud:${RESET}"
                if [ -f /etc/config/gl-cloud ]; then
                    gc_enable=$(uci get gl-cloud.@cloud[0].enable 2>/dev/null)
                    gc_deviceid=$(uci get gl-cloud.@cloud[0].token 2>/dev/null)
                    gc_server=$(uci get gl-cloud.@cloud[0].server 2>/dev/null)
                    gc_email=$(uci get gl-cloud.@cloud[0].email 2>/dev/null)
                    
                    if [ "$gc_enable" = "1" ]; then
                        printf "  Status: %bENABLED%b\n" "${GREEN}" "${RESET}"
                    else
                        printf "  Status: %bDISABLED%b\n" "${RED}" "${RESET}"
                    fi
                    
                    [ -n "$gc_email" ] && printf "  Account: %b%s%b\n" "${GREEN}" "$gc_email" "${RESET}"
                    [ -n "$gc_server" ] && printf "  Server: %s\n" "$gc_server"
                    if [ -n "$gc_deviceid" ]; then
                        token_short=$(printf "%s" "$gc_deviceid" | cut -c1-16)
                        printf "  Token: %s\n" "${token_short}..."
                    fi
                else
                    print_warning "GoodCloud not configured"
                fi
                
                printf "\n%b\n" "${CYAN}AstroWarp:${RESET}"
                if ip link show mptun0 >/dev/null 2>&1 && ip -4 addr show mptun0 | grep -q 'inet '; then
                    printf "  Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                    mptun_ip=$(ip -4 addr show mptun0 | grep 'inet ' | awk '{print $2}')
                    [ -n "$mptun_ip" ] && printf "  Interface: mptun0 (%s)\n" "$mptun_ip"
                else
                    printf "  Status: %bNOT ACTIVE%b\n" "${RED}" "${RESET}"
                    printf "  (No mptun0 interface or no IP assigned)\n"
                fi
                
                press_any_key
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

install_openspeedtest() {
    local script_url="https://raw.githubusercontent.com/phantasm22/OpenSpeedTestServer/main/install_openspeedtest.sh"
    local script_name="install_openspeedtest.sh"
    local expected_header="Author: phantasm22"

    clear
    print_centered_header "OpenSpeedTest Server Installation"

    # Check if we need to download (file missing OR invalid header)
    if [ ! -f "$script_name" ] || ! grep -q "$expected_header" "$script_name"; then
        _ost_fetch() { wget -q -O "$script_name" "$script_url" && [ -s "$script_name" ]; }

        if spin_run "Downloading OpenSpeedTest installer" _ost_fetch; then
            rm -f "$SPIN_LOG" 2>/dev/null
            chmod +x "$script_name"
            print_success "Download successful."
        else
            rm -f "$SPIN_LOG" 2>/dev/null
            print_error "Failed to download installer. Please check your connection."
            rm -f "$script_name"
            press_any_key
            return 1
        fi
    fi

    # Execute the script
    print_info "Launching installer"
    printf "\n"
    sleep 2
    
    # Check for execution bit just in case
    [ ! -x "$script_name" ] && chmod +x "$script_name"
    
    ./"$script_name"
    
    # Handle post-execution status
    if [ $? -eq 0 ]; then
        print_success "OpenSpeedTest setup sequence finished."
    else
        print_warning "Installer exited with a non-zero status."
    fi

    press_any_key
}

# -----------------------------
# Startup
# -----------------------------
# Splash + terminal detection already ran at load time (see detect_output_mode).
check_install_prompt "$@"
printf "\n"
check_self_update "$@"

# -----------------------------
# Service Verification
# -----------------------------

if [ ! -f "$AGH_INIT" ]; then
    clear
    printf "%b\n" "$SPLASH"
    if [ ! -f "/rom$AGH_INIT" ]; then
        print_warning "AdGuardHome not found/supported. AdGuardHome features will be disabled." 
        AGH_DISABLED=1
        press_any_key
    else
        print_error "AdGuardHome startup script missing! Will attempt AGH factory reset to restore it."
        sub_confirm_factory_reset
        if [ ! -f "$AGH_INIT" ]; then
            AGH_DISABLED=1
            printf "\n"
            print_warning "Recovery failed or cancelled. AdGuardHome features will be disabled."
            press_any_key
        fi
    fi
fi

# One-time sweep of any legacy co-located AdGuardHome backups (from versions before the central
# /etc/glinet_utils/backups store) into the central store - so upgrading to this version does not
# strand them, and the AGH overview counts them immediately (not only after opening Backup &
# Recovery). Idempotent: skips components already migrated. Runs only where AGH is present.
if [ -f "$AGH_INIT" ]; then
    _aghcfg="$(get_agh_config)"
    bk_migrate_legacy agh ${_aghcfg:+"$_aghcfg"} /usr/bin/AdGuardHome /etc/init.d/adguardhome 2>/dev/null
    unset _aghcfg
fi

# Safety: stress-ng can hard-crash routers on kernels < 6.6. If a previous version left it in the boot
# re-install list (persisted via the Package Manager), drop it on a susceptible kernel so it cannot
# crash-loop the router on the next firmware upgrade.
if _stressng_unsafe && [ -f /etc/lazarus.list ]; then
    sed -i '/^stress-ng$/d' /etc/lazarus.list 2>/dev/null
fi


# -----------------------------
# Main Menu
# -----------------------------
show_main_help() {
    show_paged "GL.iNet Toolkit - Main Menu Help" << 'HELPEOF'
GL.iNet Toolkit - Quick Help

What it does
────────────
The top-level menu of the GL.iNet router toolkit. Each entry opens a dedicated
area of the toolkit:

• Hardware Information      – read-only system, CPU, memory and thermal details
• AdGuardHome Control Center – DNS filtering, backups and service control
• System Tweaks             – hardware, network, package and toolkit settings
• System Benchmarks         – CPU, memory, disk and network speed tests
• System Configuration      – read-only view of the router's UCI config

Getting around (the same keys work on every screen):
• Type the number shown beside an item and press Enter to open it.
• [0] leaves the current screen — here it exits the toolkit; on inner screens
  it goes Back, or returns to the Main menu.
• [?] shows the help for whichever screen you are on.
HELPEOF
}

show_menu() {
    while true; do
        clear
        printf "%b\n" "$SPLASH"
        printf "%b\n" "${CYAN}Please select an option:${RESET}\n"
        printf "%s%sShow Hardware Information\n" "$N1" "$NSEP"
        printf "%s%sAdGuardHome Control Center\n" "$N2" "$NSEP"
        printf "%s%sSystem Tweaks\n" "$N3" "$NSEP"
        printf "%s%sSystem Benchmarks\n" "$N4" "$NSEP"
        printf "%s%sNetwork and VPN Tools\n" "$N5" "$NSEP"
        printf "%s%sView System Configuration (UCI)\n" "$N6" "$NSEP"
        printf "%s%sExit\n" "$N0" "$NSEP"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-6/0/?]: "
        read opt
        
        case $opt in
            \?|h|H|❓) show_main_help ;;
            1) show_hardware_info ;;
            2) [ $AGH_DISABLED != 1 ] && agh_control_center || { print_error "AGH not found. Feature disabled."; sleep 2; } ;;
            3) system_tweaks ;;
            4) benchmark_system ;;
            5) manage_vpn_tools ;;
            6) view_uci_config ;;
            0) clear; printf "\n"; print_success "Thanks for using GL.iNet Toolkit!"; printf "\n"; exit 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# Start
# -----------------------------
show_menu
