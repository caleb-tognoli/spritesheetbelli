# Drags a file into the window of drag_probe.gd, out of it, back in, and drops it, moving
# the real cursor. Run the probe first, then this, from the project folder:
#   godot --path . -s native/tests/drag_probe.gd
#   powershell -ExecutionPolicy Bypass -File native/tests/drag_source_windows.ps1 icon.svg
# With -Virtual it drags the file's contents instead, like a browser does.
param([string]$File, [switch]$Virtual)
$File = (Resolve-Path $File).Path
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class Mouse {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
    public static void Move(int x, int y) { SetCursorPos(x, y); mouse_event(1, 0, 0, 0, UIntPtr.Zero); }
    static void Glide(int x0, int y0, int x1, int y1) {
        for (int i = 1; i <= 20; i++) { Move(x0 + (x1 - x0) * i / 20, y0 + (y1 - y0) * i / 20); Thread.Sleep(15); }
    }
    public static void Down() { mouse_event(2, 0, 0, 0, UIntPtr.Zero); }
    public static void Start() { new Thread(Script).Start(); }
    static void Script() {
        Thread.Sleep(300);
        Glide(900, 200, 400, 300); Thread.Sleep(800);
        Glide(400, 300, 20, 20); Thread.Sleep(800);
        Glide(20, 20, 400, 300); Thread.Sleep(800);
        mouse_event(4, 0, 0, 0, UIntPtr.Zero);
    }
}
"@
[Mouse]::SetProcessDPIAware() | Out-Null
$form = New-Object System.Windows.Forms.Form
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(800, 100)
$form.Size = New-Object System.Drawing.Size(200, 200)
$form.TopMost = $true
$form.Add_MouseDown({
    [Mouse]::Start()
    $data = New-Object System.Windows.Forms.DataObject
    if ($Virtual) {
        # A FILEGROUPDESCRIPTORW with one FILEDESCRIPTORW naming the file
        $descriptor = New-Object byte[] (4 + 592)
        [BitConverter]::GetBytes([int]1).CopyTo($descriptor, 0)
        [System.Text.Encoding]::Unicode.GetBytes([System.IO.Path]::GetFileName($File)).CopyTo($descriptor, 4 + 72)
        $data.SetData("FileGroupDescriptorW", (New-Object System.IO.MemoryStream(, $descriptor)))
        $data.SetData("FileContents", (New-Object System.IO.MemoryStream(, [System.IO.File]::ReadAllBytes($File))))
    } else {
        $files = New-Object System.Collections.Specialized.StringCollection
        $files.Add($File) | Out-Null
        $data.SetFileDropList($files)
    }
    $form.DoDragDrop($data, [System.Windows.Forms.DragDropEffects]::Copy) | Out-Null
    $form.Close()
})
$form.Add_Shown({
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 300
    $timer.Add_Tick({ $this.Stop(); [Mouse]::Move(900, 200); [Mouse]::Down() })
    $timer.Start()
})
[System.Windows.Forms.Application]::Run($form)
