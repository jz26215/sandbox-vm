#!/usr/bin/env bash
# 网络加固：proxy 容器的外网网卡（sbx-egress）只能连上游代理的 IP:端口，其余一律拒绝；也不能主动连 WSL 本机
# IPv4 用 DOCKER-USER 链；IPv6 因为上游只有 IPv4，sbx-egress 的 IPv6 一律拒绝
# 安装后在 /usr/local/sbin/sandbox-fw（root 所有），由 systemd 服务 sandbox-fw 在 Docker 启动前运行
# 用法: sandbox-fw apply <.env 路径> | target <.env 路径> | show | off
# 退回: sudo systemctl disable --now sandbox-fw && sudo sandbox-fw off
IF=sbx-egress
STATE=/run/sandbox-fw.target
cmd="${1:-show}"; ENV="${2:-}"

# 由 .env 的 UPSTREAM_PROXY 算出允许的 IP:端口；算不出就输出空（= 外网全部拒绝）
target() {
  local u h="" ip port i
  u=$(grep -E '^UPSTREAM_PROXY=' "$ENV" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r" ')
  case "$u" in
    auto:*) for i in 1 2 3 4 5 6 7 8 9 10; do
              h=$(ip route show default 2>/dev/null | awk '{print $3; exit}'); [ -n "$h" ] && break; sleep 1
            done
            ip="$h"; port="${u#auto:}";;
    *:*)    ip="${u%:*}"; port="${u##*:}";;
    *)      ip=""; port="";;
  esac
  if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ && "$port" =~ ^[0-9]{1,5}$ ]]; then echo "$ip:$port"; else echo ""; fi
}
need_root() { [ "$(id -u)" = 0 ] || { echo "要用 sudo 运行"; exit 1; }; }
rej() { iptables "$@" -j REJECT 2>/dev/null || iptables "$@" -j DROP; }
ip6t() { command -v ip6tables >/dev/null 2>&1 && ip6tables "$@"; }

apply() {
  local t ip port
  t=$(target); ip="${t%:*}"; port="${t##*:}"
  # ---- IPv4 ----
  iptables -N DOCKER-USER 2>/dev/null || true
  # 改规则期间先全拒，改完再撤，不留空档
  rej -I DOCKER-USER 1 -i "$IF"
  iptables -N SBX-OUT 2>/dev/null || true
  iptables -F SBX-OUT
  [ -n "$t" ] && iptables -A SBX-OUT -d "$ip" -p tcp --dport "$port" -j RETURN
  rej -A SBX-OUT
  iptables -C DOCKER-USER -i "$IF" -j SBX-OUT 2>/dev/null || iptables -I DOCKER-USER 2 -i "$IF" -j SBX-OUT
  iptables -D DOCKER-USER -i "$IF" -j REJECT 2>/dev/null || iptables -D DOCKER-USER -i "$IF" -j DROP 2>/dev/null || true
  iptables -N SBX-IN 2>/dev/null || true
  iptables -F SBX-IN
  iptables -A SBX-IN -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
  iptables -A SBX-IN -j DROP
  iptables -C INPUT -i "$IF" -j SBX-IN 2>/dev/null || iptables -I INPUT 1 -i "$IF" -j SBX-IN
  # ---- IPv6：上游只是 IPv4，所以 sbx-egress 的 IPv6 全部拒绝、也不准连 WSL 本机 ----
  ip6t -C FORWARD -i "$IF" -j REJECT 2>/dev/null || ip6t -I FORWARD 1 -i "$IF" -j REJECT
  ip6t -C INPUT -i "$IF" -j DROP 2>/dev/null || ip6t -I INPUT 1 -i "$IF" -j DROP
  echo "$t" > "$STATE"; chmod 644 "$STATE"
  if [ -n "$t" ]; then echo "[sandbox-fw] proxy 只能连 $t（IPv4），IPv6 全部拒绝"; else echo "[sandbox-fw] 没有有效的上游代理，proxy 外网全部拒绝"; fi
}
off() {
  while iptables -D DOCKER-USER -i "$IF" -j SBX-OUT 2>/dev/null; do :; done
  while iptables -D INPUT -i "$IF" -j SBX-IN 2>/dev/null; do :; done
  iptables -F SBX-OUT 2>/dev/null; iptables -X SBX-OUT 2>/dev/null
  iptables -F SBX-IN 2>/dev/null;  iptables -X SBX-IN 2>/dev/null
  while ip6t -D FORWARD -i "$IF" -j REJECT 2>/dev/null; do :; done
  while ip6t -D INPUT -i "$IF" -j DROP 2>/dev/null; do :; done
  rm -f "$STATE"; echo "[sandbox-fw] 已关闭网络加固（proxy 又能直连外网）"
}
show() {
  echo "允许的上游：$(cat "$STATE" 2>/dev/null || echo '未生效')"
  echo "-- IPv4 DOCKER-USER";  iptables -S DOCKER-USER 2>/dev/null | grep -E "$IF|SBX" || echo "  (没有)"
  echo "-- IPv4 SBX-OUT";      iptables -S SBX-OUT 2>/dev/null || echo "  (没有)"
  echo "-- IPv4 SBX-IN";       iptables -S SBX-IN 2>/dev/null || echo "  (没有)"
  echo "-- IPv6 FORWARD";      ip6t -S FORWARD 2>/dev/null | grep "$IF" || echo "  (没有)"
  echo "-- IPv6 INPUT";        ip6t -S INPUT 2>/dev/null | grep "$IF" || echo "  (没有)"
}
case "$cmd" in
  target) target;;
  apply)  need_root; [ -f "$ENV" ] || { echo "找不到 .env：$ENV"; exit 1; }; apply;;
  off)    need_root; off;;
  show)   need_root; show;;
  *)      echo "用法: sandbox-fw apply <.env> | target <.env> | show | off"; exit 1;;
esac
