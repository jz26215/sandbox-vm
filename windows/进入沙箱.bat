@echo off
chcp 65001 >nul
wsl -d Ubuntu -- bash -lc "cd ~/sandbox-vm && ./sb.sh up >/dev/null && ./sb.sh shell"
pause
