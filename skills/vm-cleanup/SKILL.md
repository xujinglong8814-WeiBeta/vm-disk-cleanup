---
name: vm-cleanup
description: >
  Clean up disk space in a Claude Desktop Cowork session VM. Use this skill
  when the user says "clean VM",
  "clean disk", "free disk space", "disk full", "ENOSPC", "no space left",
  "clean session", "session cleanup", "disk cleanup", or when Bash commands
  fail with disk-full errors. Also use proactively before heavy operations
  like npm install or pip install in long sessions.
metadata:
  version: "0.3.0"
  platforms: ["cowork"]
---

# VM / Session Disk Cleanup

Recover from or prevent disk-full situations in Claude's working environment.

## Context

Cowork session VMs have limited internal disk space. Long sessions with package
installs, builds, and cached data can fill the disk completely. When full, ALL
Bash commands fail with ENOSPC errors
because the shell can't create temp files — a deadlock where you can't
even diagnose the problem.

## Cleanup Strategy

Run cleanups in phases — smallest operations first so they succeed even
when disk is critically low.

### Mandatory disclosure before Phases 1 and 2

Before executing cleanup, tell the user which phase is about to run and that
it performs real deletion. Do not describe any phase as risk-free or lossless.

- Explain that Phases 1 and 2 may run after an ENOSPC trigger or on a schedule
  without the Phase 3 confirmation.
- Disclose that the VM-internal portions of `/sessions` can contain matches
  from other sessions or projects. Mounted `/sessions/*/mnt` host-workspace
  trees are excluded and must never be deletion targets.
- Disclose that the `/tmp` patterns can remove temporary files or logs used by
  active processes.
- Disclose that purging pip, npm, and APT caches can require later downloads
  and may slow or block reinstalls when network access is unavailable.
- State that commands using `2>/dev/null` are best-effort. Do not claim every
  target was removed when individual errors were suppressed.

This disclosure does not replace the Phase 3 approval gate below.

### Phase 1: Emergency (needs almost zero free space)
Run these first when disk is completely full or nearly full:

```bash
# Remove Python bytecode (tiny files, frees inodes)
find -P /sessions \( -path '/sessions/*/mnt' -o -path '/sessions/*/mnt/*' \) -prune -o -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null
find -P /sessions \( -path '/sessions/*/mnt' -o -path '/sessions/*/mnt/*' \) -prune -o -type f -name '*.pyc' -delete 2>/dev/null
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
2. Ask no user to discover candidates manually. Identify the absolute directory
   containing this loaded `SKILL.md` from the path Cowork used to read it. The
   required bundled scanner is the direct child `scripts/p3-plan.sh` of that
   skill directory. Do not assume Claude Code's plugin `bin` PATH or
   `${CLAUDE_PLUGIN_ROOT}`, and do not search for, download, reconstruct, or
   substitute a missing scanner. If the bundled file cannot be read, close the
   gate.
3. Determine the current mounted user-workspace root below
   `/sessions/<session>/mnt/`, create a new audit filename below
   `<workspace>/.vm-disk-cleanup/audit/`, and invoke the scanner by its absolute
   path: `bash "/absolute/skill-dir/scripts/p3-plan.sh" --workspace-root
   "/sessions/<session>/mnt/<workspace>" --manifest
   "/absolute/workspace/.vm-disk-cleanup/audit/p3-candidates-<UTC>.tsv"`.
   The scanner checks only VM-internal portions of `/sessions` plus VM-internal
   global npm-package directories. It prunes every `/sessions/*/mnt` host mount
   and never scans the mounted workspace as a deletion-candidate root.
4. Show the user the complete candidate table in the conversation, together
   with the manifest's absolute path and SHA-256. Do not replace the table with
   a summary, top-N list, wildcard, directory count, or instructions to inspect
   the file themselves. An empty table is valid and means there is nothing to
   approve.
5. Treat any scanner error, `scan_complete: false`, `SIZE_ERROR`, missing
   manifest, manifest outside the workspace, or inability to compute its
   SHA-256 as a closed gate. Report the problem and do not request or accept
   Phase 3 confirmation. Do not hide scan errors.
6. Warn the user that:
   - `node_modules` will require dependency reinstallation;
   - `.next`, `dist`, and `build` may contain outputs that are not reproducible
     unless the project and its inputs are preserved;
   - `~/.npm-global/lib/node_modules/*` removes globally installed CLI tools,
     not cache, and the original package list may be difficult to reconstruct;
   - if the Cowork VM becomes unusable, fully quit Claude Desktop/Cowork and
     reopen it to provision a fresh blank VM. All VM-internal state should be
     treated as lost; only files confirmed to be in the mounted user workspace
     should be expected to persist.
7. Ask the user to reply exactly `CONFIRM PHASE 3 CLEANUP` and name the target
   categories they approve. Include the manifest SHA-256 in the confirmation
   prompt. A confirmation applies only to the paths shown in that prompt, that
   exact manifest hash, and the current cleanup run.
8. If the user does not provide that confirmation, declines, or changes the
   target list, stop before Phase 3. Never infer approval from the original
   cleanup request or from approval of Phases 1 and 2.

After confirmation, re-compute the manifest SHA-256 and stop if it changed.
Execute only the approved canonical paths listed in that manifest; do not
re-run broad `find ... -exec rm` or wildcard deletion commands. Global npm
packages must be explicitly named as an approved category; otherwise skip all
`global-npm-package` entries.

Reject every path at or below `/sessions/*/mnt` even if it somehow appears in a
manifest or confirmation. Cowork's mounted workspace is host data, not
disposable VM-internal state, and this skill never authorizes deleting it.

For each approved manifest entry, first verify that the path still exists, is
not a symbolic link, resolves to the exact recorded canonical path, and retains
the recorded basename/category relationship. If any check fails, skip that
entry and report it; do not substitute a parent, child, glob, or newly found
path. Record the result for every listed entry in the completion report.

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

When reporting, label results as best-effort if a command suppressed errors.
Never report complete success solely because a command returned no visible
error.

## When Disk Is Completely Full (Deadlock)

If even Phase 1 Bash commands fail with ENOSPC:

**Cowork architecture note:**

Cowork has **two separate disks** that fill independently:

1. **Mac filesystem** (mounted as `/sessions/.../mnt/`) — the user's actual
   folder on their computer. Has lots of free space typically.
2. **VM internal disk** (everything else: `/tmp`, `~/.cache`, `/var/cache/apt`,
   etc.) — a fixed-size overlay filesystem. This is what hits ENOSPC.

When Bash is broken, try these in order:

**Step 1 — Optionally inspect the Mac-side workspace (read-only):**
If Desktop Commander is installed and available, it can inspect the Mac host
workspace. Treat it as an optional integration, not a required recovery path.
This skill does not authorize or provide any host-side deletion command.
Only perform read-only inspection. Find likely space consumers via
`mcp__Desktop_Commander__start_process` with
`du -sh ~/Documents/Claude/**/node_modules 2>/dev/null | sort -rh | head`.
Note: Desktop Commander **cannot** reach VM-internal paths like `/var/cache/apt/`.

Host-side deletion, if implemented by a future separate workflow, must never
reuse scheduled-cleanup or VM Phase 3 authorization. It must accept exactly one
canonical absolute path, reject globs, relative paths, and symbolic links, show
the path's `du -sh` result, real path, and mount root, then require the user to
enter `CONFIRM HOST DELETE /absolute/path <plan-sha256>`. No such host-delete
workflow is implemented or authorized by this skill.

**Step 2 — Scan VM internal disk with Glob:**
Glob can read VM-internal paths even when Bash is broken. Scan for large
caches: `/var/cache/apt/archives/**`, `/tmp/**`, `~/.cache/**`.

**Step 3 — Do not request mounted-workspace deletion permission:**
Do not use `allow_cowork_file_delete` or any equivalent permission to delete
mounted user-workspace paths. Such a permission does not grant access to the
VM-internal apt, pip, npm, or temp paths that this skill is intended to clean.

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
