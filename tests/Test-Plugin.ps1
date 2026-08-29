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

$plugin = Get-Content -Raw -LiteralPath $pluginManifestPath | ConvertFrom-Json
$marketplace = Get-Content -Raw -LiteralPath $marketplacePath | ConvertFrom-Json
$skill = Get-Content -Raw -LiteralPath $skillPath

Assert-True ($plugin.name -eq 'vm-disk-cleanup') 'plugin name must remain stable'
Assert-True ($marketplace.plugins.Count -eq 1) 'marketplace must expose exactly one plugin'
Assert-True ($marketplace.plugins[0].name -eq $plugin.name) 'marketplace and plugin names must match'
Assert-True ($marketplace.plugins[0].version -eq $plugin.version) 'marketplace and plugin versions must match'
Assert-True ($skill -match 'version:\s+"0\.2\.1"') 'skill metadata version must match release version'

$phase3Heading = $skill.IndexOf('### Phase 3: Heavy cleanup (explicit approval required)')
$confirmation = $skill.IndexOf('CONFIRM PHASE 3 CLEANUP')
$firstPhase3Delete = $skill.IndexOf('find /sessions -name "node_modules"')

Assert-True ($phase3Heading -ge 0) 'Phase 3 approval heading is required'
Assert-True ($confirmation -gt $phase3Heading) 'confirmation gate must appear inside Phase 3'
Assert-True ($confirmation -lt $firstPhase3Delete) 'confirmation gate must appear before destructive Phase 3 commands'
Assert-True ($skill -match 'must never run automatically') 'automatic Phase 3 execution must be forbidden'
Assert-True ($skill -match 'fully quitting Claude Desktop/Cowork') 'fresh-VM recovery procedure must be disclosed'
Assert-True ($skill -match 'all VM-internal state should be\s+treated as lost') 'VM-internal data-loss warning must be explicit'
Assert-True ($skill -match 'Global npm\s+packages must be explicitly named') 'global npm packages need target-specific approval'
Assert-True ($skill -match 'Mandatory disclosure before Phases 1 and 2') 'Phase 1 and 2 disclosure is required'
Assert-True ($skill -match '/tmp') 'shared temporary-file scope must be disclosed by the skill'
Assert-True ($skill -match 'active processes') 'active-process risk must be disclosed by the skill'
Assert-True ($skill -match 'best-effort') 'suppressed errors must be reported as best-effort'

$readme = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'README.md')
$license = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'LICENSE')

Assert-True ($readme -match 'Safety warning — read before installing') 'README needs a prominent safety warning'
Assert-True ($readme -match 'Phases 1 and 2 may run automatically') 'README must disclose automatic Phase 1 and 2 deletion'
Assert-True ($readme -match '/tmp/\*\.tmp') 'README must list shared temporary-file targets'
Assert-True ($readme -match 'other sessions or projects') 'README must disclose cross-session and cross-project scope'
Assert-True ($readme -match 'globally installed CLI tools, not\s+cache') 'README must distinguish global packages from cache'
Assert-True ($readme -match 'best-effort') 'README must disclose suppressed-error limits'
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

Write-Host 'PASS: plugin manifests and Phase 3 safety contract are consistent.'
