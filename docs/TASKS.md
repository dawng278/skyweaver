# Kế hoạch Task — SkyWeaver

> Thứ tự ưu tiên: **P0 (cao nhất) → P9 (thấp nhất)**  
> Mỗi task gắn với branch cụ thể, có code mẫu và tiêu chí hoàn thành.

---

## P0 — Foundation: Go Module + Docker Compose Dev Stack

**Branch:** `feat/infrastructure`  
**Mục tiêu:** Khởi tạo môi trường phát triển đầy đủ — backend Go, agent Go, frontend Next.js, và Docker Compose stack.

### Các việc cần làm:
1. Khởi tạo Go modules cho `backend/` và `agent/`
2. Khởi tạo Next.js project trong `frontend/`
3. Xác nhận `docker compose up -d` chạy thành công (Postgres, Redis, MinIO)

### Code mẫu — `backend/cmd/server/main.go`
```go
package main

import (
    "log"
    "os"

    "github.com/gofiber/fiber/v2"
    "github.com/gofiber/fiber/v2/middleware/logger"
    "github.com/gofiber/fiber/v2/middleware/recover"
    "github.com/joho/godotenv"
)

func main() {
    // Tải biến môi trường từ .env (chỉ cho dev)
    if err := godotenv.Load(); err != nil {
        log.Println("Không tìm thấy .env, dùng biến môi trường hệ thống")
    }

    app := fiber.New(fiber.Config{
        AppName: "SkyWeaver Backend v1.0",
    })

    app.Use(recover.New())
    app.Use(logger.New())

    app.Get("/health", func(c *fiber.Ctx) error {
        return c.JSON(fiber.Map{"status": "ok", "version": "1.0.0"})
    })

    port := os.Getenv("HTTP_PORT")
    if port == "" {
        port = "8080"
    }

    log.Printf("Server khởi động tại :%s", port)
    if err := app.Listen(":" + port); err != nil {
        log.Fatalf("Lỗi khởi động server: %v", err)
    }
}
```

### Code mẫu — `backend/pkg/db/postgres.go`
```go
package db

import (
    "fmt"
    "os"

    "gorm.io/driver/postgres"
    "gorm.io/gorm"
    "gorm.io/gorm/logger"
)

func NewPostgres() (*gorm.DB, error) {
    dsn := os.Getenv("DATABASE_URL")
    if dsn == "" {
        dsn = fmt.Sprintf(
            "host=%s user=%s password=%s dbname=%s port=%s sslmode=disable",
            getenv("DB_HOST", "localhost"),
            getenv("DB_USER", "skyweaver"),
            getenv("DB_PASSWORD", ""),
            getenv("DB_NAME", "skyweaver"),
            getenv("DB_PORT", "5432"),
        )
    }
    return gorm.Open(postgres.Open(dsn), &gorm.Config{
        Logger: logger.Default.LogMode(logger.Info),
    })
}

func getenv(key, fallback string) string {
    if v := os.Getenv(key); v != "" {
        return v
    }
    return fallback
}
```

**Tiêu chí hoàn thành:**
- [ ] `go build ./...` trong `backend/` và `agent/` không lỗi
- [ ] `docker compose up -d` → tất cả service healthy
- [ ] `GET /health` trả về `{"status": "ok"}`

---

## P1 — Database Schema Migrations

**Branch:** `feat/infrastructure`  
**Mục tiêu:** Chạy 8 file SQL migration để tạo đầy đủ schema trong PostgreSQL.

### Code mẫu — Script chạy migrations
```bash
#!/bin/bash
# infra/migrations/run_migrations.sh
set -e

DB_URL="${DATABASE_URL:-postgres://skyweaver:skyweaver_secret@localhost:5432/skyweaver?sslmode=disable}"

echo "Chạy migrations..."
for file in $(ls infra/migrations/*.sql | sort); do
    echo "  → $file"
    psql "$DB_URL" -f "$file"
done
echo "Migrations hoàn thành!"
```

### Code mẫu — `backend/pkg/db/migrate.go`
```go
package db

import (
    "embed"
    "fmt"
    "io/fs"

    "gorm.io/gorm"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

func RunMigrations(db *gorm.DB) error {
    entries, err := fs.ReadDir(migrationFiles, "migrations")
    if err != nil {
        return fmt.Errorf("đọc thư mục migrations: %w", err)
    }

    for _, entry := range entries {
        if entry.IsDir() {
            continue
        }
        content, err := migrationFiles.ReadFile("migrations/" + entry.Name())
        if err != nil {
            return fmt.Errorf("đọc file %s: %w", entry.Name(), err)
        }
        if err := db.Exec(string(content)).Error; err != nil {
            return fmt.Errorf("migration %s thất bại: %w", entry.Name(), err)
        }
    }
    return nil
}
```

**Tiêu chí hoàn thành:**
- [ ] Tất cả 8 bảng tồn tại trong PostgreSQL
- [ ] `\dt` trong psql liệt kê đủ: users, oauth_accounts, refresh_tokens, credentials, servers, metrics, deployments, alert_rules, alert_events, audit_logs

---

## P2 — Auth: JWT + bcrypt + RBAC Middleware

**Branch:** `feat/auth`  
**Mục tiêu:** Xác thực người dùng với JWT RS256, hash mật khẩu bcrypt, middleware phân quyền RBAC.

### Code mẫu — `backend/internal/auth/jwt.go`
```go
package auth

import (
    "errors"
    "os"
    "time"

    "github.com/golang-jwt/jwt/v5"
    "github.com/google/uuid"
)

type Claims struct {
    UserID uuid.UUID `json:"uid"`
    Role   string    `json:"role"`
    jwt.RegisteredClaims
}

func IssueAccessToken(userID uuid.UUID, role string) (string, error) {
    claims := Claims{
        UserID: userID,
        Role:   role,
        RegisteredClaims: jwt.RegisteredClaims{
            ExpiresAt: jwt.NewNumericDate(time.Now().Add(15 * time.Minute)),
            IssuedAt:  jwt.NewNumericDate(time.Now()),
            Issuer:    "skyweaver",
        },
    }
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString([]byte(os.Getenv("JWT_SECRET")))
}

func VerifyAccessToken(tokenStr string) (*Claims, error) {
    token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (any, error) {
        if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, errors.New("phương thức ký không hợp lệ")
        }
        return []byte(os.Getenv("JWT_SECRET")), nil
    })
    if err != nil {
        return nil, err
    }
    claims, ok := token.Claims.(*Claims)
    if !ok || !token.Valid {
        return nil, errors.New("token không hợp lệ")
    }
    return claims, nil
}
```

### Code mẫu — `backend/internal/auth/password.go`
```go
package auth

import (
    "errors"

    "golang.org/x/crypto/bcrypt"
)

const bcryptCost = 12

func HashPassword(plaintext string) (string, error) {
    if len(plaintext) < 8 {
        return "", errors.New("mật khẩu phải có ít nhất 8 ký tự")
    }
    hash, err := bcrypt.GenerateFromPassword([]byte(plaintext), bcryptCost)
    return string(hash), err
}

func VerifyPassword(plaintext, hash string) bool {
    return bcrypt.CompareHashAndPassword([]byte(hash), []byte(plaintext)) == nil
}
```

### Code mẫu — `backend/internal/auth/middleware.go`
```go
package auth

import (
    "strings"

    "github.com/gofiber/fiber/v2"
)

// JWTMiddleware xác thực token trong header Authorization
func JWTMiddleware() fiber.Handler {
    return func(c *fiber.Ctx) error {
        header := c.Get("Authorization")
        if !strings.HasPrefix(header, "Bearer ") {
            return c.Status(401).JSON(fiber.Map{
                "error": fiber.Map{"code": "UNAUTHORIZED", "message": "Thiếu token xác thực"},
            })
        }
        claims, err := VerifyAccessToken(strings.TrimPrefix(header, "Bearer "))
        if err != nil {
            return c.Status(401).JSON(fiber.Map{
                "error": fiber.Map{"code": "TOKEN_INVALID", "message": "Token không hợp lệ hoặc hết hạn"},
            })
        }
        c.Locals("userID", claims.UserID)
        c.Locals("userRole", claims.Role)
        return c.Next()
    }
}

// RequireRole kiểm tra user có đủ quyền không
func RequireRole(roles ...string) fiber.Handler {
    allowed := make(map[string]bool)
    for _, r := range roles {
        allowed[r] = true
    }
    return func(c *fiber.Ctx) error {
        role, _ := c.Locals("userRole").(string)
        if !allowed[role] {
            return c.Status(403).JSON(fiber.Map{
                "error": fiber.Map{"code": "FORBIDDEN", "message": "Không đủ quyền thực hiện hành động này"},
            })
        }
        return c.Next()
    }
}
```

**Tiêu chí hoàn thành:**
- [ ] `POST /v1/auth/register` tạo user, trả về JWT
- [ ] `POST /v1/auth/login` xác thực, trả về access + refresh token
- [ ] Routes được bảo vệ trả về 401 khi thiếu token
- [ ] Routes admin trả về 403 khi user không đủ quyền

---

## P3 — Agent: gRPC Bidirectional Stream + /proc Metrics

**Branch:** `feat/agent`  
**Mục tiêu:** Agent Go thu thập metrics từ `/proc`, gửi qua gRPC stream tới Backend mỗi 10 giây.

### Code mẫu — `agent/internal/collector/metrics.go`
```go
package collector

import (
    "bufio"
    "fmt"
    "os"
    "strconv"
    "strings"
)

type Metrics struct {
    CPUUsage    float32
    RAMUsedMB   int32
    RAMTotalMB  int32
    DiskUsedGB  float32
    DiskTotalGB float32
    NetRxKbps   float32
    NetTxKbps   float32
    LoadAvg1m   float32
}

// ReadCPUUsage đọc CPU usage từ /proc/stat (2 sample, tính delta)
func ReadCPUUsage() (float32, error) {
    read := func() (idle, total uint64, err error) {
        f, err := os.Open("/proc/stat")
        if err != nil {
            return 0, 0, err
        }
        defer f.Close()
        scanner := bufio.NewScanner(f)
        for scanner.Scan() {
            line := scanner.Text()
            if !strings.HasPrefix(line, "cpu ") {
                continue
            }
            fields := strings.Fields(line)[1:]
            vals := make([]uint64, len(fields))
            for i, f := range fields {
                vals[i], _ = strconv.ParseUint(f, 10, 64)
            }
            idle = vals[3] // idle time
            for _, v := range vals {
                total += v
            }
            return
        }
        return 0, 0, fmt.Errorf("không tìm thấy dòng cpu trong /proc/stat")
    }
    // TODO: implement 2-sample delta cho accuracy
    _, total, err := read()
    if err != nil || total == 0 {
        return 0, err
    }
    return 0, nil // placeholder — implement delta trong task thực tế
}

// ReadMemory đọc RAM từ /proc/meminfo
func ReadMemory() (usedMB, totalMB int32, err error) {
    f, err := os.Open("/proc/meminfo")
    if err != nil {
        return 0, 0, err
    }
    defer f.Close()

    data := make(map[string]int64)
    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        parts := strings.Fields(scanner.Text())
        if len(parts) < 2 {
            continue
        }
        key := strings.TrimSuffix(parts[0], ":")
        val, _ := strconv.ParseInt(parts[1], 10, 64)
        data[key] = val
    }

    totalKB := data["MemTotal"]
    availKB := data["MemAvailable"]
    usedKB := totalKB - availKB

    return int32(usedKB / 1024), int32(totalKB / 1024), nil
}
```

### Code mẫu — `agent/cmd/main.go`
```go
package main

import (
    "context"
    "log"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/joho/godotenv"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)

func main() {
    godotenv.Load()

    serverAddr := os.Getenv("BACKEND_GRPC_ADDR")
    if serverAddr == "" {
        serverAddr = "localhost:50051"
    }

    // TODO: Thay insecure bằng mTLS trong production
    conn, err := grpc.Dial(serverAddr, grpc.WithTransportCredentials(insecure.NewCredentials()))
    if err != nil {
        log.Fatalf("Không kết nối được Backend: %v", err)
    }
    defer conn.Close()

    log.Printf("Agent kết nối đến %s", serverAddr)

    ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    defer cancel()

    // Vòng lặp với Exponential Backoff khi mất kết nối
    backoff := time.Second
    for {
        select {
        case <-ctx.Done():
            log.Println("Agent tắt theo yêu cầu.")
            return
        default:
            if err := runStream(ctx, conn); err != nil {
                log.Printf("Stream lỗi: %v. Thử lại sau %v...", err, backoff)
                time.Sleep(backoff)
                if backoff < 5*time.Minute {
                    backoff *= 2
                }
            } else {
                backoff = time.Second // reset khi kết nối thành công
            }
        }
    }
}

func runStream(ctx context.Context, conn *grpc.ClientConn) error {
    // TODO: Implement gRPC stream sau khi generate protobuf
    log.Println("Stream placeholder — implement sau khi có proto")
    <-ctx.Done()
    return nil
}
```

**Tiêu chí hoàn thành:**
- [ ] Define `agent.proto` với `MetricsReport` message và `AgentStream` RPC
- [ ] Agent đọc `/proc/stat`, `/proc/meminfo`, `/proc/diskstats` mỗi 10 giây
- [ ] Agent reconnect tự động khi mất kết nối (Exponential Backoff)
- [ ] Local buffer lưu tối đa 1000 records khi offline

---

## P4 — Backend gRPC Server: Nhận Metrics → Lưu PostgreSQL

**Branch:** `feat/monitoring`  
**Mục tiêu:** Backend nhận metrics stream từ Agent, batch insert vào bảng `metrics`.

### Code mẫu — `backend/internal/grpc/handler.go`
```go
package grpchandler

import (
    "context"
    "io"
    "log"
    "time"

    // pb "github.com/dawng278/skyweaver/backend/proto/agent"
)

// MetricsBuffer tích lũy metrics trước khi batch insert
type MetricsBuffer struct {
    records []MetricRecord
    maxSize int
    flushCh chan []MetricRecord
}

type MetricRecord struct {
    ServerID    string
    CollectedAt time.Time
    CPUUsage    float32
    RAMUsedMB   int32
    RAMTotalMB  int32
}

func NewMetricsBuffer(maxSize int) *MetricsBuffer {
    return &MetricsBuffer{
        maxSize: maxSize,
        flushCh: make(chan []MetricRecord, 10),
    }
}

func (b *MetricsBuffer) Add(r MetricRecord) {
    b.records = append(b.records, r)
    if len(b.records) >= b.maxSize {
        batch := make([]MetricRecord, len(b.records))
        copy(batch, b.records)
        b.records = b.records[:0]
        b.flushCh <- batch
    }
}

// AgentStreamHandler xử lý kết nối từ Agent (placeholder)
func AgentStreamHandler(ctx context.Context) error {
    buf := NewMetricsBuffer(100)
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case batch := <-buf.flushCh:
            log.Printf("Batch insert %d records vào DB", len(batch))
            // TODO: db.CreateInBatches(batch, 100)
        case <-ticker.C:
            // Flush định kỳ ngay cả khi buffer chưa đầy
            if len(buf.records) > 0 {
                batch := make([]MetricRecord, len(buf.records))
                copy(batch, buf.records)
                buf.records = buf.records[:0]
                log.Printf("Flush %d records (timeout)", len(batch))
                // TODO: db.CreateInBatches(batch, 100)
            }
        }
    }
}

// Xử lý stream từ Agent
func HandleAgentStream(stream io.Reader) {
    _ = stream
    // TODO: Implement sau khi generate protobuf
}
```

**Tiêu chí hoàn thành:**
- [ ] gRPC server lắng nghe tại `:50051`
- [ ] Nhận stream từ Agent, batch insert vào `metrics` mỗi 100 records hoặc mỗi 5 giây
- [ ] Agent mất kết nối → server detect sau 60 giây → cập nhật `servers.status = 'offline'`

---

## P5 — Server Management: SSH Check + CRUD API

**Branch:** `feat/server-management`  
**Mục tiêu:** API quản lý server, kiểm tra kết nối SSH, detect hardware info.

### Code mẫu — `backend/pkg/ssh/ping.go`
```go
package ssh

import (
    "fmt"
    "net"
    "time"

    "golang.org/x/crypto/ssh"
)

type PingResult struct {
    Connected    bool
    OSName       string
    OSVersion    string
    CPUCores     int
    TotalRAMMB   int
    DiskGB       int
    Latency      time.Duration
}

type PingOptions struct {
    Host       string
    Port       int
    Username   string
    PrivateKey []byte // PEM format, đã decrypt từ DB
    Timeout    time.Duration
}

func SSHPing(opts PingOptions) (*PingResult, error) {
    signer, err := ssh.ParsePrivateKey(opts.PrivateKey)
    if err != nil {
        return nil, fmt.Errorf("parse private key: %w", err)
    }

    config := &ssh.ClientConfig{
        User:            opts.Username,
        Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
        HostKeyCallback: ssh.InsecureIgnoreHostKey(), // TODO: Verify host key trong production
        Timeout:         opts.Timeout,
    }

    start := time.Now()
    addr := fmt.Sprintf("%s:%d", opts.Host, opts.Port)
    client, err := ssh.Dial("tcp", addr, config)
    if err != nil {
        return &PingResult{Connected: false}, nil
    }
    defer client.Close()
    latency := time.Since(start)

    result := &PingResult{
        Connected: true,
        Latency:   latency,
    }

    // Lấy thông tin OS
    session, err := client.NewSession()
    if err == nil {
        defer session.Close()
        out, _ := session.Output(`uname -s && uname -r && nproc && free -m | awk '/Mem:/{print $2}' && df -BG / | awk 'NR==2{gsub("G",""); print $2}'`)
        // TODO: Parse output vào result fields
        _ = out
    }

    return result, nil
}

// TCPCheck kiểm tra port nhanh không cần auth
func TCPCheck(host string, port int, timeout time.Duration) bool {
    addr := fmt.Sprintf("%s:%d", host, port)
    conn, err := net.DialTimeout("tcp", addr, timeout)
    if err != nil {
        return false
    }
    conn.Close()
    return true
}
```

### Code mẫu — `backend/internal/server/handler.go`
```go
package server

import (
    "github.com/gofiber/fiber/v2"
    "github.com/google/uuid"
)

type CreateServerRequest struct {
    Name         string `json:"name" validate:"required,min=1,max=100"`
    IPAddress    string `json:"ip_address" validate:"required,ip"`
    SSHPort      int    `json:"ssh_port" validate:"min=1,max=65535"`
    CredentialID string `json:"credential_id" validate:"required,uuid"`
    Tags         []string `json:"tags"`
}

func (h *Handler) Create(c *fiber.Ctx) error {
    var req CreateServerRequest
    if err := c.BodyParser(&req); err != nil {
        return c.Status(422).JSON(fiber.Map{
            "error": fiber.Map{"code": "VALIDATION_ERROR", "message": err.Error()},
        })
    }

    userID, _ := c.Locals("userID").(uuid.UUID)

    // TODO: Kiểm tra credential thuộc về user
    // TODO: Decrypt SSH key từ credential
    // TODO: SSHPing(opts) để verify kết nối
    // TODO: Lưu vào DB với status = 'pending'
    // TODO: Push task vào queue để Agent detect

    return c.Status(201).JSON(fiber.Map{
        "server": fiber.Map{
            "id":     uuid.New(),
            "name":   req.Name,
            "status": "pending",
            "owner":  userID,
        },
    })
}
```

**Tiêu chí hoàn thành:**
- [ ] `POST /v1/servers` tạo server và kiểm tra SSH trong 10 giây
- [ ] `GET /v1/servers/:id` trả về hardware_info sau khi kết nối thành công
- [ ] `DELETE /v1/servers/:id` xóa server và dừng agent stream
- [ ] Background job kiểm tra heartbeat mỗi 60 giây

---

## P6 — Real-time Monitoring: WebSocket Hub → Frontend Chart

**Branch:** `feat/monitoring`  
**Mục tiêu:** Backend WebSocket hub broadcast metrics real-time, Frontend hiển thị biểu đồ live.

### Code mẫu — `backend/internal/monitoring/hub.go`
```go
package monitoring

import (
    "encoding/json"
    "log"
    "sync"
)

type Client struct {
    ServerID string
    Send     chan []byte
}

type Hub struct {
    mu      sync.RWMutex
    clients map[string]map[*Client]bool // serverID → clients
}

func NewHub() *Hub {
    return &Hub{
        clients: make(map[string]map[*Client]bool),
    }
}

func (h *Hub) Subscribe(serverID string, client *Client) {
    h.mu.Lock()
    defer h.mu.Unlock()
    if h.clients[serverID] == nil {
        h.clients[serverID] = make(map[*Client]bool)
    }
    h.clients[serverID][client] = true
}

func (h *Hub) Unsubscribe(serverID string, client *Client) {
    h.mu.Lock()
    defer h.mu.Unlock()
    delete(h.clients[serverID], client)
}

func (h *Hub) Broadcast(serverID string, metrics any) {
    h.mu.RLock()
    defer h.mu.RUnlock()

    data, err := json.Marshal(metrics)
    if err != nil {
        log.Printf("Lỗi marshal metrics: %v", err)
        return
    }

    for client := range h.clients[serverID] {
        select {
        case client.Send <- data:
        default:
            // Client chậm quá, drop message
            log.Printf("Drop metrics cho client server %s", serverID)
        }
    }
}
```

### Code mẫu — `frontend/components/charts/MetricsChart.tsx`
```tsx
"use client";

import { useEffect, useRef, useState } from "react";
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer,
} from "recharts";

interface MetricsPoint {
  time: string;
  cpu: number;
  ram: number;
}

interface Props {
  serverID: string;
}

export function MetricsChart({ serverID }: Props) {
  const [data, setData] = useState<MetricsPoint[]>([]);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    const wsURL = `${process.env.NEXT_PUBLIC_WS_URL}/metrics/${serverID}`;
    wsRef.current = new WebSocket(wsURL);

    wsRef.current.onmessage = (event) => {
      const metrics = JSON.parse(event.data);
      setData((prev) => {
        const next = [...prev, {
          time: new Date().toLocaleTimeString(),
          cpu: metrics.cpu_usage,
          ram: Math.round((metrics.ram_used_mb / metrics.ram_total_mb) * 100),
        }];
        // Giữ 60 điểm gần nhất (10 phút)
        return next.slice(-60);
      });
    };

    return () => wsRef.current?.close();
  }, [serverID]);

  return (
    <ResponsiveContainer width="100%" height={300}>
      <LineChart data={data}>
        <CartesianGrid strokeDasharray="3 3" />
        <XAxis dataKey="time" />
        <YAxis domain={[0, 100]} unit="%" />
        <Tooltip />
        <Line type="monotone" dataKey="cpu" stroke="#3b82f6" name="CPU" dot={false} />
        <Line type="monotone" dataKey="ram" stroke="#10b981" name="RAM" dot={false} />
      </LineChart>
    </ResponsiveContainer>
  );
}
```

**Tiêu chí hoàn thành:**
- [ ] WebSocket endpoint `/ws/metrics/:serverID` hoạt động
- [ ] Frontend nhận metrics < 2 giây sau khi Agent gửi
- [ ] Chart tự động cuộn, giữ 60 điểm gần nhất
- [ ] Disconnect/reconnect WebSocket tự động

---

## P7 — Deployment Pipeline: Git Clone → Symlink → Rollback

**Branch:** `feat/deployment`  
**Mục tiêu:** Pipeline triển khai zero-downtime dùng symlink atomic, hỗ trợ rollback.

### Code mẫu — `backend/internal/deployment/pipeline.go`
```go
package deployment

import (
    "fmt"
    "os"
    "path/filepath"
    "time"
)

type DeployOptions struct {
    RepoURL    string
    Branch     string
    DeployPath string // Ví dụ: /app
    AppName    string
}

type DeployResult struct {
    VersionTag string
    Success    bool
    Log        string
}

// SymlinkDeploy thực hiện atomic deployment qua symlink
// Cấu trúc:
//   /app/releases/<version>/  ← code mới
//   /app/current             → releases/<version>  ← symlink
func SymlinkDeploy(opts DeployOptions, execFn func(cmd string) (string, error)) (*DeployResult, error) {
    versionTag := time.Now().Format("20060102_150405")
    releasePath := filepath.Join(opts.DeployPath, "releases", versionTag)
    currentPath := filepath.Join(opts.DeployPath, "current")

    result := &DeployResult{VersionTag: versionTag}
    var log string

    // Bước 1: Clone repo vào thư mục release
    out, err := execFn(fmt.Sprintf("git clone --branch %s --depth 1 %s %s",
        opts.Branch, opts.RepoURL, releasePath))
    log += "CLONE:\n" + out + "\n"
    if err != nil {
        result.Log = log
        return result, fmt.Errorf("clone thất bại: %w", err)
    }

    // Bước 2: Chạy build script nếu có
    buildScript := filepath.Join(releasePath, "deploy.sh")
    if _, err := os.Stat(buildScript); err == nil {
        out, err = execFn(fmt.Sprintf("bash %s", buildScript))
        log += "BUILD:\n" + out + "\n"
        if err != nil {
            result.Log = log
            return result, fmt.Errorf("build thất bại: %w", err)
        }
    }

    // Bước 3: Atomic symlink swap (ln -sfn là atomic)
    out, err = execFn(fmt.Sprintf("ln -sfn %s %s", releasePath, currentPath))
    log += "SYMLINK:\n" + out + "\n"
    if err != nil {
        result.Log = log
        return result, fmt.Errorf("symlink thất bại: %w", err)
    }

    // Bước 4: Reload service
    out, _ = execFn(fmt.Sprintf("systemctl reload %s 2>/dev/null || true", opts.AppName))
    log += "RELOAD:\n" + out + "\n"

    // Bước 5: Dọn dẹp — giữ 5 phiên bản gần nhất
    cleanupCmd := fmt.Sprintf(
        "ls -t %s/releases | tail -n +6 | xargs -I{} rm -rf %s/releases/{}",
        opts.DeployPath, opts.DeployPath,
    )
    execFn(cleanupCmd)

    result.Success = true
    result.Log = log
    return result, nil
}

// Rollback về phiên bản trước đó
func Rollback(deployPath string, execFn func(cmd string) (string, error)) error {
    // Lấy phiên bản trước bằng cách xem symlink và chọn version ngay trước
    out, err := execFn(fmt.Sprintf(
        "ls -t %s/releases | sed -n '2p'", deployPath,
    ))
    if err != nil || out == "" {
        return fmt.Errorf("không tìm thấy phiên bản để rollback")
    }

    prevVersion := filepath.Join(deployPath, "releases", out[:len(out)-1])
    currentPath := filepath.Join(deployPath, "current")

    _, err = execFn(fmt.Sprintf("ln -sfn %s %s", prevVersion, currentPath))
    return err
}
```

**Tiêu chí hoàn thành:**
- [ ] `POST /v1/servers/:id/deployments` kích hoạt pipeline
- [ ] Symlink swap atomic, không có downtime
- [ ] `POST /v1/deployments/:id/rollback` hoàn thành < 10 giây
- [ ] Chỉ 1 deployment chạy đồng thời trên 1 server (Distributed Lock Redis)
- [ ] Giữ 5 phiên bản gần nhất, tự dọn cũ

---

## P8 — Alerting: Rule Evaluation Loop + Telegram/Discord Notify

**Branch:** `feat/alerting`  
**Mục tiêu:** Reconciliation loop đánh giá alert rules mỗi 30 giây, gửi thông báo khi vi phạm.

### Code mẫu — `backend/internal/alerting/evaluator.go`
```go
package alerting

import (
    "bytes"
    "context"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "time"
)

type AlertRule struct {
    ID           string
    ServerID     string
    Name         string
    Metric       string  // "cpu_usage", "ram_used_percent"
    Operator     string  // "gt", "lt", "gte", "lte"
    Threshold    float32
    DurationSecs int
    CooldownSecs int
    Channels     []NotifyChannel
    LastTriggered *time.Time
}

type NotifyChannel struct {
    Type    string // "telegram", "discord", "email"
    Config  map[string]string
}

// EvaluateRule kiểm tra 1 rule với giá trị metric hiện tại
func EvaluateRule(rule AlertRule, currentValue float32) bool {
    switch rule.Operator {
    case "gt":
        return currentValue > rule.Threshold
    case "lt":
        return currentValue < rule.Threshold
    case "gte":
        return currentValue >= rule.Threshold
    case "lte":
        return currentValue <= rule.Threshold
    }
    return false
}

// CheckCooldown kiểm tra rule có trong cooldown không
func CheckCooldown(rule AlertRule) bool {
    if rule.LastTriggered == nil {
        return false // chưa trigger bao giờ → không trong cooldown
    }
    elapsed := time.Since(*rule.LastTriggered)
    return elapsed < time.Duration(rule.CooldownSecs)*time.Second
}

// SendTelegram gửi thông báo qua Telegram Bot API
func SendTelegram(chatID, botToken, message string) error {
    url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", botToken)
    payload := map[string]string{
        "chat_id":    chatID,
        "text":       message,
        "parse_mode": "Markdown",
    }
    body, _ := json.Marshal(payload)
    resp, err := http.Post(url, "application/json", bytes.NewReader(body))
    if err != nil {
        return err
    }
    defer resp.Body.Close()
    if resp.StatusCode != http.StatusOK {
        return fmt.Errorf("telegram API trả về %d", resp.StatusCode)
    }
    return nil
}

// SendDiscord gửi thông báo qua Discord Webhook
func SendDiscord(webhookURL, message string) error {
    payload := map[string]string{"content": message}
    body, _ := json.Marshal(payload)
    resp, err := http.Post(webhookURL, "application/json", bytes.NewReader(body))
    if err != nil {
        return err
    }
    defer resp.Body.Close()
    return nil
}

// ReconciliationLoop chạy mỗi 30 giây, đánh giá tất cả rules
func ReconciliationLoop(ctx context.Context, getRules func() []AlertRule, getMetric func(serverID, metric string) float32) {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ctx.Done():
            return
        case <-ticker.C:
            rules := getRules()
            for _, rule := range rules {
                value := getMetric(rule.ServerID, rule.Metric)

                if !EvaluateRule(rule, value) || CheckCooldown(rule) {
                    continue
                }

                msg := fmt.Sprintf(
                    "🚨 *[SkyWeaver Alert]* `%s`\nServer: `%s`\nMetric: `%s = %.1f%%`\nNgưỡng: `%s %.1f%%`",
                    rule.Name, rule.ServerID, rule.Metric, value, rule.Operator, rule.Threshold,
                )

                for _, ch := range rule.Channels {
                    switch ch.Type {
                    case "telegram":
                        if err := SendTelegram(ch.Config["chat_id"], ch.Config["bot_token"], msg); err != nil {
                            log.Printf("Telegram lỗi: %v", err)
                        }
                    case "discord":
                        if err := SendDiscord(ch.Config["webhook"], msg); err != nil {
                            log.Printf("Discord lỗi: %v", err)
                        }
                    }
                }
            }
        }
    }
}
```

**Tiêu chí hoàn thành:**
- [ ] `POST /v1/alert-rules` tạo rule với threshold và channels
- [ ] Loop đánh giá mỗi 30 giây, gửi Telegram/Discord khi vi phạm
- [ ] Cooldown 15 phút không gửi lặp lại
- [ ] Gửi "Resolved" khi điều kiện không còn

---

## P9 — Web Terminal: Xterm.js + SSH-over-WebSocket

**Branch:** `feat/terminal`  
**Mục tiêu:** Terminal trình duyệt đầy đủ tính năng kết nối SSH qua WebSocket, hỗ trợ ANSI codes.

### Code mẫu — `backend/internal/terminal/proxy.go`
```go
package terminal

import (
    "fmt"
    "io"
    "log"
    "time"

    "github.com/gofiber/websocket/v2"
    "golang.org/x/crypto/ssh"
)

type SSHProxy struct {
    client  *ssh.Client
    session *ssh.Session
    stdin   io.WriteCloser
    stdout  io.Reader
}

func NewSSHProxy(host string, port int, username string, privateKey []byte) (*SSHProxy, error) {
    signer, err := ssh.ParsePrivateKey(privateKey)
    if err != nil {
        return nil, fmt.Errorf("parse key: %w", err)
    }

    config := &ssh.ClientConfig{
        User:            username,
        Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
        HostKeyCallback: ssh.InsecureIgnoreHostKey(),
        Timeout:         10 * time.Second,
    }

    client, err := ssh.Dial("tcp", fmt.Sprintf("%s:%d", host, port), config)
    if err != nil {
        return nil, fmt.Errorf("SSH dial: %w", err)
    }

    session, err := client.NewSession()
    if err != nil {
        client.Close()
        return nil, fmt.Errorf("SSH session: %w", err)
    }

    // Yêu cầu pseudo-terminal (PTY) để hỗ trợ ANSI/color
    if err := session.RequestPty("xterm-256color", 40, 80, ssh.TerminalModes{
        ssh.ECHO:          1,
        ssh.TTY_OP_ISPEED: 14400,
        ssh.TTY_OP_OSPEED: 14400,
    }); err != nil {
        return nil, fmt.Errorf("request pty: %w", err)
    }

    stdin, _ := session.StdinPipe()
    stdout, _ := session.StdoutPipe()
    session.Start("/bin/bash")

    return &SSHProxy{client: client, session: session, stdin: stdin, stdout: stdout}, nil
}

func (p *SSHProxy) Close() {
    p.session.Close()
    p.client.Close()
}

// HandleWebSocket cầu nối WebSocket ↔ SSH
func HandleWebSocket(c *websocket.Conn, proxy *SSHProxy) {
    defer proxy.Close()

    // SSH stdout → WebSocket
    go func() {
        buf := make([]byte, 4096)
        for {
            n, err := proxy.stdout.Read(buf)
            if err != nil {
                return
            }
            if err := c.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
                return
            }
        }
    }()

    // WebSocket → SSH stdin
    for {
        _, msg, err := c.ReadMessage()
        if err != nil {
            log.Printf("WebSocket đóng: %v", err)
            return
        }
        if _, err := proxy.stdin.Write(msg); err != nil {
            return
        }
    }
}
```

### Code mẫu — `frontend/components/terminal/TerminalPanel.tsx`
```tsx
"use client";

import { useEffect, useRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";

interface Props {
  serverID: string;
  sessionToken: string;
}

export function TerminalPanel({ serverID, sessionToken }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const termRef = useRef<Terminal | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;

    const term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: "JetBrains Mono, Fira Code, monospace",
      theme: { background: "#0f172a", foreground: "#e2e8f0" },
    });

    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    term.open(containerRef.current);
    fitAddon.fit();
    termRef.current = term;

    const ws = new WebSocket(
      `${process.env.NEXT_PUBLIC_WS_URL}/terminal/${serverID}?token=${sessionToken}`
    );
    ws.binaryType = "arraybuffer";
    wsRef.current = ws;

    ws.onopen = () => term.writeln("\r\n\x1b[32mKết nối SSH thành công!\x1b[0m\r\n");
    ws.onmessage = (e) => term.write(new Uint8Array(e.data));
    ws.onclose = () => term.writeln("\r\n\x1b[31mKết nối đã đóng.\x1b[0m");

    // Gửi input từ terminal đến WebSocket
    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(new TextEncoder().encode(data));
      }
    });

    const handleResize = () => fitAddon.fit();
    window.addEventListener("resize", handleResize);

    return () => {
      ws.close();
      term.dispose();
      window.removeEventListener("resize", handleResize);
    };
  }, [serverID, sessionToken]);

  return (
    <div
      ref={containerRef}
      className="w-full h-full bg-slate-900 rounded-lg p-2"
      style={{ minHeight: "400px" }}
    />
  );
}
```

**Tiêu chí hoàn thành:**
- [ ] WebSocket endpoint `/ws/terminal/:serverID` yêu cầu JWT
- [ ] Xterm.js hiển thị đầy đủ màu sắc ANSI, Tab completion
- [ ] Phiên tự động đóng sau 30 phút không hoạt động
- [ ] Giới hạn tối đa 5 phiên đồng thời/tài khoản
- [ ] Ghi log toàn bộ lệnh vào `audit_logs`

---

## Tổng hợp Tiến độ

| P | Task | Branch | Trạng thái |
|---|---|---|---|
| P0 | Foundation: Go module + Docker stack | `feat/infrastructure` | ⬜ Chưa bắt đầu |
| P1 | DB Migrations | `feat/infrastructure` | ⬜ Chưa bắt đầu |
| P2 | Auth: JWT + bcrypt + RBAC | `feat/auth` | ⬜ Chưa bắt đầu |
| P3 | Agent: gRPC + /proc metrics | `feat/agent` | ⬜ Chưa bắt đầu |
| P4 | Backend gRPC nhận metrics | `feat/monitoring` | ⬜ Chưa bắt đầu |
| P5 | Server CRUD + SSH check | `feat/server-management` | ⬜ Chưa bắt đầu |
| P6 | WebSocket hub + Frontend chart | `feat/monitoring` | ⬜ Chưa bắt đầu |
| P7 | Deployment pipeline + symlink | `feat/deployment` | ⬜ Chưa bắt đầu |
| P8 | Alert eval + Telegram/Discord | `feat/alerting` | ⬜ Chưa bắt đầu |
| P9 | Web terminal Xterm.js + SSH proxy | `feat/terminal` | ⬜ Chưa bắt đầu |

> Cập nhật trạng thái thành: 🔄 Đang làm | ✅ Hoàn thành | ❌ Bị chặn
