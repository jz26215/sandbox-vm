#!/usr/bin/env bash
# 沙箱控制脚本（在 WSL Ubuntu 里运行）
set -euo pipefail
cd "$(dirname "$0")"
ENV=.env

get()  { { grep -E "^$1=" "$ENV" || true; } | tail -1 | cut -d= -f2- | tr -d '\r"'; }
setv() { if grep -qE "^$1=" "$ENV"; then sed -i "s|^$1=.*|$1=$2|" "$ENV"; else echo "$1=$2" >> "$ENV"; fi; }
log()  { local f; f="$(get MEMORY_LOG)"; f="${f:-./ops.md}"; f="$(date +"$f")"
         { mkdir -p "$(dirname "$f")" && echo "- $(date '+%m-%d %H:%M') 沙箱：$*" >> "$f"; } 2>/dev/null \
           || echo "(操作记录没写进去：$f)"; }
upstream() {
  local u; u="$(get UPSTREAM_PROXY)"
  [[ -z "$u" ]] && { echo ""; return; }
  if [[ "$u" == auto:* ]]; then
    echo "$(ip route show default | awk '{print $3; exit}'):${u#auto:}"
  else echo "$u"; fi
}
dc() { UPSTREAM="$(upstream)" docker compose "$@"; }
# 网络加固：上游代理变了 → 防火墙跟着改（要 Linux 密码）；没装加固就跳过
fwsync() {
  systemctl cat sandbox-fw >/dev/null 2>&1 || return 0
  [ -f ./fw.sh ] || return 0
  local want have
  want="$(bash ./fw.sh target "$ENV" || true)"; have="$(cat /run/sandbox-fw.target 2>/dev/null || true)"
  case "$want" in 127.*) return 0;; esac          # 断网测试用的假地址，不用改
  [ "$want" = "$have" ] && return 0
  [ -z "$want" ] && echo "提醒：网络加固开着，没有上游代理时 proxy 外网全部拒绝（要直连先 sudo sandbox-fw off）"
  echo "上游代理变了，更新防火墙（可能要输入 Linux 密码）"; sudo systemctl restart sandbox-fw || echo "✘ 防火墙没更新"
}
fwstat() { if systemctl cat sandbox-fw >/dev/null 2>&1; then echo "网络加固：$(systemctl is-active sandbox-fw 2>/dev/null || true)，proxy 只能连 $(cat /run/sandbox-fw.target 2>/dev/null || echo '?')"; else echo "网络加固：没装（运行 bash tools/install-fw.sh）"; fi; }
# 参考时钟：只显示，不改沙箱时区
clock() {
  local z p s e h d wk=(一 二 三 四 五 六 日) in=0
  z="$(get REF_TZ)"; z="${z:-America/Los_Angeles}"
  p="$(get REF_PEAK)"; p="${p:-9-18}"; s=$((10#${p%-*})); e=$((10#${p#*-}))
  h=$((10#$(TZ="$z" date +%H))); d=$(TZ="$z" date +%u)
  echo "本地：$(date '+%m-%d %H:%M') 周${wk[$(( $(date +%u) - 1 ))]}"
  echo "参考（$z）：$(TZ="$z" date '+%m-%d %H:%M') 周${wk[$((d - 1))]}"
  if [ "$d" -le 5 ]; then
    if [ $s -lt $e ]; then [ $h -ge $s ] && [ $h -lt $e ] && in=1; else { [ $h -ge $s ] || [ $h -lt $e ]; } && in=1; fi
  fi
  if [ $in -eq 1 ]; then echo "→ 现在是高峰期（参考地工作日 ${s}:00–${e}:00）"; else echo "→ 现在不是高峰期（高峰：参考地工作日 ${s}:00–${e}:00）"; fi
}
# 构建时 BuildKit 解析基础镜像不走 dockerd 代理 → 先用 docker pull（走代理）拉到本地
pullbase() { local i; for i in $(grep -h '^FROM' box/Dockerfile proxy/Dockerfile | awk '{print $2}' | sort -u); do
  docker image inspect "$i" >/dev/null 2>&1 || { echo "拉基础镜像 $i"; docker pull "$i" || echo "✘ 拉 $i 失败（代理没通？见 setup/4-设置Docker代理.sh）"; }; done; }

case "${1:-help}" in
  up)       mkdir -p data noX11; pullbase; dc up -d --build; log "启动 TZ=$(get SANDBOX_TZ) 端口=$(get ALLOW_PORTS) 上游=$(get UPSTREAM_PROXY)";;
  down)     dc down; log "停止";;
  tz)       z="${2:-}"; [[ -n "$z" ]] || { echo "用法: ./sb.sh tz Asia/Tokyo"; exit 1; }
            [[ -f "/usr/share/zoneinfo/$z" ]] || { echo "未知时区: $z"; exit 1; }
            setv SANDBOX_TZ "$z"; dc up -d box; dc exec -T box date; log "时区→$z";;
  allow)    shift; for d in "$@"; do grep -qxF "$d" allowlist.txt || echo "$d" >> allowlist.txt; done
            dc restart proxy; log "放行 $*";;
  deny)     shift; for d in "$@"; do grep -vxF "$d" allowlist.txt > allowlist.tmp || true; mv allowlist.tmp allowlist.txt; done
            dc restart proxy; log "移除 $*";;
  ports)    shift; setv ALLOW_PORTS "\"$*\""; dc up -d proxy; log "端口→$*";;
  upstream) setv UPSTREAM_PROXY "${2:-}"; fwsync; dc up -d proxy; log "上游→${2:-直连}";;
  fw)       fwstat;;
  shell)    dc exec box bash;;
  clock)    clock;;
  reftz)    z="${2:-}"; [[ -n "$z" && -f "/usr/share/zoneinfo/$z" ]] || { echo "未知时区: $z（例子：America/Los_Angeles）"; exit 1; }
            setv REF_TZ "$z"; echo "参考时区已设为 $z"; log "参考时区→$z";;
  peak)     [[ "${2:-}" =~ ^[0-9]{1,2}-[0-9]{1,2}$ ]] || { echo "用法: ./sb.sh peak 9-18"; exit 1; }
            setv REF_PEAK "$2"; echo "高峰时段已设为参考地 $2 点"; log "高峰时段→$2";;
  claude|codex) t="$1"; d="/sandbox/${2:-}"; dc up -d >/dev/null || { echo "✘ 沙箱启动失败（原因见上面几行）"; exit 1; }
            dc exec -w "$d" box "$t";;
  run)      shift; dc exec -T box bash -lc "$*";;
  status)   dc ps; echo "时区: $(get SANDBOX_TZ)  端口: $(get ALLOW_PORTS)  上游: $(get UPSTREAM_PROXY)"
            fwstat
            echo "白名单:"; grep -vE '^\s*(#|$)' allowlist.txt | sed 's/^/  /';;
  logs)     dc logs --tail=50 proxy;;
  test)     bash test/selftest.sh;;
  *) cat <<'EOF'
用法: ./sb.sh <命令>
  up                 构建并启动沙箱
  down               停止并删除容器（data/ 保留）
  tz <时区>          改时区，如 ./sb.sh tz America/New_York
  allow <域名...>    加白名单，如 ./sb.sh allow 'api.openai.com' '*.example.com'
  deny <域名...>     移出白名单
  ports <端口...>    允许的 HTTPS 端口，如 ./sb.sh ports 443 8443
  upstream <x>       上游代理：auto:7890 / 172.x.x.x:7890 / 留空=直连
  shell              进入沙箱
  claude [文件夹]    在沙箱里打开 Claude Code（文件夹相对 data/，可不填）
  codex  [文件夹]    在沙箱里打开 Codex
  clock              显示本地和参考时区的时间，以及是否高峰期
  reftz <时区>       设参考时区，如 ./sb.sh reftz America/New_York
  peak <几点-几点>   设高峰时段（参考地时间，工作日），如 ./sb.sh peak 9-18
  run "<命令>"       在沙箱里执行一条命令
  fw                 看网络加固状态（proxy 只能连哪个上游代理）
  status | logs | test
EOF
  ;;
esac
