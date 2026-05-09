-- Migration 001: Bảng Users & OAuth & Refresh Tokens
-- Thực thi: psql -U skyweaver -d skyweaver -f 001_users.sql

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Bảng người dùng chính
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) UNIQUE NOT NULL,
    password_hash   VARCHAR(255),           -- NULL nếu chỉ dùng OAuth
    display_name    VARCHAR(100) NOT NULL,
    avatar_url      TEXT,
    role            VARCHAR(20) NOT NULL DEFAULT 'developer'
                    CHECK (role IN ('super_admin', 'admin', 'developer', 'viewer')),
    totp_secret     TEXT,                   -- AES-256 encrypted, NULL nếu chưa bật 2FA
    totp_enabled    BOOLEAN DEFAULT FALSE,
    is_active       BOOLEAN DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Bảng liên kết OAuth
CREATE TABLE IF NOT EXISTS oauth_accounts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider        VARCHAR(50) NOT NULL CHECK (provider IN ('github', 'google')),
    provider_uid    VARCHAR(255) NOT NULL,
    access_token    TEXT,                   -- AES-256 encrypted
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (provider, provider_uid)
);

CREATE INDEX IF NOT EXISTS idx_oauth_accounts_user ON oauth_accounts(user_id);

-- Bảng Refresh Token
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash      VARCHAR(255) NOT NULL UNIQUE,  -- SHA-256 của token thực
    device_info     TEXT,
    ip_address      INET,
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);
