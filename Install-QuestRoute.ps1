param(
    [string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'QuestRoute')).Path
$parent = (Resolve-Path -LiteralPath $AddOnsPath).Path
if ((Split-Path -Leaf $parent) -ne 'AddOns') {
    throw 'Choose the existing Interface\AddOns directory for the Forever client.'
}
$destination = Join-Path $parent 'QuestRoute'
$files = @('QuestRoute.toc', 'Model.lua', 'Data.lua', 'UI.lua', 'Core.lua', 'README.md')
foreach ($name in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) {
        throw "Missing source file: $name"
    }
}
if (Test-Path -LiteralPath $destination) {
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'QuestRoute.toc') -PathType Leaf)) {
        throw 'The destination already exists and does not appear to be QuestRoute. No files changed.'
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupRoot = Join-Path $PSScriptRoot 'dist\backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $backup = Join-Path $backupRoot "QuestRoute-$stamp"
    Copy-Item -LiteralPath $destination -Destination $backup -Recurse
    Write-Output "Backed up existing addon to $backup"
} else {
    New-Item -ItemType Directory -Path $destination | Out-Null
}
foreach ($name in $files) {
    $from = Join-Path $source $name
    $to = Join-Path $destination $name
    Copy-Item -LiteralPath $from -Destination $to -Force
    if ((Get-FileHash -LiteralPath $from).Hash -ne (Get-FileHash -LiteralPath $to).Hash) {
        throw "Verification failed for $name"
    }
}
Write-Output "Installed and verified $($files.Count) files in $destination"
Write-Output 'Enable QuestRoute in WoW. Restart if the new addon is not listed. Use /qr to open the planner, or /qr test to preview sample quests.'
