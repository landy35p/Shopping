# start-frontend.ps1 — 啟動前端服務
# 使用方式：在 Shopping/ 目錄執行 .\start-frontend.ps1

# 設定輸出編碼為 UTF-8 以避免亂碼
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root        = Split-Path $PSScriptRoot -Parent     # Shopping/ 的上一層
$frontendDir = Join-Path $root "Shopping-frontend"

Write-Host "== 檢查並安裝 pnpm =="
if (!(Get-Command pnpm -ErrorAction SilentlyContinue)) {
    Write-Host "pnpm 未安裝，正在安裝..."
    npm install -g pnpm
}

Write-Host "== 安裝前端依賴 =="
Push-Location $frontendDir
pnpm install
Pop-Location

Write-Host "== 1. 啟動前端 (新視窗) =="
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$frontendDir'; pnpm dev"

Write-Host ""
Write-Host "前端：http://localhost:5173"