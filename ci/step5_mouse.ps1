$ErrorActionPreference = 'Continue'
# Real mouse on the real Windows VLC with the installed skin: drag from several places, resize from the edges.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public delegate bool EnumProc(IntPtr h, IntPtr l);
}
"@
[void][W]::SetProcessDPIAware()
$shots = "$env:GITHUB_WORKSPACE\shots"
function Shot($name) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $bmp.Save("$shots\$name.png")
}
function Wins($pid0) {
  $list = New-Object System.Collections.ArrayList
  $cb = [W+EnumProc]{ param($h, $l)
    $p = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$p)
    if ($p -eq $pid0 -and [W]::IsWindowVisible($h)) {
      $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
      $sb = New-Object System.Text.StringBuilder 256; [void][W]::GetWindowText($h, $sb, 256)
      if (($r.R - $r.L) -gt 200) { [void]$list.Add([pscustomobject]@{H=$h; T=$sb.ToString(); L=$r.L; Tp=$r.T; Wd=$r.R-$r.L; Ht=$r.B-$r.T}) }
    }
    $true }
  [void][W]::EnumWindows($cb, [IntPtr]::Zero)
  $list
}
function Main($pid0) { (Wins $pid0 | Sort-Object { $_.Wd * $_.Ht } -Descending | Select-Object -First 1) }
function Drag($pid0, $name, [int]$ox, [int]$oy, [int]$dx, [int]$dy) {
  $m = Main $pid0
  if (-not $m) { "$name : no window"; return }
  $ax = $m.L + $ox; $ay = $m.Tp + $oy
  [void][W]::SetCursorPos($ax, $ay); Start-Sleep -Milliseconds 400
  [W]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
  for ($i = 1; $i -le 10; $i++) { [void][W]::SetCursorPos($ax + [int]($dx * $i / 10), $ay + [int]($dy * $i / 10)); Start-Sleep -Milliseconds 40 }
  Start-Sleep -Milliseconds 300
  [W]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 600
  $a = Main $pid0
  "{0,-22} at({1},{2}) drag({3},{4})  before {5}x{6}+{7}+{8}  after {9}x{10}+{11}+{12}" -f $name, $ox, $oy, $dx, $dy, $m.Wd, $m.Ht, $m.L, $m.Tp, $a.Wd, $a.Ht, $a.L, $a.Tp
}
$vlc = "C:\Program Files\VideoLAN\VLC\vlc.exe"
foreach ($mode in 'idle', 'playing') {
  "==== $mode"
  $args2 = @('--no-qt-privacy-ask')
  if ($mode -eq 'playing') { $args2 += "$env:GITHUB_WORKSPACE\test.mp4" }
  $p = Start-Process $vlc -ArgumentList $args2 -PassThru
  Start-Sleep 12
  $m = Main $p.Id
  if (-not $m) { "no main window found"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; continue }
  "window: '$($m.T)' $($m.Wd)x$($m.Ht)+$($m.L)+$($m.Tp)"
  Shot "mouse_${mode}_0"
  $w = $m.Wd; $h = $m.Ht
  Drag $p.Id 'title_left' 6 10 30 20
  Drag $p.Id 'title_text' ([int]($w * 0.3)) 14 30 20
  Drag $p.Id 'title_right_of_text' ([int]($w * 0.6)) 14 -30 -20
  Drag $p.Id 'body' ([int]($w * 0.5)) ([int]($h * 0.45)) 30 20
  Drag $p.Id 'right_edge_body' ($w - 2) ([int]($h * 0.4)) 60 0
  $m = Main $p.Id
  Drag $p.Id 'bottom_edge' ([int]($m.Wd * 0.5)) ($m.Ht - 2) 0 50
  $m = Main $p.Id
  Drag $p.Id "se_corner" ($m.Wd - 8) ($m.Ht - 8) 40 40
  Shot "mouse_${mode}_1"
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep 2
}
