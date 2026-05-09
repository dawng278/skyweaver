# Kiến trúc Module: Monitoring

**Branch:** `feat/monitoring`  
**Mục đích:** Nhận metrics stream từ Agent qua gRPC, batch insert vào PostgreSQL, publish qua Redis pub/sub, broadcast real-time tới Frontend qua WebSocket.

---

## Luồng Dữ liệu

```
Agent (gRPC stream)
  │  MetricsReport (every 10s)
  ▼
gRPC StreamHandler
  │  Buffer tích lũy 100 records hoặc mỗi 5 giây
  ▼
Batch Insert → PostgreSQL metrics table
  │
  ▼
Redis PUBLISH "metrics:{server_id}"
  │
  ▼
WebSocket Hub.Broadcast()
  │  JSON: {cpu_usage, ram_used_mb, ram_total_mb, ...}
  ▼
Frontend WebSocket Client
  │
  ▼
Recharts LineChart re-render
```

## Cấu trúc Files

```
backend/internal/monitoring/
├── handler.go         # gRPC stream handler — nhận từ Agent
├── hub.go             # WebSocket Hub — broadcast đến Frontend clients
├── ws_handler.go      # HTTP/WebSocket endpoint handler
├── downsampler.go     # Cron job: aggregate metrics_hourly mỗi giờ
├── retention.go       # Cron job: xóa partition cũ > 90 ngày
└── service.go         # Business logic: query metrics theo time range
```

## WebSocket Hub

```go
// Một Hub quản lý tất cả WebSocket connections
Hub {
  clients: map[serverID]map[*Client]bool
  
  Subscribe(serverID, client)
  Unsubscribe(serverID, client)
  Broadcast(serverID, metrics)  // O(n) với n = clients theo dõi server đó
}
```

## Downsampling Strategy

| Độ phân giải | Dữ liệu | Bảng |
|---|---|---|
| 10 giây | 0 - 7 ngày | `metrics` (partitioned) |
| 1 giờ | 7 - 30 ngày | `metrics_hourly` |
| Xóa | > 90 ngày | Partition drop |

## Cron Jobs

- **Downsampler:** Chạy mỗi giờ, gộp `metrics` vào `metrics_hourly` cho data 7-30 ngày trước
- **Retention:** Chạy mỗi ngày lúc 02:00, drop partitions > 90 ngày

## Task Liên quan: P4, P6
