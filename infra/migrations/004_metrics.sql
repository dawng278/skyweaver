-- Migration 004: Bảng Metrics (Time-series)
-- Lưu dữ liệu metrics với table partitioning theo tháng

-- Bảng metrics chính (độ phân giải đầy đủ, 10 giây/record)
CREATE TABLE IF NOT EXISTS metrics (
    id              BIGSERIAL,
    server_id       UUID NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    collected_at    TIMESTAMPTZ NOT NULL,
    cpu_usage       REAL NOT NULL CHECK (cpu_usage BETWEEN 0 AND 100),
    ram_used_mb     INTEGER NOT NULL CHECK (ram_used_mb >= 0),
    ram_total_mb    INTEGER NOT NULL CHECK (ram_total_mb > 0),
    disk_used_gb    REAL NOT NULL CHECK (disk_used_gb >= 0),
    disk_total_gb   REAL NOT NULL CHECK (disk_total_gb > 0),
    net_rx_kbps     REAL NOT NULL DEFAULT 0,
    net_tx_kbps     REAL NOT NULL DEFAULT 0,
    load_avg_1m     REAL,
    PRIMARY KEY (server_id, collected_at)
) PARTITION BY RANGE (collected_at);

-- Tạo partition theo tháng (tạo trước 3 tháng)
CREATE TABLE IF NOT EXISTS metrics_2026_04 PARTITION OF metrics
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE IF NOT EXISTS metrics_2026_05 PARTITION OF metrics
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE IF NOT EXISTS metrics_2026_06 PARTITION OF metrics
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE INDEX IF NOT EXISTS idx_metrics_server_time
    ON metrics(server_id, collected_at DESC);

-- Bảng metrics downsampled (1 giờ / bucket) — dữ liệu từ 7-30 ngày
CREATE TABLE IF NOT EXISTS metrics_hourly (
    server_id           UUID NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    hour_bucket         TIMESTAMPTZ NOT NULL,
    avg_cpu             REAL,
    max_cpu             REAL,
    avg_ram_used_mb     INTEGER,
    max_ram_used_mb     INTEGER,
    avg_disk_used_gb    REAL,
    avg_net_rx_kbps     REAL,
    avg_net_tx_kbps     REAL,
    sample_count        INTEGER DEFAULT 0,
    PRIMARY KEY (server_id, hour_bucket)
);

CREATE INDEX IF NOT EXISTS idx_metrics_hourly_server_time
    ON metrics_hourly(server_id, hour_bucket DESC);
