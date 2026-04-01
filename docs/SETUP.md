# 工程師架設指南

本文說明如何在本機完整建制 Yahoo 購物 AI 推薦 Demo，包含快速啟動（Fake 模式）與完整 Ollama AI 模式。

---

## 目錄

1. [系統需求](#1-系統需求)
2. [Repo 複製](#2-repo-複製)
3. [快速啟動 — Fake 模式](#3-快速啟動--fake-模式)
4. [完整模式 — Ollama AI](#4-完整模式--ollama-ai)
5. [環境變數設定參考](#5-環境變數設定參考)
6. [Provider 切換說明](#6-provider-切換說明)
7. [常見問題排除](#7-常見問題排除)

---

## 1. 系統需求

| 工具 | 版本 | 用途 |
|------|------|------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | 4.x+ | PostgreSQL + pgvector（必要）、Ollama（選用） |
| [.NET SDK](https://dotnet.microsoft.com/download) | **8.0** | 後端 |
| [Node.js](https://nodejs.org/) | 20 LTS+ | 前端建置環境 |
| [pnpm](https://pnpm.io/installation) | 9+ | 前端套件管理 |
| Python | 3.10+（選用） | 從 HuggingFace 下載真實資料集 |

> **pnpm 安裝**：`npm install -g pnpm`

---

## 2. Repo 複製

系統由三個獨立 Repo 組成，請分別 clone 到同一父目錄：

```bash
git clone https://github.com/landy35p/Shopping.git
git clone https://github.com/landy35p/Shopping-backend.git
git clone https://github.com/landy35p/Shopping-frontend.git
```

最終目錄結構：

```
AIProject/
├── Shopping/           ← 基礎設施（docker-compose、文件）
├── Shopping-backend/   ← ASP.NET Core 8 API
└── Shopping-frontend/  ← React + Vite 前端
```

---

## 3. 快速啟動 — Fake 模式

Fake 模式使用預設 mock 向量與固定回應，**不需要 Ollama**，5 分鐘內可完整啟動。

### Step 1：啟動資料庫

```bash
cd Shopping
docker compose up -d
```

確認容器健康：

```bash
docker compose ps
# shopping-postgres   healthy
```

### Step 2：初始化後端資料

```bash
cd Shopping-backend

# 建立 DB schema、匯入 200 筆商品 + 3 位用戶 + 13 筆購買記錄
dotnet run -- seed

# 為所有商品產生 Fake 向量（毫秒級，無需 Ollama）
dotnet run -- embed
```

預期輸出（embed）：

```
=== GenerateEmbeddings: Starting ===
Products without embeddings: 200
[1/200] ... [200/200]
Done. 200 embeddings generated.
```

### Step 3：啟動後端

```bash
# 在 Shopping-backend 目錄
dotnet run
```

後端啟動後顯示：

```
Now listening on: http://localhost:5000
Hosting environment: Development
```

驗證：`curl http://localhost:5000/api/products` 應回傳 JSON 商品列表。

### Step 4：啟動前端

```bash
cd Shopping-frontend

# 複製環境設定
cp .env.example .env.development

# 安裝依賴
pnpm install

# 從後端同步 API 型別（需後端已啟動）
pnpm gen:api

# 啟動開發伺服器
pnpm dev
```

開啟瀏覽器：**http://localhost:5173**

> 若 5173 已被占用，Vite 會自動改用 5174，請依終端機顯示的 URL 開啟。

---

## 4. 完整模式 — Ollama AI

此模式使用 nomic-embed-text 產生真實語義向量，並以 qwen2.5:7b 生成繁體中文推薦說明。

### Step 1：啟動 Ollama 容器

在 `Shopping/docker-compose.yml` 中加入 Ollama 服務（或手動啟動）：

**方式 A — 加入 docker-compose.yml**（建議）

```yaml
# 在 Shopping/docker-compose.yml 的 services: 下新增：
  ollama:
    image: ollama/ollama:latest
    container_name: ollama_embedding
    restart: unless-stopped
    ports:
      - '11434:11434'
    volumes:
      - ollama_data:/root/.ollama

# 在 volumes: 下新增：
  ollama_data:
```

然後重新啟動：

```bash
docker compose up -d
```

**方式 B — 直接 docker run**

```bash
docker run -d --name ollama_embedding \
  -p 11434:11434 \
  -v ollama_data:/root/.ollama \
  ollama/ollama:latest
```

### Step 2：拉取 AI 模型

```bash
# Embedding 模型（274 MB）
docker exec ollama_embedding ollama pull nomic-embed-text

# LLM 推薦模型（4.7 GB，視網速約需 5-15 分鐘）
docker exec ollama_embedding ollama pull qwen2.5:7b
```

確認模型已就緒：

```bash
docker exec ollama_embedding ollama list
# nomic-embed-text  ...
# qwen2.5:7b        ...
```

### Step 3：切換 Provider

編輯 `Shopping-backend/appsettings.Development.json`：

```json
{
  "LlmSettings": {
    "Provider": "ollama"
  },
  "EmbeddingSettings": {
    "Provider": "ollama"
  },
  "Cors": {
    "AllowedOrigins": [ "http://localhost:5173" ]
  }
}
```

### Step 4：重新生成真實向量

```bash
cd Shopping-backend

# 清除舊的 Fake 向量，改由 nomic-embed-text 重新生成
# 若 DB 為全新，可直接執行；若已有舊向量，先清除：
# docker exec -i shopping-postgres psql -U shopping -d shopping_db -c 'UPDATE "Products" SET "Embedding" = NULL;'

dotnet run -- embed
```

每筆商品約需 100-200 ms（CPU-only 模式），200 筆約 60-90 秒。

### Step 5：啟動後端與前端

同 Fake 模式 Step 3–4，啟動後端與前端即可。

> **效能備註（CPU-only）**：nomic-embed-text 查詢約 21 秒，qwen2.5:7b 首 token 約 88 秒，總等待時間 90-120 秒屬正常，前端有兩階段 spinner 提示進度。如有 NVIDIA GPU 可在 docker run 加上 `--gpus all` 大幅加速。

---

## 5. 環境變數設定參考

### Shopping-backend/appsettings.json（基準設定，不隨環境改變）

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5433;Database=shopping_db;Username=shopping;Password=shopping_dev"
  },
  "LlmSettings": {
    "Provider": "fake",
    "Ollama": { "BaseUrl": "http://localhost:11434", "Model": "qwen2.5:7b" },
    "OpenAi":  { "ApiKey": "",                       "Model": "gpt-4o-mini" }
  },
  "EmbeddingSettings": {
    "Provider": "fake",
    "Ollama": { "BaseUrl": "http://localhost:11434", "Model": "nomic-embed-text" }
  }
}
```

### Shopping-backend/appsettings.Development.json（本機開發覆蓋）

| 欄位 | Fake 模式 | Ollama 模式 |
|------|-----------|------------|
| `LlmSettings.Provider` | `"fake"` | `"ollama"` |
| `EmbeddingSettings.Provider` | `"fake"` | `"ollama"` |
| `Cors.AllowedOrigins` | `["http://localhost:5173"]` | `["http://localhost:5173"]` |

### Shopping-frontend/.env.development

```
VITE_API_BASE_URL=http://localhost:5000
```

---

## 6. Provider 切換說明

| Provider | 需要服務 | 效能 | 適用情境 |
|----------|---------|------|---------|
| `fake` | 無 | 即時 | 前端 UI 開發、CI/CD、快速 Demo |
| `ollama` | Ollama 容器 + 模型 | 慢（CPU）/ 快（GPU） | 本機完整 Demo |
| `openai` | OpenAI API Key | 快（雲端） | 未來雲端展示 |

切換 Provider **不需修改任何業務邏輯**，只需改 `appsettings.Development.json` 並重啟後端。

---

## 7. 常見問題排除

### ❌ `dotnet run` 報 "Cannot connect to database"

確認 DB 容器正在運行且健康：

```bash
docker compose ps
# shopping-postgres 應為 healthy 狀態
```

若容器未啟動：`docker compose up -d`

---

### ❌ 前端顯示 "連線失敗"

確認後端已啟動並監聽 :5000：

```bash
curl http://localhost:5000/api/products
```

若後端未啟動：`cd Shopping-backend && dotnet run`

---

### ❌ `pnpm gen:api` 失敗

確認後端已啟動，且 Swagger 可存取：

```bash
curl http://localhost:5000/swagger/v1/swagger.json
```

---

### ❌ Ollama embed 非常慢或卡住

- 確認 `ollama_embedding` 容器正在運行：`docker ps | grep ollama`
- 確認模型已拉取：`docker exec ollama_embedding ollama list`
- CPU-only 每筆約 100-200 ms，200 筆約 2-4 分鐘，屬正常

---

### ❌ 前端 Port 5173 被占用

Vite 會自動退讓，終端機會顯示實際 URL（如 `:5174`）。若需固定使用 5173：

```bash
# 找出並停止占用 5173 的 process
netstat -ano | findstr :5173
Stop-Process -Id <PID> -Force
```

---

### 修改 appsettings 後需重啟後端

```bash
# 找到後端 PID 並停止
Get-Process -Name "Shopping.Api" | Stop-Process -Force
# 重新啟動
dotnet run
```

---

## 附錄：一鍵啟動腳本（PowerShell）

```powershell
# start-all.ps1 — 在 AIProject/ 目錄執行

# 1. 確認 DB
Set-Location .\Shopping
docker compose up -d

# 2. 後端
Start-Process powershell -ArgumentList "-NoExit", "-Command", @"
  Set-Location D:\AIProject\Shopping-backend
  dotnet run
"@

# 3. 前端（2 秒後）
Start-Sleep 2
Start-Process powershell -ArgumentList "-NoExit", "-Command", @"
  Set-Location D:\AIProject\Shopping-frontend
  pnpm dev
"@

Write-Host "後端：http://localhost:5000"
Write-Host "前端：http://localhost:5173"
```
