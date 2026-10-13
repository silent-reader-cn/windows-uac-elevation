# windows-uac-elevation

在 **Windows 用户级会话**里，用一条命令拿到管理员权限执行目标命令，并且**把提权进程的输出取回来**。

适用于自动化 / Agent / CI / 运维脚本：你的 shell 不是管理员，但某条命令必须是（重启 NSSM 服务、`sc stop`、改 `HKLM`、写 `Program Files`……）。

```
非管理员 shell  ──Start-Process -Verb RunAs──▶  提权进程（会弹 UAC 或静默通过）
                                                        │
                                              输出重定向到日志文件
                                                        │
   非管理员 shell  ◀──────── 读日志文件 ─────────────────┘
```

英文版见 [README.en.md](README.en.md)。

## 为什么需要这个

提权后的进程**不继承当前 shell 的 stdout/stderr**。所以下面这种写法拿不到任何输出，也判断不出成功还是失败：

```bash
# ❌ 拿不到输出；退出码只代表 Start-Process 本身成功
powershell -Command "Start-Process nssm -ArgumentList 'restart','ComfyUI' -Verb RunAs -Wait"
```

正确做法是**让提权进程把输出写进文件，再回读**。本仓库的两个脚本封装了这件事。

另一个真实坑：**包装器的退出码不代表内层命令成功**。`Start-Process` 只要把进程拉起来就返回 0，里面命令挂掉你也不知道。所以脚本永远打印日志内容 —— **以日志为判据**。

## 环境要求

| 项 | 要求 |
|---|---|
| 系统 | Windows 10 / 11、Server 2016+ |
| PowerShell | 5.1（系统自带）或 PowerShell 7+ |
| 权限 | 当前账号**属于本机 Administrators 组**（否则 UAC 会要求输入管理员密码，无法自动化） |
| UAC | 保持默认即可；完全无人值守时才需要额外设置（见下） |

## 快速开始

### PowerShell 版（原生，推荐）

```powershell
.\scripts\Elevate-Command.ps1 -Command "C:\ProgramData\chocolatey\bin\nssm.exe restart ComfyUI"
```

### Bash / Git-Bash / MSYS 版

```bash
bash scripts/elevate.sh "C:/ProgramData/chocolatey/bin/nssm.exe restart ComfyUI"
```

**命令内部的路径必须写成原生 Windows 形式 `C:/...`**。写成 `/c/...` 会被静默落到 `C:\c\...`，脚本会告诉你"日志文件不存在"。

### 先看看当前状态

```powershell
powershell -NoProfile -Command "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
# True  = 已经是管理员，根本不需要本工具
# False = 需要提权
```

## 关于 UAC 设置（请认真读）

`-Verb RunAs` 会触发 UAC。**UAC 的当前档位决定你要不要做任何改动**：

| `ConsentPromptBehaviorAdmin` | 行为 | 需要改吗 |
|---|---|---|
| **5**（Windows 默认） | 弹"是否允许此应用对你的设备进行更改？" | **不用改**。有人点一下"是"即可。自动化跑批时会一直等 |
| **2** | 要求输入管理员密码 | 必须输入密码，无法自动化 |
| **0** | 静默提权，不弹任何框 | 可完全无人值守 |

查看当前档位：

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' |
  Select-Object EnableLUA, ConsentPromptBehaviorAdmin, PromptOnSecureDesktop | Format-List
```

### ⚠️ 关于把它设成 0（静默提权）

把 `ConsentPromptBehaviorAdmin` 设为 `0` 可以让脚本完全无人值守，但请注意：

> **这会取消 UAC 的提示环节，等于让任何已登录进程都能在你不知情的情况下提权运行。** 这是 Windows 上恶意软件最想拿到的条件之一。

因此本仓库**不提供**"一键把 UAC 关掉"的安装步骤，也**不建议**在通用机器上这么做。合理的用法是：

- **偶尔要用 / 交互式使用** → 保持默认（5），弹框时点"是"。这就是全部代价。
- **必须无人值守**（无人值守的服务机、专用构建机、隔离虚拟机）→ 才考虑设 0，并且应在**受控、专用、可随时重建**的环境里，而不是你的日常工作机。
- 无论哪种情况，都**不要**在听信一个 README 的情况下改安全设置 —— 先确认你知道自己在放弃什么。

如果你的场景确实需要无人值守，正确的做法通常不是降低 UAC，而是把这条命令做成**以服务身份运行的计划任务 / Windows 服务**（SYSTEM 或指定服务账号），让权限来自服务身份，而不是来自 UAC 提示。

## 验证（不看日志不算成功）

提权命令"跑起来了"只说明它被执行，必须独立复核结果：

```bash
# 示例：确认服务真的重启了 —— PID 必须变化
netstat -ano | grep LISTENING | grep ":30005"
```

**PID 没变 = 没重启成功。** 只改状态显示而不换 PID 的"成功"是假的。

## 坑

- **包装器退出码不可信**：永远以日志文件内容为判据。
- **路径必须 `C:/...`**：提权命令里跑的是原生 Windows 程序，`/c/...` 会被静默写到 `C:\c\...`。
- **`-Wait` 可能永久挂住**：若 UAC 弹框在等人点，脚本会一直等待。请给外层调用设超时。
- **提权进程杀不掉**：非提权会话里 `Stop-Process` 杀提权进程会失败，需要用同样提权的命令去收。
- **提权会话的环境变量不同**：PATH、代理都跟当前 shell 不一样，命令里别依赖 shell 里 `export` 过的东西；**用绝对路径**。
- **UAC 被关闭时**（`EnableLUA=0`）：提权通常直接成功，但账号仍可能是受限令牌，先跑一次状态检查。

## 许可

MIT
