-- Migration 002: Bảng Credentials (SSH Key / Password)
-- Lưu trữ thông tin xác thực với mã hóa AES-256-GCM

CREATE TABLE IF NOT EXISTS credentials (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            VARCHAR(100) NOT NULL,
    type            VARCHAR(20) NOT NULL CHECK (type IN ('ssh_key', 'password')),
    username        VARCHAR(100),
    -- encrypted_data: AES-256-GCM ciphertext (private key hoặc password)
    encrypted_data  BYTEA NOT NULL,
    -- nonce: GCM nonce 12 bytes, random mỗi lần encrypt
    nonce           BYTEA NOT NULL,
    -- fingerprint: SHA-256 fingerprint của SSH public key (không nhạy cảm)
    fingerprint     VARCHAR(255),
    last_used_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_credentials_owner ON credentials(owner_id);
CREATE INDEX IF NOT EXISTS idx_credentials_type ON credentials(owner_id, type);
