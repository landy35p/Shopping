# Yahoo Shopping AI 推薦 Demo — 系統規格書

> **版本**：v1.2  
> **日期**：2026-04-01  
> **目標**：技術展示用途，無 Yahoo 後台存取，展示「混合式 AI 推薦」前後端完整實作  
> **架構原則**：前後端完全分離，各自獨立 Repo / CI / 部署；透過 OpenAPI Contract 同步型別

---

## 目錄

1. [專案目標](#1-專案目標)
2. [技術決策](#2-技術決策)
3. [系統架構](#3-系統架構)
4. [Repo 管理策略](#4-repo-管理策略)
5. [前後端分離設計](#5-前後端分離設計)
6. [LLM 抽象層設計](#6-llm-抽象層設計-核心)
7. [目錄結構](#7-目錄結構)
8. [資料庫 Schema](#8-資料庫-schema)
9. [API 規格](#9-api-規格)
10. [實作 Phases](#10-實作-phases)
11. [驗收標準](#11-驗收標準)
12. [決策記錄](#12-決策記錄)

---

## 1. 專案目標

建立一個 **Yahoo 購物風格的 AI 個性化推薦 Demo**，採用「Embedding 向量召回 + LLM 串流說明」的兩階段混合架構：

- **Stage 1（< 50ms）**：pgvector 向量相似度搜尋，快速召回 Top-20 候選商品
- **Stage 2（1–3s streaming）**：LLM 根據用戶 profile 生成個性化中文推薦理由，透過 SSE 串流至前端

Demo 情境為首頁「為你推薦」個人化區塊，可切換 3 個不同 persona 觀察推薦差異。

---

## 2. 技術決策

| 層次 | 技術選擇 | 版本 / 說明 |
|------|---------|------------|
| **Frontend Repo** | `Shopping-frontend` | React + Vite + TypeScript，獨立 Repo / CI / 部署 |
| **Backend Repo** | `Shopping-backend` | ASP.NET Core 8 Web API，獨立 Repo / CI / 部署 |
| **Infra Repo** | `Shopping`（現有） | `docker-compose.yml` + 全局文件，本機開發共用基礎設施 |
| **Frontend** | React + Vite + TypeScript | 獨立啟動，Port `5173`，SSE 消費使用 `@microsoft/fetch-event-source` |
| **Frontend Dev Proxy** | Vite Proxy | 開發期間代理 `/api/*` → `http://localhost:5000`，迴避 CORS |
| **Frontend 環境設定** | `.env` 檔 | `VITE_API_BASE_URL` 區分 dev / prod |
| **API Contract** | `openapi-typescript` | 從後端 Swagger 自動產生前端 TypeScript 型別，防止型別漂移 |
| **Backend** | ASP.NET Core Web API | 獨立啟動，Port `5000`，.NET 8 LTS |
| **Backend CORS** | `builder.Services.AddCors()` | 開發允許 `localhost:5173`；正式設定白名單 |
| **ORM** | Entity Framework Core + Npgsql | `Npgsql.EntityFrameworkCore.PostgreSQL` |
| **Vector DB** | PostgreSQL 16 + pgvector | 768 維向量，ivfflat index，cosine similarity |
| **Embedding 模型** | Ollama `nomic-embed-text` | 768 dim，可替換為 Fake 模式 |
| **LLM** | Ollama `qwen2.5:7b` | 中文支援，可替換為 Fake / OpenAI |
| **LLM 切換機制** | `appsettings.json` | `LlmProvider: fake \| ollama \| openai` |
| **資料來源** | Amazon Reviews 2023 — Electronics | HuggingFace `McAuley-Lab/Amazon-Reviews-2023`，取樣 200 筆 |
| **容器化** | Docker Compose | PostgreSQL + pgvector |

---

## 3. 系統架構

### Repo 關係

```
GitHub
├── Shopping              ← Infra Repo（docker-compose + 全局文件）
├── Shopping-backend      ← 後端 Repo（ASP.NET Core 8）
└── Shopping-frontend     ← 前端 Repo（React + Vite）
```

### 執行期通訊

```
┌──────────────────────────────────────────────────────────┐
│  Shopping-frontend  (React + Vite)  :5173                 │
│  ┌───────────────────────────────────────────────────┐   │
│  │  UserProfileSwitcher                              │   │
│  │  RecommendationSection                            │   │
│  │    └─ ProductCard × 5（打字機串流說明）            │   │
│  └────────────────────┬──────────────────────────────┘   │
│  開發期 Vite Proxy     │ /api/* → localhost:5000           │
│  正式期 直接呼叫       │ VITE_API_BASE_URL                 │
└────────────────────────┼─────────────────────────────────┘
                         │ HTTP / SSE
                         ▼
┌──────────────────────────────────────────────────────────┐
│  Shopping-backend  (ASP.NET Core 8)  :5000                │
│  CORS 白名單: localhost:5173                              │
│  ┌───────────────────────────────────────────────────┐   │
│  │  GET /api/recommendations/stream?userId={}        │   │
│  │    RecommendationService                          │   │
│  │      Stage 1: IEmbeddingService                   │   │
│  │        → pgvector 召回 Top-20  (< 50ms)           │   │
│  │      Stage 2: ILlmService streaming               │   │
│  │        → SSE 串流至前端        (1~3s)              │   │
│  └───────────────────────────────────────────────────┘   │
│  Swagger → openapi.json  ←── 前端執行 pnpm gen:api 取用   │
│  DI: LlmProvider = fake | ollama | openai                 │
└────────────────────────┬─────────────────────────────────┘
                         │
             ┌───────────┴────────────┐
             ▼                        ▼
        PostgreSQL + pgvector      Ollama :11434
        (Shopping Infra / Docker)  (本地，fake 模式可不啟動)
```

---

## 4. Repo 管理策略

### 三個 Repo 的職責

| Repo | 用途 | 獨立 CI |
|------|------|--------|
| `Shopping` | `docker-compose.yml`、全局文件（`docs/spec.md`）、開發環境說明 | ❌（純基礎設施）|
| `Shopping-backend` | ASP.NET Core 8 API、EF Core Migration、資料 Scripts | ✅ dotnet test → build → deploy |
| `Shopping-frontend` | React + Vite + TypeScript 前端 | ✅ pnpm build → deploy |

### API Contract 同步流程（防止型別漂移）

```
Shopping-backend
  Swashbuckle 自動產生
       ↓
  GET http://localhost:5000/swagger/v1/swagger.json
       ↓  pnpm gen:api（Shopping-frontend 中執行）
  src/api/schema.ts   ← 自動產生，不手動編寫
       ↓
  src/api/client.ts   ← import 型別，呼叫 API
       ↓
  TypeScript 編譯     ← 後端改 schema → 前端編譯報錯，立即發現
```

```jsonc
// Shopping-frontend/package.json
{
  "scripts": {
    "gen:api": "openapi-typescript http://localhost:5000/swagger/v1/swagger.json -o src/api/schema.ts"
  }
}
```

### 各自 CI/CD 管道

**Shopping-backend** `.github/workflows/ci.yml`
```
push to main
  → dotnet test
  → dotnet build --configuration Release
  → docker build & push (ghcr.io/...)
```

**Shopping-frontend** `.github/workflows/ci.yml`
```
push to main
  → pnpm install
  → pnpm gen:api  (需後端已部署，從正式 URL 拉 openapi.json)
  → pnpm build    (TypeScript 編譯，型別不符直接失敗)
```

### 本機開發啟動順序

```powershell
# ① 啟動 DB（Shopping Infra Repo）
cd Shopping
docker compose up -d

# ② 啟動後端（Shopping-backend）
cd Shopping-backend
dotnet run
# → :5000，swagger 自動產生 openapi.json

# ③ 同步 API 型別後啟動前端（Shopping-frontend）
cd Shopping-frontend
pnpm gen:api      # 從 localhost:5000 拉取最新 schema
pnpm dev          # → :5173
```

---

## 5. 前後端分離設計

### 通訊方式

| 情境 | 方式 | 說明 |
|------|------|------|
| 開發期 | Vite Proxy | 前端 `/api/*` 請求由 Vite dev server 代理轉發到後端，前端程式碼無需寫死 port |
| 正式期 | 直接呼叫 | 前端讀取 `VITE_API_BASE_URL` 環境變數，直接打後端 URL |

### Frontend 環境變數

```
# frontend/.env.development
VITE_API_BASE_URL=http://localhost:5000

# frontend/.env.production
VITE_API_BASE_URL=https://api.your-domain.com
```

### Vite Proxy 設定（開發期）

```typescript
// frontend/vite.config.ts
export default defineConfig({
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:5000',
        changeOrigin: true,
        // SSE 需關閉 compression 才能即時串流
        configure: (proxy) => {
          proxy.on('proxyReq', (proxyReq) => {
            proxyReq.setHeader('Accept-Encoding', 'identity');
          });
        },
      },
    },
  },
});
```

### Backend CORS 設定

```csharp
// Program.cs
builder.Services.AddCors(options =>
{
    options.AddPolicy("FrontendPolicy", policy =>
    {
        var origins = builder.Configuration.GetSection("Cors:AllowedOrigins")
                             .Get<string[]>() ?? [];
        policy.WithOrigins(origins)
              .AllowAnyHeader()
              .AllowAnyMethod()
              // SSE 需要 AllowCredentials 或確保不帶 Cookie
              .SetIsOriginAllowed(_ => true); // Dev only
    });
});

app.UseCors("FrontendPolicy");
```

```json
// appsettings.Development.json
{
  "Cors": {
    "AllowedOrigins": [ "http://localhost:5173" ]
  }
}
```

### 啟動方式（完全獨立）

```powershell
# Terminal 1 — 啟動 DB
docker compose up -d

# Terminal 2 — 啟動後端
cd backend
dotnet run

# Terminal 3 — 啟動前端
cd frontend
pnpm dev
```

---

## 6. LLM 抽象層設計（核心）

### 介面定義

```csharp
// Services/Abstractions/ILlmService.cs
public interface ILlmService
{
    IAsyncEnumerable<string> StreamRecommendationsAsync(
        IReadOnlyList<Product> candidates,
        UserProfile user,
        CancellationToken ct = default);
}

// Services/Abstractions/IEmbeddingService.cs
public interface IEmbeddingService
{
    Task<float[]> GetEmbeddingAsync(string text, CancellationToken ct = default);
}
```

### 三種實作對照

| 實作類別 | 行為 | 需要 Ollama | 使用時機 |
|---------|------|------------|---------|
| `FakeLlmService` | 回傳預設 mock 說明，每字元延遲 30ms 模擬串流 | ❌ | 開發 / CI / 前端 UI 調整 |
| `OllamaLlmService` | 呼叫 `http://localhost:11434/api/chat` streaming | ✅ | 本機 Demo |
| `OpenAiLlmService` | 呼叫 OpenAI Chat Completions streaming API | ❌（需 Key） | 未來雲端展示 |
| `FakeEmbeddingService` | 回傳固定種子向量（查詢結果一致） | ❌ | 開發 / CI |
| `OllamaEmbeddingService` | 呼叫 `http://localhost:11434/api/embeddings` | ✅ | 本機 Demo |

### appsettings.json 設定結構

```json
{
  "LlmSettings": {
    "Provider": "fake",
    "Ollama": {
      "BaseUrl": "http://localhost:11434",
      "Model": "qwen2.5:7b"
    },
    "OpenAi": {
      "ApiKey": "",
      "Model": "gpt-4o"
    }
  },
  "EmbeddingSettings": {
    "Provider": "fake",
    "Ollama": {
      "BaseUrl": "http://localhost:11434",
      "Model": "nomic-embed-text"
    }
  }
}
```

### DI 工廠注冊（Program.cs）

```csharp
var llmProvider = builder.Configuration["LlmSettings:Provider"];
builder.Services.AddSingleton<ILlmService>(llmProvider switch
{
    "ollama" => new OllamaLlmService(...),
    "openai" => new OpenAiLlmService(...),
    _        => new FakeLlmService()
});
```

---

## 7. 目錄結構

### Shopping（Infra Repo）

```
Shopping/                        # github.com/.../Shopping
├── docker-compose.yml           # PostgreSQL 16 + pgvector
└── docs/
    └── spec.md                  # 本文件
```

### Shopping-backend（後端 Repo）

```
Shopping-backend/                # github.com/.../Shopping-backend
├── backend/                                    # ──── 獨立後端專案 ────
│   ├── Controllers/
│   │   ├── RecommendationsController.cs        # SSE endpoint
│   │   └── ProductsController.cs
│   ├── Services/
│   │   ├── Abstractions/
│   │   │   ├── ILlmService.cs
│   │   │   └── IEmbeddingService.cs
│   │   ├── Llm/
│   │   │   ├── FakeLlmService.cs
│   │   │   ├── OllamaLlmService.cs
│   │   │   └── OpenAiLlmService.cs             # 預留，未實作
│   │   ├── Embedding/
│   │   │   ├── FakeEmbeddingService.cs
│   │   │   └── OllamaEmbeddingService.cs
│   │   └── RecommendationService.cs            # 兩階段 pipeline
│   ├── Repositories/
│   │   └── ProductRepository.cs               # pgvector 向量查詢
│   ├── Models/
│   │   ├── Product.cs
│   │   ├── UserProfile.cs
│   │   └── RecommendationResult.cs
│   ├── Data/
│   │   ├── AppDbContext.cs                     # EF Core DbContext
│   │   └── Migrations/
│   ├── Settings/
│   │   ├── LlmSettings.cs
│   │   └── EmbeddingSettings.cs
│   ├── Scripts/
│   │   ├── download-dataset.py                 # HuggingFace 資料下載
│   │   ├── SeedData.cs                         # 植入 mock users + 購買記錄
│   │   └── GenerateEmbeddings.cs               # 批次產生向量寫入 pgvector
│   ├── appsettings.json                        # LlmProvider, DB, CORS 正式設定
│   ├── appsettings.Development.json            # CORS AllowedOrigins: localhost:5173
│   └── Shopping.Api.csproj
└── .github/
    └── workflows/
        └── ci.yml               # dotnet test → build → docker push
```

### Shopping-frontend（前端 Repo）

```
Shopping-frontend/               # github.com/.../Shopping-frontend
├── frontend/                                   # ──── 獨立前端專案 ────
│   ├── src/
│   │   ├── api/
│   │   │   └── client.ts                       # API base URL 統一入口
│   │   ├── components/
│   │   │   ├── ProductCard.tsx                 # 商品卡 + 打字機動畫
│   │   │   ├── RecommendationSection.tsx       # Skeleton → 卡片列表
│   │   │   └── UserProfileSwitcher.tsx         # Persona 切換按鈕
│   │   ├── hooks/
│   │   │   └── useRecommendations.ts           # SSE 消費 hook
│   │   ├── pages/
│   │   │   └── HomePage.tsx
│   │   └── data/
│   │       └── mockUsers.ts                    # 3 個 persona 定義
│   ├── .env.development                        # VITE_API_BASE_URL=http://localhost:5000
│   ├── .env.production                         # VITE_API_BASE_URL=https://...
│   ├── .env.example                            # 範本，提交至 git
│   ├── vite.config.ts                          # Proxy /api/* → localhost:5000
│   └── package.json                            # gen:api script
└── .github/
    └── workflows/
        └── ci.yml               # pnpm gen:api → pnpm build → deploy
```

---

## 8. 資料庫 Schema

```sql
-- pgvector 擴充
CREATE EXTENSION IF NOT EXISTS vector;

-- 商品資料表
CREATE TABLE products (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asin        VARCHAR(20) UNIQUE NOT NULL,
    title       TEXT NOT NULL,
    description TEXT,
    category    VARCHAR(100),
    price       NUMERIC(10, 2),
    rating      NUMERIC(3, 2),
    image_url   TEXT,
    embedding   vector(768)       -- nomic-embed-text 768 維
);

-- 向量索引（cosine similarity，lists 值 = 商品數 / 1000）
CREATE INDEX ON products USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 1);

-- 用戶資料表
CREATE TABLE users (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(100) NOT NULL,
    persona_tag  VARCHAR(50)         -- e.g. "tech-enthusiast"
);

-- 購買記錄
CREATE TABLE purchases (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID REFERENCES users(id),
    product_id   UUID REFERENCES products(id),
    purchased_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 9. API 規格

### `GET /api/recommendations/stream`

| 項目 | 內容 |
|------|------|
| 說明 | 根據用戶購買紀錄，串流回傳個性化推薦商品與 AI 說明 |
| Query Params | `userId: string`（必填） |
| Response Headers | `Content-Type: text/event-stream` |
| Response Format | Server-Sent Events |

**SSE 事件格式：**
```
event: product
data: {"id":"...","title":"...","price":99.99,"rating":4.5,"imageUrl":"..."}

event: reasoning
data: {"productId":"...","text":"因為您購買了 Sony 耳機，"}

event: reasoning
data: {"productId":"...","text":"推薦這款降噪耳機套..."}

event: done
data: {}
```

### `GET /api/products`

| 項目 | 內容 |
|------|------|
| 說明 | 取得商品列表 |
| Query Params | `page: int`（預設 1），`pageSize: int`（預設 20） |
| Response | `200 OK` JSON 商品陣列 |

---

## 10. 實作 Phases

### Phase 0：Repo 初始化與環境建置

**Shopping（Infra）**
- [ ] 保留 `docker-compose.yml`（PostgreSQL 16 + pgvector `ankane/pgvector`）
- [ ] 更新 `docs/spec.md`（本文件）

**Shopping-backend**
- [ ] `gh repo create Shopping-backend --public` 建立後端 Repo
- [ ] `dotnet new webapi -n Shopping.Api` 初始化專案
- [ ] 安裝 NuGet：`Npgsql.EntityFrameworkCore.PostgreSQL`、`Pgvector.EntityFrameworkCore`、`Swashbuckle.AspNetCore`
- [ ] 確認 `appsettings.Development.json` 加入 CORS `AllowedOrigins: ["http://localhost:5173"]`
- [ ] 建立 `.github/workflows/ci.yml`（dotnet test → dotnet build）

**Shopping-frontend**
- [ ] `gh repo create Shopping-frontend --public` 建立前端 Repo
- [ ] `pnpm create vite . -- --template react-ts` 初始化專案
- [ ] 安裝依賴：`@microsoft/fetch-event-source`、`openapi-typescript`
- [ ] 新增 `.env.development`（`VITE_API_BASE_URL=http://localhost:5000`）與 `.env.example`
- [ ] `vite.config.ts` 設定 `/api/*` proxy + SSE 相容設定
- [ ] `package.json` 新增 `gen:api` script
- [ ] 建立 `.github/workflows/ci.yml`（pnpm gen:api → pnpm build）

**本機工具**
- [ ] Ollama 安裝：`ollama pull nomic-embed-text` + `ollama pull qwen2.5:7b`

### Phase 1：LLM 抽象層（最優先，Shopping-backend）
> ✅ 完成後前端可立即開發，不依賴 Ollama

- [ ] 定義 `ILlmService` + `IEmbeddingService` 介面
- [ ] 實作 `FakeLlmService`（固定 mock 資料 + 30ms / 字元 stream 模擬）
- [ ] 實作 `FakeEmbeddingService`（固定種子向量）
- [ ] `LlmSettings.cs` + `EmbeddingSettings.cs` Options 類別
- [ ] `Program.cs` DI 工廠注冊 + CORS middleware 注冊

### Phase 2：資料準備（可與 Phase 1 平行，Shopping-backend）
- [ ] `Scripts/download-dataset.py`（HuggingFace Electronics 取樣 200 筆 → `products.json`）
- [ ] EF Core Migration（建立 `products`、`users`、`purchases` table）
- [ ] `Scripts/SeedData.cs`（3 個 mock user + 各 3–5 筆購買記錄）
- [ ] `Scripts/GenerateEmbeddings.cs`（批次 embed → 寫入 pgvector）

### Phase 3：後端核心服務（depends on Phase 1 + 2，Shopping-backend）
- [ ] `Repositories/ProductRepository.cs`（EF Core + `<=>` cosine distance 向量查詢）
- [ ] `Services/Embedding/OllamaEmbeddingService.cs`（HttpClient → Ollama embed API）
- [ ] `Services/Llm/OllamaLlmService.cs`（HttpClient streaming → `IAsyncEnumerable<string>`）
- [ ] `Services/RecommendationService.cs`（兩階段 pipeline 協調器）
- [ ] `Controllers/RecommendationsController.cs`（SSE endpoint）
- [ ] `Controllers/ProductsController.cs`（商品列表）

### Phase 4：前端展示（depends on Phase 1，不需等 Phase 3，Shopping-frontend）
- [ ] 執行 `pnpm gen:api` 從後端產生 `src/api/schema.ts`（需後端已啟動）
- [ ] `api/client.ts`（import `schema.ts` 型別，讀取 `VITE_API_BASE_URL` 作為統一入口）
- [ ] `data/mockUsers.ts`（3 個 persona：科技達人 / 居家主義 / 運動愛好者）
- [ ] `hooks/useRecommendations.ts`（`@microsoft/fetch-event-source` SSE hook，endpoint 使用 `client.ts`）
- [ ] `components/ProductCard.tsx`（商品圖、標題、價格、星評 + 打字機 AI 說明）
- [ ] `components/UserProfileSwitcher.tsx`（切換 persona 按鈕）
- [ ] `components/RecommendationSection.tsx`（Skeleton loading → 卡片列表）
- [ ] `pages/HomePage.tsx`（Yahoo 風格標題列 + 推薦區塊組合）

### Phase 5：整合 + Demo 優化（depends on Phase 3 + 4，跨 Repo）
- [ ] 切換 `appsettings.json` → `Provider: ollama`，驗證真實 Ollama 推薦品質
- [ ] Prompt 微調（qwen2.5:7b 中文推薦理由格式與品質）
- [ ] 動畫細節：卡片淡入、切換 persona 的 fade-out / fade-in
- [ ] Error handling：Ollama 未啟動時顯示友善提示

---

## 11. 驗收標準

| # | 測試項目 | 預期結果 |
|---|---------|---------|
| 1 | `LlmProvider=fake` 下啟動前端 | 不啟動 Ollama 仍可看到完整推薦卡片與串流說明 |
| 2 | `LlmProvider=ollama` 下推薦品質 | 推薦說明為繁體中文、語意與用戶 persona 相符 |
| 3 | 修改 `appsettings.json` 切換 Provider | **不需修改任何業務邏輯程式碼**（DIP 驗證） |
| 4 | 切換「科技達人」→「居家主義」 | 推薦商品集合明顯不同（個性化驗證） |
| 5 | SSE 連線中斷 | 前端自動重連，不白屏 |
| 6 | Ollama 未啟動（`Provider=ollama`） | 顯示友善錯誤訊息，不顯示技術例外錯誤 |
| 7 | 前端直接存取 `:5000/api/*`（不透過 proxy） | 後端 CORS 正確拒絕或接受（依 origin 白名單） |
| 8 | 前後端分別獨立啟動關閉 | 互不影響，後端停止時前端顯示 loading/error 狀態 |
| 9 | 後端修改 response schema 後執行 `pnpm gen:api` | `schema.ts` 自動更新，前端使用舊型別處 TypeScript 編譯報錯 |
| 10 | Shopping-backend CI push | dotnet test + build 通過，與前端 Repo 完全獨立 |

---

## 12. 決策記錄

| 決策 | 理由 |
|------|------|
| **3 Repo 方案** | 模擬真實企業架構：前後端各自獨立 CI/CD；Infra repo 統一管理本機開發 DB 環境，不污染業務 code |
| **前後端完全分離** | 獨立啟動、獨立維護；未來可各自部署到不同服務（Vercel + Azure App Service）不需改動程式碼 |
| **openapi-typescript codegen** | 取代手寫 API 型別；後端改 schema → 前端 `gen:api` → TypeScript 編譯報錯，比 runtime 錯誤早發現 |
| **開發期用 Vite Proxy** | 前端開發時不需設定 CORS，proxy 讓前端程式碼只寫 `/api/*` 路徑即可；切換環境僅改 `.env` 檔 |
| **`api/client.ts` 統一入口** | 所有 API 呼叫都從此處讀取 `VITE_API_BASE_URL`，日後更換 base URL 只需改一處 |
| **Vite Proxy 針對 SSE 關閉 compression** | SSE 需要逐塊傳輸，啟用 gzip 會導致緩衝後一次性送出，破壞即時串流效果 |
| **先實作 Fake 模式** | 讓前後端平行開發，前端不必等 Ollama 設定完成才能調 UI |
| **Embedding 也有 Fake 實作** | 在無 Ollama 的 CI 環境能驗證 DB schema 與查詢邏輯 |
| **OpenAiLlmService 預留不實作** | 保留擴充點；若 Demo 後需雲端部署，只需填入 API Key 並實作此類別 |
| **選用 qwen2.5:7b** | 中文推薦理由品質優於 llama3，本機 7B 約需 6GB RAM/VRAM |
| **選用 nomic-embed-text** | 768 維、多語言支援、Ollama 官方模型庫收錄 |
| **選用 ivfflat index** | 200 筆商品量級，ivfflat 效能足夠；量級達萬筆以上改用 hnsw |
