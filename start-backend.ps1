# start-backend.ps1 — 啟動後端服務和資料庫
# 使用方式：在 Shopping/ 目錄執行 .\start-backend.ps1

# 設定輸出編碼為 UTF-8 以避免亂碼
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root       = Split-Path $PSScriptRoot -Parent     # Shopping/ 的上一層
$backendDir = Join-Path $root "Shopping-backend"
$infraDir   = $PSScriptRoot                        # 本腳本所在的 Shopping/

Write-Host "== 1. 啟動資料庫 =="
Push-Location $infraDir
docker compose up -d
Pop-Location

Write-Host "== 2. 啟動後端 (新視窗) =="
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$backendDir'; dotnet run"

Write-Host ""
Write-Host "後端：http://localhost:5000"
Write-Host "Swagger：http://localhost:5000/swagger"