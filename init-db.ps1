# init-db.ps1 — 放在 Shopping/ 目錄
# 用途：建立資料庫 schema 並匯入商品/用戶/購買記錄（首次使用）
# 使用方式：在 Shopping/ 目錄執行 .\init-db.ps1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root       = Split-Path $PSScriptRoot -Parent
$backendDir = Join-Path $root "Shopping-backend"

Write-Host "== 資料庫初始化（seed）=="
Write-Host "   建立 schema + 匯入商品/用戶/購買記錄..."
Push-Location $backendDir
dotnet run -- seed
Pop-Location
Write-Host "   Seed 完成。"
