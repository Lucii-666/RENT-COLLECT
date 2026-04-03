-- OTP Verifications table for Twilio phone OTP
-- Email OTP is handled natively by Supabase Auth

CREATE TABLE IF NOT EXISTS otp_verifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  identifier TEXT NOT NULL,          -- phone number or email
  otp_code TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'phone', -- 'phone' or 'email'
  verified BOOLEAN DEFAULT FALSE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookups by identifier + type
CREATE INDEX idx_otp_verifications_lookup
  ON otp_verifications (identifier, type, verified);

-- Auto-cleanup: delete expired OTPs (older than 10 minutes)
-- This can be run periodically via a cron or pg_cron extension
-- For now, the edge function cleans up on each new send request

-- RLS: only the edge function (service role) accesses this table
ALTER TABLE otp_verifications ENABLE ROW LEVEL SECURITY;

-- No public policies — only service_role can access
-- The edge function uses SUPABASE_SERVICE_ROLE_KEY
