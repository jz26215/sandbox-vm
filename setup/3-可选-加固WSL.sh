#!/usr/bin/env bash
# 可选：让 WSL 这台虚拟机本身也看不到 Windows 盘、不能调用 Windows 程序。
# 影响：这个 Ubuntu 里所有东西都访问不了 /mnt/c、/mnt/d（其他 WSL 用法会受影响）。
set -e
sudo tee -a /etc/wsl.conf >/dev/null <<'EOF'
[automount]
enabled=false
mountFsTab=false
[interop]
enabled=false
appendWindowsPath=false
EOF
echo "已写入 /etc/wsl.conf。到 PowerShell 执行 wsl --shutdown 生效。撤销：删掉这几行再 shutdown。"
