# 第 1 步：管理员 PowerShell 运行。Win11 家庭版也可以。
# 作用：装 WSL2（一个轻量 Hyper-V 虚拟机）+ Ubuntu
wsl --install -d Ubuntu --web-download
Write-Host "完成后重启电脑 → 打开 Ubuntu 设置用户名密码 → 运行第 2 步" -ForegroundColor Green
