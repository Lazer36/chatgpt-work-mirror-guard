# chatgpt-work-mirror-guard

Fixes the Windows ChatGPT desktop error **"Could not use this project for a local chat" / “无法将此项目用于本地聊天”** that appears when you create a **Work** inside a ChatGPT project.

A tiny guard script kills the app's own idle `node_repl.exe` prewarm helpers while ChatGPT is running — those helpers park their working directory inside the project mirror and block the file-system sync that a Work creation needs. Everything else is left alone.

解决了在ChatGPT项目中创建“工作区”时出现的Windows ChatGPT桌面错误：“无法将此项目用于本地聊天”。 

该修复方案包含了一个小型脚本：在ChatGPT运行期间，该脚本会终止应用程序自身的idle_node_repl.exe进程。这些进程会占用项目镜像中的工作目录，从而阻碍了创建“工作区”所需的文件系统同步操作。除此之外，其他一切功能均不受影响。

> Tested against ChatGPT desktop `26.915.4065.0` (OpenAI.Codex MSIX) on Windows 11, 2026-09.
> Verified live: creations succeed on the first click and after switching projects; log shows `Conversation created` with no `sync failed`.

---

## Symptoms & root cause

When you open a project's **Work** tab and create a Work, the desktop app sometimes fails with:

> Could not use this project for a local chat / 无法将此项目用于本地聊天

The desktop log (`...\Local\Packages\OpenAI.Codex_*\LocalCache\Local\Codex\Logs\...`) shows, right before every failure:

```
error  ChatGPT project context sync failed   stage=filesystem   sourceCount=5 ...
info   client.performance.span   outcome=failure reason=submit_failed
```

**Root cause (verified on the machine, not speculation):**

1. Every time you open a project's Work page, the app spawns idle *prewarm* helpers (`node_repl.exe`) whose **current working directory is the project mirror** `%USERPROFILE%\.codex\.chatgpt-projects\<project-id>\`. Windows keeps a lock on a process' working directory.
2. When you create a Work, the app must **rewrite/rotate that same mirror** during the project-context sync.
3. Rotation collides with the prewarm handles → `stage=filesystem` failure → the generic error.

It is a race *by design* on Windows: the app both parks a process in the directory it wants to rotate. This matches the reports in openai/codex issues [#35680](https://github.com/openai/codex/issues/35680), [#34499](https://github.com/openai/codex/issues/34499) and [#42215](https://github.com/openai/codex/issues/42215).

> ⚠️ Reinstalling the app does **not** fix this (it wipes your trust table and local history and the error returns). Reinstalling is exactly what made things worse for us.

## Quick start

Requirements: Windows 10/11, PowerShell 5.1+ (built-in). No admin needed except the optional auto-start.

**Option A - one-shot fix (when the error appears):**
Right-click `scripts/unlock-codex-mirror.ps1` → *Run with PowerShell*. It kills only the mirror-parked helpers (it reads each process' *real* cwd from its PEB — active conversations are never touched), then retry creating the Work. No app restart needed.

**Option B - resident guard (recommended):**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\watch-codex-mirror.ps1
```

While ChatGPT runs it sweeps every 300 ms and kills mirror-parked helpers the moment they appear — creations succeed on the first click. It **self-exits ~45 s after ChatGPT closes**, so nothing lingers.

**Option C - auto-start with ChatGPT (no boot autostart):**
Double-click `install-auto-start.bat` (admin, once). It registers a WMI event subscription: when ChatGPT starts, the guard launches hidden; when ChatGPT closes, the guard exits by itself. Zero footprint while you are not using ChatGPT. Undo with `uninstall-auto-start.bat`.

## How the guard stays safe

| Check | Effect |
|---|---|
| process name must be `node_repl.exe` | ChatGPT's own helper; nothing else is considered |
| real cwd (read from PEB, not guessed) must be inside `.codex\.chatgpt-projects` | active conversations live under `Documents\Codex\<date>\<slug>` and are never matched |
| kills are per-process | other chats, windows and apps are unaffected |

Known trade-offs (rare): if a conversation itself runs *inside* the mirror (observed once right after a mirror reset), its browser/computer-use tools pause until you send a new message or reopen the chat; killing prewarms gives up their "faster Work start" benefit (~fraction of a second).

## Repository layout

```
scripts/watch-codex-mirror.ps1          resident guard (self-exits with ChatGPT)
scripts/unlock-codex-mirror.ps1         one-shot precise unlocker
scripts/install-wmi-subscription.ps1    auto-start with ChatGPT (admin, once)
scripts/uninstall-wmi-subscription.ps1  remove the auto-start (admin, once)
install-auto-start.bat / uninstall-auto-start.bat   elevated launchers
docs/troubleshooting.md                 full decision tree when the error appears
docs/timeline.md                        the original investigation, step by step
```

## FAQ

**Does it steal performance?**
While ChatGPT runs: ~3 % of one core, ~90 MB RAM (it is PowerShell). When ChatGPT is closed: zero (the guard is not running).

**I use several chats / Work windows at once - any impact?**
No. Helpers are per-conversation with their own working directories; the guard filters by the mirror path, so normal conversations are untouched and kills are per-process, never per-window.

**The error came back once - what do I do?**
Click *Create* again. If it persists, run the unlocker script, or fully quit ChatGPT (tray icon → Quit) and reopen. Do **not** reinstall the app.

## Disclaimer

This is an unofficial community workaround for an upstream defect, provided as-is with no warranty. It terminates idle helper processes belonging to the ChatGPT desktop app on your own machine. Not affiliated with OpenAI.

## License

[MIT](LICENSE)
