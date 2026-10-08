param([string]$ModsDirectory = (Join-Path $env:APPDATA 'Balatro\Mods'))
$ErrorActionPreference = 'Stop'
if (Get-Process -Name Balatro -ErrorAction SilentlyContinue) {
    throw 'Please close Balatro before installing Seed Roller.'
}
$source = Join-Path $PSScriptRoot 'SeedRoller'
if (-not (Test-Path -LiteralPath (Join-Path $source 'SeedRoller.json'))) {
    throw 'Extract the entire ZIP first. SeedRoller must be beside this installer.'
}
$modsRoot = [IO.Path]::GetFullPath($ModsDirectory)
$target = [IO.Path]::GetFullPath((Join-Path $modsRoot 'SeedRoller'))
if ([IO.Path]::GetDirectoryName($target) -ne $modsRoot.TrimEnd('\','/')) {
    throw 'Target directory check failed.'
}
New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
if (Test-Path -LiteralPath $target) {
    $backupRoot = Join-Path $env:APPDATA 'Balatro\SeedRoller-backups'
    $backup = Join-Path $backupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup -Recurse
    Write-Host "Previous version backed up to: $backup"
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
    Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
}
Write-Host "Installed: $target"
Write-Host 'Restart Balatro. Start a fresh run and open Options > Seed Roller to choose Jokers and shop range, then start or stop random-run search.'

