#!/usr/bin/env bash
# 第 2 步：在 Ubuntu 里运行：bash /mnt/d/sandbox-vm/setup/2-安装Docker.sh /mnt/d/sandbox-vm
# 参数是你在 Windows 上解压的项目目录（/mnt/盘符/路径）
set -euo pipefail
SRC="${1:?用法: bash 2-安装Docker.sh /mnt/d/sandbox-vm}"
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2 dos2unix
sudo usermod -aG docker "$USER"
grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null || printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
sudo systemctl enable --now docker 2>/dev/null || true
# 复制到 WSL 自己的磁盘：更快，且 data/ 与 Windows 盘分开
rm -rf ~/sandbox-vm && cp -r "$SRC" ~/sandbox-vm
find ~/sandbox-vm -type f \( -name '*.sh' -o -name '*.yml' -o -name '*.txt' -o -name '.env' -o -name 'Dockerfile' \) -exec dos2unix -q {} +
chmod +x ~/sandbox-vm/sb.sh ~/sandbox-vm/test/selftest.sh ~/sandbox-vm/proxy/entrypoint.sh
echo "完成。到 PowerShell 执行: wsl --shutdown ；再开 Ubuntu： cd ~/sandbox-vm && ./sb.sh up && ./sb.sh test"
