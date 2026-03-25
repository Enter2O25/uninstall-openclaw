# OpenClaw 一键卸载脚本

这套脚本面向 `Linux`、`macOS`、`Windows` 三个平台，启动后会提供两种卸载模式：

1. `全部卸载清理（包括环境）`
2. `保留环境，只卸载清理 OpenClaw`

## 文件说明

- `uninstall-openclaw.sh`
  Linux / macOS 主脚本，支持交互式和命令行参数。
- `uninstall-openclaw.command`
  macOS 启动包装，双击后会调用 `uninstall-openclaw.sh`。
- `uninstall-openclaw.ps1`
  Windows PowerShell 主脚本。
- `uninstall-openclaw.bat`
  Windows 启动包装，双击后会调用 `uninstall-openclaw.ps1`。
- `remote-uninstall.sh`
  Linux / macOS 远程启动脚本，会下载并执行最新的 `uninstall-openclaw.sh`。
- `remote-uninstall.ps1`
  Windows 远程启动脚本，会下载并执行最新的 `uninstall-openclaw.ps1`。

## 功能覆盖

### 两种模式都会执行

- 停止名称或命令行中包含 `openclaw` 的进程
- 停止并清理常见的 OpenClaw 服务
- 尝试调用系统登记的卸载入口或常见包管理器卸载 OpenClaw
- 删除常见安装目录、缓存目录、日志目录、启动项和快捷方式

### 仅“全部卸载清理（包括环境）”会执行

- 删除常见的 OpenClaw 专属虚拟环境目录
- 删除 `OPENCLAW_*` 相关环境变量
- 清理 `PATH` 或 shell 配置中与 OpenClaw 相关的条目

## 使用方式

脚本会尽量自动清理，但如果 OpenClaw 安装在系统目录、注册为系统服务，或写入了系统级环境变量，请使用 `sudo`、管理员 PowerShell 或“以管理员身份运行”执行。

## 远程一键卸载

适合“不想先 clone 仓库，只想直接远程执行”的场景。

### Linux / macOS

交互式远程执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main/remote-uninstall.sh | bash
```

远程执行“全部卸载清理（包括环境）”：

```bash
curl -fsSL https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main/remote-uninstall.sh | bash -s -- --mode full --yes
```

远程执行“保留环境，只卸载清理 OpenClaw”：

```bash
curl -fsSL https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main/remote-uninstall.sh | bash -s -- --mode app --yes
```

如果目标机器没有 `curl`，也可以使用：

```bash
wget -qO- https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main/remote-uninstall.sh | bash -s -- --mode full --yes
```

### Windows

交互式远程执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create((Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main/remote-uninstall.ps1').Content))"
```

远程执行“全部卸载清理（包括环境）”：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create((Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main/remote-uninstall.ps1').Content)) -Mode full -Yes"
```

远程执行“保留环境，只卸载清理 OpenClaw”：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create((Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main/remote-uninstall.ps1').Content)) -Mode app -Yes"
```

如果你需要走企业镜像或私有 Raw 地址，可以通过 `OPENCLAW_REMOTE_BASE_URL` 覆盖默认下载地址。

### Linux / macOS

先赋予执行权限：

```bash
chmod +x ./uninstall-openclaw.sh ./uninstall-openclaw.command
```

交互式运行：

```bash
./uninstall-openclaw.sh
```

直接指定“全部卸载清理（包括环境）”：

```bash
./uninstall-openclaw.sh --mode full --yes
```

直接指定“保留环境，只卸载清理 OpenClaw”：

```bash
./uninstall-openclaw.sh --mode app --yes
```

先预演、不真正删除：

```bash
./uninstall-openclaw.sh --mode full --dry-run
```

### Windows

最简单方式：

- 双击 `uninstall-openclaw.bat`

也可以在 PowerShell 中运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\uninstall-openclaw.ps1
```

直接指定模式：

```powershell
.\uninstall-openclaw.ps1 -Mode full -Yes
.\uninstall-openclaw.ps1 -Mode app -Yes
```

预演模式：

```powershell
.\uninstall-openclaw.ps1 -Mode full -DryRun
```

## 自定义安装目录

如果你的 OpenClaw 不在脚本内置的默认目录里，可以通过环境变量追加路径：

### Linux / macOS

```bash
export OPENCLAW_EXTRA_PATHS="/data/openclaw:/srv/openclaw"
./uninstall-openclaw.sh --mode full --yes
```

### Windows

```powershell
$env:OPENCLAW_EXTRA_PATHS = 'D:\OpenClaw;E:\Apps\OpenClaw'
.\uninstall-openclaw.ps1 -Mode full -Yes
```

## 当前脚本的默认假设

- OpenClaw 相关目录命名通常包含 `openclaw` / `OpenClaw`
- “保留环境”指保留 Python / Conda / pipx 等运行环境，只卸载 OpenClaw 本体及其数据
- “全部卸载”只清理明显属于 OpenClaw 的环境目录，不会主动删除用户共享的 Python、Node、Conda 主程序

如果你的 OpenClaw 使用了非常规服务名、环境变量名或安装路径，建议先用 `dry-run` 预览，再按实际情况补充 `OPENCLAW_EXTRA_PATHS`。
