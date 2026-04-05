# embed-products.ps1 — 放在 Shopping/ 目錄
# 用途：為所有商品產生 Fake 向量（embed）
# 使用方式：在 Shopping/ 目錄執行 .\embed-products.ps1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root       = Split-Path $PSScriptRoot -Parent
$backendDir = Join-Path $root "Shopping-backend"

Write-Host "== 商品向量化（embed）=="
Write-Host "   正在為所有商品產生 Fake 向量..."
Push-Location $backendDir
dotnet run -- embed
Pop-Location
Write-Host "   Embed 完成。"
