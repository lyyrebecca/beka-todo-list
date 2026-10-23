param([Parameter(Mandatory = $true)][string]$ExecutablePath)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class UiPointer {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder name, int size);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
}
'@
[UiPointer]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

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
        if ($script:process -and $window.Current.ProcessId -ne $script:process.Id) { continue }
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
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke(); return
    }
    # Native MessageBox buttons can be exposed as Pane peers on hosted runners.
    # Target an observed real Button HWND rather than a rectangle sampled while
    # Windows is still positioning a newly opened dialog. Orb/handle tests below
    # continue to use actual mouse down/move/up without this fallback.
    $handle=[IntPtr]$element.Current.NativeWindowHandle
    if($handle -ne [IntPtr]::Zero) {
        $class=[Text.StringBuilder]::new(256)
        [UiPointer]::GetClassName($handle,$class,$class.Capacity) | Out-Null
        if($class.ToString() -eq 'Button') {
            $dialogButtonId=$element.Current.AutomationId
            [UiPointer]::SetForegroundWindow([UiPointer]::GetAncestor($handle,2)) | Out-Null
            $result=[IntPtr]::Zero
            if([UiPointer]::SendMessageTimeout($handle,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero,2,3000,[ref]$result) -eq [IntPtr]::Zero) { throw 'Observed native dialog button did not acknowledge BM_CLICK.' }
            Write-Host "Native dialog activation: ID=$dialogButtonId"
            return
        }
    }
    # Use the observed visible rectangle and real pointer input, then verify data.
    $rect=$element.Current.BoundingRectangle
    if ($element.Current.IsOffscreen -or $rect.Width -le 0 -or $rect.Height -le 0) { throw 'Control has no visible click rectangle.' }
    [UiPointer]::SetCursorPos([int]($rect.X+$rect.Width/2),[int]($rect.Y+$rect.Height/2)) | Out-Null
    [UiPointer]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    [UiPointer]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
}

function Assert-InitialKeyboardFocus($window, [string]$id) {
    # MUST run before Set-Text/SetFocus: those helpers would hide a first-open bug.
    # This checks real keyboard focus, NOT Chinese IME composition/candidates.
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $field = Find-ElementById $window $id
        if ($field -and $field.Current.HasKeyboardFocus) {
            Write-Host "Initial keyboard focus passed without UIA SetFocus: $id"
            return
        }
        Start-Sleep -Milliseconds 100
    } while ($clock.Elapsed.TotalSeconds -lt 5)
    $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
    throw "First-open keyboard focus missing: $id; actual=$($focused.Current.AutomationId) / $($focused.Current.ControlType.ProgrammaticName)"
}

function Set-Text($element, [string]$value) {
    $pattern = $null
    if (-not $element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        $condition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
        $edit = $element.FindFirst($script:descendants, $condition)
        if (-not $edit -or -not $edit.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) { throw "No editable ValuePattern for $($element.Current.AutomationId) / $($element.Current.ClassName)." }
        $element = $edit
    }
    $element.SetFocus()
    if ($pattern.Current.IsReadOnly) { throw "Text field '$($element.Current.AutomationId)' is read-only." }
    $pattern.SetValue($value)
}

function Select-Combo($window, [string]$id, [string]$itemName) {
    $combo = Wait-ElementById $window $id
    $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty, $itemName),
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem),
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $script:process.Id))
    $item = $null
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $matches = $script:root.FindAll($script:descendants, $condition)
        for ($i=0; $i -lt $matches.Count; $i++) {
            $candidate = $matches.Item($i)
            if (-not $candidate.Current.IsOffscreen -and $candidate.Current.BoundingRectangle.Width -gt 0) { $item=$candidate; break }
        }
        if (-not $item) { Start-Sleep -Milliseconds 100 }
    } while (-not $item -and $timer.Elapsed.TotalSeconds -lt 5)
    if (-not $item) { throw "Combo item '$itemName' was not exposed on screen." }
    $pattern = $null
    if ($item.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern,[ref]$pattern)) { $pattern.Select() }
    else {
        # Explicit XAML ComboBoxItem peers do not always expose SelectionItem.
        # Click the observed popup item and verify persisted values afterwards.
        $rect=$item.Current.BoundingRectangle
        [UiPointer]::SetCursorPos([int]($rect.X+$rect.Width/2),[int]($rect.Y+$rect.Height/2)) | Out-Null
        [UiPointer]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
        [UiPointer]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 100
    }
    $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse()
}
function Wait-MergeButton {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    do {
        $windows=$script:root.FindAll($script:children,$script:all)
        for($i=0; $i -lt $windows.Count; $i++) {
            $window=$windows.Item($i)
            if($window.Current.ProcessId -ne $script:process.Id) { continue }
            $dialogCondition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty, '导入备份')
            $dialog=if($window.Current.Name -eq '导入备份') { $window } else { $window.FindFirst($script:descendants,$dialogCondition) }
            if(-not $dialog) { continue }
            $elements=$dialog.FindAll($script:descendants,$script:all)
            for($j=0; $j -lt $elements.Count; $j++) {
                $e=$elements.Item($j)
                if(-not $e.Current.IsOffscreen -and ($e.Current.AutomationId -in @('7','CommandButton_7') -or $e.Current.Name -in @('No','否','否(N)','&No','&否(N)'))) { return $e }
            }
        }
        Start-Sleep -Milliseconds 100
    } while($timer.Elapsed.TotalSeconds -lt 15)
    throw 'CLI import confirmation merge/No button did not appear.'
}
function Wait-DialogButton([string]$message, [string]$id) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do {
        $windows=$script:root.FindAll($script:children,$script:all)
        for($i=0;$i -lt $windows.Count;$i++) {
            $w=$windows.Item($i)
            if($w.Current.ProcessId -ne $script:process.Id) { continue }
            $textCondition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$message)
            $text=$w.FindFirst($script:descendants,$textCondition)
            if(-not $text){continue}
            $dialog=[System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($text)
            $button=Find-ElementById $dialog $id
            if($button -and -not $button.Current.IsOffscreen){return $button}
            # Modern native dialog providers sometimes expose OK as id=2.
            # Match its observed localized role, never an arbitrary Pane.
            $names=switch($id){'1'{@('OK','确定','确定(O)','&OK')};'6'{@('Yes','是','是(Y)','&Yes')};'7'{@('No','否','否(N)','&No')}}
            $controls=$dialog.FindAll($script:descendants,$script:all)
            for($j=0;$j -lt $controls.Count;$j++){
                $candidate=$controls.Item($j)
                if(-not $candidate.Current.IsOffscreen -and $candidate.Current.Name -in $names){return $candidate}
            }
        }
        Start-Sleep -Milliseconds 100
    } while($clock.Elapsed.TotalSeconds -lt 10)
    throw "Confirmation button $id for '$message' not found."
}
function Wait-ProcessMenu([string]$name) {
    $condition=[System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ProcessIdProperty,$script:process.Id),
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$name),
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::MenuItem))
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do {
        $e=$script:root.FindFirst($script:descendants,$condition)
        if($e -and -not $e.Current.IsOffscreen){return $e}
        Start-Sleep -Milliseconds 100
    }while($clock.Elapsed.TotalSeconds -lt 10)
    throw "Menu '$name' not found."
}
function Wait-DataState([scriptblock]$predicate,[string]$label) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do {
        $data=Read-Data
        if(& $predicate $data){return}
        Start-Sleep -Milliseconds 100
    }while($clock.Elapsed.TotalSeconds -lt 10)
    throw "Persisted state did not reach: $label"
}
function Read-Data { Get-Content -LiteralPath (Join-Path (Split-Path $exe) 'Data\data.json') -Raw | ConvertFrom-Json }

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
    Assert-InitialKeyboardFocus $welcome 'OwnerNameInput'
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
    Assert-InitialKeyboardFocus $editor 'TodoTextBox'
    Set-Text (Wait-ElementById $editor 'TodoTextBox') 'Windows 中文输入与编辑验收'
    Select-Combo $editor 'PriorityInput' '重要 🌟'
    Select-Combo $editor 'ModeInput' '截止日期'
    Set-Text (Wait-ElementById $editor 'DateInput') ([DateTime]::Today.AddDays(5).ToString('yyyy-MM-dd'))
    (Wait-ElementById $editor 'TodoTextBox').SetFocus()
    Set-Text (Wait-ElementById $editor 'TimeInput') '22:15'
    Select-Combo $editor 'ReminderInput' '提前一天'
    Set-Text (Wait-ElementById $editor 'ReminderTimeInput') '21:00'
    Invoke-Button (Wait-ElementByName $editor '保存' ([System.Windows.Automation.ControlType]::Button))
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main 'Windows 中文输入与编辑验收'
    $added = (Read-Data).items[0]
    if ([DateTimeOffset]::Parse($added.schedule.date).LocalDateTime.Date -ne [DateTime]::Today.AddDays(5) -or [DateTimeOffset]::Parse($added.schedule.date).LocalDateTime.Hour -ne 22 -or $added.priority -ne 'Important' -or $added.schedule.mode -ne 'Deadline' -or $added.schedule.reminderMode -ne 'DayBefore' -or $added.schedule.reminderTimeMinutes -ne 1260) { throw 'Create priority/schedule did not persist.' }

    Invoke-Button (Wait-ElementByName $main '编辑待办' ([System.Windows.Automation.ControlType]::Button))
    $editor = Wait-WindowContainingElementId 'TodoTextBox'
    Assert-InitialKeyboardFocus $editor 'TodoTextBox'
    Set-Text (Wait-ElementById $editor 'TodoTextBox') 'Windows 中文输入编辑完成'
    Select-Combo $editor 'ModeInput' '期间'
    Set-Text (Wait-ElementById $editor 'StartInput') ([DateTime]::Today.AddDays(2).ToString('yyyy-MM-dd'))
    (Wait-ElementById $editor 'TodoTextBox').SetFocus()
    Set-Text (Wait-ElementById $editor 'EndInput') ([DateTime]::Today.AddDays(8).ToString('yyyy-MM-dd'))
    (Wait-ElementById $editor 'TodoTextBox').SetFocus()
    Set-Text (Wait-ElementById $editor 'ReminderTimeInput') '08:30'
    Invoke-Button (Wait-ElementByName $editor '保存' ([System.Windows.Automation.ControlType]::Button))
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main 'Windows 中文输入编辑完成'
    Wait-Text $main 'Windows 中文输入与编辑验收' $false
    $edited = (Read-Data).items[0]
    if ($edited.schedule.mode -ne 'Period' -or $edited.schedule.reminderTimeMinutes -ne 510 -or $edited.schedule.startDate -ne [DateTime]::Today.AddDays(2).ToString('yyyy-MM-dd')) { throw 'Edit dates/daily reminder did not persist.' }

    Invoke-Button (Wait-ElementByName $main '编辑待办' ([System.Windows.Automation.ControlType]::Button))
    $editor = Wait-WindowContainingElementId 'TodoTextBox'
    Assert-InitialKeyboardFocus $editor 'TodoTextBox'
    Select-Combo $editor 'ModeInput' '某一天'
    Set-Text (Wait-ElementById $editor 'DateInput') ([DateTime]::Today.AddDays(4).ToString('yyyy-MM-dd'))
    (Wait-ElementById $editor 'TodoTextBox').SetFocus()
    Select-Combo $editor 'ReminderInput' '到时提醒'
    Set-Text (Wait-ElementById $editor 'TimeInput') '10:00'
    Invoke-Button (Wait-ElementByName $editor '保存' ([System.Windows.Automation.ControlType]::Button))
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    $day = (Read-Data).items[0]
    if ($day.schedule.mode -ne 'Day' -or $day.schedule.reminderMode -ne 'AtTime' -or [DateTimeOffset]::Parse($day.schedule.date).LocalDateTime.Hour -ne 10) { throw 'Day mode editing did not persist.' }
    Invoke-Button (Wait-ElementByName $main '编辑待办' ([System.Windows.Automation.ControlType]::Button))
    $editor = Wait-WindowContainingElementId 'TodoTextBox'
    Assert-InitialKeyboardFocus $editor 'TodoTextBox'
    Select-Combo $editor 'ModeInput' '无时间'
    Invoke-Button (Wait-ElementByName $editor '保存' ([System.Windows.Automation.ControlType]::Button))
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    $none = (Read-Data).items[0]
    if ($none.schedule -and ($none.schedule.mode -ne 'None' -or $none.schedule.reminderMode -ne 'None')) { throw 'Clearing schedule did not persist.' }

    $importFile = Join-Path (Split-Path $exe) 'command import.json'
    @{schemaVersion=1;exportedAt=[DateTimeOffset]::UtcNow.ToString('o');items=@(@{id=[guid]::NewGuid().ToString();text='CLI 导入验收';createdAt=[DateTimeOffset]::UtcNow.ToString('o');priority='Normal';completed=$false});archived=@()} | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $importFile
    $second = Start-Process $exe -ArgumentList @('--portable','--import',('"' + $importFile + '"')) -PassThru
    if (-not $second.WaitForExit(10000)) { Stop-Process $second.Id -Force; throw 'Import second instance did not exit.' }
    Invoke-Button (Wait-MergeButton)
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main 'CLI 导入验收'

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

    # Ctrl+N, whitespace validation, and actual handle dragging (not model calls).
    [System.Windows.Forms.SendKeys]::SendWait('^n')
    $editor=Wait-WindowContainingElementId 'TodoTextBox'
    Set-Text (Wait-ElementById $editor 'TodoTextBox') '   '
    Invoke-Button (Wait-ElementByName $editor '保存' ([System.Windows.Automation.ControlType]::Button))
    Invoke-Button (Wait-DialogButton '待办内容不能为空。' '1')
    if((Read-Data).items.Count -ne 2){throw 'Whitespace todo was incorrectly created.'}
    Set-Text (Wait-ElementById $editor 'TodoTextBox') '排序回归条目'
    Invoke-Button (Wait-ElementByName $editor '保存' ([System.Windows.Automation.ControlType]::Button))
    $main=Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main '排序回归条目'
    $thumbCondition=[System.Windows.Automation.AndCondition]::new([System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Thumb),[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,'拖动调整顺序'))
    $handles=$main.FindAll($script:descendants,$thumbCondition)
    if($handles.Count -ne 3){throw 'Expected three draggable row handles.'}
    $source=$handles.Item(2).Current.BoundingRectangle;$target=$handles.Item(1).Current.BoundingRectangle
    $x=[int]($source.X+$source.Width/2);$y=[int]($source.Y+$source.Height/2);$dest=[int]($target.Y+2)
    [UiPointer]::SetCursorPos($x,$y) | Out-Null;[UiPointer]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    try {
        for($step=1;$step -le 8;$step++){
            [UiPointer]::SetCursorPos($x,($y+[int](($dest-$y)*$step/8))) | Out-Null
            Start-Sleep -Milliseconds 40
        }
    }finally{[UiPointer]::mouse_event(4,0,0,0,[UIntPtr]::Zero)}
    Start-Sleep -Milliseconds 300
    Wait-DataState {param($d) $d.items[1].text -eq '排序回归条目'} 'real handle drag order'

    # Let the four-second completion timer actually expire, then restore history.
    $main=Wait-WindowContainingElementId 'AddTodoButton'
    $checkCondition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::CheckBox)
    $main.FindFirst($script:descendants,$checkCondition).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
    Start-Sleep -Milliseconds 4500
    Wait-DataState {param($d) $d.archived.Count -eq 1} 'four-second archive'
    Invoke-Button (Wait-ElementById $main 'ArchiveButton')
    $main=Wait-WindowContainingElementId 'NameTitle'
    Invoke-Button (Wait-ElementByName $main '恢复' ([System.Windows.Automation.ControlType]::Button))
    Wait-DataState {param($d) $d.archived.Count -eq 0 -and $d.items.text -contains 'Windows 中文输入编辑完成'} 'history restore'
    Invoke-Button (Wait-ElementById $main 'ArchiveButton')
    $main=Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main 'Windows 中文输入编辑完成'

    # Delete a real row through its context menu.
    $text=Wait-ElementByName $main 'CLI 导入验收' ([System.Windows.Automation.ControlType]::Text)
    $r=$text.Current.BoundingRectangle
    [UiPointer]::SetCursorPos([int]($r.X+$r.Width/2),[int]($r.Y+$r.Height/2)) | Out-Null
    [UiPointer]::mouse_event(8,0,0,0,[UIntPtr]::Zero);[UiPointer]::mouse_event(16,0,0,0,[UIntPtr]::Zero)
    Invoke-Button (Wait-ProcessMenu '删除')
    Wait-DataState {param($d) $d.items.text -notcontains 'CLI 导入验收'} 'context menu delete'

    # Complete the remaining normal row and clear archive with explicit confirmation.
    $main=Wait-WindowContainingElementId 'AddTodoButton'
    $checks=$main.FindAll($script:descendants,$checkCondition)
    $checks.Item(1).GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
    Start-Sleep -Milliseconds 4500
    Invoke-Button (Wait-ElementById $main 'ArchiveButton')
    $main=Wait-WindowContainingElementId 'NameTitle'
    Invoke-Button (Wait-ElementByName $main '清空全部已完成' ([System.Windows.Automation.ControlType]::Button))
    Invoke-Button (Wait-DialogButton '确定清空全部已完成事项？' '6')
    Wait-DataState {param($d) $d.archived.Count -eq 0} 'archive clear'
    Invoke-Button (Wait-ElementById $main 'ArchiveButton')

    Stop-Process -Id $process.Id -Force
    $process = $null
    Start-Sleep -Seconds 1

    $process = Start-Process -FilePath $exe -ArgumentList @('--safe-mode', '--diagnostics', '--portable') -PassThru
    $main = Wait-WindowContainingElementId 'AddTodoButton'
    Wait-Text $main 'Windows 中文输入编辑完成'

    Write-Host 'Windows UI smoke passed: naming, Unicode text, priority, date/deadline creation, period/daily editing, second-launch import, completion undo, real handle dragging, archive restore/clear, context deletion, Ctrl+N, blank validation and persistence. This is not an IME composition test.'
}
catch {
    Write-Host $_.ScriptStackTrace
    Write-Host $_.Exception.ToString()
    $windows=$script:root.FindAll($script:children,$script:all)
    for($i=0; $i -lt $windows.Count; $i++) {
        $w=$windows.Item($i)
        if($process -and $w.Current.ProcessId -eq $process.Id) {
            Write-Host "APP WINDOW: $($w.Current.Name)"
            $elements=$w.FindAll($script:descendants,$script:all)
            for($j=0; $j -lt $elements.Count; $j++) { $e=$elements.Item($j); Write-Host "$($e.Current.ControlType.ProgrammaticName) ID=$($e.Current.AutomationId) NAME=$($e.Current.Name)" }
        }
    }
    $logRoot = Join-Path (Split-Path $exe) 'Data\Logs'
    Get-ChildItem $logRoot -Filter 'startup-*.log' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName }
    throw
}
finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
}
