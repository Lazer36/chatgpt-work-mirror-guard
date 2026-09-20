# unlock-codex-mirror.ps1 - one-shot precise unlocker (Windows)
#
# When ChatGPT desktop shows "Could not use this project for a local chat"
# while creating a Work, this script kills ONLY the node_repl.exe helper
# processes whose real working directory (read from their PEB) sits inside
# the project mirror. Then it verifies each mirror directory is unlockable
# with a reversible rename test. Active conversation helpers (cwd under
# Documents\Codex) are never touched. ASCII only on purpose: Windows
# PowerShell 5.1 misreads BOM-less UTF-8 scripts.

param([switch]$NoPause)
$ErrorActionPreference = "SilentlyContinue"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PwdReader {
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
    public static string ReadCwd(int pid) {
        IntPtr h = OpenProcess(0x1F0FFF, false, pid);
        if (h == IntPtr.Zero) return null;
        try {
            var pbi = new PROCESS_BASIC_INFORMATION(); int rl; IntPtr rr = IntPtr.Zero;
            if (NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(pbi), out rl) != 0) return null;
            byte[] buf = new byte[8];
            if (!ReadProcessMemory(h, (IntPtr)((long)pbi.PebBaseAddress + 0x20), buf, 8, out rr)) return null;
            long pp = BitConverter.ToInt64(buf, 0);
            if (pp == 0) return null;
            if (!ReadProcessMemory(h, (IntPtr)(pp + 0x38), buf, 2, out rr)) return null;
            int len = BitConverter.ToUInt16(buf, 0);
            if (len <= 0 || len > 1024) return null;
            if (!ReadProcessMemory(h, (IntPtr)(pp + 0x40), buf, 8, out rr)) return null;
            long sp = BitConverter.ToInt64(buf, 0);
            byte[] s = new byte[len];
            if (!ReadProcessMemory(h, (IntPtr)sp, s, len, out rr)) return null;
            return Encoding.Unicode.GetString(s);
        } finally { CloseHandle(h); }
    }
}
"@

$mirrorRoot = (Join-Path $env:USERPROFILE ".codex\.chatgpt-projects").ToLower()
$killed = 0
foreach ($p in (Get-Process -Name node_repl -ErrorAction SilentlyContinue)) {
    $cwd = [PwdReader]::ReadCwd($p.Id)
    Write-Host ("PID {0,-6} cwd = {1}" -f $p.Id, $cwd)
    if ($cwd -and $cwd.ToLower().StartsWith($mirrorRoot)) {
        Stop-Process -Id $p.Id -Force
        Write-Host "  -> killed (mirror lock holder)" -ForegroundColor Yellow
        $killed++
    }
}
Write-Host ("Killed {0} mirror lock holder(s)." -f $killed)

$dirs = Get-ChildItem $mirrorRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "g-p-*" }
foreach ($d in $dirs) {
    $t = "$($d.FullName)_t"
    if (Rename-Item $d.FullName $t -PassThru -ErrorAction SilentlyContinue) {
        Rename-Item $t $d.FullName | Out-Null
        Write-Host ("UNLOCKED: {0}" -f $d.Name) -ForegroundColor Green
    } else {
        Write-Host ("STILL LOCKED: {0}  (run again, or fully quit and reopen the app)" -f $d.Name) -ForegroundColor Red
    }
}
if (-not $NoPause) { Read-Host "Done. Press Enter to close" | Out-Null }
