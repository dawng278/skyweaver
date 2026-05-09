# Tài liệu Kiến trúc Hệ thống — SkyWeaver

> **Phiên bản:** 1.0.0 | **Cập nhật:** 2026

---

## 1. Tổng quan Kiến trúc 3-Plane

Hệ thống được thiết kế theo mô hình **3-Plane Architecture** kết hợp **Agent-Server Pattern**:

```
╔══════════════════════════════════════════════════════════════╗
║                     CONTROL PLANE                            ║
║  ┌──────────────────────┐    ┌──────────────────────────┐   ║
║  │   Frontend (Next.js) │    │  Backend Orchestrator    │   ║
║  │   - App Router       │◄──►│  (Golang / Fiber)        │   ║
║  │   - Server Components│    │  - REST API  :8080       │   ║
║  │   - Xterm.js Terminal│    │  - gRPC Server :50051    │   ║
║  │   - WebSocket Client │    │  - Worker Pool           │   ║
║  │   - Recharts / D3    │    │  - Reconciliation Loop   │   ║
║  └──────────────────────┘    └──────────┬───────────────┘   ║
║                                          │                   ║
║                         ┌────────────────┼──────────────┐   ║
║                    ┌────▼───┐      ┌─────▼──┐   ┌──────▼─┐  ║
║                    │  PgSQL │      │ Redis  │   │  MinIO │  ║
║                    │  :5432 │      │ :6379  │   │  :9000 │  ║
║                    └────────┘      └────────┘   └────────┘  ║
╚══════════════════════════════════════════════════════════════╝
                              │ gRPC Stream (mTLS TLS 1.3)
╔══════════════════════════════════════════════════════════════╗
║                      DATA PLANE                              ║
║         Kênh truyền dữ liệu được mã hóa bằng mTLS           ║
╚══════════════════════════════════════════════════════════════╝
                              │
╔══════════════════════════════════════════════════════════════╗
║                    EXECUTION PLANE                           ║
║  ┌────────────┐    ┌────────────┐    ┌────────────┐          ║
║  │  Go Agent  │    │  Go Agent  │    │  Go Agent  │          ║
║  │ (AWS EC2)  │    │ (GCP VM)   │    │  (On-prem) │          ║
║  │ /proc read │    │ /proc read │    │ /proc read │          ║
║  │ Docker mgmt│    │ Docker mgmt│    │ Docker mgmt│          ║
║  │ Local Buf  │    │ Local Buf  │    │ Local Buf  │          ║
║  └────────────┘    └────────────┘    └────────────┘          ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 2. Cấu trúc Thư mục Dự án

```
skyweaver/
├── .github/
│   └── workflows/
│       ├── ci-backend.yml        # Go lint + test
│       ├── ci-frontend.yml       # ESLint + Next.js build
│       ├── ci-agent.yml          # Cross-compile binary
│       ├── security-scan.yml     # gosec + trivy
│       └── docker-build.yml      # Build & push ghcr.io
│
├── backend/                      # Golang Orchestrator
│   ├── cmd/
│   │   ├── server/main.go        # Entry point HTTP + gRPC server
│   │   └── agent/main.go         # Entry point Agent (deprecated, see /agent)
│   ├── internal/
│   │   ├── auth/                 # JWT, OAuth2, 2FA, RBAC
│   │   ├── server/               # Server CRUD, SSH check
│   │   ├── credential/           # AES-256-GCM encrypt/decrypt
│   │   ├── monitoring/           # Metrics ingest, WebSocket hub
│   │   ├── deployment/           # Pipeline, symlink, rollback
│   │   ├── alerting/             # Rule eval, notification
│   │   ├── worker/               # Worker Pool + Task Queue
│   │   ├── reconciler/           # Reconciliation loop
│   │   ├── grpc/                 # gRPC handlers/interceptors
│   │   └── terminal/             # SSH proxy over WebSocket
│   ├── pkg/
│   │   ├── crypto/               # AES, TLS utilities
│   │   ├── ssh/                  # SSH executor
│   │   └── db/                   # Database connection pool
│   ├── proto/                    # Protobuf definitions (.proto files)
│   ├── go.mod
│   └── go.sum
│
├── frontend/                     # Next.js 14+ TypeScript
│   ├── app/
│   │   ├── (auth)/login/
│   │   ├── (auth)/register/
│   │   ├── dashboard/
│   │   │   ├── servers/[id]/metrics/
│   │   │   ├── servers/[id]/terminal/
│   │   │   ├── servers/[id]/deployments/
│   │   │   ├── credentials/
│   │   │   ├── alerts/
│   │   │   └── settings/
│   │   └── api/                  # Route Handlers (BFF layer)
│   ├── components/
│   │   ├── ui/                   # Shared UI components
│   │   ├── charts/               # Recharts wrappers
│   │   └── terminal/             # Xterm.js component
│   ├── package.json
│   └── tsconfig.json
│
├── agent/                        # Go Agent (static binary)
│   ├── cmd/main.go               # Entry point
│   ├── internal/
│   │   ├── collector/            # /proc reader, metrics
│   │   ├── executor/             # Command executor
│   │   └── buffer/               # Local metrics buffer
│   ├── pkg/                      # Shared utilities
│   ├── go.mod
│   └── go.sum
│
├── infra/
│   ├── docker/
│   │   ├── Dockerfile.backend
│   │   ├── Dockerfile.frontend
│   │   └── Dockerfile.agent
│   ├── nginx/
│   │   └── nginx.conf            # Reverse proxy config
│   └── migrations/               # SQL schema files
│       ├── 001_users.sql
│       ├── 002_credentials.sql
│       ├── 003_servers.sql
│       ├── 004_metrics.sql
│       ├── 005_deployments.sql
│       ├── 006_alert_rules.sql
│       ├── 007_alert_events.sql
│       └── 008_audit_logs.sql
│
├── docs/
│   ├── ARCHITECTURE.md           # File này
│   └── TASKS.md                  # Kế hoạch task theo ưu tiên
│
├── docker-compose.yml            # Dev stack đầy đủ
├── .env.example                  # Template biến môi trường
├── .gitignore
└── README.md
```

---

## 3. Sơ đồ ERD (Text)

```
users (1) ──────< oauth_accounts
  │
  ├──── (1) ─────< refresh_tokens
  │
  ├──── (1) ─────< credentials (1) ─────< servers (1) ─────< metrics
  │                                           │           └─────< metrics_hourly
  │                                           ├───────────────< deployments
  │                                           └───────────────< alert_rules ────< alert_events
  │
  └──── (1) ─────< audit_logs
```

---

## 4. Luồng Dữ liệu Chính

### 4.1 Luồng Metrics Real-time
```
Agent (/proc)
  → goroutine MetricsCollector (every 10s)
  → gRPC bidirectional stream (mTLS)
  → Backend StreamHandler
  → Batch insert PostgreSQL metrics table
  → Redis pub/sub channel "metrics:{server_id}"
  → WebSocket Hub.Broadcast()
  → Frontend WebSocket client
  → React state update
  → Recharts re-render
```

### 4.2 Luồng Deployment
```
User → POST /api/deployments
  → Backend validation + Distributed Lock (Redis)
  → Task Queue (Redis List)
  → Worker Pool picks task
  → gRPC command đến Agent
  → Agent: git clone → build → symlink atomic
  → Agent: notify status stream
  → Backend: update deployments table
  → WebSocket: push status đến Frontend
```

### 4.3 Luồng Alert
```
Reconciliation Loop (every 30s)
  → Query avg metrics từ DB (last N seconds)
  → So sánh với alert_rules threshold
  → Nếu vi phạm & cooldown hết hạn:
    → Insert alert_events (firing)
    → Gửi Telegram/Discord/Email webhook
    → Update last_triggered_at
  → Khi điều kiện hết: Insert alert_events (resolved)
```

---

## 5. Quyết định Kiến trúc (ADR)

### ADR-01: gRPC thay vì REST cho Agent-Backend
- **Lý do:** Bidirectional streaming, Protocol Buffer nén ~60% so JSON, overhead thấp
- **Đánh đổi:** Phức tạp hơn REST

### ADR-02: Backend Stateless
- **Lý do:** Cho phép scale ngang (horizontal scaling)
- **Thực hiện:** Session trong Redis, File state trong MinIO

### ADR-03: Symlink-based Zero-Downtime Deployment
- **Lý do:** `ln -sfn` là atomic operation của OS
- **Cấu trúc:**
  ```
  /app/releases/20260101_120000/  ← phiên bản cũ
  /app/releases/20260102_150000/  ← phiên bản hiện tại
  /app/current -> releases/20260102_150000  ← symlink
  ```

### ADR-04: AES-256-GCM cho Credential
- **Lý do:** Authenticated encryption, chống tampering, NIST recommended
- **Thực hiện:** Key từ env var, nonce random 12 bytes mỗi lần encrypt

### ADR-05: mTLS cho Agent-Backend
- **Lý do:** Xác thực hai chiều — Backend verify Agent, Agent verify Backend
- **Thực hiện:** CA tự ký, Agent mang client certificate khi kết nối

---

## 6. Yêu cầu Phi chức năng

| Chỉ tiêu | Mục tiêu |
|---|---|
| API P95 latency | < 200ms |
| Metrics real-time delay | < 2 giây |
| Concurrent Agent | ≥ 500 gRPC streams |
| Uptime | ≥ 99.5% |
| Test coverage (backend) | ≥ 75% |
| Agent binary size | < 20MB |
| Deployment rollback time | < 10 giây |

---

## 7. Kiến trúc Bảo mật

```
┌─────────────────────────────────────────────┐
│               Security Layers                │
│                                             │
│  L1: TLS 1.3 (HTTPS + mTLS gRPC)           │
│  L2: JWT (RS256, 15min) + Refresh Token     │
│  L3: RBAC (super_admin > admin > developer > viewer) │
│  L4: AES-256-GCM (Credential at-rest)      │
│  L5: bcrypt cost=12 (Password hash)         │
│  L6: Rate Limiting 100 req/min/IP           │
│  L7: Audit Log (tất cả thao tác quan trọng) │
└─────────────────────────────────────────────┘
```
