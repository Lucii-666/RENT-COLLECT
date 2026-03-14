-- =============================================
-- SUPABASE STORAGE BUCKET SETUP
-- Run this in the Supabase SQL Editor to initialize required buckets
-- =============================================

-- 1. Create Buckets
INSERT INTO storage.buckets (id, name, public)
VALUES 
  ('id-proofs', 'id-proofs', false),
  ('photos', 'photos', true),
  ('payment-proofs', 'payment-proofs', false),
  ('maintenance-photos', 'maintenance-photos', true)
ON CONFLICT (id) DO NOTHING;

-- 2. Storage Policies (Allow authenticated users to upload)

-- ID PROOFS (Private access, owners and self can read)
CREATE POLICY "Users can upload own id proofs"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'id-proofs');

CREATE POLICY "Owners and self can view id proofs"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'id-proofs');

-- PHOTOS (Public read, authenticated upload)
CREATE POLICY "Users can upload own photos"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'photos');

CREATE POLICY "Public can view photos"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'photos');

-- PAYMENT PROOFS (Private, owners and self can read)
CREATE POLICY "Users can upload payment proofs"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'payment-proofs');

CREATE POLICY "Owners and self can view payment proofs"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'payment-proofs');

-- MAINTENANCE PHOTOS (Authenticated upload and read)
CREATE POLICY "Users can upload maintenance photos"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'maintenance-photos');

CREATE POLICY "Users can view maintenance photos"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'maintenance-photos');
