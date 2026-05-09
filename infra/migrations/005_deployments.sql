-- Migration 005: Bảng Deployments (Lịch sử triển khai)

CREATE TABLE IF NOT EXISTS deployments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id       UUID NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    triggered_by    UUID NOT NULL REFERENCES users(id),
    app_name        VARCHAR(100) NOT NULL,
    repo_url        TEXT NOT NULL,
    branch          VARCHAR(100) DEFAULT 'main',
    commit_sha      VARCHAR(40),
    version_tag     VARCHAR(50),            -- Ví dụ: "20260101_120000"
    deploy_path     TEXT NOT NULL,          -- Đường dẫn trên server
    status          VARCHAR(20) DEFAULT 'pending'
                    CHECK (status IN ('pending', 'running', 'success', 'failed', 'rolled_back')),
    log_output      TEXT,
    started_at      TIMESTAMPTZ,
    finished_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_deployments_server
    ON deployments(server_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_deployments_status
    ON deployments(status) WHERE status IN ('pending', 'running');
