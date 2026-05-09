-- Migration 008: Bảng Audit Logs (Nhật ký hoạt động)

CREATE TABLE IF NOT EXISTS audit_logs (
    id              BIGSERIAL PRIMARY KEY,
    user_id         UUID REFERENCES users(id) ON DELETE SET NULL,
    -- action: 'user.login', 'server.create', 'deployment.trigger', 'credential.use'
    action          VARCHAR(100) NOT NULL,
    resource_type   VARCHAR(50),    -- 'server', 'credential', 'deployment', 'alert_rule'
    resource_id     UUID,
    ip_address      INET,
    user_agent      TEXT,
    -- metadata: thông tin thêm tùy action
    metadata        JSONB,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user
    ON audit_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource
    ON audit_logs(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action
    ON audit_logs(action, created_at DESC);
-- Xóa audit logs > 1 năm bằng cron job
-- DELETE FROM audit_logs WHERE created_at < NOW() - INTERVAL '1 year';
