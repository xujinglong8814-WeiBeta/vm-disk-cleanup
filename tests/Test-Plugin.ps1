$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$pluginManifestPath = Join-Path $repositoryRoot '.claude-plugin/plugin.json'
$marketplacePath = Join-Path $repositoryRoot '.claude-plugin/marketplace.json'
$skillPath = Join-Path $repositoryRoot 'skills/vm-cleanup/SKILL.md'
$planPath = Join-Path $repositoryRoot 'skills/vm-cleanup/scripts/p3-plan.sh'

$plugin = Get-Content -Raw -LiteralPath $pluginManifestPath | ConvertFrom-Json
$marketplace = Get-Content -Raw -LiteralPath $marketplacePath | ConvertFrom-Json
$skill = Get-Content -Raw -LiteralPath $skillPath
$plan = Get-Content -Raw -LiteralPath $planPath

Assert-True ($plugin.name -eq 'vm-disk-cleanup') 'plugin name must remain stable'
Assert-True ($marketplace.plugins.Count -eq 1) 'marketplace must expose exactly one plugin'
Assert-True ($marketplace.plugins[0].name -eq $plugin.name) 'marketplace and plugin names must match'
Assert-True ($marketplace.plugins[0].version -eq $plugin.version) 'marketplace and plugin versions must match'
Assert-True ($plugin.version -eq '0.3.0') 'plugin version must match release version'
Assert-True ($skill -match 'version:\s+"0\.3\.0"') 'skill metadata version must match release version'
Assert-True (($plugin.platforms.Count -eq 1) -and ($plugin.platforms[0] -eq 'cowork')) 'plugin must be Cowork-only'

$phase3Heading = $skill.IndexOf('### Phase 3: Heavy cleanup (explicit approval required)')
$confirmation = $skill.IndexOf('CONFIRM PHASE 3 CLEANUP')
$firstPhase3Execution = $skill.IndexOf('After confirmation, re-compute the manifest SHA-256')

Assert-True ($phase3Heading -ge 0) 'Phase 3 approval heading is required'
Assert-True ($confirmation -gt $phase3Heading) 'confirmation gate must appear inside Phase 3'
Assert-True ($confirmation -lt $firstPhase3Execution) 'confirmation gate must appear before Phase 3 execution instructions'
Assert-True ($skill -match 'must never run automatically') 'automatic Phase 3 execution must be forbidden'
Assert-True ($skill -match 'fully quitting Claude Desktop/Cowork') 'fresh-VM recovery procedure must be disclosed'
Assert-True ($skill -match 'all VM-internal state should be\s+treated as lost') 'VM-internal data-loss warning must be explicit'
Assert-True ($skill -match 'Global npm\s+packages must be explicitly named') 'global npm packages need target-specific approval'
Assert-True ($skill -match 'Mandatory disclosure before Phases 1 and 2') 'Phase 1 and 2 disclosure is required'
Assert-True ($skill -match '/tmp') 'shared temporary-file scope must be disclosed by the skill'
Assert-True ($skill -match 'active processes') 'active-process risk must be disclosed by the skill'
Assert-True ($skill -match 'best-effort') 'suppressed errors must be reported as best-effort'
Assert-True ($skill -match 'Ask no user to discover candidates manually') 'the agent must discover Phase 3 candidates'
Assert-True ($skill -match 'Show the user the complete candidate table') 'the complete Phase 3 candidate table must be displayed'
Assert-True ($skill -match 'scan_complete: false') 'incomplete scans must close the Phase 3 gate'
Assert-True ($skill -match 're-compute the manifest SHA-256') 'manifest integrity must be checked before deletion'
Assert-True ($skill -notmatch 'rm -rf\s+"/Users/') 'host-side deletion examples are forbidden'
Assert-True ($skill -match 'does not authorize or provide any host-side deletion command') 'host deletion must be explicitly disallowed'
Assert-True ($skill -match 'prunes every `/sessions/\*/mnt` host mount') 'P3 discovery must prune mounted host workspaces'
Assert-True ($skill -notmatch '(?m)^find \.') 'the current directory must not be a cleanup root'

Assert-True (Test-Path -LiteralPath $planPath -PathType Leaf) 'the Phase 3 read-only scanner is required'
Assert-True ($plan -match 'find -P') 'the scanner must not follow symbolic links during discovery'
Assert-True ($plan -match "-path '/sessions/\*/mnt'") 'the scanner must prune Cowork host mounts'
Assert-True ($plan -match 'Mounted host-workspace candidate refused') 'mounted candidates need a fail-closed check'
Assert-True ($plan -match 'canonical_path') 'the scanner must emit canonical paths'
Assert-True ($plan -match 'size_bytes') 'the scanner must emit candidate sizes'
Assert-True ($plan -match 'scan_complete') 'the scanner must record scan completeness'
Assert-True ($plan -match "printf 'SHA-256: %s") 'the scanner must display the manifest hash'
Assert-True ($plan -match "exit 2") 'an incomplete scan must return a blocking status'
Assert-True ($plan -notmatch 'rm -rf') 'the Phase 3 scanner must remain read-only with respect to candidates'

$readme = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'README.md')
$license = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'LICENSE')
$gitignore = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot '.gitignore')

Assert-True ($readme -match 'Safety warning — read before installing') 'README needs a prominent safety warning'
Assert-True ($readme -match 'Only for Claude Desktop Cowork') 'README must declare its only supported application and mode'
Assert-True ($readme -match 'Claude Code and unrestricted local-shell environments are explicitly outside') 'README must exclude Claude Code support'
Assert-True ($readme -match 'Phases 1 and 2 may run automatically') 'README must disclose automatic Phase 1 and 2 deletion'
Assert-True ($readme -match '/tmp/\*\.tmp') 'README must list shared temporary-file targets'
Assert-True ($readme -match 'other sessions or projects') 'README must disclose cross-session and cross-project scope'
Assert-True ($readme -match 'globally installed CLI tools, not\s+cache') 'README must distinguish global packages from cache'
Assert-True ($readme -match 'best-effort') 'README must disclose suppressed-error limits'
Assert-True ($readme -match 'must not ask you to locate candidates') 'README must promise agent-generated candidate discovery'
Assert-True ($readme -match 'complete candidate list') 'README must describe the P3 audit manifest'
Assert-True ($readme -match 'This plugin contains no host-side delete') 'README must prohibit host deletion'
Assert-True ($readme -match 'CONFIRM HOST DELETE /absolute/path <plan-sha256>') 'README must document the separate future host-delete gate'
Assert-True ($gitignore -match '\.vm-disk-cleanup/audit/') 'runtime audit manifests must be excluded from source control'
Assert-True ($readme -match 'warranty disclaimer') 'README must link the full MIT terms'
Assert-True ($readme -notmatch '(?i)private marketplace|private repository|private derivative') 'public README must not claim the repository is private'
Assert-True ($marketplace.name -eq 'vm-disk-cleanup-marketplace') 'public marketplace name must be stable'
Assert-True ($marketplace.metadata.description -notmatch '(?i)private') 'marketplace description must not claim private status'
Assert-True ($plugin.description -match '(?i)destructive') 'plugin listing must disclose destructive behavior'
Assert-True ($marketplace.metadata.description -match '(?i)destructive') 'marketplace listing must disclose destructive behavior'
Assert-True ($null -eq $plugin.privacy_policy) 'unrelated upstream privacy policy must not be published as this fork policy'
Assert-True ($null -eq $plugin.terms_of_service) 'unrelated upstream terms must not be published as this fork terms'
Assert-True ($license -match 'MIT License') 'full MIT license text is required'
Assert-True ($license -match 'Copyright \(c\) 2026 MSApps') 'upstream copyright notice must be preserved'

Write-Host 'PASS: plugin manifests, read-only P3 planning, and safety contracts are consistent.'
