-- Rent Collection App - User's Supabase Schema
-- This schema matches the existing database structure

-- Enums (run these first if not already created)
-- CREATE TYPE document_category AS ENUM ('id_proof', 'contract', 'receipt', 'other');
-- CREATE TYPE document_status AS ENUM ('tenant_uploaded', 'owner_uploaded', 'verified', 'rejected');
-- CREATE TYPE payment_status AS ENUM ('pending', 'paid', 'partial', 'overdue');
-- CREATE TYPE property_status AS ENUM ('active', 'inactive', 'maintenance');
-- CREATE TYPE approval_status AS ENUM ('pending', 'approved', 'rejected');
-- CREATE TYPE user_role AS ENUM ('owner', 'manager', 'tenant');

CREATE TABLE public.app_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  setting_key text NOT NULL UNIQUE,
  setting_value text,
  description text,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT app_settings_pkey PRIMARY KEY (id)
);

CREATE TABLE public.user_profiles (
  id uuid NOT NULL,
  email text,
  full_name text NOT NULL,
  mobile_number text NOT NULL UNIQUE,
  role text NOT NULL,
  is_approved boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT user_profiles_pkey PRIMARY KEY (id),
  CONSTRAINT user_profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);

CREATE TABLE public.properties (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  property_name text NOT NULL,
  property_address text NOT NULL,
  total_units integer NOT NULL DEFAULT 1,
  available_units integer NOT NULL DEFAULT 0,
  status text DEFAULT 'active',
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT properties_pkey PRIMARY KEY (id),
  CONSTRAINT properties_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.user_profiles(id)
);

CREATE TABLE public.floors (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL,
  floor_number integer NOT NULL,
  floor_name text NOT NULL,
  total_units integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT floors_pkey PRIMARY KEY (id),
  CONSTRAINT floors_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id)
);

CREATE TABLE public.tenant_profiles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  property_id uuid NOT NULL,
  room_number text,
  monthly_rent numeric NOT NULL,
  security_deposit numeric NOT NULL,
  move_in_date date NOT NULL,
  lease_start_date date NOT NULL,
  lease_end_date date,
  approval_status text DEFAULT 'pending',
  electricity_meter_reading numeric,
  photo_id_url text,
  live_photo_url text,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT tenant_profiles_pkey PRIMARY KEY (id),
  CONSTRAINT tenant_profiles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.user_profiles(id),
  CONSTRAINT tenant_profiles_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id)
);

CREATE TABLE public.units (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL,
  floor_id uuid,
  unit_number text NOT NULL,
  unit_type text,
  bedrooms integer DEFAULT 1,
  bathrooms integer DEFAULT 1,
  square_feet numeric,
  monthly_rent numeric,
  is_occupied boolean DEFAULT false,
  tenant_profile_id uuid,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT units_pkey PRIMARY KEY (id),
  CONSTRAINT units_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id),
  CONSTRAINT units_floor_id_fkey FOREIGN KEY (floor_id) REFERENCES public.floors(id),
  CONSTRAINT units_tenant_profile_id_fkey FOREIGN KEY (tenant_profile_id) REFERENCES public.tenant_profiles(id)
);

CREATE TABLE public.payments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_profile_id uuid NOT NULL,
  property_id uuid NOT NULL,
  payment_month date NOT NULL,
  rent_amount numeric NOT NULL,
  electricity_charges numeric DEFAULT 0,
  other_charges numeric DEFAULT 0,
  total_amount numeric NOT NULL,
  paid_amount numeric DEFAULT 0,
  payment_status text DEFAULT 'pending',
  payment_date timestamp with time zone,
  payment_method text,
  transaction_id text,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT payments_pkey PRIMARY KEY (id),
  CONSTRAINT payments_tenant_profile_id_fkey FOREIGN KEY (tenant_profile_id) REFERENCES public.tenant_profiles(id),
  CONSTRAINT payments_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id)
);

CREATE TABLE public.documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  title text NOT NULL,
  category text NOT NULL,
  file_path text NOT NULL,
  file_name text NOT NULL,
  file_size integer NOT NULL,
  file_type text NOT NULL,
  thumbnail_url text,
  uploaded_by uuid,
  property_id uuid,
  tenant_id uuid,
  status text NOT NULL DEFAULT 'tenant_uploaded',
  is_shared boolean DEFAULT false,
  shared_with uuid,
  share_expires_at timestamp with time zone,
  download_restricted boolean DEFAULT false,
  version integer DEFAULT 1,
  notes text,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT documents_pkey PRIMARY KEY (id),
  CONSTRAINT documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.user_profiles(id),
  CONSTRAINT documents_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id),
  CONSTRAINT documents_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.user_profiles(id),
  CONSTRAINT documents_shared_with_fkey FOREIGN KEY (shared_with) REFERENCES public.user_profiles(id)
);

CREATE TABLE public.document_versions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  document_id uuid,
  version integer NOT NULL,
  file_path text NOT NULL,
  uploaded_by uuid,
  changes_description text,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT document_versions_pkey PRIMARY KEY (id),
  CONSTRAINT document_versions_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id),
  CONSTRAINT document_versions_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.user_profiles(id)
);

CREATE TABLE public.document_access_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  document_id uuid,
  user_id uuid,
  action text NOT NULL,
  ip_address text,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT document_access_logs_pkey PRIMARY KEY (id),
  CONSTRAINT document_access_logs_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id),
  CONSTRAINT document_access_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id)
);

CREATE TABLE public.roommates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_profile_id uuid NOT NULL,
  roommate_name text NOT NULL,
  roommate_mobile text NOT NULL,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT roommates_pkey PRIMARY KEY (id),
  CONSTRAINT roommates_tenant_profile_id_fkey FOREIGN KEY (tenant_profile_id) REFERENCES public.tenant_profiles(id)
);

CREATE TABLE public.sms_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL,
  recipient_mobile text NOT NULL,
  message text NOT NULL,
  notification_type text NOT NULL,
  status text DEFAULT 'pending',
  twilio_message_sid text,
  sent_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT sms_notifications_pkey PRIMARY KEY (id),
  CONSTRAINT sms_notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.user_profiles(id)
);

CREATE TABLE public.tenant_activities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  activity_type text NOT NULL,
  activity_description text NOT NULL,
  activity_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  is_read boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT tenant_activities_pkey PRIMARY KEY (id),
  CONSTRAINT tenant_activities_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.user_profiles(id)
);

-- Indexes
CREATE INDEX idx_user_profiles_mobile ON public.user_profiles(mobile_number);
CREATE INDEX idx_user_profiles_role ON public.user_profiles(role);
CREATE INDEX idx_tenant_profiles_status ON public.tenant_profiles(approval_status);
CREATE INDEX idx_payments_status ON public.payments(payment_status);
CREATE INDEX idx_units_occupied ON public.units(is_occupied);

-- RLS Policies
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

-- Users can read/update own profile
CREATE POLICY "Users can read own profile" ON public.user_profiles
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.user_profiles
    FOR UPDATE USING (auth.uid() = id);

-- Owners can read their properties
CREATE POLICY "Owners can manage properties" ON public.properties
    FOR ALL USING (owner_id = auth.uid());

-- Tenants can read their tenant profile
CREATE POLICY "Tenants can read own profile" ON public.tenant_profiles
    FOR SELECT USING (tenant_id = auth.uid());

-- Handle new user trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_profiles (id, full_name, email, mobile_number, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', 'User'),
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'mobile_number', NEW.phone),
        COALESCE(NEW.raw_user_meta_data->>'role', 'tenant')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
