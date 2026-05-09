# Kiến trúc Module: Deployment

**Branch:** `feat/deployment`  
**Mục đích:** Pipeline triển khai zero-downtime dùng symlink atomic, distributed lock Redis, hỗ trợ rollback về phiên bản trước.

---

## Luồng Deployment

```
POST /v1/servers/:id/deployments
  │
  ├── Validate request (repo_url, branch, deploy_path)
  ├── Acquire Redis LOCK "deploy:{server_id}" (TTL 10 phút)
  │     → LOCK bị chiếm? → 409 CONFLICT
  ├── Insert deployment record (status = 'pending')
  ├── Push task vào Redis Queue "deploy_tasks"
  │
  └── Worker picks task:
        ├── UPDATE status = 'running'
        ├── Send gRPC command đến Agent:
        │     git clone --branch {branch} --depth 1 {repo} /app/releases/{version}
        │     bash /app/releases/{version}/deploy.sh  (nếu có)
        │     ln -sfn /app/releases/{version} /app/current  ← ATOMIC
        │     systemctl reload {app_name} || true
        │     ls -t /app/releases | tail -n +6 | xargs rm -rf  ← cleanup
        ├── Stream logs về Backend → lưu vào deployment.log_output
        ├── UPDATE status = 'success' | 'failed'
        └── Release Redis LOCK
```

## Zero-Downtime Symlink Pattern

```
TRƯỚC swap:
  /app/current → /app/releases/20260101_120000  ← đang phục vụ

TRONG swap (atomic):
  ln -sfn /app/releases/20260102_150000 /app/current

SAU swap (< 1ms):
  /app/current → /app/releases/20260102_150000  ← phiên bản mới
```

## Rollback Flow

```
POST /v1/deployments/:id/rollback
  │
  ├── Tìm phiên bản gần nhất có status = 'success' trước deployment này
  ├── Acquire Redis LOCK
  ├── ln -sfn /app/releases/{prev_version} /app/current
  ├── systemctl reload {app_name}
  └── UPDATE deployment status = 'rolled_back' (< 10 giây)
```

## Cấu trúc Files

```
backend/internal/deployment/
├── handler.go       # HTTP handlers: Create, List, Rollback, GetLogs
├── pipeline.go      # SymlinkDeploy(), Rollback() logic
├── worker.go        # Worker Pool task consumer
├── lock.go          # Redis distributed lock: Acquire, Release
└── model.go         # Deployment GORM model
```

## API Endpoints

| Method | Path | Quyền | Mô tả |
|---|---|---|---|
| POST | `/v1/servers/:id/deployments` | developer+ | Trigger deployment |
| GET | `/v1/servers/:id/deployments` | developer | Lịch sử deployment |
| GET | `/v1/deployments/:id/logs` | developer | Stream logs real-time |
| POST | `/v1/deployments/:id/rollback` | admin | Rollback |

## Constraints

- Chỉ 1 deployment chạy đồng thời / server (Distributed Lock)
- Giữ 5 phiên bản gần nhất (tự dọn cũ)
- Rollback < 10 giây

## Task Liên quan: P7
