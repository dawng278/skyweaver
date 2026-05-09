# Kiến trúc Module: Agent

**Branch:** `feat/agent`  
**Mục đích:** Go Agent static binary — thu thập metrics hệ thống, gửi qua gRPC bidirectional stream (mTLS) đến Backend, tự kết nối lại khi mất mạng.

---

## Vòng đời Agent

```
Start
  │
  ▼
Load Config (env vars / config file)
  │
  ▼
Load/Generate Client Certificate (mTLS)
  │
  ▼
Establish gRPC Stream (mTLS TLS 1.3) ◄─── Retry: Exponential Backoff (1s→5min)
  │
  ├──▶ Goroutine A: MetricsCollector (every 10s)
  │       /proc/stat   → CPU usage (2-sample delta)
  │       /proc/meminfo → RAM used/total
  │       /proc/diskstats → Disk I/O
  │       /proc/net/dev  → Network rx/tx
  │       → send qua gRPC stream
  │
  ├──▶ Goroutine B: CommandExecutor (on demand)
  │       Nhận lệnh từ Backend qua stream
  │       Thực thi lệnh shell với timeout
  │       Stream output về Backend
  │
  ├──▶ Goroutine C: HealthReporter (every 30s)
  │       Gửi heartbeat để Backend biết agent còn sống
  │
  └──▶ Local Buffer: Khi stream đứt
          Lưu tối đa 1000 MetricsPoint vào ring buffer
          Flush khi reconnect thành công
```

## Cấu trúc Files

```
agent/
├── cmd/main.go                  # Entry point, setup gRPC, graceful shutdown
├── internal/
│   ├── collector/
│   │   ├── metrics.go           # Đọc /proc/*
│   │   └── metrics_test.go      # Unit tests
│   ├── executor/
│   │   └── command.go           # Shell command executor với timeout
│   └── buffer/
│       └── ring_buffer.go       # Ring buffer cho local metrics khi offline
├── pkg/
│   └── cert/                    # Load/Generate mTLS client certificate
└── proto/                       # Symlink hoặc copy từ backend/proto/
```

## Proto Definition (agent.proto)

```protobuf
syntax = "proto3";
package agent;

message MetricsReport {
  string server_id    = 1;
  int64  timestamp    = 2;  // Unix nanoseconds
  float  cpu_usage    = 3;
  int32  ram_used_mb  = 4;
  int32  ram_total_mb = 5;
  float  disk_used_gb = 6;
  float  disk_total_gb = 7;
  float  net_rx_kbps  = 8;
  float  net_tx_kbps  = 9;
  float  load_avg_1m  = 10;
}

message Command {
  string id      = 1;
  string payload = 2;  // Shell command
  int32  timeout = 3;  // Seconds
}

message CommandOutput {
  string command_id = 1;
  bytes  data       = 2;
  bool   done       = 3;
  int32  exit_code  = 4;
}

message Heartbeat {
  string agent_version = 1;
  int64  uptime_secs   = 2;
}

service AgentService {
  rpc Stream(stream AgentMessage) returns (stream BackendMessage);
}

message AgentMessage {
  oneof payload {
    MetricsReport metrics   = 1;
    CommandOutput cmd_output = 2;
    Heartbeat     heartbeat  = 3;
  }
}

message BackendMessage {
  oneof payload {
    Command cmd = 1;
  }
}
```

## Yêu cầu Phi chức năng

- Binary size < 20MB (CGO_ENABLED=0, `-s -w` ldflags)
- Tự reconnect với Exponential Backoff: 1s → 2s → 4s → ... tối đa 5 phút
- Local buffer: ring buffer 1000 MetricsPoint (~80KB RAM)
- Goroutine leak-free: sử dụng context để cancel tất cả goroutines

## Task Liên quan: P3
