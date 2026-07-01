-- Migration: auto_sync_config — automatic model sync/verify cron settings
--
-- Run: psql -U newapi -d newapi -f migration-2026-06-19-auto-sync-config.sql

BEGIN;

CREATE TABLE IF NOT EXISTS auto_sync_config (
    id INT PRIMARY KEY DEFAULT 1,
    enabled BOOLEAN NOT NULL DEFAULT false,
    interval_minutes INT NOT NULL DEFAULT 15,
    last_run_at BIGINT DEFAULT 0,
    last_run_status TEXT DEFAULT '',
    updated_at BIGINT NOT NULL,
    updated_by TEXT DEFAULT ''
);

-- Ensure only one row (singleton pattern)
INSERT INTO auto_sync_config (id, enabled, interval_minutes, updated_at)
VALUES (1, false, 15, EXTRACT(EPOCH FROM NOW())::bigint)
ON CONFLICT (id) DO NOTHING;

COMMIT;
