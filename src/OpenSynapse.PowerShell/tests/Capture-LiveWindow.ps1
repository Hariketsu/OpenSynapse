#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$ResultPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class OpenSynapseLiveWindow
{
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    public sealed class WindowInfo
    {
        public IntPtr Handle { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public uint Dpi { get; set; }
        public string Title { get; set; }
    }

    private delegate bool EnumWindowsCallback(IntPtr windowHandle, IntPtr parameter);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr windowHandle, out uint processId);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool IsWindowVisible(IntPtr windowHandle);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetWindowRect(IntPtr windowHandle, out RECT rectangle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr windowHandle, StringBuilder text, int maximumCount);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr windowHandle);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetProcessDpiAwarenessContext(IntPtr awarenessContext);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetForegroundWindow(IntPtr windowHandle);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool BringWindowToTop(IntPtr windowHandle);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool ShowWindow(IntPtr windowHandle, int command);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetWindowPos(
        IntPtr windowHandle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    public static void EnablePerMonitorV2()
    {
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); }
        catch (EntryPointNotFoundException) { }
    }

    public static void Activate(IntPtr windowHandle)
    {
        ShowWindow(windowHandle, 9);
        SetWindowPos(windowHandle, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
        BringWindowToTop(windowHandle);
        SetForegroundWindow(windowHandle);
    }

    public static void ClearTopMost(IntPtr windowHandle)
    {
        SetWindowPos(windowHandle, new IntPtr(-2), 0, 0, 0, 0, 0x0001 | 0x0002);
    }

    public static WindowInfo Find(uint expectedProcessId)
    {
        WindowInfo result = null;
        EnumWindows(delegate(IntPtr handle, IntPtr parameter)
        {
            uint processId;
            GetWindowThreadProcessId(handle, out processId);
            if (processId != expectedProcessId || !IsWindowVisible(handle)) return true;
            RECT rectangle;
            if (!GetWindowRect(handle, out rectangle)) return true;
            int width = rectangle.Right - rectangle.Left;
            int height = rectangle.Bottom - rectangle.Top;
            if (width < 800 || height < 600) return true;
            StringBuilder title = new StringBuilder(256);
            GetWindowText(handle, title, title.Capacity);
            result = new WindowInfo
            {
                Handle = handle,
                Left = rectangle.Left,
                Top = rectangle.Top,
                Width = width,
                Height = height,
                Dpi = GetDpiForWindow(handle),
                Title = title.ToString()
            };
            return false;
        }, IntPtr.Zero);
        return result;
    }
}
'@
[OpenSynapseLiveWindow]::EnablePerMonitorV2()

$dataDirectory = Join-Path $env:LOCALAPPDATA 'OpenSynapse'
$runtimePath = Join-Path $dataDirectory 'runtime.json'
if (-not (Test-Path -LiteralPath $runtimePath)) { throw 'OpenSynapse runtime record was not found.' }
$runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
[IO.File]::WriteAllText((Join-Path $dataDirectory 'show.request'), (Get-Date).ToString('o'))
try { Start-ScheduledTask -TaskName OpenSynapse -ErrorAction Stop } catch { }

$window = $null
foreach ($attempt in 1..30) {
    Start-Sleep -Milliseconds 250
    $window = [OpenSynapseLiveWindow]::Find([uint32]$runtime.ProcessId)
    if ($null -ne $window) { break }
}
if ($null -eq $window) { throw "No visible OpenSynapse window was found for PID $($runtime.ProcessId)." }
[OpenSynapseLiveWindow]::Activate($window.Handle)
Start-Sleep -Milliseconds 800
$window = [OpenSynapseLiveWindow]::Find([uint32]$runtime.ProcessId)

$fullPath = [IO.Path]::GetFullPath($OutputPath)
$directory = Split-Path -Parent $fullPath
if (-not (Test-Path -LiteralPath $directory)) { [IO.Directory]::CreateDirectory($directory) | Out-Null }
$bitmap = New-Object Drawing.Bitmap($window.Width, $window.Height)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.CopyFromScreen($window.Left, $window.Top, 0, 0, $bitmap.Size)
}
finally {
    $graphics.Dispose()
    [OpenSynapseLiveWindow]::ClearTopMost($window.Handle)
}
$bitmap.Save($fullPath, [Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

$result = [pscustomobject]@{
    Result = 'PASS'
    ProcessId = [int]$runtime.ProcessId
    Title = $window.Title
    Dpi = $window.Dpi
    ScalePercent = [Math]::Round(($window.Dpi / 96.0) * 100)
    Width = $window.Width
    Height = $window.Height
    OutputPath = $fullPath
}
if ($ResultPath) {
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}
$result | Format-List
