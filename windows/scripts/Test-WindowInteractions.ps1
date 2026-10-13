param(
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [int]$Cycles = 100,
    [switch]$ExpectLegacyFailure
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class OrbInput {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr c);
}
'@
[OrbInput]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
$exe = (Resolve-Path $ExecutablePath).Path
$root = Split-Path $exe
$evidence = [IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Force $evidence, (Join-Path $root 'Data') | Out-Null
# Test only a fresh, isolated package extraction. Never point this at user data.
$settingsPath = Join-Path $root 'Data\settings.json'
if (Test-Path $settingsPath) { throw 'UI test requires a fresh extraction with no existing settings.' }
@{ownerName='Window QA';isMinimized=$false;desktopMode=$false} | ConvertTo-Json | Set-Content -Encoding UTF8 $settingsPath
$process = $null
$trace = [Collections.Generic.List[object]]::new()
$violations = [Collections.Generic.List[string]]::new()
$desktop = [System.Windows.Automation.AutomationElement]::RootElement
$children = [System.Windows.Automation.TreeScope]::Children
$descendants = [System.Windows.Automation.TreeScope]::Descendants
$all = [System.Windows.Automation.Condition]::TrueCondition

function Main-Window {
    $condition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
    $windows = $desktop.FindAll($children, $condition)
    for ($i=0; $i -lt $windows.Count; $i++) {
        $w = $windows.Item($i)
        if ($w.Current.Name -like '*Todo list*') { return $w }
    }
    return $null
}
function Find-Control($w, [string]$id, [string]$name='') {
    $condition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
    $element = $w.FindFirst($descendants,$condition)
    if ($element) { return $element }
    $elements=$w.FindAll($descendants,$all)
    for($i=0; $i -lt $elements.Count; $i++) { if($elements.Item($i).Current.Name -eq $name) { return $elements.Item($i) } }
    return $null
}
function Bounds([IntPtr]$h) {
    $r = [OrbInput+RECT]::new()
    if(-not [OrbInput]::GetWindowRect($h,[ref]$r)) { throw 'GetWindowRect failed: process/window disappeared.' }
    return $r
}
function Record([string]$stage,[IntPtr]$h,[int]$cycle) {
    $r=Bounds $h
    $trace.Add(@{stage=$stage;cycle=$cycle;left=$r.Left;top=$r.Top;right=$r.Right;bottom=$r.Bottom;dpi=[OrbInput]::GetDpiForWindow($h);processAlive=(-not $process.HasExited)})
}
function Screenshot([string]$name,[IntPtr]$h) {
    $screen=[Windows.Forms.Screen]::FromHandle($h).Bounds
    $bitmap=[Drawing.Bitmap]::new($screen.Width,$screen.Height)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try { $graphics.CopyFromScreen($screen.Location,[Drawing.Point]::Empty,$screen.Size); $bitmap.Save((Join-Path $evidence "$name.png"),[Drawing.Imaging.ImageFormat]::Png) }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
}
function Check([bool]$condition,[string]$message) {
    if (-not $condition) { $violations.Add($message); if(-not $ExpectLegacyFailure) { throw $message } }
}
function Check-Visible([IntPtr]$h,[string]$stage) {
    $process.Refresh(); Check (-not $process.HasExited) "Process exited at $stage"
    $r=Bounds $h; $a=[Windows.Forms.Screen]::FromHandle($h).WorkingArea
    Check ($r.Right -gt $r.Left -and $r.Bottom -gt $r.Top) "Empty window at $stage"
    Check ($r.Left -ge $a.Left -and $r.Top -ge $a.Top -and $r.Right -le $a.Right -and $r.Bottom -le $a.Bottom) "Offscreen window at $stage"
}
function Drag-Orb([IntPtr]$h,[int]$dx,[int]$dy,[int]$cycle,[int]$number) {
    [OrbInput]::SetForegroundWindow($h) | Out-Null
    $before=Bounds $h; $x=[int](($before.Left+$before.Right)/2); $y=[int](($before.Top+$before.Bottom)/2)
    [OrbInput]::SetCursorPos($x,$y) | Out-Null
    [OrbInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    try {
        Start-Sleep -Milliseconds 25
        for($step=1; $step -le 6; $step++) {
            [OrbInput]::SetCursorPos(($x+[int]($dx*$step/6)),($y+[int]($dy*$step/6))) | Out-Null
            Start-Sleep -Milliseconds 25
            if($cycle -eq 1) { Screenshot "drag-$number-$step" $h }
        }
        $during=Bounds $h
        Record "drag-$number-held" $h $cycle
        Check ([Math]::Abs($during.Left-$before.Left) -ge [Math]::Abs($dx)*.6) "Horizontal drag frozen at cycle $cycle drag $number"
    }
    finally { [OrbInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero) }
    Start-Sleep -Milliseconds 220
    Check-Visible $h "drag-$number-release"
    Record "drag-$number-release" $h $cycle
}
try {
    $process=Start-Process $exe -ArgumentList '--portable','--diagnostics' -PassThru
    $w=$null
    for($attempt=0; $attempt -lt 100 -and -not $w; $attempt++) { Start-Sleep -Milliseconds 100; $w=Main-Window }
    if(-not $w) { throw 'Main window did not appear.' }
    $h=[IntPtr]$w.Current.NativeWindowHandle
    Screenshot 'panel-before' $h
    for($cycle=1; $cycle -le $Cycles; $cycle++) {
        $w=Main-Window
        $min=Find-Control $w 'MinimizeButton' ([string][char]0x2212)
        if(-not $min) { throw 'Minimize control missing.' }
        $min.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 260
        Check-Visible $h 'minimized'; Record 'minimized' $h $cycle
        $r=Bounds $h
        $size=48*[OrbInput]::GetDpiForWindow($h)/96
        Check ([Math]::Abs(($r.Right-$r.Left)-$size) -le 2) "Orb width incorrect at cycle $cycle"
        Drag-Orb $h -140 15 $cycle 1
        Drag-Orb $h -120 -15 $cycle 2
        $r=Bounds $h
        [OrbInput]::SetCursorPos([int](($r.Left+$r.Right)/2),[int](($r.Top+$r.Bottom)/2)) | Out-Null
        [OrbInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [OrbInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 180
        Check-Visible $h 'restored'; Record 'restored' $h $cycle
        if($cycle -eq 1 -or $cycle -eq $Cycles) { Screenshot "panel-restored-$cycle" $h }
    }
    # A second launch must exit and leave the tested instance alive.
    $second=Start-Process $exe -ArgumentList '--portable','--diagnostics' -PassThru
    if(-not $second.WaitForExit(10000)) { Stop-Process $second.Id -Force; throw 'Second instance did not exit.' }
    Check-Visible $h 'second-launch'
    if($ExpectLegacyFailure -and $violations.Count -eq 0) { throw 'Legacy regression was not reproduced; investigate instead of assuming.' }
    $os=Get-CimInstance Win32_OperatingSystem
    @{os=$os.Caption;build=$os.BuildNumber;cycles=$Cycles;legacy=$ExpectLegacyFailure.IsPresent;violations=@($violations.ToArray());dpi=[OrbInput]::GetDpiForWindow($h);status=if($ExpectLegacyFailure){'legacy-failure-reproduced'}else{'passed'};tests='Native mouse down/move/up, 2 drags per cycle, restore, bounds, process, second instance'} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $evidence 'summary.json')
}
finally {
    $trace.ToArray() | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $evidence 'window-trace.json')
    $logs=Join-Path $root 'Data\Logs'
    if(Test-Path $logs) { Copy-Item $logs (Join-Path $evidence 'diagnostics') -Recurse -Force }
    if($process -and -not $process.HasExited) { Stop-Process $process.Id -Force }
}
