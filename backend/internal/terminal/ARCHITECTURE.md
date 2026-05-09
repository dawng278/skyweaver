# Kiến trúc Module: Terminal

**Branch:** `feat/terminal`  
**Mục đích:** Web Terminal qua WebSocket + SSH proxy — người dùng mở terminal SSH trực tiếp trong trình duyệt với Xterm.js, đầy đủ ANSI/color/Tab completion.

---

## Luồng Terminal Session

```
Browser (Xterm.js)
  │  WebSocket connect /ws/terminal/{serverID}?token=JWT
  ▼
Backend WebSocket Handler
  │  Xác thực JWT
  │  Kiểm tra server thuộc về user
  │  Decrypt SSH private key từ DB
  │  Giới hạn: tối đa 5 sessions/user (Redis counter)
  ▼
SSHProxy
  │  ssh.Dial() → SSH Client
  │  session.RequestPty("xterm-256color", rows, cols, modes)
  │  session.Start("/bin/bash")
  │
  ├──▶ goroutine: SSH stdout → WebSocket binary frames
  └──── WebSocket binary frames → SSH stdin
  
Ghi log: tất cả lệnh → audit_logs

Idle timeout: 30 phút không activity → đóng session
```

## Cấu trúc Files

```
backend/internal/terminal/
├── handler.go       # WebSocket endpoint, auth, session limit
├── proxy.go         # SSHProxy struct: Dial, RequestPty, pipe goroutines
├── session.go       # Session manager: TTL, idle detection, Redis counter
└── audit.go         # Ghi lệnh vào audit_logs
```

## Frontend Component

```
frontend/components/terminal/
├── TerminalPanel.tsx    # Xterm.js init, WebSocket pipe, resize handling
└── useTerminalWS.ts     # Custom hook WebSocket management
```

## Session Limits

```
Mỗi lần mở terminal:
  1. INCR "terminal_sessions:{user_id}" (Redis, TTL = session timeout)
  2. GET counter → nếu > 5: reject với 429 TOO_MANY_SESSIONS
  3. Khi close: DECR "terminal_sessions:{user_id}"

Idle timeout:
  - Backend track last_activity timestamp
  - Goroutine kiểm tra mỗi 60 giây
  - Nếu idle > 30 phút: đóng WebSocket + SSH session
```

## PTY Resize

Khi browser resize:
```
Frontend → WebSocket gửi JSON: {"type": "resize", "rows": 24, "cols": 80}
Backend → session.WindowChange(rows, cols)
```

## Bảo mật

- JWT required — không thể mở terminal không auth
- SSH key không bao giờ expose về Frontend
- Tất cả lệnh thực thi được ghi vào `audit_logs`
- Session tự đóng sau 30 phút idle

## Task Liên quan: P9
