# watch-codex-mirror.ps1 - on-demand guard for ChatGPT desktop (Windows)
#
# Kills idle "node_repl.exe" prewarm helpers whose working directory sits
# inside the ChatGPT project mirror (%USERPROFILE%\.codex\.chatgpt-projects).
# Those helpers block the project-context sync that runs when you create a
# Work inside a ChatGPT project, which makes the desktop app show
#   "Could not use this project for a local chat" / “无法将此项目用于本地聊天”.
# Active conversation helpers (cwd under Documents\Codex) are never touched.
#
# Lifecycle (v5): run it whenever you like - it keeps guarding while
# ChatGPT (codex.exe) runs and self-exits ~45s after ChatGPT closes.
# A named mutex makes double-starts harmless.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File watch-codex-mirror.ps1
# Optional parameters (needed only when running as SYSTEM via WMI):
#   -MirrorRoot <path>  defaults to %USERPROFILE%\.codex\.chatgpt-projects
#   -LogPath <path>     defaults to %USERPROFILE%\Documents\chatgpt-work-mirror-guard\guard.log

param(
    [switch]$NoPause,
    [string]$MirrorRoot,
    [string]$LogPath
)
$ErrorActionPreference = "SilentlyContinue"

if (-not $MirrorRoot) { $MirrorRoot = Join-Path $env:USERPROFILE ".codex\.chatgpt-projects" }
if (-not $LogPath) {
    $dir = Join-Path $env:USERPROFILE "Documents\chatgpt-work-mirror-guard"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $LogPath = Join-Path $dir "guard.log"
}
$mirrorRootLower = $MirrorRoot.ToLower()

# --- single instance ---
$created = $false
$m = New-Object System.Threading.Mutex($true, "ChatGPTMirrorGuard", [ref]$created)
if (-not $created) { exit }

Add-Type @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class MirrorGuard {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll.dll")]
    public static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PROCESS_BASIC_INFORMATION info, int len, out int returnLength);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out IntPtr read);
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_BASIC_INFORMATION {
        public IntPtr Reserved1; public IntPtr PebBaseAddress; public IntPtr Reserved2a;
        public IntPtr Reserved2b; public IntPtr UniquePid; public IntPtr Reserved3;
    }

    // Reads a process' real current working directory from its PEB.
    public static string ReadCwd(IntPtr h, int pid) {
        var pbi = new PROCESS_BASIC_INFORMATION(); int rl; IntPtr rr = IntPtr.Zero;
        if (NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(pbi), out rl) != 0) return null;
        byte[] buf = new byte[8];
        if (!ReadProcessMemory(h, (IntPtr)((long)pbi.PebBaseAddress + 0x20), buf, 8, out rr)) return null;
        long pp = BitConverter.ToInt64(buf, 0);
        if (pp == 0) return null;
        if (!ReadProcessMemory(h, (IntPtr)(pp + 0x38), buf, 2, out rr)) return null;   // CURDIR.DosPath.Length
        int len = BitConverter.ToUInt16(buf, 0);
        if (len <= 0 || len > 1024) return null;
        if (!ReadProcessMemory(h, (IntPtr)(pp + 0x40), buf, 8, out rr)) return null;   // CURDIR.DosPath.Buffer
        long sp = BitConverter.ToInt64(buf, 0);
        byte[] s = new byte[len];
        if (!ReadProcessMemory(h, (IntPtr)sp, s, len, out rr)) return null;
        return Encoding.Unicode.GetString(s);
    }

    // Kills node_repl helpers parked inside the mirror. Returns count killed.
    public static int Sweep(string mirrorRootLower, string logPath) {
        int killed = 0;
        foreach (var proc in Process.GetProcessesByName("node_repl")) {
            try {
                IntPtr h = OpenProcess(0x1F0FFF, false, proc.Id);
                if (h != IntPtr.Zero) {
                    try {
                        string cwd = ReadCwd(h, proc.Id);
                        if (cwd != null && cwd.ToLower().StartsWith(mirrorRootLower)) {
                            try {
                                proc.Kill();
                                Interlocked.Increment(ref killed);
                                try { File.AppendAllText(logPath,
                                    "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] killed lock holder PID "
                                    + proc.Id + " cwd=" + cwd + Environment.NewLine, Encoding.UTF8); } catch {}
                            } catch {}
                        }
                    } finally { CloseHandle(h); }
                }
            } catch {} finally { proc.Dispose(); }
        }
        return killed;
    }
}
"@

function Write-Log($msg) {
    try { Add-Content -Path $LogPath -Value ("[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] " + $msg) -Encoding UTF8 } catch {}
}

Write-Log "guard ON (follows ChatGPT lifecycle), guarding $mirrorRootLower"

# Exit 45s after ChatGPT (codex.exe) is gone.
$goneTicks = 0
try {
    while ($true) {
        if (Get-Process -Name codex -ErrorAction SilentlyContinue) {
            $goneTicks = 0
            [MirrorGuard]::Sweep($mirrorRootLower, $LogPath) | Out-Null
        } else {
            $goneTicks++
            if ($goneTicks -gt 150) { break }   # 150 x 300ms = 45s
        }
        Start-Sleep -Milliseconds 300
    }
} finally {
    Write-Log "guard OFF (ChatGPT closed ~45s ago)"
}
$m.ReleaseMutex()
if (-not $NoPause) { Read-Host "Guard exited. Press Enter to close" | Out-Null }
