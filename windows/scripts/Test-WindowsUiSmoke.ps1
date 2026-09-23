param([Parameter(Mandatory = $true)][string]$ExecutablePath)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$exe = (Resolve-Path -LiteralPath $ExecutablePath).Path
$root = [System.Windows.Automation.AutomationElement]::RootElement
$descendants = [System.Windows.Automation.TreeScope]::Descendants
$children = [System.Windows.Automation.TreeScope]::Children
$all = [System.Windows.Automation.Condition]::TrueCondition
$process = $null

function Get-Window([string]$name) {
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    return $script:root.FindFirst($script:children, $condition)
}

function Wait-Window([string]$name, [int]$timeoutSeconds = 15) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $window = Get-Window $name
        if ($window) { return $window }
        Start-Sleep -Milliseconds 250
    } while ($timer.Elapsed.TotalSeconds -lt $timeoutSeconds)
    $openWindows = @()
    $topLevel = $script:root.FindAll($script:children, $script:all)
    for ($i = 0; $i -lt $topLevel.Count; $i++) {
        try { $openWindows += $topLevel.Item($i).Current.Name }
        catch { }
    }
    throw "Timed out waiting for window '$name'. Open top-level UIA windows: $($openWindows -join ' | ')"
}

function Find-WindowContainingElementId([string]$automationId) {
    $windows = $script:root.FindAll($script:children, $script:all)
    for ($i = 0; $i -lt $windows.Count; $i++) {
        $window = $windows.Item($i)
        if (Find-ElementById $window $automationId) { return $window }
    }
    return $null
}

function Wait-WindowContainingElementId([string]$automationId, [int]$timeoutSeconds = 15) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $window = Find-WindowContainingElementId $automationId
        if ($window) { return $window }
        Start-Sleep -Milliseconds 250
    } while ($timer.Elapsed.TotalSeconds -lt $timeoutSeconds)
    throw "Timed out waiting for a window containing AutomationId '$automationId'."
}

function Find-ElementById($window, [string]$automationId) {
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $automationId)
    return $window.FindFirst($script:descendants, $condition)
}

function Wait-ElementById($window, [string]$automationId, [int]$timeoutSeconds = 10) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $element = Find-ElementById $window $automationId
        if ($element) { return $element }
        Start-Sleep -Milliseconds 200
    } while ($timer.Elapsed.TotalSeconds -lt $timeoutSeconds)
    throw "Timed out waiting for AutomationId '$automationId'."
}

function Find-ElementByName($window, [string]$name, [System.Windows.Automation.ControlType]$controlType) {
    $elements = $window.FindAll($script:descendants, $script:all)
    for ($i = 0; $i -lt $elements.Count; $i++) {
        $element = $elements.Item($i)
        try {
            if ($element.Current.ControlType -eq $controlType -and $element.Current.Name -eq $name) { return $element }
        }
        catch { }
    }
    return $null
}

function Wait-ElementByName($window, [string]$name, [System.Windows.Automation.ControlType]$controlType, [int]$timeoutSeconds = 10) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $element = Find-ElementByName $window $name $controlType
        if ($element) { return $element }
        Start-Sleep -Milliseconds 200
    } while ($timer.Elapsed.TotalSeconds -lt $timeoutSeconds)
    throw "Timed out waiting for $controlType '$name'."
}

function Invoke-Button($element) {
    $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Set-Text($element, [string]$value) {
    $pattern = $element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    if ($pattern.Current.IsReadOnly) { throw "Text field '$($element.Current.AutomationId)' is read-only." }
    $pattern.SetValue($value)
}

function Wait-Text($window, [string]$value, [bool]$shouldExist = $true, [int]$timeoutSeconds = 10) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $elements = $window.FindAll($script:descendants, $script:all)
        $found = $false
        for ($i = 0; $i -lt $elements.Count; $i++) {
            try { if ($elements.Item($i).Current.Name -eq $value) { $found = $true; break } }
            catch { }
        }
        if ($found -eq $shouldExist) { return }
        Start-Sleep -Milliseconds 200
    } while ($timer.Elapsed.TotalSeconds -lt $timeoutSeconds)
    throw "Expected text '$value' existence=$shouldExist was not reached."
}

try {
    # This runs only against a fresh temporary extraction of the Portable package.
    $process = Start-Process -FilePath $exe -ArgumentList @('--portable', '--diagnostics') -PassThru
    Start-Sleep -Seconds 1
    $process.Refresh()
    if ($process.HasExited) {
        $logRoot = Join-Path (Split-Path $exe) 'Data\Logs'
        $logs = Get-ChildItem -LiteralPath $logRoot -Filter 'startup-*.log' -ErrorAction SilentlyContinue |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        throw "Application exited before the first-run window appeared. $($logs -join "`n")"
    }

    # Some Windows hosted-runner UIA providers expose owned WPF dialogs with an
    # empty Window.Name. Find those by their stable control AutomationId instead.
    $welcome = Wait-WindowContainingElementId 'OwnerNameInput'
    Set-Text (Wait-ElementById $welcome 'OwnerNameInput') 'Windows验收'
    Invoke-Button (Wait-ElementByName $welcome '保存' ([System.Windows.Automation.ControlType]::Button))

    $settingsPath = Join-Path (Split-Path $exe) 'Data\settings.json'
    $settingsTimer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $settings = if (Test-Path -LiteralPath $settingsPath) { Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json } else { $null }
        if ($settings -and $settings.OwnerName -eq 'Windows验收') { break }
        Start-Sleep -Milliseconds 200
    } while ($settingsTimer.Elapsed.TotalSeconds -lt 10)
    if (-not $settings -or $settings.OwnerName -ne 'Windows验收') {
        $localSettings = Join-Path $env:LOCALAPPDATA 'LiquidTodo\settings.json'
        $files = Get-ChildItem -LiteralPath (Split-Path $exe) -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        $logRoot = Join-Path (Split-Path $exe) 'Data\Logs'
        $logs = Get-ChildItem -LiteralPath $logRoot -Filter 'startup-*.log' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        throw "First-run name was not saved to portable settings. Portable content: $($settings | ConvertTo-Json -Compress); local settings: $(if (Test-Path $localSettings) { Get-Content $localSettings -Raw } else { '<missing>' }); files: $($files -join ' | '); startup logs: $($logs -join ' | ')"
    }

    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Invoke-Button (Wait-ElementById $main 'AddTodoButton')
    $editor = Wait-WindowContainingElementId 'TodoTextBox'
    Set-Text (Wait-ElementById $editor 'TodoTextBox') 'Windows 中文输入与编辑验收'
    Invoke-Button (Wait-ElementByName $editor '保存' ([System.Windows.Automation.ControlType]::Button))
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main 'Windows 中文输入与编辑验收'

    Invoke-Button (Wait-ElementByName $main '编辑待办' ([System.Windows.Automation.ControlType]::Button))
    $editor = Wait-WindowContainingElementId 'TodoTextBox'
    Set-Text (Wait-ElementById $editor 'TodoTextBox') 'Windows 中文输入编辑完成'
    Invoke-Button (Wait-ElementByName $editor '保存' ([System.Windows.Automation.ControlType]::Button))
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main 'Windows 中文输入编辑完成'
    Wait-Text $main 'Windows 中文输入与编辑验收' $false

    $checkbox = $main.FindFirst($script:descendants,
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::CheckBox))
    if (-not $checkbox) { throw 'The todo completion checkbox was not exposed to UI Automation.' }
    $checkbox.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Invoke-Button (Wait-ElementByName $main '已完成 · 撤销' ([System.Windows.Automation.ControlType]::Button))
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main 'Windows 中文输入编辑完成'

    Stop-Process -Id $process.Id -Force
    $process = $null
    Start-Sleep -Seconds 1

    $process = Start-Process -FilePath $exe -ArgumentList @('--safe-mode', '--diagnostics', '--portable') -PassThru
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main 'Windows 中文输入编辑完成'

    Write-Host 'Windows UI smoke passed: first-run naming, CJK text entry, add/edit, completion undo and restart persistence.'
}
finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
}
