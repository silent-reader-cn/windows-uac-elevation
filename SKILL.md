---
name: windows-uac-elevation
description: "Use when 会话未提权却要跑需管理员的命令（重启服务、改系统设置）。"
version: 1.0.0
author: Hermes Agent
license: MIT
tags: [windows, uac, elevation, admin, nssm, powershell]
related_skills: [windows-services, windows-env, hermes-troubleshooting]
metadata:
  hermes:
    tags: [windows, uac, elevation, admin, nssm, powershell]
    related_skills: [windows-services, windows-env]
---

# Windows 提权执行（UAC）

在**用户级会话**（bash/MSYS，非管理员）里执行需要管理员权限的命令：`nssm restart`、`sc stop`、改 `HKLM`、写 `Program Files` 等。

## When to Use

- 命令报 `OpenService FAILED 5` / `Can't open service!` / `Access is denied`
- 要重启 NSSM 服务（ComfyUI 等常驻服务）让新代码／升级后的依赖生效
- 任何"以管理员身份运行才有用"的运维动作

## 0. 先确认提权是否可行（别瞎试）

```bash
# 当前是否已提权 —— False 才需要下面的提权
powershell -NoProfile -Command "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"

# UAC 行为
powershell -NoProfile -Command "Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' | Select EnableLUA,ConsentPromptBehaviorAdmin,PromptOnSecureDesktop | Format-List"
```

`ConsentPromptBehaviorAdmin` 的含义：

| 值 | 行为 | 对自动化的意义 |
|---|---|---|
| **0** | **静默提权，不弹框** | 可全自动，`Start-Process -Verb RunAs` 直接过 |
| 5 | 提示"是否允许"（默认） | 需要人点；`PromptOnSecureDesktop=0` 时弹框不黑屏 |
| 2 | 需输入管理员密码 | 全自动不可行，要人介入 |

`EnableLUA=0` 表示 UAC 整体关闭。

## 1. 提权执行（输出必须重定向回读）

`terminal` 跑在 bash 里，**提权后的进程不会把 stdout 送回当前会话** —— 必须重定向到文件再读。

```bash
rm -f "C:/tmp/elevated.log"
powershell -NoProfile -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','<你的命令> > C:/tmp/elevated.log 2>&1' -Verb RunAs -Wait"
cat "C:/tmp/elevated.log"
```

`-Wait` 会等提权进程结束。**`terminal` 的退出码只代表 `Start-Process` 成功，不代表里面的命令成功** —— 永远以日志文件内容为判据。

### 实战：重启 NSSM 服务

```bash
rm -f "C:/tmp/svc.log"
powershell -NoProfile -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','C:\ProgramData\chocolatey\bin\nssm.exe restart ComfyUI > C:\tmp\svc.log 2>&1' -Verb RunAs -Wait"
cat "C:/tmp/svc.log"   # 期望看到 STOP / START 操作成功完成
```

`nssm` 常装在 `C:\ProgramData\chocolatey\bin\nssm.exe`；先用 `which nssm` 确认，**提权命令里写绝对路径**（提权进程的 PATH 与当前 bash 不同）。

### 免手写：`scripts/elevate.sh`

```bash
bash scripts/elevate.sh "C:/ProgramData/chocolatey/bin/nssm.exe restart ComfyUI"
```

## 2. 验证（不看日志不算成功）

提权命令"跑成功"只说明它执行了，必须独立复核结果：

```bash
nssm status ComfyUI                                      # SERVICE_RUNNING
netstat -ano | grep LISTENING | grep ":<端口>"             # PID 换新 = 真重启了
curl -s -m 10 http://127.0.0.1:<端口>/system_stats         # 服务自报的版本/依赖
```

**PID 没变 = 没重启成功。** 只改状态显示而不换 PID 的"成功"是假的。

## 坑

- **不要为了绕过限制而提权。** 涉及删数据、改系统配置、装驱动这类破坏性动作，先跟用户确认；提权只是手段，不是跳过确认的理由。
- **提权进程杀不掉**：非提权会话 `Stop-Process` 杀提权进程会失败，要同样提权的命令去收。
- **路径必须 `C:/...`**：提权命令里跑的是原生 Windows 程序，写 `/c/...` 会被静默落到 `C:\c\...`，日志"看起来没写"其实写错地方了。
- **`-Wait` 可能永久挂住**：若 UAC 弹框等人点，脚本会一直等。批处理场景要给外层超时。
- 提权会话的 PATH／代理与当前 bash 不同，别依赖 shell 里 `export` 过的变量。

## 验证清单

- [ ] 提权前确认 `IsInRole(Administrator)` 为 `False`（否则本来就有权限，别绕圈）
- [ ] `ConsentPromptBehaviorAdmin=0` 才可静默提权，否则先跟用户确认
- [ ] 日志文件里有命令自身的成功输出（不是空文件）
- [ ] 目标状态真实生效（服务 PID 变化／端口探活／自报版本核对）
