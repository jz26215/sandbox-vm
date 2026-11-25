#!/usr/bin/env bash
# 安装网络加固 sandbox-fw：proxy 容器只能连 .env 里的上游代理（iptables + ip6tables + 开机服务）
# 用法: cd ~/sandbox-vm && bash tools/install-fw.sh     （中间要输入 Linux 密码）
# 退回: sudo systemctl disable --now sandbox-fw && sudo sandbox-fw off
cd "$(dirname "$0")/.." || exit 1
DST="$(pwd)"
[ -f .env ] || { echo "✘ 找不到 .env：先 cp .env.example .env，填好 UPSTREAM_PROXY"; exit 1; }
grep -qE '^UPSTREAM_PROXY=.+' .env || echo "提醒：UPSTREAM_PROXY 是空的，装好后 proxy 外网会全部拒绝"
echo "== 1. 安装规则脚本和开机服务"
sudo install -o root -g root -m 755 fw.sh /usr/local/sbin/sandbox-fw || { echo "✘ 安装失败"; exit 1; }
sudo tee /etc/systemd/system/sandbox-fw.service >/dev/null <<EOF
[Unit]
Description=sandbox-vm network hardening (proxy can only reach upstream proxy)
After=network.target
Before=docker.service
PartOf=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/sandbox-fw apply $DST/.env

[Install]
WantedBy=multi-user.target docker.service
EOF
sudo systemctl daemon-reload
sudo systemctl enable sandbox-fw >/dev/null 2>&1
sudo systemctl restart sandbox-fw || { sudo systemctl status sandbox-fw --no-pager -l; exit 1; }
echo "== 2. 重建沙箱网络（data 不受影响）"
docker compose down
./sb.sh up || { echo "✘ 启动失败"; exit 1; }
sleep 2
echo "== 3. 检查"
ip link show sbx-egress >/dev/null 2>&1 && echo "  ✔ 网卡 sbx-egress 已建好" || echo "  ✘ 没找到网卡 sbx-egress"
# 注意：Docker 会把 ~/.docker/config.json 里的代理注入成容器的 HTTP_PROXY，测直连前必须去掉，否则会误报
px() { docker compose exec -T proxy sh -c 'unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; wget -q -T 6 -O /dev/null "$1"' _ "$1" >/dev/null 2>&1 && echo "能 ✘" || echo "不能 ✔"; }
echo "  proxy 直连 IPv4 1.1.1.1：$(px http://1.1.1.1)"
echo "  proxy 直连 example.org：$(px http://example.org)"
echo "  proxy 直连 IPv6：$(px 'http://[2606:4700:4700::1111]/')"
echo "  沙箱经代理 → github.com：$(docker compose exec -T box curl -s -o /dev/null -m 15 -w '%{http_code}' https://github.com 2>/dev/null)（200 = 正常）"
./sb.sh test
sudo /usr/local/sbin/sandbox-fw show
