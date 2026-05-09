# Kiến trúc Module: Server Management

**Branch:** `feat/server-management`  
**Mục đích:** CRUD API quản lý máy chủ, kiểm tra kết nối SSH, phát hiện hardware info, nhận heartbeat từ Agent.

---

## Luồng Thêm Máy chủ

```
User → POST /v1/servers
  │
  ├── Validate IP address, port, credential_id
  ├── Decrypt SSH private key từ credentials table
  ├── SSHPing(host, port, username, key) trong 10 giây
  │     → Kết nối SSH thành công?
  │       ├── Yes: parse hardware info (uname, nproc, free, df)
  │       │         update status = 'online', hardware_info
  │       └── No:  status = 'error', message = "SSH connection failed"
  ├── Insert vào bảng servers
  └── Push task vào Redis queue: "register_agent:{server_id}"
        → Worker gửi lệnh cài Agent qua SSH
```

## Cấu trúc Files

```
backend/internal/server/
├── handler.go       # HTTP handlers: Create, Get, List, Update, Delete
├── service.go       # Business logic: SSH check, hardware detection
├── heartbeat.go     # Background job: check heartbeat mỗi 60 giây
└── model.go         # Server struct, GORM model
```

## Heartbeat Monitor

```
Background goroutine (every 60s):
  SELECT * FROM servers WHERE status = 'online'
    AND last_seen_at < NOW() - INTERVAL '60 seconds'
  → UPDATE status = 'offline'
  → Gửi alert nếu có alert rule cho server
```

## SSH Hardware Detection

Sau khi kết nối SSH thành công, chạy commands:
```bash
uname -s          # OS name: Linux
uname -r          # Kernel: 5.15.0-91-generic
nproc             # CPU cores: 4
free -m           # RAM total/used
df -BG /          # Disk total/used
cat /etc/os-release | grep PRETTY_NAME  # OS version
```

## API Endpoints

| Method | Path | Quyền | Mô tả |
|---|---|---|---|
| POST | `/v1/servers` | admin | Thêm server |
| GET | `/v1/servers` | developer | Danh sách server |
| GET | `/v1/servers/:id` | developer | Chi tiết server |
| PUT | `/v1/servers/:id` | admin | Cập nhật server |
| DELETE | `/v1/servers/:id` | admin | Xóa server |
| POST | `/v1/servers/:id/check` | admin | Kiểm tra kết nối lại |

## Task Liên quan: P5
