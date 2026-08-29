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
Assert-True ($marketplace.plugins.Count -eq 1) 'private marketplace must expose exactly one plugin'
Assert-True ($marketplace.plugins[0].name -eq $plugin.name) 'marketplace and plugin names must match'
Assert-True ($marketplace.plugins[0].version -eq $plugin.version) 'marketplace and plugin versions must match'
Assert-True ($skill -match 'version:\s+"0\.2\.0"') 'skill metadata version must match release version'

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

Write-Host 'PASS: plugin manifests and Phase 3 safety contract are consistent.'
