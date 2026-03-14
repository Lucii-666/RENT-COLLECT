-- Enable RLS for all tables
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.electricity_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_verifications ENABLE ROW LEVEL SECURITY;

-- RLS policies for user_profiles
CREATE POLICY "Users can view their own profile." ON public.user_profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile." ON public.user_profiles FOR UPDATE USING (auth.uid() = id);

-- RLS policies for payments
CREATE POLICY "Users can view their own payments." ON public.payments FOR SELECT USING (auth.uid() = (SELECT user_id FROM public.properties WHERE id = (SELECT property_id FROM public.floors WHERE id = (SELECT floor_id FROM public.units WHERE id = unit_id))));
CREATE POLICY "Users can create their own payments." ON public.payments FOR INSERT WITH CHECK (auth.uid() = (SELECT user_id FROM public.properties WHERE id = (SELECT property_id FROM public.floors WHERE id = (SELECT floor_id FROM public.units WHERE id = unit_id))));

-- RLS policies for maintenance_requests
CREATE POLICY "Users can view their own maintenance requests." ON public.maintenance_requests FOR SELECT USING (auth.uid() = (SELECT user_id FROM public.properties WHERE id = (SELECT property_id FROM public.floors WHERE id = (SELECT floor_id FROM public.units WHERE id = unit_id))));
CREATE POLICY "Users can create their own maintenance requests." ON public.maintenance_requests FOR INSERT WITH CHECK (auth.uid() = (SELECT user_id FROM public.properties WHERE id = (SELECT property_id FROM public.floors WHERE id = (SELECT floor_id FROM public.units WHERE id = unit_id))));

-- RLS policies for electricity_readings
CREATE POLICY "Users can view their own electricity readings." ON public.electricity_readings FOR SELECT USING (auth.uid() = (SELECT user_id FROM public.properties WHERE id = (SELECT property_id FROM public.floors WHERE id = (SELECT floor_id FROM public.units WHERE id = unit_id))));
CREATE POLICY "Users can create their own electricity readings." ON public.electricity_readings FOR INSERT WITH CHECK (auth.uid() = (SELECT user_id FROM public.properties WHERE id = (SELECT property_id FROM public.floors WHERE id = (SELECT floor_id FROM public.units WHERE id = unit_id))));

-- RLS policies for notifications
CREATE POLICY "Users can view their own notifications." ON public.notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create their own notifications." ON public.notifications FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own notifications." ON public.notifications FOR DELETE USING (auth.uid() = user_id);

-- RLS policies for room_history
CREATE POLICY "Users can view their own room history." ON public.room_history FOR SELECT USING (auth.uid() = user_id);

-- RLS policies for otp_verifications
CREATE POLICY "Users can manage their own OTP verifications." ON public.otp_verifications FOR ALL USING (auth.uid() = user_id);
