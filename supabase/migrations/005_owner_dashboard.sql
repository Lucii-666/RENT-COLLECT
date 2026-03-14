-- Owner Dashboard: room_codes, maintenance_requests, max_occupancy
-- Migration 005

-- 1. Add occupancy limit to units
ALTER TABLE units ADD COLUMN IF NOT EXISTS max_occupancy integer DEFAULT 1;

-- 2. Room join codes
CREATE TABLE IF NOT EXISTS room_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id uuid NOT NULL REFERENCES units(id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE,
  max_uses integer NOT NULL DEFAULT 1,
  used_count integer NOT NULL DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz
);

CREATE INDEX idx_room_codes_unit ON room_codes(unit_id);
CREATE INDEX idx_room_codes_code ON room_codes(code);

-- 3. Maintenance requests
CREATE TABLE IF NOT EXISTS maintenance_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES user_profiles(id),
  property_id uuid NOT NULL REFERENCES properties(id),
  unit_id uuid REFERENCES units(id),
  title text NOT NULL,
  description text,
  priority text DEFAULT 'medium',
  status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX idx_maintenance_property ON maintenance_requests(property_id);
CREATE INDEX idx_maintenance_status ON maintenance_requests(status);

-- 4. RLS for room_codes
ALTER TABLE room_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Owners can manage room codes" ON room_codes
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM units u
      JOIN properties p ON u.property_id = p.id
      WHERE u.id = room_codes.unit_id
      AND p.owner_id = auth.uid()
    )
  );

CREATE POLICY "Anyone can read active codes" ON room_codes
  FOR SELECT USING (is_active = true);

-- 5. RLS for maintenance_requests
ALTER TABLE maintenance_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenants can create maintenance requests" ON maintenance_requests
  FOR INSERT WITH CHECK (tenant_id = auth.uid());

CREATE POLICY "Tenants can read own requests" ON maintenance_requests
  FOR SELECT USING (tenant_id = auth.uid());

CREATE POLICY "Owners can read requests for their properties" ON maintenance_requests
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM properties p
      WHERE p.id = maintenance_requests.property_id
      AND p.owner_id = auth.uid()
    )
  );

CREATE POLICY "Owners can update requests for their properties" ON maintenance_requests
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM properties p
      WHERE p.id = maintenance_requests.property_id
      AND p.owner_id = auth.uid()
    )
  );

-- 6. Past tenants history (archive when owner removes a tenant)
CREATE TABLE IF NOT EXISTS past_tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid,
  property_id uuid NOT NULL REFERENCES properties(id),
  unit_id uuid REFERENCES units(id),
  room_number text,
  tenant_name text NOT NULL,
  tenant_mobile text,
  tenant_email text,
  monthly_rent numeric,
  move_in_date date,
  move_out_date date DEFAULT CURRENT_DATE,
  removal_reason text DEFAULT 'vacated',
  photo_id_url text,
  live_photo_url text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_past_tenants_unit ON past_tenants(unit_id);
CREATE INDEX idx_past_tenants_property ON past_tenants(property_id);

ALTER TABLE past_tenants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Owners can read past tenants" ON past_tenants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM properties p
      WHERE p.id = past_tenants.property_id
      AND p.owner_id = auth.uid()
    )
  );

CREATE POLICY "Owners can insert past tenants" ON past_tenants
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM properties p
      WHERE p.id = past_tenants.property_id
      AND p.owner_id = auth.uid()
    )
  );
