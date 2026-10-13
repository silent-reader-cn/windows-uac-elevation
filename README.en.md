# windows-uac-elevation

Run a single command **elevated** from a non-elevated Windows session — and actually get the output back.

Built for automation / agents / CI / ops scripts: your shell isn't an administrator, but one command must be (restarting an NSSM service, `sc stop`, editing `HKLM`, writing to `Program Files`, ...).

```
non-elevated shell  ──Start-Process -Verb RunAs──▶  elevated process (UAC prompt or silent)
                                                          │
                                                 stdout/stderr redirected to a log file
                                                          │
   non-elevated shell  ◀──────── read the log file ───────┘
```

## Why this exists

An elevated process does **not** inherit your shell's stdout/stderr, so this yields no output and no reliable success signal:

```bash
# ❌ no output; the exit code only reflects Start-Process itself
powershell -Command "Start-Process nssm -ArgumentList 'restart','ComfyUI' -Verb RunAs -Wait"
```

The fix is to have the elevated process **write its output to a file and read it back**. Both scripts here do exactly that.

Second real trap: **the wrapper's exit code does not reflect the inner command.** `Start-Process` returns as soon as it launches the process. The scripts therefore always print the captured log — **the log is the source of truth**.

## Requirements

| Item | Requirement |
|---|---|
| OS | Windows 10 / 11, Server 2016+ |
| PowerShell | 5.1 (built in) or PowerShell 7+ |
| Account | Must be a member of the local **Administrators** group, otherwise UAC asks for a password and automation is impossible |
| UAC | Default settings are fine; truly unattended operation needs more (see below) |

## Quick start

```powershell
.\scripts\Elevate-Command.ps1 -Command "C:\ProgramData\chocolatey\bin\nssm.exe restart ComfyUI"
```

```bash
bash scripts/elevate.sh "C:/ProgramData/chocolatey/bin/nssm.exe restart ComfyUI"
```

**Paths inside the command must be native Windows paths (`C:/...`).** A `/c/...` path is silently written to `C:\c\...`; the script will report that no log was produced.

## About UAC settings (please read)

| `ConsentPromptBehaviorAdmin` | Behaviour | Do you need to change it? |
|---|---|---|
| **5** (Windows default) | Prompts "Do you want to allow this app to make changes?" | **No.** Someone clicks Yes. Unattended runs will block |
| **2** | Requires an administrator password | Cannot be automated |
| **0** | Elevates silently, no prompt | Fully unattended |

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' |
  Select-Object EnableLUA, ConsentPromptBehaviorAdmin, PromptOnSecureDesktop | Format-List
```

### ⚠️ About setting it to 0 (silent elevation)

Setting `ConsentPromptBehaviorAdmin` to `0` enables unattended runs, but:

> **It removes the UAC prompt, meaning any process running in your session can elevate without your knowledge.** This is one of the conditions malware on Windows most wants.

This repository therefore **does not ship** a "one-click disable UAC" step and **does not recommend** it on general-purpose machines. Sensible usage:

- **Interactive / occasional** -> keep the default (5) and click Yes. That is the entire cost.
- **Genuinely unattended** (headless build box, dedicated dedicated VM) -> only then consider 0, and only in a controlled, disposable environment — never on your daily driver.
- Either way, **never weaken a security setting just because a README told you to** — understand what you are giving up first.

If you truly need unattended elevation, the right answer is usually not lowering UAC but running the command as a **scheduled task or Windows service** (SYSTEM or a dedicated service account), so the privilege comes from the service identity rather than from bypassing the prompt.

## Verify — the log is not optional

A wrapper exit code of 0 means the process started, nothing more.

```bash
netstat -ano | grep LISTENING | grep ":30005"   # PID must have changed
```

**Same PID = it did not actually restart.**

## Pitfalls

- **Wrapper exit code is not the inner command's exit code** — always read the log.
- **Native paths only** (`C:/...`), never `/c/...`.
- **`-Wait` can hang forever** if a UAC prompt is waiting for a human. Set an outer timeout.
- **Elevated processes cannot be killed** from a non-elevated session; you need an elevated command to clean up.
- **The elevated session has different environment variables** (PATH, proxies). Use absolute paths; don't rely on `export`ed variables.

## License

MIT
