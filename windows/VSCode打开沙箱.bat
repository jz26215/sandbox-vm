@echo off
chcp 65001 >nul
rem 先启动沙箱，再让 VS Code 直接连进容器的 /sandbox（省掉 连WSL / 开发容器 / 附加 / 打开文件夹 几步）
rem 下面那串十六进制 = {"containerName":"/sandbox-vm-box-1","cwd":"\\wsl.localhost\Ubuntu\"}
echo 检查并启动沙箱...
wsl -d Ubuntu -- bash -lc "cd ~/sandbox-vm && ./sb.sh up >/dev/null"
if errorlevel 1 (
  echo 沙箱没启动起来，VS Code 先不打开
  pause
  exit /b 1
)
echo 正在打开 VS Code，左下角出现「容器 sandbox-vm-box-1」就连好了
call code --folder-uri "vscode-remote://attached-container+7b22636f6e7461696e65724e616d65223a222f73616e64626f782d766d2d626f782d31222c22637764223a225c5c5c5c77736c2e6c6f63616c686f73745c5c5562756e74755c5c227d/sandbox"
timeout /t 5 >nul
