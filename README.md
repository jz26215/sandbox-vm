# sandbox-vm：在 Windows 上隔离运行 AI 编程工具的思路

**中文** | [English](README.en.md)

> **⚠️ 声明：本项目的代码和文档主要由 AI 生成，仅作思路参考。**
>
> 作者在 AI 助手的指导下，在自己的一台电脑上一步步搭建和实测。没有经过专业的安全审计，不保证没有漏洞，也不保证在你的电脑上能直接跑通。请先读懂再用，风险自负。
>
> 发出来是想听听大家的思路，欢迎在 Issue 里指出问题，或者给出更好的做法。

**English summary** — An AI-generated, reference-only design for running AI coding agents (Claude Code, Codex CLI) on Windows inside WSL2 + Docker. The agent container can read/write only one folder, has no DNS and no route to the internet, and reaches only allowlisted domains through a tinyproxy sidecar. Host iptables/ip6tables pin that sidecar to the single upstream proxy (IP:port) the user chooses, so the sandbox goes fully offline when that proxy is down. Optional VS Code Dev Containers access, with each side channel audited. Docs are in Chinese. Not security-audited.

---

## 想解决什么

作者的需求，也是判断「做到没做到」的标准：

1. 在 Windows 上运行 Claude Code、Codex 这类会自己执行命令的 AI 工具，但不让它们碰到电脑上的其它文件。
2. 沙箱里只能读写**一个**指定的文件夹。
3. 只能通过**自己指定的代理端口**上网，而且只能访问白名单里的域名。代理断了就彻底断网，不能自己改成直连。
4. 除了登录，沙箱里的软件拿不到任何外部的文件和数据，比如剪贴板、SSH 密钥、git 账号、图形界面。
5. 命令行和 VS Code 图形界面都能用。
6. 中文提示，Windows 上双击就能用。

## 架构

```
Windows
 └─ WSL2（Ubuntu，轻量虚拟机）
     ├─ sandbox-fw（iptables / ip6tables 开机服务，比 Docker 先生效）
     └─ Docker
         ├─ box 容器（Claude Code / Codex / python / gcc）
         │    只挂载 data/ → /sandbox；根文件系统只读；非 root；去掉全部权限
         │    只接在 sandbox_net（internal：没有外网路由）；不给 DNS
         │        │
         │        ▼ 只能找 proxy
         └─ proxy 容器（tinyproxy）
              只放行白名单域名 + 指定端口（默认 443）的 HTTPS
                  │ 外网网卡 sbx-egress
                  ▼ sandbox-fw：只能连这一个 IP:端口
              Windows 上的代理软件（上游代理）──► 互联网
```

一句话：**box 没有路，proxy 只认白名单，主机防火墙只让 proxy 去一个地方。**

| 层 | 做什么 | 防的是什么 |
|---|---|---|
| 1. box 容器 | 只接 internal 网络，不给 DNS，只挂载 `data/`，根只读，非 root，`cap_drop: ALL` | 程序无视代理设置直接连外网；DNS 隧道；读写其它文件；改系统 |
| 2. proxy 容器 | tinyproxy 默认拒绝，只放行白名单域名和指定端口 | 访问白名单以外的网站；用 IP 直连 |
| 3. sandbox-fw | proxy 的外网网卡只能连上游代理的 IP:端口；IPv6 全拒；不能主动连 WSL 本机 | proxy 被绕过或配置出错时直连外网；上游代理断了以后回落直连 |

设计理由见 [docs/设计思路.md](docs/设计思路.md)，踩过的坑见 [docs/排查记录.md](docs/排查记录.md)。

## 哪些能直接用，哪些要配置

图例：✅ 作者实测可用　⚙️ 要按你的环境配置　🧪 写了但没充分验证　⚠️ 已知局限

### ✅ 作者实测可用

| 部分 | 实测结果 |
|---|---|
| box / proxy 双容器隔离 | 自检全部通过：看不到 Windows 盘、根只读、非 root、无外部 DNS、绕过代理无路由 |
| 白名单 + 端口限制 | 非白名单域名被拒，用 IP 直连被拒，白名单域名正常 |
| 经上游代理出网 | `UPSTREAM_PROXY=auto:<端口>` 自动找 Windows 主机 IP |
| 主机防火墙 sandbox-fw | proxy 直连 IPv4 地址、域名、IPv6 都被拒；只有上游代理那个 IP:端口能通 |
| 断网测试 | 退出 Windows 上的代理软件后，沙箱 HTTPS 和 HTTP 全部不通；重新打开后自动恢复。真实退出和模拟两种都测过 |
| 沙箱里的 Claude Code + Codex CLI | 都能装、能打开；工具装在镜像里，登录信息存在 `data/`，重建镜像不丢 |
| VS Code 连进沙箱 | Dev Containers 附加到容器，Claude / Codex 插件装在容器那一侧 |
| VS Code 通道收紧 | 不转发 SSH / GPG / git 凭据；终端里的程序不能让 Windows 打开网页；图形界面 X11 通道用只读空目录堵住。逐项检查过，见 [docs/VSCode.md](docs/VSCode.md) |
| 资源上限 | CPU 和内存上限可以在 `.env` 里改，测过 4 核 4G |
| 时区 | 可以改容器时区 |

### ⚙️ 需要你自己配置

| 项目 | 怎么配 |
|---|---|
| 上游代理 | `.env` 里写 `UPSTREAM_PROXY=auto:<你的代理端口>`；代理软件要打开「允许局域网连接」 |
| 白名单 | `allowlist.txt` 按你用的工具增删。默认放了 GitHub、PyPI、npm、Anthropic、OpenAI、VS Code 服务端 |
| Docker 拉镜像走代理 | Docker Hub 直连不通时运行 `setup/4-设置Docker代理.sh <端口>` |
| Linux 用户 | 沙箱里用 uid 1000。WSL 里第一个用户一般就是 1000，不是的话 `data/` 会写不进去 |
| WSL 发行版名 | 脚本默认叫 `Ubuntu` |
| Windows 双击入口 | `windows/打开沙箱文件夹.bat` 里要改成你的 Linux 用户名 |
| VS Code 用户设置 | 运行 `tools/vscode_settings.py`，会列出改动，输入 y 才改，原文件自动备份 |
| 其它 | 时区、资源上限、操作记录路径都在 `.env` |

### 🧪 写了但没充分验证

- **普通 HTTP 的端口限制**：tinyproxy 的 `ConnectPort` 只管 HTTPS（CONNECT）。普通 HTTP 访问白名单域名的其它端口能不能通，没测。
- **重启电脑后防火墙规则**：按 Docker 文档，`DOCKER-USER` 链里的规则会保留。作者环境里一直正常，但没有专门做重启测试。
- **`setup/3-可选-加固WSL.sh`**：让整个 WSL 看不到 Windows 盘、不能调用 Windows 程序。作者没跑过。
- **`dev.containers.forwardWSLServices`**：这个 VS Code 设置名不确定是否正确。设错了也没坏处。
- **登录回调端口**：关掉 VS Code 自动转发端口（`remote.autoForwardPorts=false`）后，插件登录要用的回调端口（如 1455）还能不能转发，没验证。
- **Claude Code 在沙箱里的登录流程**：作者没逐步确认。
- **Windows 家庭版**：WSL2 按理支持，作者没确认自己的版本。

### ⚠️ 已知局限（目前做不到或没解决）

- **VS Code 连接经常卡约 4 分钟**：卡在 Dev Containers 插件内部一个 240 秒的超时，根本原因没查明。有一次在 WSL 刚重启后很快就连上了。详见 [docs/排查记录.md](docs/排查记录.md)。
- **VS Code 插件的通道关不掉**：插件（包括 Claude、Codex 官方插件）能读 Windows 剪贴板；能让 Windows 浏览器打开网址，网址里可以夹带数据，不受白名单限制；还能申请使用你在 VS Code 里登录的账号，但要你点同意。只用命令行时（`./sb.sh claude`、`windows/打开Claude.bat`）没有这些通道。
- **白名单域名本身可以用来外传数据**：比如往 github.com 推代码。域名白名单拦不住这种情况，敏感项目请把白名单删到最少。
- **没有 TLS 解密**：tinyproxy 只看 CONNECT 请求里的主机名。通配域名（如 `*.githubusercontent.com`）放行的范围比较大。
- **不是独立虚拟机**：容器和 WSL 共用一个 Linux 内核。如果出现容器逃逸，就能到达 WSL，而 WSL 默认能看到 Windows 盘（`setup/3` 可以关掉）。
- **proxy 容器还能做域名解析**：用的是 Docker 自带的 DNS，box 容器不能。
- **系统信息看得到**：沙箱里能看到 CPU 型号、内核版本这类信息。

## 不做什么

- **不做任何指纹、地区、设备伪装**，不用于规避任何服务的条款或风控。时区功能只是为了测试和时间有关的代码。
- 请遵守你所用服务（Anthropic、OpenAI 等）的使用条款。

## 快速开始

1. **装 WSL**：用管理员 PowerShell 运行 `setup\1-安装WSL.ps1`，重启电脑，打开 Ubuntu 设置用户名和密码。
2. **准备配置**：把本仓库下载到 Windows，比如 `D:\sandbox-vm`。把 `.env.example` 复制一份改名为 `.env`，填好 `UPSTREAM_PROXY`。
3. **装 Docker**：在 Ubuntu 里运行 `bash /mnt/d/sandbox-vm/setup/2-安装Docker.sh /mnt/d/sandbox-vm`，它会把项目复制到 `~/sandbox-vm`。然后在 PowerShell 运行 `wsl --shutdown`，再重新打开 Ubuntu。
4. **拉镜像走代理**（Docker Hub 直连不通时）：代理软件打开「允许局域网连接」，运行 `bash ~/sandbox-vm/setup/4-设置Docker代理.sh <端口>`。
5. **启动**：`cd ~/sandbox-vm && ./sb.sh up && ./sb.sh test`。最后 3 项（proxy 直连）要等装完网络加固才会通过。
6. **网络加固**：`bash tools/install-fw.sh`，中间要输入 Linux 密码。
7. **断网测试**（可选）：`bash tools/nettest.sh`。
8. **日常使用**：`./sb.sh claude`、`./sb.sh codex`、`./sb.sh shell`；或者在 Windows 上双击 `windows\` 里的 .bat。
9. **想用 VS Code**：看 [docs/VSCode.md](docs/VSCode.md)。

`./sb.sh` 不带参数会列出全部命令：改时区、加减白名单、改端口、改上游代理等。

## 目录结构

```
.
├── README.md
├── README.en.md          英文版 README
├── .env.example            配置样例（复制成 .env）
├── docker-compose.yml      box + proxy 两个容器、两个网络
├── allowlist.txt           白名单域名
├── sb.sh                   控制脚本（在 WSL 里运行）
├── sb.ps1                  Windows PowerShell 快捷入口
├── fw.sh                   主机防火墙规则（由 tools/install-fw.sh 装成 sandbox-fw 服务）
├── box/Dockerfile          沙箱镜像：node:22-bookworm-slim + Claude Code + Codex + python/gcc
├── proxy/                  tinyproxy 镜像和启动脚本
├── test/selftest.sh        13 项隔离自检
├── setup/                  1 装 WSL / 2 装 Docker / 3 可选加固 WSL / 4 Docker 走代理
├── tools/
│   ├── install-fw.sh       安装网络加固
│   ├── nettest.sh          断网测试
│   ├── vscode_settings.py  VS Code 推荐设置（改前确认并备份）
│   └── vscode_check.py     VS Code 连着时，检查沙箱能碰到哪些外部通道
├── windows/                双击入口（.bat）
└── docs/
    ├── 设计思路.md
    ├── VSCode.md
    └── 排查记录.md
```

## 作者的测试环境（2026 年 11 月）

- Windows 11，家庭版还是专业版没确认
- WSL2 Ubuntu，NAT 网络模式
- Docker 29.1.3（Ubuntu 软件源里的 `docker.io`）
- VS Code 1.147 + Dev Containers 0.475.0
- Claude Code 2.1.331、Codex CLI 0.172.0

## 相关项目

搭完以后才发现已经有不少类似的做法。下面这些作者**没有逐个试用**，介绍来自各项目的说明页，可以对比参考：

- [Claude Code devcontainer 防火墙脚本（gist）](https://gist.github.com/mmizutani/01d47aa43f0593bfd1c754d0898f7d5c)：基于 Claude Code 官方 devcontainer 的 `init-firewall.sh` 改的，用 iptables 只放行白名单
- [MyKEms/claude-code-sandbox](https://github.com/MyKEms/claude-code-sandbox)：Dev Container 模板，只放行白名单的代理，登录信息持久化
- [FoamoftheSea/claude-code-sandbox](https://github.com/FoamoftheSea/claude-code-sandbox)：同样是 internal 网络 + 代理，用 Squid 读取 TLS 的 SNI 做白名单
- [foxirain/agent-egress-lock](https://github.com/foxirain/agent-egress-lock)：Docker + Squid + 主机防火墙，限制 AI 工具的出网
- [EraPartner/Lockbox](https://github.com/EraPartner/Lockbox)：devcontainer 出网锁定，防火墙 + Squid 白名单
- [thiagolmoraes/leash](https://github.com/thiagolmoraes/leash)：带 TLS 解密、域名白名单和系统调用监控
- [agent37-platform/claude-code-docker](https://github.com/agent37-platform/claude-code-docker)、[itscooleric/clide](https://github.com/itscooleric/clide)：把 Claude Code 等工具放进带出网防火墙的容器

本项目比较侧重这几点（不代表别的项目没有）：Windows + WSL2 场景；出口串到用户本机代理软件的端口，并在主机防火墙层面做到「代理断了就断网」；把 VS Code 连进沙箱后的各条通道逐项列出来；中文说明和双击入口。

## 想请教大家的问题

1. VS Code Dev Containers 连接卡 240 秒的原因，以及怎么避免。
2. tinyproxy 比 Squid（SNI peek-and-splice）或 Envoy 差多少，值不值得换。
3. 怎么防止通过白名单域名外传数据，比如限制上传、只读 token。
4. VS Code 插件的剪贴板和打开浏览器通道，有没有办法在不影响登录的前提下关掉。
5. 要不要换成 gVisor、Kata 或者 Hyper-V 隔离的完整虚拟机，换了代价有多大。

## 许可证

待定。
