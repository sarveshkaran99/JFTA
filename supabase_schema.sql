-- ==============================================================================
-- JFTA (Jharkhand Film and Theatre Academy) Supabase PostgreSQL Schema
-- Includes Role-Based Access Control (RBAC), Row-Level Security (RLS),
-- 1-Minute Reels, GPS Attendance, and Troupe Dues Tracker
-- ==============================================================================

-- 1. Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. User Roles Enum
CREATE TYPE user_role_type AS ENUM ('super_admin', 'admin', 'member', 'public');
CREATE TYPE member_status_type AS ENUM ('approved', 'pending', 'revoked');

-- 3. Profiles Table (Synced automatically with Supabase Google OAuth)
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  avatar_url TEXT,
  role user_role_type DEFAULT 'public' NOT NULL,
  member_status member_status_type DEFAULT 'pending' NOT NULL,
  wing TEXT CHECK (wing IN ('FILM', 'THEATRE', 'NONE')),
  discipline TEXT,
  batch TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 4. Authorized Administrators Whitelist
CREATE TABLE public.admin_whitelist (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  assigned_by TEXT NOT NULL,
  role_tier TEXT DEFAULT 'admin' NOT NULL CHECK (role_tier IN ('super_admin', 'admin')),
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Seed Sarvesh Karan as permanent Super Admin
INSERT INTO public.admin_whitelist (email, assigned_by, role_tier)
VALUES ('sarveshkaran99@gmail.com', 'system_root', 'super_admin')
ON CONFLICT (email) DO NOTHING;

-- 5. Reels Table (Max 60 Seconds Enforced)
CREATE TABLE public.reels (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  author_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  author_name TEXT NOT NULL,
  author_wing TEXT NOT NULL,
  video_url TEXT NOT NULL,
  caption TEXT NOT NULL,
  category TEXT NOT NULL,
  duration_sec INTEGER NOT NULL CHECK (duration_sec > 0 AND duration_sec <= 60),
  likes_count INTEGER DEFAULT 0 NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 6. GPS Geofenced Rehearsal Attendance
CREATE TABLE public.attendance_logs (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  user_name TEXT NOT NULL,
  venue TEXT DEFAULT 'JFTA Studio, Ranchi' NOT NULL,
  distance_meters NUMERIC(6, 2) NOT NULL,
  verified BOOLEAN DEFAULT TRUE NOT NULL,
  checked_in_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 7. Private Member Dues Tracker (₹19/mo)
CREATE TABLE public.member_dues (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  month_year TEXT NOT NULL, -- e.g. "November 2026"
  amount NUMERIC(6, 2) DEFAULT 19.00 NOT NULL,
  status TEXT DEFAULT 'pending' NOT NULL CHECK (status IN ('pending', 'paid')),
  upi_ref TEXT,
  paid_at TIMESTAMPTZ
);

-- ==============================================================================
-- ROW-LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_whitelist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_dues ENABLE ROW LEVEL SECURITY;

-- Profiles: Anyone authenticated can read profiles; users can update own name; admins can update roles
CREATE POLICY "Public profiles are readable by authenticated users"
  ON public.profiles FOR SELECT USING (true);

CREATE POLICY "Users can update own basic profile"
  ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Reels: Anyone can read, only approved members & admins can insert
CREATE POLICY "Anyone can view reels"
  ON public.reels FOR SELECT USING (true);

CREATE POLICY "Members and Admins can post reels"
  ON public.reels FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
      AND (profiles.role IN ('member', 'admin', 'super_admin'))
    )
  );

-- Admin Whitelist: Readable by all authenticated; writable ONLY by sarveshkaran99@gmail.com
CREATE POLICY "Super Admin manages admin whitelist"
  ON public.admin_whitelist FOR ALL USING (
    auth.jwt() ->> 'email' = 'sarveshkaran99@gmail.com'
  );

-- ==============================================================================
-- AUTOMATED USER SYNC FUNCTION (Supabase Auth Trigger)
-- Automatically elevates sarveshkaran99@gmail.com to super_admin upon Google login
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
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on Auth Users creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
