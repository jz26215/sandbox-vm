#!/bin/sh
# 由环境变量 + 白名单生成 tinyproxy 配置，默认拒绝一切
set -eu
C=/tmp/tinyproxy.conf
sed 's/\r$//' /etc/tinyproxy/allowlist.txt | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' > /tmp/allow.txt || true
{
  echo "Port 8888"
  echo "Listen 0.0.0.0"
  echo "Timeout 600"
  echo "MaxClients 50"
  echo "Allow ${BOX_SUBNET}"
  echo "LogLevel Connect"
  echo "PidFile \"/tmp/tinyproxy.pid\""
  echo "DisableViaHeader Yes"
  echo "FilterType fnmatch"
  echo "Filter \"/tmp/allow.txt\""
  echo "FilterDefaultDeny Yes"
  for p in ${ALLOW_PORTS}; do echo "ConnectPort $p"; done
  if [ -n "${UPSTREAM:-}" ]; then echo "Upstream http ${UPSTREAM}"; fi
} > "$C"
echo "[proxy] 端口: ${ALLOW_PORTS}  上游: ${UPSTREAM:-直连}"
echo "[proxy] 白名单:"; sed 's/^/  /' /tmp/allow.txt
exec tinyproxy -d -c "$C"
