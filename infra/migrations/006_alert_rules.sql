-- Migration 006: Bảng Alert Rules (Quy tắc cảnh báo)

CREATE TABLE IF NOT EXISTS alert_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- NULL = áp dụng cho tất cả server của user
    server_id           UUID REFERENCES servers(id) ON DELETE CASCADE,
    name                VARCHAR(100) NOT NULL,
    metric              VARCHAR(50) NOT NULL
                        CHECK (metric IN ('cpu_usage', 'ram_used_percent', 'disk_used_percent',
                                          'net_rx_kbps', 'net_tx_kbps', 'load_avg_1m')),
    operator            VARCHAR(5) NOT NULL CHECK (operator IN ('gt', 'lt', 'gte', 'lte')),
    threshold           REAL NOT NULL,
    -- Điều kiện phải tồn tại liên tục trong N giây
    duration_secs       INTEGER DEFAULT 300 CHECK (duration_secs > 0),
    -- Thời gian im lặng sau khi cảnh báo (chống spam)
    cooldown_secs       INTEGER DEFAULT 900 CHECK (cooldown_secs >= 0),
    -- channels: [{"type": "telegram", "chat_id": "..."}, {"type": "discord", "webhook": "..."}]
    channels            JSONB NOT NULL DEFAULT '[]',
    is_active           BOOLEAN DEFAULT TRUE,
    last_triggered_at   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alert_rules_owner ON alert_rules(owner_id);
CREATE INDEX IF NOT EXISTS idx_alert_rules_server ON alert_rules(server_id)
    WHERE server_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_alert_rules_active ON alert_rules(is_active)
    WHERE is_active = TRUE;
