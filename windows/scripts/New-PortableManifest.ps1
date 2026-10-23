[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PublishDirectory,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [Parameter(Mandatory = $true)][string]$Version
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $PublishDirectory).Path
$required = @('LiquidTodo.exe', 'LiquidTodo.dll', 'LiquidTodo.runtimeconfig.json', 'LiquidTodo.deps.json', 'Assets/LiquidTodo.ico', 'Assets/LiquidTodo.png', 'portable.flag', 'README-Windows.txt', 'LICENSE')
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)) {
        throw "Portable publish is missing required file: $file"
    }
}

$runtimeConfig = Get-Content -LiteralPath (Join-Path $root 'LiquidTodo.runtimeconfig.json') -Raw | ConvertFrom-Json
if ($runtimeConfig.runtimeOptions.tfm -notlike 'net8.0*') { throw 'Portable publish did not contain the expected .NET 8 runtime configuration.' }

$files = Get-ChildItem -LiteralPath $root -File -Recurse |
    Where-Object { $_.Name -ne (Split-Path -Leaf $OutputFile) } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        [ordered]@{
            path = $relative
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

$manifest = [ordered]@{
    formatVersion = 1
    product = 'LiquidTodo'
    version = $Version
    runtime = 'win-x64 self-contained'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    files = @($files)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputFile -Encoding utf8NoBOM
