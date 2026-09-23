[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [switch]$LaunchSmokeTest
)

$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $PackagePath).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("LiquidTodo-portable-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null

try {
    Expand-Archive -LiteralPath $package -DestinationPath $root -Force
    $required = @('LiquidTodo.exe', 'LiquidTodo.dll', 'LiquidTodo.runtimeconfig.json', 'LiquidTodo.deps.json', 'Assets/LiquidTodo.ico', 'Assets/LiquidTodo.png', 'Assets/LiquidGlassPanel.png', 'portable.flag', 'README-Windows.txt', 'LICENSE', 'manifest.json')
    foreach ($file in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)) { throw "Portable ZIP is missing $file" }
    }

    $forbidden = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
        $_.Name -match '^(data|settings)\.json$' -or $_.Extension -in '.log', '.pdb' -or $_.FullName -match '[\\/]Backups[\\/]'
    }
    if ($forbidden) { throw "Portable ZIP contains local or debug data: $($forbidden.FullName -join ', ')" }

    $manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($file in $manifest.files) {
        $path = Join-Path $root $file.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Manifest file missing: $($file.path)" }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $file.sha256) { throw "Manifest checksum mismatch: $($file.path)" }
    }

    if ($LaunchSmokeTest) {
        $process = Start-Process -FilePath (Join-Path $root 'LiquidTodo.exe') -ArgumentList @('--safe-mode', '--diagnostics') -PassThru
        try {
            Start-Sleep -Seconds 7
            $process.Refresh()
            if ($process.HasExited) {
                $logs = Get-ChildItem -LiteralPath (Join-Path $root 'Data\Logs') -Filter 'startup-*.log' -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
                throw "Portable process exited during launch smoke test. $($logs -join "`n")"
            }
        }
        finally {
            if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
        }
    }

    Write-Host "Portable package verification passed: $package"
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
