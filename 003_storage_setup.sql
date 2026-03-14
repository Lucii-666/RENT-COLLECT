-- Create storage buckets
INSERT INTO storage.buckets (id, name, public)
VALUES
  ('receipts', 'receipts', false),
  ('documents', 'documents', false),
  ('profile-photos', 'profile-photos', false),
  ('maintenance-images', 'maintenance-images', false);

-- Storage policies for receipts
CREATE POLICY "Users can upload receipts." ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'receipts');
CREATE POLICY "Users can view their own receipts." ON storage.objects FOR SELECT TO authenticated USING (auth.uid() = owner);

-- Storage policies for documents
CREATE POLICY "Users can upload documents." ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'documents');
CREATE POLICY "Users can view their own documents." ON storage.objects FOR SELECT TO authenticated USING (auth.uid() = owner);

-- Storage policies for profile-photos
CREATE POLICY "Users can upload profile photos." ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'profile-photos');
CREATE POLICY "Users can view their own profile photos." ON storage.objects FOR SELECT TO authenticated USING (auth.uid() = owner);

-- Storage policies for maintenance-images
CREATE POLICY "Users can upload maintenance images." ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'maintenance-images');
CREATE POLICY "Users can view their own maintenance images." ON storage.objects FOR SELECT TO authenticated USING (auth.uid() = owner);
