# LocalAI-Guardian

一个专注于 Windows 本地 AI 进程保活的开源小工具，不包含网络服务、账户凭据或远程控制功能。

## 功能

- 定期检查目标本地 AI 程序是否正在运行
- 进程退出后自动重新启动
- 限制一小时内最大重启次数，避免无限重启
- 记录运行日志并自动限制日志大小
- 提供独立的状态查看脚本
- 可以通过 VBS 在后台静默启动

默认示例监控 Ollama：

```text
ollama serve
```

## 文件

| 文件 | 作用 |
| --- | --- |
| `看门狗.ps1` | 主监控循环，发现进程退出后自动拉起 |
| `Status.ps1` | 查看目标进程和最近日志 |
| `Start-Silent.vbs` | 无窗口启动看门狗 |
| `config.example.json` | 配置模板，包含目标进程、启动参数和检查间隔 |
| `.gitignore` | 排除运行日志 |

## 配置

先复制配置模板：

```powershell
Copy-Item .\config.example.json .\config.json
```

然后编辑本地生成的 `config.json`：

```json
{
  "processName": "ollama",
  "executablePath": "ollama.exe",
  "arguments": "serve",
  "workingDirectory": "",
  "startHidden": true,
  "checkIntervalSeconds": 5,
  "restartDelaySeconds": 5,
  "maxRestartsPerHour": 12,
  "logFileName": "guardian.log",
  "logMaxBytes": 1048576,
  "logTailLines": 1000
}
```

主要字段：

| 字段 | 说明 |
| --- | --- |
| `processName` | 用于检测的进程名，不带 `.exe` |
| `executablePath` | 要启动的程序，可以是绝对路径或 PATH 中的命令 |
| `arguments` | 启动参数 |
| `workingDirectory` | 可选工作目录 |
| `startHidden` | 是否隐藏启动窗口 |
| `checkIntervalSeconds` | 检测间隔 |
| `restartDelaySeconds` | 启动后等待时间 |
| `maxRestartsPerHour` | 每小时内最大重启次数 |

如果需要换成其他本地 AI 程序，只需要修改这些字段。

## 使用

前台运行，方便观察日志：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\看门狗.ps1"
```

只检查并处理一次：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\看门狗.ps1" -Once
```

后台静默运行：

```text
双击 Start-Silent.vbs
```

查看状态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Status.ps1"
```

查看日志：

```powershell
Get-Content ".\guardian.log" -Tail 50 -Wait
```

## 停止

在任务管理器中结束对应的 `powershell.exe` 进程，或者关闭启动它的终端窗口。

如果通过 `Start-Silent.vbs` 启动，可在任务管理器中查找 PowerShell 命令行中包含 `看门狗.ps1` 的进程并结束。

## 适用情况

- Windows 10 或 Windows 11
- 本机已经安装需要长期运行的 AI 程序
- 程序支持命令行启动
- 用户希望进程退出后自动恢复

## 不适用情况

- macOS 或 Linux
- 必须通过图形界面手动启动的程序
- 不能重复启动的程序
- 需要网络服务或远程管理功能的场景

## 说明

这是一个最小化进程守护示例。运行前请确认 `config.json` 中的程序路径和参数正确，并确认该程序允许被重复启动。
