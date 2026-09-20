# Investigation timeline (2026-09-19, one evening)

All times local (UTC+8). Machine: Windows 11, ChatGPT desktop 26.915.4065.0
(OpenAI.Codex MSIX). One ChatGPT project ("mirror" = local copy of the
project under `%USERPROFILE%\.codex\.chatgpt-projects\<project-id>`),
5 source PDFs (~77 MB).

## Background

The user had reinstalled the desktop app earlier that day to fix an
unrelated issue. Creating a Work inside the project then failed with
"Could not use this project for a local chat" / “无法将此项目用于本地聊天”.

## Act 1 - trust table wiped by the reinstall (20:06-20:14)

- `%USERPROFILE%\.codex` timestamps all start at 20:06: the reinstall had
  deleted it, including the `[projects] trust_level` entries in config.toml.
- 20:07 Work creation → mirror rebuilt, files synced, but the app logged
  ~30x `Failed to prewarm local conversation: Unknown local project`
  (20:08-20:08:55), then on every submit:
  `ChatGPT project context sync failed stage=filesystem` → `submit_failed`.
- For ~6 minutes the app silently retried instead of prompting (defect #1:
  swallowed failure).
- 20:14:47 the app finally surfaced "Trust this folder?"; clicking Trust
  wrote `trust_level = "trusted"` at 20:14:48.529; a session started
  118 ms later. First layer fixed.

## Act 2 - the error keeps coming back (20:25-23:00)

- 20:25:45: same `sync failed stage=filesystem` **with trust already in
  place** → a second, independent cause exists.
- The app-server database (`logs_2.sqlite`) and desktop logs showed the
  UI string maps to `sync failed stage=filesystem` → `submit_failed`
  (22 ms apart, every time).
- ZCode-side theory (network/proxy) was tested and **rejected**: TUN off /
  system proxy on throughout, and the same direct-connect timeouts appeared
  during successful creations too (noise, not cause).
- ChatGPT-side investigation killed two `node_repl.exe` helpers and moved
  the mirror away at 20:46:30 → mirror rebuilt 20:47 → **20:48:10
  `Conversation created`** (success #1). But it was still unclear why.
- 21:55 x3 and 23:00 x3: failures returned. A fresh `bang-w` work was
  created successfully at 22:24-22:26 (success #2) in between.

## Act 3 - root cause proven (23:14-23:45)

- Reading each helper's **real working directory from its PEB**
  (NtQueryInformationProcess) showed pairs of `node_repl.exe` with
  `cwd = <project mirror>` - the app parks idle prewarm threads inside
  the directory it later needs to rotate.
- A reversible rename test on the mirror failed with sharing violation
  while those helpers lived, and succeeded after they were killed:
  the directory lock is the mechanism.
- Deterministic reproduction: every entry into the project's Work page
  spawns a fresh pair of mirror-cwd helpers; the next Work creation's
  sync (`stage=filesystem`) then loses the race. Failures at 21:55, 23:00,
  23:25, 23:28-30, 23:44, 23:51 all fit; successes (20:48, 22:26, 23:54 x2,
  23:59, 00:17) all happened with the mirror clear.
- Removing a leftover `output\` file inside the mirror (an open handle on
  it) also unblocked the rename once - file handles inside the directory
  block rotation the same way directory handles do.

## Act 4 - the guard (23:52 onward)

- A resident script sweeps every 300 ms, reads each `node_repl.exe`
  helper's PEB cwd, and kills only helpers parked inside the mirror.
  A mutex enforces single instance; it self-exits 45 s after ChatGPT
  closes; a WMI `__InstanceCreationEvent` subscription (created once,
  admin) starts it automatically when ChatGPT launches.
- Result: creations on the first click, including after switching
  projects. Log evidence: `Conversation created` at 23:54:20, 23:54:35,
  23:59:01, 00:17:56 with no `sync failed` in between.

## Honest caveats

- The first failure after the fix may still appear if the click lands
  within the sweep interval; the second click succeeds.
- If a conversation itself runs inside the mirror (observed once, right
  after a mirror reset), its browser/computer-use tools pause when the
  guard kills its helper; text chat and history are unaffected.
- The defect is upstream (the app prewarms into the directory it later
  rotates). The guard is a workaround, not a fix of the app.
