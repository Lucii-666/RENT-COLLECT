-- Migration 006: Create notifications table
-- This table was referenced in 002_enable_rls.sql but never created

CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type text NOT NULL DEFAULT 'general',
  title text NOT NULL,
  message text NOT NULL,
  is_read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_read ON notifications(user_id, is_read);

-- RLS (may already exist from 002, use IF NOT EXISTS pattern)
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist, then recreate
DO $$
BEGIN
  -- Try to drop existing policies (from 002_enable_rls.sql)
  BEGIN
    DROP POLICY IF EXISTS "Users see own notifications" ON notifications;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $$;

CREATE POLICY "Users see own notifications" ON notifications
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can update own notifications" ON notifications
  FOR UPDATE USING (user_id = auth.uid());

-- Allow inserts (for creating notifications for other users)
CREATE POLICY "Authenticated users can create notifications" ON notifications
  FOR INSERT WITH CHECK (true);
