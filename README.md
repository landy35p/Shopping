# Yahoo 購物 AI 推薦 Demo

> 以「Embedding 向量召回 + LLM 串流說明」展示混合式 AI 個性化推薦的完整前後端實作。

## Demo 預覽

切換三位虛構用戶（科技控 / 居家達人 / 運動王子），觀察 AI 如何依照個人購買習慣推薦不同商品，並以繁體中文即時串流推薦說明。

## Repo 結構

| Repo | 說明 |
|------|------|
| **Shopping**（本 Repo） | 基礎設施：`docker-compose.yml`、技術文件 |
| **Shopping-backend** | ASP.NET Core 8 API，向量搜尋 + LLM 串流，Port `5000` |
| **Shopping-frontend** | React 19 + Vite 6，SSE 消費 + 動畫 UI，Port `5173` |

## 快速開始

**Fake 模式（不需 Ollama，5 分鐘內可啟動）：**

```bash
# 1. 啟動 DB
docker compose up -d

# 2. 後端
cd Shopping-backend && dotnet run -- seed
dotnet run

# 3. 前端（另開 Terminal）
cd Shopping-frontend && pnpm install && pnpm dev
```

開啟 http://localhost:5173

**完整 Ollama 模式（真實 AI 推薦）：** 請見 [docs/SETUP.md](docs/SETUP.md)

## 文件

| 文件 | 對象 |
|------|------|
| [docs/SETUP.md](docs/SETUP.md) | 工程師：完整環境建制與設定說明 |
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | 使用者：Demo 操作與功能說明 |
| [docs/spec.md](docs/spec.md) | 架構師：技術規格與設計決策 |

## 技術架構

```
React + Vite (前端) ──SSE──► ASP.NET Core 8 (後端) ──► PostgreSQL + pgvector
                                                    └──► Ollama (LLM / Embedding)
```

- **向量搜尋**：pgvector cosine similarity，< 50ms 召回 Top-20 候選
- **LLM 串流**：qwen2.5:7b 生成繁體中文推薦理由，Server-Sent Events 即時推送
- **Provider 切換**：修改 `appsettings.json` 即可在 `fake / ollama / openai` 間切換，零程式碼改動
