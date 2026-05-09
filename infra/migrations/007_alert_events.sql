-- Migration 007: Bảng Alert Events (Lịch sử cảnh báo đã kích hoạt)

CREATE TABLE IF NOT EXISTS alert_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id         UUID NOT NULL REFERENCES alert_rules(id) ON DELETE CASCADE,
    server_id       UUID NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    status          VARCHAR(20) NOT NULL CHECK (status IN ('firing', 'resolved')),
    metric_value    REAL NOT NULL,
    message         TEXT,
    notified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alert_events_rule
    ON alert_events(rule_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alert_events_server
    ON alert_events(server_id, created_at DESC);
