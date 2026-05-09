# Kiến trúc Module: Auth

**Branch:** `feat/auth`  
**Mục đích:** Xác thực & Phân quyền — JWT, OAuth2 (GitHub/Google), 2FA TOTP, RBAC.

---

## Luồng Xác thực

```
┌─────────┐        ┌───────────┐        ┌──────────┐
│ Frontend│        │  Backend  │        │   Redis  │
└────┬────┘        └─────┬─────┘        └────┬─────┘
     │                   │                   │
     │ POST /auth/login   │                   │
     │──────────────────▶│                   │
     │                   │ bcrypt.Compare()  │
     │                   │ VerifyTOTP()      │
     │                   │ IssueJWT(15min)   │
     │                   │ IssueRefreshToken │
     │                   │ Store token_hash ─────────▶│
     │◀──────────────────│                   │
     │ access + refresh  │                   │
     │                   │                   │
     │ GET /api/... + JWT │                   │
     │──────────────────▶│                   │
     │                   │ JWTMiddleware     │
     │                   │ RequireRole()     │
     │◀──────────────────│                   │
     │ 200 / 401 / 403   │                   │
```

## Cấu trúc Files

```
backend/internal/auth/
├── jwt.go          # IssueAccessToken(), VerifyAccessToken(), Claims struct
├── password.go     # HashPassword(bcrypt cost=12), VerifyPassword()
├── totp.go         # GenerateTOTPSecret(), VerifyTOTP()
├── oauth.go        # GitHub/Google OAuth2 callback handler
├── middleware.go   # JWTMiddleware(), RequireRole()
└── handler.go      # HTTP handlers: register, login, refresh, logout, 2fa setup
```

## Phân quyền RBAC

| Role | Quyền |
|---|---|
| `super_admin` | Tất cả quyền |
| `admin` | Quản lý server, credential trong org |
| `developer` | Xem metrics, trigger deployment đã approve |
| `viewer` | Chỉ xem dashboard |

## Bảo mật

- JWT HS256, Access Token TTL 15 phút, Refresh Token TTL 7 ngày
- Refresh Token được hash SHA-256 trước khi lưu DB
- bcrypt cost factor = 12 (tương đương ~250ms/hash)
- TOTP: RFC 6238, window ±1 step (30 giây)
- Rate limit: 10 requests/phút cho `/auth/login` (chống brute force)

## Task Liên quan: P2
