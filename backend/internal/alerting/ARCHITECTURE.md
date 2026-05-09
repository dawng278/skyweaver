# Kiến trúc Module: Alerting

**Branch:** `feat/alerting`  
**Mục đích:** Đánh giá alert rules mỗi 30 giây, gửi thông báo qua Telegram/Discord/Email khi vi phạm ngưỡng, tránh spam với cooldown.

---

## Reconciliation Loop

```
Goroutine: ReconciliationLoop (every 30s)
  │
  ├── Fetch tất cả active alert_rules từ DB (hoặc cache Redis)
  │
  ├── Với mỗi rule:
  │     ├── Query avg metric trong duration_secs gần nhất
  │     │     SELECT AVG(cpu_usage) FROM metrics
  │     │     WHERE server_id = ? AND collected_at > NOW() - interval
  │     │
  │     ├── EvaluateRule(currentValue, operator, threshold)
  │     │
  │     ├── Vi phạm? ──→ CheckCooldown(last_triggered_at, cooldown_secs)
  │     │                  ├── Trong cooldown → bỏ qua
  │     │                  └── Hết cooldown:
  │     │                        ├── INSERT alert_events (firing)
  │     │                        ├── SendNotifications(channels, message)
  │     │                        └── UPDATE last_triggered_at = NOW()
  │     │
  │     └── Không vi phạm nhưng có event 'firing' gần nhất?
  │           → INSERT alert_events (resolved)
  │           → Gửi "Resolved" notification
  │
  └── Chờ 30 giây tiếp theo
```

## Channels Supported

| Type | Config Fields | Ví dụ |
|---|---|---|
| `telegram` | `bot_token`, `chat_id` | Bot API sendMessage |
| `discord` | `webhook` | Discord Webhook POST |
| `email` | `to`, `smtp_host`, `smtp_port` | SMTP TLS |

## Cấu trúc Files

```
backend/internal/alerting/
├── evaluator.go       # EvaluateRule(), CheckCooldown(), ReconciliationLoop()
├── notifier.go        # SendTelegram(), SendDiscord(), SendEmail()
├── handler.go         # HTTP handlers: CRUD alert rules
└── model.go           # AlertRule, AlertEvent GORM models
```

## Alert Rule Config (JSONB channels)

```json
{
  "channels": [
    {
      "type": "telegram",
      "bot_token": "123456:ABC...",
      "chat_id": "-1001234567890"
    },
    {
      "type": "discord",
      "webhook": "https://discord.com/api/webhooks/..."
    }
  ]
}
```

## Message Format (Telegram/Discord)

```
🚨 [SkyWeaver Alert] CPU Cao — Server Production-01
Metric: cpu_usage = 92.5% (ngưỡng: > 85%)
Thời gian: 2026-05-09 15:30:00 UTC
Server: 192.168.1.10 (aws-ec2-prod)
```

## API Endpoints

| Method | Path | Mô tả |
|---|---|---|
| POST | `/v1/alert-rules` | Tạo rule |
| GET | `/v1/alert-rules` | Danh sách rules |
| PUT | `/v1/alert-rules/:id` | Cập nhật rule |
| DELETE | `/v1/alert-rules/:id` | Xóa rule |
| GET | `/v1/alert-events` | Lịch sử events |

## Task Liên quan: P8
