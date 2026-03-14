-- =============================================
-- Row Level Security (RLS) Migration
-- Ensures complete data isolation between property owners
-- =============================================

-- Enable RLS on all critical tables
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE floors ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE electricity_readings ENABLE ROW LEVEL SECURITY;

-- =============================================
-- PROPERTIES: Owners can only access their own
-- =============================================
CREATE POLICY "Owners manage own properties" ON properties
  FOR ALL USING (
    owner_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

-- =============================================
-- FLOORS: Access via owned properties
-- =============================================
CREATE POLICY "Users access floors via properties" ON floors
  FOR ALL USING (
    property_id IN (
      SELECT id FROM properties WHERE owner_id = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

-- =============================================
-- ROOMS: Access via floors in owned properties
-- =============================================
CREATE POLICY "Users access rooms via properties" ON rooms
  FOR ALL USING (
    floor_id IN (
      SELECT f.id FROM floors f
      JOIN properties p ON f.property_id = p.id
      WHERE p.owner_id = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

-- =============================================
-- TENANTS: Owners see their tenants, tenants see self
-- =============================================
CREATE POLICY "Owners and tenants access tenant_details" ON tenant_details
  FOR ALL USING (
    property_id IN (
      SELECT id FROM properties WHERE owner_id = auth.uid()
    ) OR
    user_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

-- =============================================
-- PAYMENTS: Owners and tenants only
-- =============================================
CREATE POLICY "Users access own payments" ON payments
  FOR ALL USING (
    property_id IN (
      SELECT id FROM properties WHERE owner_id = auth.uid()
    ) OR
    tenant_id IN (
      SELECT id FROM tenant_details WHERE user_id = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

-- =============================================
-- MAINTENANCE: Owners and requesting tenants
-- =============================================
CREATE POLICY "Users access maintenance requests" ON maintenance_requests
  FOR ALL USING (
    property_id IN (
      SELECT id FROM properties WHERE owner_id = auth.uid()
    ) OR
    tenant_id IN (
      SELECT id FROM tenant_details WHERE user_id = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

-- =============================================
-- DOCUMENTS: Owners and uploading tenants
-- =============================================
CREATE POLICY "Users access own documents" ON documents
  FOR ALL USING (
    property_id IN (
      SELECT id FROM properties WHERE owner_id = auth.uid()
    ) OR
    tenant_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

-- =============================================
-- NOTIFICATIONS: Users see their own notifications
-- =============================================
CREATE POLICY "Users see own notifications" ON notifications
  FOR ALL USING (
    user_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

-- =============================================
-- ELECTRICITY READINGS: Via rooms in properties
-- =============================================
CREATE POLICY "Users access electricity readings" ON electricity_readings
  FOR ALL USING (
    room_id IN (
      SELECT r.id FROM rooms r
      JOIN floors f ON r.floor_id = f.id
      JOIN properties p ON f.property_id = p.id
      WHERE p.owner_id = auth.uid()
    ) OR
    tenant_id IN (
      SELECT id FROM tenant_details WHERE user_id = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

-- =============================================
-- USER PROFILES: Users see own profile, developers see all
-- =============================================
CREATE POLICY "Users see own profile" ON user_profiles
  FOR SELECT USING (
    id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'developer'
    )
  );

CREATE POLICY "Users update own profile" ON user_profiles
  FOR UPDATE USING (id = auth.uid());

-- =============================================
-- Add developer role to role constraint
-- =============================================
ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_role_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_role_check
  CHECK (role IN ('tenant', 'manager', 'owner', 'developer'));

-- =============================================
-- Create developer account
-- Note: Password should be set via Supabase dashboard or Auth API
-- =============================================
-- This is a placeholder - actual user creation done via Supabase Auth
