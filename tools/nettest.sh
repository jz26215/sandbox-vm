#!/usr/bin/env bash
# 断网测试：上游代理断了以后，沙箱是不是真的上不了网；测完再确认能恢复
# 用法: cd ~/sandbox-vm && bash tools/nettest.sh    结果写到 nettest.log
LOG="$(cd "$(dirname "$0")/.." && pwd)/nettest.log"
exec > >(tee "$LOG") 2>&1
cd "$(dirname "$0")/.." || exit 1
get() { { grep -E "^$1=" .env || true; } | tail -1 | cut -d= -f2- | tr -d '\r"'; }
ORIG="$(get UPSTREAM_PROXY)"
H=$(ip route show default | awk '{print $3; exit}')
if [ -z "$ORIG" ]; then echo "现在没设上游代理（沙箱直连），这个测试不适用。"; exit 0; fi
case "$ORIG" in auto:*) UP="$H:${ORIG#auto:}";; *) UP="$ORIG";; esac

# 沙箱里访问网址，输出状态码
B()    { docker compose exec -T box curl -s -o /dev/null -m 15 -w '%{http_code}' "$1" 2>/dev/null; }
# WSL 直接经上游代理访问（确认代理软件是不是真的关了/开了）
UPC()  { curl -s -o /dev/null -m 8 -w '%{http_code}' -x "http://$UP" https://github.com 2>/dev/null; }
# proxy 容器自己绕开上游直连外网（信息项）
PX()   { docker compose exec -T proxy sh -c 'command -v wget' >/dev/null 2>&1 || { echo "测不了（容器里没有 wget）"; return; }
         docker compose exec -T proxy sh -c 'unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; wget -q -T 8 -O /dev/null http://example.org' >/dev/null 2>&1 && echo 能 || echo 不能; }
# 空 / 000 / 5xx（代理自己返回的错误页）= 不通
dead() { case "$1" in ''|000|5??) return 0;; *) return 1;; esac; }
show() { if dead "$2"; then echo "  $1 → ${2:-无响应}（不通）"; else echo "  $1 → $2（通）"; fi; }

M=""
restore() {
  [ "$M" = 2 ] || return 0
  M=done2
  echo "== 改回上游代理 $ORIG"
  ./sb.sh upstream "$ORIG" >/dev/null 2>&1 && echo "  已改回" || echo "  ✘ 改回失败：手动运行 cd ~/sandbox-vm && ./sb.sh upstream $ORIG"
  sleep 3
}
trap restore EXIT
trap 'echo; echo "已中断"; [ "$M" = 1 ] && echo "记得把代理软件重新打开"; exit 1' INT

echo "== $(date '+%F %T') 断网测试  上游代理 $UP（.env 里是 $ORIG）"
echo "== 1. 断网前（代理开着）"
u=$(UPC);                 show "WSL 经上游代理 → github.com" "$u"
b=$(B https://github.com); show "沙箱 → https://github.com" "$b"
echo "  proxy 容器绕开上游直连 example.org：$(PX)"
if dead "$b"; then echo "✘ 代理开着时沙箱就上不了网，没法测。先修网络：bash setup/4-设置Docker代理.sh <端口>"; exit 1; fi

echo
echo "选怎么断："
echo "  1 我去把 Windows 上的代理软件退出（真实测试，推荐）"
echo "  2 不动软件，临时把上游改成一个不存在的地址（模拟，测完自动改回）"
read -r -p "输入数字后回车：" M
case "$M" in
  1) for i in 1 2 3; do
       read -r -p "现在退出代理软件（托盘图标右键 → 退出，不是只关窗口），好了回车：" _
       u=$(UPC); dead "$u" && break
       echo "  上游代理还能连上（$u），软件可能没完全退出，再试一次"
     done
     dead "$u" || { echo "✘ 代理一直没断开，测试取消"; exit 1; } ;;
  2) echo "临时把上游改成 127.0.0.1:1（不存在的地址）…"
     ./sb.sh upstream 127.0.0.1:1 >/dev/null 2>&1 || { echo "✘ 改不了上游"; exit 1; }
     sleep 3 ;;
  *) M=""; echo "没选，已取消"; exit 0 ;;
esac

echo "== 2. 断网后"
R1=$(B https://github.com);      show "沙箱 → https://github.com（白名单）" "$R1"
R1b=$(B https://api.openai.com); show "沙箱 → https://api.openai.com（白名单）" "$R1b"
R2=$(B http://github.com);       show "沙箱 → http://github.com（普通 HTTP）" "$R2"
PXR=$(PX); echo "  proxy 容器绕开上游直连 example.org：$PXR"

echo "== 3. 恢复"
if [ "$M" = 1 ]; then
  for i in 1 2 3; do
    read -r -p "现在把代理软件重新打开，好了回车：" _
    u=$(UPC); dead "$u" || break
    echo "  还连不上上游代理（${u:-无响应}），等软件启动完再回车"
  done
else restore; fi
sleep 2
R3=$(B https://github.com); show "沙箱 → https://github.com" "$R3"

if dead "$R1" && dead "$R1b"; then H1="断了 ✔"; else H1="还能连 ✘"; fi
if dead "$R2"; then H2="断了 ✔"; else H2="还能连 ✘"; fi
if dead "$R3"; then H3="没恢复 ✘"; else H3="已恢复 ✔"; fi
[ "$M" = 1 ] && W=真实 || W=模拟
echo
echo "== 结论（$W 断网）"
echo "  断网后 HTTPS：$H1"
echo "  断网后普通 HTTP：$H2"
echo "  恢复后：$H3"
echo "  proxy 容器自己能直连外网：$PXR"
if [ "$PXR" = 能 ]; then echo "  （「能」= 网络加固没生效：断网只靠代理软件不回落直连；运行 bash tools/install-fw.sh）"
else echo "  （「不能」= 网络加固生效：proxy 只能连上游代理）"; fi
echo
echo "结果已写到 nettest.log"
echo "== 结束 $(date '+%F %T')"
