# SkyWeaver 🌩️

> **Hệ thống Điều phối và Giám sát Tài nguyên Cloud Lai**  
> Hybrid Cloud Resource Orchestrator & Monitor

[![CI Backend](https://github.com/dawng278/skyweaver/actions/workflows/ci-backend.yml/badge.svg)](https://github.com/dawng278/skyweaver/actions/workflows/ci-backend.yml)
[![CI Frontend](https://github.com/dawng278/skyweaver/actions/workflows/ci-frontend.yml/badge.svg)](https://github.com/dawng278/skyweaver/actions/workflows/ci-frontend.yml)
[![CI Agent](https://github.com/dawng278/skyweaver/actions/workflows/ci-agent.yml/badge.svg)](https://github.com/dawng278/skyweaver/actions/workflows/ci-agent.yml)
[![Security Scan](https://github.com/dawng278/skyweaver/actions/workflows/security-scan.yml/badge.svg)](https://github.com/dawng278/skyweaver/actions/workflows/security-scan.yml)

---

## Giới thiệu

SkyWeaver là nền tảng SaaS cho phép **quản lý, triển khai và giám sát** tài nguyên trên nhiều môi trường điện toán đám mây (AWS, GCP, Azure) và máy chủ vật lý thông qua một giao diện tập trung duy nhất.

### Tính năng chính

| Module | Mô tả |
|---|---|
| 🔐 **Xác thực & Phân quyền** | JWT, OAuth2 (GitHub/Google), 2FA TOTP, RBAC |
| 🖥️ **Quản lý Máy chủ** | SSH check, phát hiện hardware, gắn nhãn, nhóm |
| 📊 **Giám sát Real-time** | Metrics CPU/RAM/Disk/Network qua gRPC stream, WebSocket |
| 🚀 **Deployment Pipeline** | Git clone → Symlink atomic → Zero-downtime → Rollback |
| 🚨 **Alerting** | Rule-based alerts, Telegram/Discord/Email webhook |
| 💻 **Web Terminal** | SSH-over-WebSocket, Xterm.js ANSI-compatible |
| 🤖 **Go Agent** | Static binary < 20MB, mTLS, local buffer khi mất mạng |

---

## Kiến trúc Tổng thể

```
┌─────────────────── CONTROL PLANE ────────────────────┐
│  Next.js Frontend  ◄──────►  Golang Backend (gRPC+REST) │
│                                    │                   │
│                         PostgreSQL + Redis + MinIO     │
└───────────────────────────┬──────────────────────────-┘
                             │ gRPC Stream (mTLS)
                   ┌─────────┼─────────┐
              ┌────▼───┐ ┌───▼────┐ ┌──▼─────┐
              │ Agent  │ │ Agent  │ │ Agent  │
              │(AWS EC2)│ │(GCP VM)│ │(On-prem│
              └────────┘ └────────┘ └────────┘
```

Xem chi tiết: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## Công nghệ

| Lớp | Công nghệ |
|---|---|
| Frontend | Next.js 14+, TypeScript, React Query, Recharts, Xterm.js |
| Backend | Go 1.21+, Fiber, gRPC, GORM, go-redis |
| Agent | Go 1.21+ (static CGO_ENABLED=0), Protocol Buffers |
| Database | PostgreSQL 15, Redis 7, MinIO |
| Infra | Docker Compose, Nginx, GitHub Actions |

---

## Cấu trúc Nhánh

| Nhánh | Mục đích |
|---|---|
| `main` | Production — merge sau review |
| `develop` | Integration — tích hợp các feature |
| `feat/infrastructure` | Docker, Nginx, DB migrations |
| `feat/auth` | JWT, OAuth2, 2FA, RBAC |
| `feat/agent` | Go Agent binary, gRPC, /proc metrics |
| `feat/monitoring` | Metrics ingestion, downsampling, WebSocket |
| `feat/server-management` | SSH check, Server CRUD, heartbeat |
| `feat/deployment` | Pipeline, Symlink, Rollback |
| `feat/alerting` | Alert rules, Telegram/Discord notify |
| `feat/terminal` | Xterm.js, SSH proxy WebSocket |
| `feat/frontend` | Next.js App Router, UI components |

---

## Bắt đầu Phát triển

```bash
# Clone repo
git clone git@github.com:dawng278/skyweaver.git
cd skyweaver

# Copy file môi trường
cp .env.example .env

# Khởi động toàn bộ stack
docker compose up -d

# Backend (port 8080)
cd backend && go run ./cmd/server

# Frontend (port 3000)
cd frontend && npm install && npm run dev

# Agent (kết nối tới backend)
cd agent && go run ./cmd/agent
```

---

## Task Kế hoạch

Xem chi tiết thứ tự ưu tiên và code mẫu: [docs/TASKS.md](docs/TASKS.md)

---

## Tác giả

**dawng278** — Đồ án Tốt nghiệp, 2026