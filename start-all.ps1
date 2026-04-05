# start-all.ps1 — 放在 Shopping/ 目錄，與 Shopping-backend/ Shopping-frontend/ 同層
# 使用方式：在 Shopping/ 目錄執行 .\start-all.ps1

# 設定輸出編碼為 UTF-8 以避免亂碼
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root       = Split-Path $PSScriptRoot -Parent     # Shopping/ 的上一層
$backendDir = Join-Path $root "Shopping-backend"
$frontendDir= Join-Path $root "Shopping-frontend"
$infraDir   = $PSScriptRoot                        # 本腳本所在的 Shopping/

Write-Host "== 1. 啟動資料庫 =="
Push-Location $infraDir
docker compose up -d
Pop-Location

Write-Host ""
Write-Host "== 提示：首次使用請另行執行以下腳本 =="
Write-Host "   .\init-db.ps1        # 建立 schema + 匯入商品/用戶/購買記錄"
Write-Host "   .\embed-products.ps1 # 為所有商品產生 Fake 向量"

Write-Host ""
Write-Host "== 檢查並安裝 pnpm =="
if (!(Get-Command pnpm -ErrorAction SilentlyContinue)) {
    Write-Host "pnpm 未安裝，正在安裝..."
    npm install -g pnpm
}

Write-Host "== 3. 啟動後端 (新視窗) =="
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$backendDir'; dotnet run"

Write-Host "== 4. 等待後端啟動... =="
Start-Sleep 4

Write-Host "== 5. 啟動前端 (新視窗) =="
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$frontendDir'; pnpm dev"

Write-Host ""
Write-Host "後端：http://localhost:5000"
Write-Host "前端：http://localhost:5173"
Write-Host "Swagger：http://localhost:5000/swagger"
