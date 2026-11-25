# Windows 侧快捷入口：.\sb.ps1 up / .\sb.ps1 tz Asia/Tokyo / .\sb.ps1 allow '*.example.com'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$q = ($Rest | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join ' '
wsl -d Ubuntu -- bash -lc "cd ~/sandbox-vm && ./sb.sh $q"
