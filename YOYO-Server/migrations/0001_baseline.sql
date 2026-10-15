-- Baseline migration. Mirrors schema.sql — keep these two files in sync.
-- Fix A-20: credits DEFAULT 0 (and src/credits.ts:DEFAULT_FREE_CREDITS).
-- Adds `rate_limits` table (A-21).

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    apple_user_id TEXT UNIQUE NOT NULL,
    email TEXT,
    full_name TEXT,
    credits INTEGER DEFAULT 0,
    subscription_status INTEGER DEFAULT 0,
    subscription_end_date TEXT,
    original_transaction_id TEXT,
    last_transaction_id TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_users_apple_user_id ON users(apple_user_id);
CREATE INDEX IF NOT EXISTS idx_users_original_txn_id ON users(original_transaction_id);

CREATE TABLE IF NOT EXISTS shared_automation_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    rule_json TEXT NOT NULL,
    user_id INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_shared_rules_code ON shared_automation_rules(code);

CREATE TABLE IF NOT EXISTS rate_limits (
    user_id INTEGER NOT NULL,
    bucket TEXT NOT NULL,
    window_start INTEGER NOT NULL,
    count INTEGER NOT NULL,
    PRIMARY KEY (user_id, bucket)
);
