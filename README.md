# VM Disk Cleanup

Prevent and recover from disk-full errors in Claude's working environment — both **Cowork** session VMs and **Claude Code** sandboxes.

## Safety warning — read before installing

This plugin performs destructive filesystem cleanup with commands such as
`find ... -delete` and `rm -rf`. It is intended for disposable VM and sandbox
storage, but a matching path can still contain data you care about. Verify all
scopes before using it on any persistent or local filesystem.

- **Phases 1 and 2 may run automatically** after an ENOSPC error and may be
  used by a scheduled cleanup. They do not require the Phase 3 confirmation.
- Phase 1 removes Python bytecode below `/sessions` and the current directory;
  matching directories can belong to other sessions or projects. It also
  removes `/tmp/*.tmp`, `/tmp/*.log`, `/tmp/tmp*`, `/tmp/pip-*`, `/tmp/npm-*`,
  cached APT packages, and runs `apt-get clean`.
- Phase 2 purges the active user's pip and npm caches, including
  `~/.cache/pip` and `~/.npm/_cacache`. Later installs may need network access
  and additional time to rebuild these caches.
- Deleting shared temporary files or logs can disrupt an active process.
  `/sessions` and `.` are scope boundaries, not guarantees that every match is
  safe to remove.
- Several cleanup commands suppress individual errors with `2>/dev/null`.
  A completion report is therefore best-effort and must not be treated as proof
  that every target was removed.
- Keep important files in a verified mounted user workspace or another backup.
  Do not rely on VM-internal storage for the only copy of important data.

Review the target environment before enabling automatic or scheduled cleanup.
Do not install or run this plugin where those deletion scopes are unacceptable.

## The Problem

Long Claude sessions accumulate disk-eating artifacts: npm/pip caches, `node_modules`, Python bytecode, build outputs, and temp files. When the disk fills completely, even basic Bash commands fail with `ENOSPC` errors — creating a deadlock where you can't diagnose or fix the problem.

## What It Does

A 3-phase cleanup that starts with the lightest operations (so they work even when disk is nearly full) and escalates:

| Phase | What it clears | Disk needed | Execution policy |
|-------|----------------|-------------|------------------|
| **1 — Emergency** | Python bytecode, shared temp patterns, apt cache | Almost zero | May run automatically; destructive |
| **2 — Medium** | User pip and npm caches | Minimal | May run automatically; destructive |
| **3 — Heavy** | node_modules, build artifacts, global packages | Some free space | Explicit per-run approval required |

## Phase 3 safety gate

Phase 3 never runs automatically. Before it can run, Claude must show the exact
candidate paths and estimated sizes, explain the reinstall and data-loss risks,
and ask for the exact confirmation phrase `CONFIRM PHASE 3 CLEANUP`. Approval is
valid only for the displayed targets and the current cleanup run. Scheduled
cleanup is limited to Phases 1 and 2.

Phase 3 has additional risks:

- `node_modules` must be recreated with the correct package manager and lockfile.
- `.next`, `dist`, and `build` may contain outputs that cannot be reproduced if
  their source inputs or toolchain are missing.
- `~/.npm-global/lib/node_modules/*` contains globally installed CLI tools, not
  cache. That category must be named explicitly in the approval request and
  may be impossible to reconstruct without a prior package inventory.
- No reply, a refusal, or any change to the displayed target list means Phase 3
  must stop and request a new confirmation.

If the Cowork VM is completely unusable, fully quit Claude Desktop/Cowork and
reopen it so Cowork can provision a fresh blank VM. Merely closing a window or
conversation may not replace the VM. Treat every VM-internal package, tool,
cache, and unsaved file as lost. Only files verified to be in the mounted user
workspace should be expected to persist; verify important files before relying
on this recovery path.

## Installation

### Step 1: Add the marketplace (one-time)

**Claude Code (CLI):**
```
/plugin marketplace add xujinglong8814-WeiBeta/vm-disk-cleanup
```

**Cowork (Desktop App):**
Go to **Settings → Plugins → Marketplaces → Add**, and enter
`xujinglong8814-WeiBeta/vm-disk-cleanup`.

This marketplace contains only this plugin.

### Step 2: Install the plugin

**Claude Code:**
```
/plugin install vm-disk-cleanup@vm-disk-cleanup-marketplace
```

**Cowork:**
Go to **Settings → Plugins**, search for **vm-disk-cleanup**, and click **Install**.
## Usage

Just say any of these naturally:

- "clean VM" / "clean disk"
- "disk full" / "no space left"
- "free disk space"
- "session cleanup"

The skill can activate automatically when it detects ENOSPC errors in Bash
output. Automatic activation does not authorize Phase 3, but Phases 1 and 2
still delete the paths listed in the safety warning above.

### Pro tip: Pair with a scheduled task

In **Cowork**, you can set up a scheduled task that runs Phases 1 and 2 every
2 hours to prevent disk-full situations. Do this only after accepting their
deletion scopes and the risk of affecting active processes. A schedule can
never approve Phase 3.

## Setup

No configuration is required, but the safety review above is required before
automatic or scheduled use.

## Requirements

- **Cowork**: Any session (Linux VM with Bash)
- **Claude Code**: Any environment with Bash access

## License

MIT. See [LICENSE](LICENSE) for the complete permission notice, conditions,
and warranty disclaimer.

This derivative is based on MSApps-Mobile/claude-plugins commit
`70eee8673c300b766fec3ec138521594111760bd`.
