[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$InstallerPath)

$ErrorActionPreference = 'Stop'
$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("LiquidTodo-installer-" + [Guid]::NewGuid().ToString('N'))
$installDir = Join-Path $root 'app'
$appProcess = $null
New-Item -ItemType Directory -Path $root | Out-Null

try {
    $setup = Start-Process -FilePath $installer -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
        "/DIR=$installDir", '/TASKS=autostart'
    ) -Wait -PassThru
    if ($setup.ExitCode -ne 0) { throw "Setup exited with code $($setup.ExitCode)." }

    $exe = Join-Path $installDir 'LiquidTodo.exe'
    $assets = Join-Path $installDir 'Assets'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Setup did not install LiquidTodo.exe.' }
    if (-not (Test-Path -LiteralPath (Join-Path $assets 'LiquidGlassPanel.png') -PathType Leaf)) { throw 'Setup omitted the glass panel asset.' }
    if (-not (Test-Path -LiteralPath (Join-Path $assets 'LiquidTodo.ico') -PathType Leaf)) { throw 'Setup omitted the tray icon.' }

    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runValue = (Get-ItemProperty -LiteralPath $runKey -Name LiquidTodo -ErrorAction Stop).LiquidTodo
    if ($runValue -notmatch [regex]::Escape($exe) -or $runValue -notmatch '--autostart') {
        throw "The requested login-start task was not registered correctly: $runValue"
    }

    $appProcess = Start-Process -FilePath $exe -ArgumentList @('--safe-mode', '--diagnostics', '--portable') -PassThru
    Start-Sleep -Seconds 7
    $appProcess.Refresh()
    if ($appProcess.HasExited) {
        $logs = Get-ChildItem -LiteralPath (Join-Path $installDir 'Data\Logs') -Filter 'startup-*.log' -ErrorAction SilentlyContinue |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        throw "Installed app exited during launch smoke test. $($logs -join "`n")"
    }
    Stop-Process -Id $appProcess.Id -Force
    $appProcess = $null

    $uninstaller = Join-Path $installDir 'unins000.exe'
    if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) { throw 'Setup did not install its uninstaller.' }
    $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) { throw "Uninstaller exited with code $($uninstall.ExitCode)." }
    if (Get-ItemProperty -LiteralPath $runKey -Name LiquidTodo -ErrorAction SilentlyContinue) {
        throw 'Uninstaller left the LiquidTodo autostart registry value behind.'
    }

    Write-Host 'Setup install, installed launch, login-start registration and uninstall smoke tests passed.'
}
finally {
    if ($appProcess -and -not $appProcess.HasExited) { Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
