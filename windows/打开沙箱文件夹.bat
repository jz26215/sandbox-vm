@echo off
chcp 65001 >nul
rem 把下面的 你的Linux用户名 改成你在 Ubuntu 里的用户名
set "WSLUSER=你的Linux用户名"
explorer.exe "\\wsl$\Ubuntu\home\%WSLUSER%\sandbox-vm\data"
