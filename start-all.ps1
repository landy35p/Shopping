# start-all.ps1 — 放在 Shopping/ 目錄，與 Shopping-backend/ Shopping-frontend/ 同層
# 使用方式：在 Shopping/ 目錄執行 .\start-all.ps1

$root       = Split-Path $PSScriptRoot -Parent     # Shopping/ 的上一層
$backendDir = Join-Path $root "Shopping-backend"
$frontendDir= Join-Path $root "Shopping-frontend"
$infraDir   = $PSScriptRoot                        # 本腳本所在的 Shopping/

Write-Host "== 1. 啟動資料庫 =="
Push-Location $infraDir
docker compose up -d
Pop-Location

Write-Host "== 2. 啟動後端 (新視窗) =="
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$backendDir'; dotnet run"

Write-Host "== 3. 等待後端啟動... =="
Start-Sleep 4

Write-Host "== 4. 啟動前端 (新視窗) =="
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$frontendDir'; pnpm dev"

Write-Host ""
Write-Host "後端：http://localhost:5000"
Write-Host "前端：http://localhost:5173"
Write-Host "Swagger：http://localhost:5000/swagger"
