---
name: vm-cleanup
description: >
  Clean up disk space in the Claude working environment (Cowork session VM
  or Claude Code sandbox). Use this skill when the user says "clean VM",
  "clean disk", "free disk space", "disk full", "ENOSPC", "no space left",
  "clean session", "session cleanup", "disk cleanup", or when Bash commands
  fail with disk-full errors. Also use proactively before heavy operations
  like npm install or pip install in long sessions.
metadata:
  version: "0.2.0"
  platforms: ["claude-code", "cowork"]
---

# VM / Session Disk Cleanup

Recover from or prevent disk-full situations in Claude's working environment.

## Context

Both Cowork session VMs and Claude Code sandboxes have limited disk space.
Long sessions with package installs, builds, and cached data can fill the
disk completely. When full, ALL Bash commands fail with ENOSPC errors
because the shell can't create temp files — a deadlock where you can't
even diagnose the problem.

## Cleanup Strategy

Run cleanups in phases — smallest operations first so they succeed even
when disk is critically low.

### Phase 1: Emergency (needs almost zero free space)
Run these first when disk is completely full or nearly full:

```bash
# Remove Python bytecode (tiny files, frees inodes)
find /sessions -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null
find /sessions -name "*.pyc" -delete 2>/dev/null
find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null
```

```bash
# Clear temp files
rm -rf /tmp/*.tmp /tmp/*.log /tmp/tmp* /tmp/pip-* /tmp/npm-* 2>/dev/null
```

```bash
# Clear apt/package manager cache
rm -rf /var/cache/apt/archives/*.deb 2>/dev/null
apt-get clean 2>/dev/null
```

### Phase 2: Medium cleanup (clear package caches)

```bash
# Clear pip cache
pip cache purge 2>/dev/null
rm -rf ~/.cache/pip 2>/dev/null
```

```bash
# Clear npm cache
npm cache clean --force 2>/dev/null
rm -rf ~/.npm/_cacache 2>/dev/null
```

### Phase 3: Heavy cleanup (explicit approval required)

Phase 3 deletes dependencies, build outputs, and potentially global tools. It
must never run automatically, including from an ENOSPC trigger, proactive
cleanup, or a scheduled task.

Before running any Phase 3 command:

1. Re-check disk usage with `df -h /` and confirm that Phases 1 and 2 were not
   sufficient.
2. Perform a read-only scan and show the exact candidate paths and estimated
   sizes. Do not hide scan errors.
3. Warn the user that:
   - `node_modules` will require dependency reinstallation;
   - `.next`, `dist`, and `build` may contain outputs that are not reproducible
     unless the project and its inputs are preserved;
   - `~/.npm-global/lib/node_modules/*` removes globally installed CLI tools,
     not cache, and the original package list may be difficult to reconstruct;
   - if the Cowork VM becomes unusable, fully quit Claude Desktop/Cowork and
     reopen it to provision a fresh blank VM. All VM-internal state should be
     treated as lost; only files confirmed to be in the mounted user workspace
     should be expected to persist.
4. Ask the user to reply exactly `CONFIRM PHASE 3 CLEANUP` and name the target
   categories they approve. A confirmation applies only to the paths shown in
   that prompt and only to the current cleanup run.
5. If the user does not provide that confirmation, declines, or changes the
   target list, stop before Phase 3. Never infer approval from the original
   cleanup request or from approval of Phases 1 and 2.

After confirmation, execute only the approved commands and paths. Global npm
packages must be explicitly named as an approved category; otherwise skip the
last command below.

```bash
# Remove node_modules (recreate with npm install)
find /sessions -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null
find . -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null
```
```bash
# Remove build artifacts (recreate with build command)
find /sessions \( -name ".next" -o -name "dist" -o -name "build" \) -type d -exec rm -rf {} + 2>/dev/null
find . \( -name ".next" -o -name "dist" -o -name "build" \) -type d -exec rm -rf {} + 2>/dev/null
```

```bash
# Remove global npm packages
rm -rf ~/.npm-global/lib/node_modules/* 2>/dev/null
```

## Execution Steps

1. Check current disk usage: `df -h /`
2. Run Phase 1 commands (always)
3. Check if space was freed — if yes and enough, stop here
4. Run Phase 2 commands
5. If more space is still needed, complete the Phase 3 read-only scan, risk
   disclosure, and explicit approval gate above
6. Run only the approved Phase 3 targets; otherwise stop cleanup after Phase 2
7. Final disk check: `df -h /`
8. Report before/after free space, executed phases, skipped targets, and errors
   to the user
9. If disk was over 80% full, recommend running Phases 1 and 2 at session start

## When Disk Is Completely Full (Deadlock)

If even Phase 1 Bash commands fail with ENOSPC:

**In Claude Code:** Suggest the user exit and restart Claude Code. The
sandbox environment resets on restart.

**In Cowork — important architecture note:**

Cowork has **two separate disks** that fill independently:

1. **Mac filesystem** (mounted as `/sessions/.../mnt/`) — the user's actual
   folder on their computer. Has lots of free space typically.
2. **VM internal disk** (everything else: `/tmp`, `~/.cache`, `/var/cache/apt`,
   etc.) — a fixed-size overlay filesystem. This is what hits ENOSPC.

When Bash is broken, try these in order:

**Step 1 — Optionally inspect the Mac-side workspace:**
If Desktop Commander is installed and available, it can inspect the Mac host
workspace. Treat it as an optional integration, not a required recovery path.
Do not delete anything through it without showing the exact paths and obtaining
the same Phase 3 confirmation described above. A common candidate is:
```
rm -rf "/Users/<username>/Documents/Claude/<project>/node_modules"
```
Find the real Mac path via `mcp__Desktop_Commander__start_process` with
`du -sh ~/Documents/Claude/**/node_modules 2>/dev/null | sort -rh | head`.
Note: Desktop Commander **cannot** reach VM-internal paths like `/var/cache/apt/`.

**Step 2 — Scan VM internal disk with Glob:**
Glob can read VM-internal paths even when Bash is broken. Scan for large
caches: `/var/cache/apt/archives/**`, `/tmp/**`, `~/.cache/**`.

**Step 3 — `allow_cowork_file_delete` scope:**
This tool only enables deletion for paths inside the mounted user workspace
(the `mnt/` folder). It cannot grant access to VM-internal system paths.

**Step 4 — If VM internal disk is the problem:**
There is no way to clean the VM's internal disk (apt cache, pip cache, npm
cache) from outside the VM when Bash is broken, Docker is not installed on
the Mac, and Desktop Commander cannot reach those paths.
**Recommend fully quitting Claude Desktop/Cowork and reopening it** — closing
only the window or conversation may not replace the VM. A fresh VM is expected
to be blank: all VM-internal packages, caches, tools, and unsaved files are
lost. Mounted user-workspace files are expected to persist, but the user should
verify that important files are mounted before relying on this recovery path.

## Prevention Tips

Share these with the user when relevant:
- Run cleanup before heavy installs (`npm install`, `pip install`, `apt install`)
- Use `pip install --no-cache-dir` to avoid caching
- Remove `node_modules` from old projects before starting new ones
- For recurring maintenance, pair with a scheduled task that runs every 2 hours
- In Cowork, the VM internal disk is the bottleneck — the Mac disk rarely fills up
