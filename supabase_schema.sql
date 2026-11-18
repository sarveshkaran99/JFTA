-- ==============================================================================
-- JFTA (Jharkhand Film and Theatre Academy) Supabase PostgreSQL Schema
-- Includes Role-Based Access Control (RBAC), Row-Level Security (RLS),
-- 1-Minute Reels, Community Posts, GPS Attendance, and Troupe Dues Tracker
-- ==============================================================================

-- 1. Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. User Roles & Status Types (Create if not exists)
DO $$ BEGIN
  CREATE TYPE user_role_type AS ENUM ('super_admin', 'admin', 'member', 'public');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE member_status_type AS ENUM ('approved', 'pending', 'revoked');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- 3. Profiles Table (Holds members, applicants, and admins)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  avatar_url TEXT,
  role user_role_type DEFAULT 'public' NOT NULL,
  member_status member_status_type DEFAULT 'pending' NOT NULL,
  wing TEXT DEFAULT 'FILM',
  discipline TEXT DEFAULT 'Artist',
  batch TEXT DEFAULT '2026',
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
ALTER TABLE public.profiles ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 4. Authorized Administrators Whitelist
CREATE TABLE IF NOT EXISTS public.admin_whitelist (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  assigned_by TEXT NOT NULL,
  role_tier TEXT DEFAULT 'admin' NOT NULL CHECK (role_tier IN ('super_admin', 'admin')),
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
ALTER TABLE public.admin_whitelist ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- Seed Sarvesh Karan as permanent Super Admin
INSERT INTO public.admin_whitelist (id, email, assigned_by, role_tier)
VALUES (gen_random_uuid(), 'sarveshkaran99@gmail.com', 'system_root', 'super_admin')
ON CONFLICT (email) DO NOTHING;

-- Seed Super Admin Profile
INSERT INTO public.profiles (id, email, full_name, role, member_status, wing, discipline, batch)
VALUES (gen_random_uuid(), 'sarveshkaran99@gmail.com', 'Sarvesh Karan', 'super_admin', 'approved', 'FILM', 'Founder & Director', '2026')
ON CONFLICT (email) DO UPDATE SET role = 'super_admin', member_status = 'approved';

-- 5. Reels Table (Max 60 Seconds Enforced)
CREATE TABLE IF NOT EXISTS public.reels (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  author_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  author_name TEXT NOT NULL,
  author_wing TEXT NOT NULL,
  video_url TEXT NOT NULL,
  caption TEXT NOT NULL,
  category TEXT NOT NULL,
  duration_sec INTEGER NOT NULL CHECK (duration_sec > 0 AND duration_sec <= 60),
  likes_count INTEGER DEFAULT 0 NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
ALTER TABLE public.reels ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 6. Backstage Community Posts Table
CREATE TABLE IF NOT EXISTS public.posts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  author_name TEXT NOT NULL,
  author_tag TEXT NOT NULL,
  author_avatar TEXT,
  text TEXT NOT NULL,
  hashtags TEXT,
  img_url TEXT,
  likes_count INTEGER DEFAULT 0 NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
ALTER TABLE public.posts ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 7. GPS Geofenced Rehearsal Attendance
CREATE TABLE IF NOT EXISTS public.attendance_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  user_name TEXT NOT NULL,
  venue TEXT DEFAULT 'JFTA Studio, Ranchi' NOT NULL,
  distance_meters NUMERIC(6, 2) NOT NULL,
  verified BOOLEAN DEFAULT TRUE NOT NULL,
  checked_in_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
ALTER TABLE public.attendance_logs ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 8. Private Member Dues Tracker (₹19/mo)
CREATE TABLE IF NOT EXISTS public.member_dues (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  user_email TEXT,
  month_year TEXT NOT NULL, -- e.g. "November 2026"
  amount NUMERIC(6, 2) DEFAULT 19.00 NOT NULL,
  status TEXT DEFAULT 'pending' NOT NULL CHECK (status IN ('pending', 'paid')),
  upi_ref TEXT,
  paid_at TIMESTAMPTZ
);
ALTER TABLE public.member_dues ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- ==============================================================================
-- ROW-LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_whitelist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_dues ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if re-running
DROP POLICY IF EXISTS "Allow public read on profiles" ON public.profiles;
DROP POLICY IF EXISTS "Allow public insert on profiles" ON public.profiles;
DROP POLICY IF EXISTS "Allow public update on profiles" ON public.profiles;

DROP POLICY IF EXISTS "Allow public read on admin_whitelist" ON public.admin_whitelist;
DROP POLICY IF EXISTS "Allow public insert on admin_whitelist" ON public.admin_whitelist;
DROP POLICY IF EXISTS "Allow public delete on admin_whitelist" ON public.admin_whitelist;

DROP POLICY IF EXISTS "Allow public read on reels" ON public.reels;
DROP POLICY IF EXISTS "Allow public insert on reels" ON public.reels;
DROP POLICY IF EXISTS "Allow public update on reels" ON public.reels;

DROP POLICY IF EXISTS "Allow public read on posts" ON public.posts;
DROP POLICY IF EXISTS "Allow public insert on posts" ON public.posts;
DROP POLICY IF EXISTS "Allow public delete on posts" ON public.posts;

DROP POLICY IF EXISTS "Allow public read on attendance" ON public.attendance_logs;
DROP POLICY IF EXISTS "Allow public insert on attendance" ON public.attendance_logs;

DROP POLICY IF EXISTS "Allow public read on dues" ON public.member_dues;
DROP POLICY IF EXISTS "Allow public insert on dues" ON public.member_dues;
DROP POLICY IF EXISTS "Allow public update on dues" ON public.member_dues;

-- Policies for Profiles
CREATE POLICY "Allow public read on profiles" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Allow public insert on profiles" ON public.profiles FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public update on profiles" ON public.profiles FOR UPDATE USING (true);

-- Policies for Admin Whitelist
CREATE POLICY "Allow public read on admin_whitelist" ON public.admin_whitelist FOR SELECT USING (true);
CREATE POLICY "Allow public insert on admin_whitelist" ON public.admin_whitelist FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public delete on admin_whitelist" ON public.admin_whitelist FOR DELETE USING (true);

-- Policies for Reels
CREATE POLICY "Allow public read on reels" ON public.reels FOR SELECT USING (true);
CREATE POLICY "Allow public insert on reels" ON public.reels FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public update on reels" ON public.reels FOR UPDATE USING (true);

-- Policies for Posts
CREATE POLICY "Allow public read on posts" ON public.posts FOR SELECT USING (true);
CREATE POLICY "Allow public insert on posts" ON public.posts FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public delete on posts" ON public.posts FOR DELETE USING (true);

-- Policies for Attendance Logs
CREATE POLICY "Allow public read on attendance" ON public.attendance_logs FOR SELECT USING (true);
CREATE POLICY "Allow public insert on attendance" ON public.attendance_logs FOR INSERT WITH CHECK (true);

-- Policies for Member Dues
CREATE POLICY "Allow public read on dues" ON public.member_dues FOR SELECT USING (true);
CREATE POLICY "Allow public insert on dues" ON public.member_dues FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public update on dues" ON public.member_dues FOR UPDATE USING (true);

-- ==============================================================================
-- AUTOMATED USER SYNC FUNCTION (Supabase Auth Trigger if using Supabase Auth)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  is_admin BOOLEAN;
  is_super_admin BOOLEAN;
BEGIN
  is_super_admin := (NEW.email = 'sarveshkaran99@gmail.com');
  SELECT EXISTS(SELECT 1 FROM public.admin_whitelist WHERE email = NEW.email) INTO is_admin;

  INSERT INTO public.profiles (id, email, full_name, avatar_url, role, member_status)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    NEW.raw_user_meta_data->>'avatar_url',
    CASE
      WHEN is_super_admin THEN 'super_admin'::user_role_type
      WHEN is_admin THEN 'admin'::user_role_type
      ELSE 'public'::user_role_type
    END,
    CASE
      WHEN is_super_admin OR is_admin THEN 'approved'::member_status_type
      ELSE 'pending'::member_status_type
    END
  )
  ON CONFLICT (email) DO UPDATE SET
    role = EXCLUDED.role,
    member_status = EXCLUDED.member_status;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ==============================================================================
-- 9. SUPABASE STORAGE BUCKET FOR 1-MINUTE VERTICAL REELS
-- ==============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'reels',
  'reels',
  true,
  52428800, -- 50 MB
  ARRAY['video/mp4', 'video/quicktime', 'video/webm', 'video/x-m4v']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 52428800;

-- Storage RLS Policies for Reels Video Streaming & Uploads
DROP POLICY IF EXISTS "Public View Reels" ON storage.objects;
CREATE POLICY "Public View Reels" ON storage.objects
  FOR SELECT USING (bucket_id = 'reels');

DROP POLICY IF EXISTS "Public Upload Reels" ON storage.objects;
CREATE POLICY "Public Upload Reels" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'reels');

DROP POLICY IF EXISTS "Public Update Reels" ON storage.objects;
CREATE POLICY "Public Update Reels" ON storage.objects
  FOR UPDATE USING (bucket_id = 'reels');
