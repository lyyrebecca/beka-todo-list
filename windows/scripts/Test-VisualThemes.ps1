param(
    [Parameter(Mandatory=$true)][string]$ExecutablePath,
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [switch]$AllowTestDesktopChanges
)
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -and -not $AllowTestDesktopChanges) { throw 'Run in an isolated Windows QA desktop, or explicitly allow temporary desktop theme changes.' }
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing,System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ThemeNative {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr c);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,string l,uint f,uint timeout,out IntPtr result);
}
'@
[ThemeNative]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
$exe=(Resolve-Path $ExecutablePath).Path; $root=Split-Path $exe
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Force $evidence | Out-Null
$data=Join-Path $root 'Data'
if(Test-Path $data) { throw 'Visual QA requires fresh extraction, not user data.' }
New-Item -ItemType Directory $data | Out-Null
@{ownerName='贝卡';isMinimized=$false;desktopMode=$false} | ConvertTo-Json | Set-Content (Join-Path $data 'settings.json') -Encoding UTF8
$items=@('把今天的一件事做好','整理本周计划','散步，给自己一点空闲') | ForEach-Object {
 @{id=[guid]::NewGuid().ToString();text=$_;createdAt=[DateTimeOffset]::UtcNow.ToString('o');priority=if($_ -eq '把今天的一件事做好'){'Important'}else{'Normal'};completed=$false}
}
@{items=@($items);archived=@()} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $data 'data.json') -Encoding UTF8
$key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$existed=Test-Path $key
$previous=if($existed){(Get-ItemProperty $key -ErrorAction Stop).AppsUseLightTheme}else{$null}
$process=$null; $backdrop=$null
$desktop=[Windows.Automation.AutomationElement]::RootElement
$children=[Windows.Automation.TreeScope]::Children; $descendants=[Windows.Automation.TreeScope]::Descendants
function Apply-TestTheme([bool]$dark) {
 New-Item $key -Force | Out-Null
 New-ItemProperty $key -Name AppsUseLightTheme -Value ([int](-not $dark)) -PropertyType DWord -Force | Out-Null
 $out=[IntPtr]::Zero
 [ThemeNative]::SendMessageTimeout([IntPtr]0xffff,0x001A,[IntPtr]::Zero,'ImmersiveColorSet',2,2000,[ref]$out) | Out-Null
}
function Main-Window {
 $condition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty,$process.Id)
 $all=$desktop.FindAll($children,$condition)
 for($i=0;$i -lt $all.Count;$i++){if($all.Item($i).Current.Name -like '*Todo list*'){return $all.Item($i)}}
 return $null
}
function Wait-Theme([string]$label) {
 $clock=[Diagnostics.Stopwatch]::StartNew()
 do {
  $process.Refresh();if($process.HasExited){throw 'Visual candidate process exited.'}
  $w=Main-Window
  if($w -and $w.Current.ItemStatus -eq $label){return $w}
  Start-Sleep -Milliseconds 100
 } while($clock.Elapsed.TotalSeconds -lt 15)
 throw "Live theme change did not reach $label"
}
function Screenshot([string]$name,[IntPtr]$h) {
 $r=[ThemeNative+RECT]::new()
 if(-not [ThemeNative]::GetWindowRect($h,[ref]$r)){throw 'Window unavailable for visual capture.'}
 $b=[Drawing.Bitmap]::new(($r.Right-$r.Left),($r.Bottom-$r.Top)); $g=[Drawing.Graphics]::FromImage($b)
 try {
  $g.CopyFromScreen([Drawing.Point]::new($r.Left,$r.Top),[Drawing.Point]::Empty,$b.Size)
  $b.Save((Join-Path $evidence "$name.png"),[Drawing.Imaging.ImageFormat]::Png)
  if($name -like '*panel*') {
   $sample=$b.GetPixel(160,60)
   if($sample.B-$sample.G -lt 18 -or $sample.R-$sample.G -lt 8){throw 'Captured reading plane is not the approved purple material, or was obscured.'}
   if($name -like 'night*' -and $sample.G -gt 130){throw 'Night plane is too bright or did not switch.'}
   if($name -like 'day*' -and ($sample.G -lt 155 -or $sample.G -gt 215)){throw 'Day plane is too bright/dark or did not switch.'}
  }
  if($name -like '*orb*') {
   foreach($p in @(@(0,0),@(($b.Width-1),0),@(0,($b.Height-1)),@(($b.Width-1),($b.Height-1)))) {
    $c=$b.GetPixel($p[0],$p[1]);$bg=$backdrop.BackColor
    if([Math]::Abs($c.R-$bg.R)+[Math]::Abs($c.G-$bg.G)+[Math]::Abs($c.B-$bg.B) -gt 8){throw 'Orb has a nontransparent square corner.'}
   }
  }
 } finally {$g.Dispose();$b.Dispose()}
}
try {
 Apply-TestTheme $false
 $backdrop=[Windows.Forms.Form]::new();$backdrop.FormBorderStyle='None';$backdrop.ShowInTaskbar=$false;$backdrop.StartPosition='Manual';$backdrop.TopMost=$true
 $backdrop.Bounds=[Windows.Forms.Screen]::PrimaryScreen.Bounds;$backdrop.BackColor=[Drawing.Color]::FromArgb(222,217,229)
 $backdrop.Show();[Windows.Forms.Application]::DoEvents()
 $process=Start-Process $exe -ArgumentList '--portable','--diagnostics' -PassThru
 foreach($dark in @($false,$true,$false)) {
  Apply-TestTheme $dark
  $label=if($dark){'夜间 · 烟紫玻璃'}else{'白天 · 轻雾紫'}
  $w=Wait-Theme $label;$h=[IntPtr]$w.Current.NativeWindowHandle
  $backdrop.BackColor=if($dark){[Drawing.Color]::FromArgb(48,42,58)}else{[Drawing.Color]::FromArgb(222,217,229)}
  $backdrop.BringToFront();$backdrop.Refresh();[Windows.Forms.Application]::DoEvents()
  [ThemeNative]::SetWindowPos($h,[IntPtr](-1),0,0,0,0,0x13) | Out-Null
  [ThemeNative]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Milliseconds 350
  $name=if($dark){'night'}else{'day'}
  Screenshot "$name-panel" $h
  $id=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'MinimizeButton')
  $button=$w.FindFirst($descendants,$id);$button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
  Start-Sleep -Milliseconds 300
  $id=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'OrbLabel')
  $glyph=$w.FindFirst($descendants,$id)
  if(-not $glyph -or $glyph.Current.Name -cne ([string][char]0x5e72)){throw 'Floating label is not native U+5E72 干.'}
  Screenshot "$name-orb" $h
  $r=[ThemeNative+RECT]::new();[ThemeNative]::GetWindowRect($h,[ref]$r) | Out-Null
  [ThemeNative]::SetCursorPos([int](($r.Left+$r.Right)/2),[int](($r.Top+$r.Bottom)/2)) | Out-Null
  [ThemeNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[ThemeNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 300
 }
 @{status='passed';checks='Live day/night/day switch; native U+5E72 orb label; transparent corners on light/dark desktop';os=(Get-CimInstance Win32_OperatingSystem).Caption;dpi='per-window native capture';realDesktopCapture=$true} | ConvertTo-Json | Set-Content (Join-Path $evidence 'summary.json') -Encoding UTF8
} finally {
 if($process -and -not $process.HasExited){Stop-Process $process.Id -Force}
 if($backdrop){$backdrop.Close();$backdrop.Dispose()}
 if($null -ne $previous){Set-ItemProperty $key -Name AppsUseLightTheme -Value $previous}
 elseif(Test-Path $key){Remove-ItemProperty $key -Name AppsUseLightTheme -ErrorAction SilentlyContinue}
 $out=[IntPtr]::Zero;[ThemeNative]::SendMessageTimeout([IntPtr]0xffff,0x001A,[IntPtr]::Zero,'ImmersiveColorSet',2,2000,[ref]$out) | Out-Null
}
