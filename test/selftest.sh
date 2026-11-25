#!/usr/bin/env bash
# 自检：网络只走白名单、文件只限 /sandbox、时区正确
cd "$(dirname "$0")/.."
pass=0; fail=0
ok()  { echo "✔ $1"; pass=$((pass+1)); }
bad() { echo "✘ $1"; fail=$((fail+1)); }
R()   { docker compose exec -T box sh -c "$1" >/dev/null 2>&1; }

first=$(grep -vE '^\s*(#|$)' allowlist.txt | grep -v '\*' | head -1 | tr -d '\r')
[ -n "$first" ] && { R "curl -fsS -o /dev/null -m 20 https://$first" && ok "白名单 $first 可访问" || bad "白名单 $first 访问失败（检查上游代理/网络）"; }
R "curl -sS -o /dev/null -m 10 https://example.org"          && bad "非白名单 example.org 竟然能访问" || ok "非白名单域名被拒"
R "curl -sS -o /dev/null -m 10 https://1.1.1.1"              && bad "IP 直连经代理成功"              || ok "IP 直连被拒"
R "curl --noproxy '*' -sS -o /dev/null -m 6 https://1.1.1.1" && bad "绕过代理直连成功"              || ok "绕过代理无路由"
R "python3 -c 'import socket;socket.gethostbyname(\"example.com\")'"  && bad "DNS 可解析外部域名"            || ok "无外部 DNS"
R "test -e /mnt/c || test -e /mnt/d"                         && bad "能看到宿主盘"                  || ok "看不到宿主盘"
R "touch /etc/x"                                             && bad "根文件系统可写"                || ok "根文件系统只读"
R "echo hi > /sandbox/.st && rm /sandbox/.st"                && ok  "/sandbox 可读写"               || bad "/sandbox 不可写（检查 data/ 属主是否 1000）"
[ "$(docker compose exec -T box id -u | tr -d '\r')" = "1000" ] && ok "非 root 运行" || bad "以 root 运行"
want=$(grep -E '^SANDBOX_TZ=' .env | cut -d= -f2 | tr -d '\r"')
got=$(docker compose exec -T box sh -c 'echo $TZ' | tr -d '\r')
[ "$want" = "$got" ] && ok "时区 $got（$(docker compose exec -T box date '+%F %T %Z' | tr -d '\r')）" || bad "时区不符 想要 $want 实际 $got"
if docker compose exec -T proxy sh -c 'command -v wget' >/dev/null 2>&1; then
  PX() { docker compose exec -T proxy sh -c 'unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; wget -q -T 6 -O /dev/null "$1"' _ "$1" >/dev/null 2>&1; }
  PX http://1.1.1.1 && bad "proxy 能直连 IPv4 地址 1.1.1.1（网络加固没生效）" || ok "proxy 直连 IPv4 地址被拒"
  PX http://example.org && bad "proxy 能直连 example.org（网络加固有洞）" || ok "proxy 直连 example.org 被拒"
  PX 'http://[2606:4700:4700::1111]/' && bad "proxy 能直连 IPv6（网络加固有洞）" || ok "proxy 直连 IPv6 被拒（或容器没有 IPv6）"
else bad "测不了 proxy 直连（容器里没有 wget）"; fi
echo "通过 $pass 项，失败 $fail 项"; [ "$fail" -eq 0 ]
