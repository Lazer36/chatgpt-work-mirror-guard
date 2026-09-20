# Troubleshooting: "Could not use this project for a local chat"

Decision tree for the ChatGPT desktop (Windows) Work-creation error.
Chinese UI string: “无法将此项目用于本地聊天”.

## Step 0 - do NOT reinstall the app

Uninstalling wipes `%USERPROFILE%\.codex` (trust table, local history,
Work folders) and the error returns anyway. It only makes things worse.

## Step 1 - retry once

The underlying failure is a race between idle prewarm helpers and the
project-context sync. Retries succeed often (observed repeatedly).

## Step 2 - fully quit and reopen

Tray icon → Quit (closing the window is not enough), then create the Work
again. A fresh app instance has no stale handles.

## Step 3 - run the precise unlocker

`scripts/unlock-codex-mirror.ps1` (right-click → Run with PowerShell).
It prints every node_repl helper with its real working directory, kills
only the ones parked inside the project mirror, and rename-tests each
mirror to prove it is unlockable. Then retry immediately.

## Step 4 - use the resident guard

`scripts/watch-codex-mirror.ps1` keeps the mirror permanently clear while
ChatGPT runs. With the guard active, creations succeeded on the first
click, including after switching projects (verified 2026-09-19/20).

## If it still fails

1. Note the exact second of the failure and open the desktop log:
   `%LOCALAPPDATA%\Packages\OpenAI.Codex_*\LocalCache\Local\Codex\Logs\<yyyy>\<mm>\<dd>\codex-desktop-*.log`
2. Search for `ChatGPT project context sync failed` - confirm `stage=filesystem`
   and that it is not preceded by a trust prompt.
3. Check `%USERPROFILE%\.codex\config.toml` still contains, for every
   project you use:
   `[projects.'c:\users\<you>\.codex\.chatgpt-projects\<project-id>']`
   `trust_level = "trusted"` (missing entries produce a different,
   earlier failure: `Unknown local project`).
4. Report to OpenAI with: app version, project id, failure timestamps,
   the `stage=filesystem` log lines, and the observation that
   `node_repl.exe` helpers hold their working directory inside the
   project mirror while the sync tries to rotate it.

## Related, but different problems

- **"Trust this folder?" prompt** - normal, once per mirror/work folder.
  It appears again after `%USERPROFILE%\.codex` was deleted (e.g. by an
  uninstaller). Clicking Trust persists `trust_level = "trusted"` into
  `%USERPROFILE%\.codex\config.toml`.
- **Repeated trust prompts for the same folder** - the config entry was
  not persisted (file read-only, ACL problem) or the path form differs.
  Inspect `config.toml` under `[projects]`.
