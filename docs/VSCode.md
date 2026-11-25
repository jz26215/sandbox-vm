# 用 VS Code 连进沙箱

> 本文主要由 AI 生成，仅作思路参考。

原理：VS Code 的窗口在 Windows 上运行，但读文件、运行命令、插件都在沙箱容器里运行。只用命令行的话，不需要这一部分。

## 第一次准备

1. 在 Windows 上装 VS Code，再装两个微软官方插件：**WSL**、**Dev Containers**。
2. 在 Ubuntu 里运行 `python3 ~/sandbox-vm/tools/vscode_settings.py`。它会列出要改的设置，输入 `y` 才改，原文件自动备份到同一个目录。

## 打开沙箱

- **一键打开**：双击 `windows/VSCode打开沙箱.bat`。它先启动沙箱，再用 `code --folder-uri` 直接打开容器里的 `/sandbox`。
- **手动打开**：普通 VS Code 窗口里看不到这个容器，因为 Docker 装在 WSL 里。步骤：
  1. 按 `Ctrl+Shift+P`，运行 `WSL: Connect to WSL`。
  2. 在 WSL 窗口左侧打开「远程资源管理器」，上方下拉选「开发容器」。
  3. 右键 `sandbox-vm-box-1`，选「附加到新窗口」。
  4. 连上后打开文件夹 `/sandbox`。
- 注意：附加时选「附加到正在运行的容器」，**不是**「附加到 Kubernetes 容器」。

## 装插件

在**连进沙箱的那个窗口**里安装官方插件：Claude Code（发布者 Anthropic）、Codex（发布者 OpenAI）。扩展页面要显示「已在容器 sandbox-vm-box-1 上启用」才算装对。装在本地的话，插件就不在沙箱里，没有隔离。

## 推荐设置（`tools/vscode_settings.py` 会设置）

| 设置 | 值 | 作用 |
|---|---|---|
| `window.restoreWindows` | `none` | 打开 VS Code 不自动连回沙箱 |
| `dev.containers.copyGitConfig` | `false` | 不把本机的 git 账号信息复制进沙箱 |
| `dev.containers.gitCredentialHelperConfigLocation` | `none` | 沙箱不能借用本机的 git 登录 |
| `dev.containers.dockerCredentialHelper` | `false` | 沙箱不能借用本机的 Docker 登录 |
| `remote.downloadExtensionsLocally` | `true` | 插件由 Windows 下载后传进沙箱，沙箱不用放行插件商店 |
| `remote.autoForwardPorts` | `false` | 不自动把沙箱里的端口转发到本机 |
| `remote.restoreForwardedPorts` | `false` | 重连时不恢复上次转发的端口 |
| `dev.containers.forwardWSLServices` | `false` | 不把 WSL 里的 SSH / GPG 等服务转进沙箱（设置名不确定） |
| `dev.containers.mountWaylandSocket` | `false` | 不把 Wayland 图形界面接进沙箱 |
| `git.useIntegratedAskPass` / `git.terminalAuthentication` | `false` | 沙箱里的 git 不能通过 VS Code 弹框找你要密码 |
| `terminal.integrated.env.linux` | `{"BROWSER": null}` | 终端里的程序不能让 Windows 打开网页 |

## 通道检查结果

VS Code 连着沙箱、并开着一个终端时运行：
`cd ~/sandbox-vm && docker compose exec -T box python3 - < tools/vscode_check.py`

| 通道 | 状态 | 怎么处理的 |
|---|---|---|
| Windows 盘 | ✅ 看不到 | 只挂载 `data/` |
| SSH 密钥、GPG | ✅ 没有 | 设置关掉 |
| git / Docker 登录 | ✅ 借不到 | 设置关掉 |
| git 密码弹窗 | ✅ 没有 | 设置关掉 |
| 图形界面 Wayland | ✅ 没有 | 设置关掉 |
| 图形界面 X11 | ✅ 连不上 | VS Code 设置管不住，compose 把只读空目录挂到 `/tmp/.X11-unix` |
| 终端里的程序打开 Windows 网页 | ✅ 不能 | `BROWSER=null` |
| 端口自动转发 | ✅ 关闭 | 设置关掉（登录回调端口未验证） |
| 插件打开 Windows 网页 | ⚠️ 开着 | 登录要用。网址里能夹带数据，不受白名单限制 |
| 插件读剪贴板 | ⚠️ 开着 | VS Code 给插件的接口，关不掉。用 VS Code 时剪贴板里别放密码 |
| 插件申请 VS Code 账号 | ⚠️ 要你同意 | 弹窗时点拒绝 |

## 已知问题：连接卡约 4 分钟

Dev Containers 插件第一次转发连接时，走了一条已经断掉的内部通道，要等满 240 秒超时才换别的办法。沙箱、代理、防火墙都和这个无关。已经排除的原因和时间线见 [排查记录.md](排查记录.md)。连上以后使用正常，所以尽量连上就别关。
