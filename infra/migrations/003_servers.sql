-- Migration 003: Bảng Servers (Quản lý máy chủ)

CREATE TABLE IF NOT EXISTS servers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    credential_id   UUID REFERENCES credentials(id) ON DELETE SET NULL,
    name            VARCHAR(100) NOT NULL,
    ip_address      INET NOT NULL,
    ssh_port        SMALLINT DEFAULT 22 CHECK (ssh_port BETWEEN 1 AND 65535),
    grpc_port       SMALLINT DEFAULT 50051 CHECK (grpc_port BETWEEN 1 AND 65535),
    status          VARCHAR(20) DEFAULT 'pending'
                    CHECK (status IN ('pending', 'online', 'offline', 'error')),
    agent_version   VARCHAR(20),
    -- os_info: {"name": "Ubuntu", "version": "22.04", "arch": "amd64"}
    os_info         JSONB,
    -- hardware_info: {"cpu_cores": 4, "total_ram_mb": 8192, "disk_gb": 100}
    hardware_info   JSONB,
    tags            TEXT[] DEFAULT '{}',
    last_seen_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_servers_owner ON servers(owner_id);
CREATE INDEX IF NOT EXISTS idx_servers_status ON servers(status);
-- GIN index cho tìm kiếm theo tag
CREATE INDEX IF NOT EXISTS idx_servers_tags ON servers USING GIN(tags);
