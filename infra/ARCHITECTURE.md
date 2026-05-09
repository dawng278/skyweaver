# Kiến trúc Module: Infrastructure

**Branch:** `feat/infrastructure`  
**Mục đích:** Thiết lập toàn bộ môi trường vận hành — Docker Compose dev stack, Nginx reverse proxy, database schema migrations, Dockerfiles production.

---

## Thành phần

```
infra/
├── docker/
│   ├── Dockerfile.backend    # Multi-stage Go build → alpine runtime (non-root)
│   ├── Dockerfile.frontend   # Multi-stage Node build → standalone Next.js
│   └── Dockerfile.agent      # Multi-stage Go build → scratch image
├── nginx/
│   └── nginx.conf            # Reverse proxy + rate limiting + WebSocket upgrade
└── migrations/
    ├── 001_users.sql          # users, oauth_accounts, refresh_tokens
    ├── 002_credentials.sql    # credentials (AES-256-GCM)
    ├── 003_servers.sql        # servers (GIN index trên tags)
    ├── 004_metrics.sql        # metrics partitioned + metrics_hourly downsampled
    ├── 005_deployments.sql    # deployments
    ├── 006_alert_rules.sql    # alert_rules
    ├── 007_alert_events.sql   # alert_events
    └── 008_audit_logs.sql     # audit_logs
```

## Docker Compose Services

| Service | Image | Port | Vai trò |
|---|---|---|---|
| `postgres` | postgres:15-alpine | 5432 | Database chính |
| `redis` | redis:7-alpine | 6379 | Cache, Lock, Queue |
| `minio` | minio/minio | 9000/9001 | Object storage |
| `backend` | build local | 8080/50051 | HTTP API + gRPC |
| `frontend` | build local | 3000 | Next.js app |
| `nginx` | nginx:alpine | 80/443 | Reverse proxy |

## Quyết định Kiến trúc

- **Healthcheck** trên postgres và redis để đảm bảo backend chỉ khởi động khi DB sẵn sàng
- **Non-root user** trong tất cả Dockerfiles (`USER nobody:nobody`, `USER node`)
- **scratch base** cho Agent image — tối thiểu attack surface
- **Rate limiting** tại Nginx: 100 req/phút/IP
- **WebSocket upgrade** cho `/ws` endpoint tại Nginx

## Task Liên quan: P0, P1
