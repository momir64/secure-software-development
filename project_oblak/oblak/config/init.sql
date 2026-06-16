CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lambdas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    script_filename TEXT NOT NULL,
    env_hash TEXT,
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    lambda_id UUID REFERENCES lambdas(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    detail JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO users (username, password_hash) VALUES
    ('demo',  '$2a$12$LnZwWJ21RVJHkLNZ28BG3e8iUpIcPadExFUbWm9q63QFMA5.5vsse'),  -- password: 123
    ('demo2', '$2a$12$LnZwWJ21RVJHkLNZ28BG3e8iUpIcPadExFUbWm9q63QFMA5.5vsse')   -- password: 123
ON CONFLICT (username) DO NOTHING;

