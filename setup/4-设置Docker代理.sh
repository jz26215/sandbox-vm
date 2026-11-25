#!/usr/bin/env bash
# 第 4 步：让 Docker 通过 Windows 上的代理下载镜像（WSL 为 NAT 模式时用）
# 用法: bash ~/sandbox-vm/setup/4-设置Docker代理.sh [端口]
# 不填端口会自动试常见端口。前提：代理客户端打开「允许局域网连接(Allow LAN)」
set -uo pipefail
HOST=$(ip route show default | awk '{print $3; exit}')
echo "Windows 主机 IP（WSL 看到的）: $HOST"
try() { curl -s -o /dev/null -m 8 -w '%{http_code}' -x "http://$HOST:$1" https://registry-1.docker.io/v2/ 2>/dev/null; }
PORT="${1:-}"
if [ -z "$PORT" ]; then
  for p in 7890 7897 10809 10808 1080 8080 20171 20172; do
    c=$(try $p); echo "  试 $p → ${c:-无响应}"
    if [ "$c" = "401" ] || [ "$c" = "200" ]; then PORT=$p; break; fi
  done
else
  c=$(try "$PORT"); echo "  试 $PORT → ${c:-无响应}"
  [ "$c" = "401" ] || [ "$c" = "200" ] || PORT=""
fi
if [ -z "$PORT" ]; then
  echo "✘ 没连上代理。检查：1) 代理客户端已打开「允许局域网」 2) 端口对不对（在客户端设置里看 HTTP/混合端口）"
  echo "  3) Windows 防火墙弹窗时选「允许」。改好后重跑本脚本，可带端口：bash $0 7890"
  exit 1
fi
P="http://$HOST:$PORT"
echo "✔ 代理可用: $P"
# 1) Docker 服务本身（拉镜像）
sudo mkdir -p /etc/systemd/system/docker.service.d
printf '[Service]\nEnvironment="HTTP_PROXY=%s"\nEnvironment="HTTPS_PROXY=%s"\nEnvironment="NO_PROXY=localhost,127.0.0.1,172.30.0.0/24"\n' "$P" "$P" \
  | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null
# 2) 构建镜像时 apk 下载
mkdir -p ~/.docker
printf '{\n "proxies": {"default": {"httpProxy": "%s", "httpsProxy": "%s", "noProxy": "localhost,127.0.0.1,172.30.0.0/24"}}\n}\n' "$P" "$P" > ~/.docker/config.json
sudo systemctl daemon-reload && sudo systemctl restart docker
# 3) 沙箱出口也走这个代理（自动跟随主机 IP 变化）
if [ -f ~/sandbox-vm/.env ]; then
  sed -i "s|^UPSTREAM_PROXY=.*|UPSTREAM_PROXY=auto:$PORT|" ~/sandbox-vm/.env
  echo "已设 ~/sandbox-vm/.env: UPSTREAM_PROXY=auto:$PORT"
fi
# 4) 顺手装 buildx，去掉那条 WARN
sudo apt-get install -y docker-buildx >/dev/null 2>&1 && echo "已装 docker-buildx" || echo "docker-buildx 没装上（不影响使用）"
echo "完成。接着运行: cd ~/sandbox-vm && ./sb.sh up && ./sb.sh test"
