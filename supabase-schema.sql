-- ================================================================
--  BlogForge — Supabase SQL Schema  (safe to re-run)
--  Paste this entire file into:
--  Supabase Dashboard → SQL Editor → New Query → Run
-- ================================================================
--
--  AFTER running this SQL:
--  1. Go to Authentication → Users → Add User (or Invite)
--     Create your admin account with your email + password.
--     That is the account you log in with at the Admin panel.
--
--  2. Go to Settings → API
--     Copy "Project URL" and "anon public" key.
--     Paste them into blogforge.html:
--       const SUPABASE_URL = 'YOUR_PROJECT_URL';
--       const SUPABASE_KEY = 'YOUR_ANON_KEY';
--
--  3. Open the site and click ⚙ Admin → sign in → New Post.
-- ================================================================


-- ────────────────────────────────────────
--  CLEAN SLATE
--  Drops all BlogForge tables (and their policies + triggers)
--  so this script is completely safe to re-run at any time.
-- ────────────────────────────────────────
DROP TABLE IF EXISTS public.contact_messages CASCADE;
DROP TABLE IF EXISTS public.donors           CASCADE;
DROP TABLE IF EXISTS public.subscribers      CASCADE;
DROP TABLE IF EXISTS public.posts            CASCADE;
DROP TABLE IF EXISTS public.authors          CASCADE;
DROP FUNCTION IF EXISTS public.handle_updated_at CASCADE;


-- ────────────────────────────────────────
--  1. AUTHORS
-- ────────────────────────────────────────
CREATE TABLE public.authors (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  name       text        NOT NULL,
  initials   text        NOT NULL,
  color      text        NOT NULL DEFAULT '#888888',
  role       text,
  bio        text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.authors ENABLE ROW LEVEL SECURITY;

-- Public visitors can read author profiles
CREATE POLICY "Authors: public read"
  ON public.authors FOR SELECT
  USING (true);

-- Admin can create / edit / delete authors
CREATE POLICY "Authors: admin write"
  ON public.authors FOR ALL TO authenticated
  USING  (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- ⚠  GRANT is required for tables created via SQL editor.
--    Without these the authenticated role gets "permission denied"
--    even when an RLS policy would allow the operation.
GRANT SELECT                        ON public.authors TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.authors TO authenticated;


-- ────────────────────────────────────────
--  2. POSTS
-- ────────────────────────────────────────
CREATE TABLE public.posts (
  id           uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  title        text        NOT NULL,
  excerpt      text        DEFAULT '',
  body         text        DEFAULT '',
  category     text        NOT NULL
                 CHECK (category IN ('Technology','Design','Culture','Opinion')),
  author_id    uuid        REFERENCES public.authors(id) ON DELETE SET NULL,
  status       text        NOT NULL DEFAULT 'published'
                 CHECK (status IN ('published','draft')),
  read_time    text        DEFAULT '3 min read',
  published_at timestamptz DEFAULT now(),
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

-- Anonymous visitors: only see published posts
CREATE POLICY "Posts: public read published"
  ON public.posts FOR SELECT TO anon
  USING (status = 'published');

-- Logged-in admin: can read all posts including drafts
CREATE POLICY "Posts: admin read all"
  ON public.posts FOR SELECT TO authenticated
  USING (true);

-- Logged-in admin: full write access (insert, update, delete)
CREATE POLICY "Posts: admin write"
  ON public.posts FOR ALL TO authenticated
  USING  (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- Table-level grants
GRANT SELECT                        ON public.posts TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.posts TO authenticated;

-- Auto-stamp updated_at on every save
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER posts_updated_at
  BEFORE UPDATE ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Enable Realtime on posts so the public site refreshes
-- automatically when admin publishes or edits.
ALTER PUBLICATION supabase_realtime ADD TABLE public.posts;


-- ────────────────────────────────────────
--  3. SUBSCRIBERS
-- ────────────────────────────────────────
CREATE TABLE public.subscribers (
  id        uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  email     text        UNIQUE NOT NULL,
  source    text        DEFAULT 'Homepage',
  status    text        NOT NULL DEFAULT 'active'
              CHECK (status IN ('active','pending','unsubscribed')),
  joined_at timestamptz DEFAULT now()
);

ALTER TABLE public.subscribers ENABLE ROW LEVEL SECURITY;

-- Anyone can subscribe (public insert, no login needed)
CREATE POLICY "Subscribers: public insert"
  ON public.subscribers FOR INSERT
  WITH CHECK (true);

-- Only admin can view / update / delete subscriber records
CREATE POLICY "Subscribers: admin read"
  ON public.subscribers FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Subscribers: admin update"
  ON public.subscribers FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Subscribers: admin delete"
  ON public.subscribers FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL);

-- Table-level grants
GRANT INSERT                        ON public.subscribers TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.subscribers TO authenticated;


-- ────────────────────────────────────────
--  4. DONORS
-- ────────────────────────────────────────
CREATE TABLE public.donors (
  id            uuid           DEFAULT gen_random_uuid() PRIMARY KEY,
  name          text           NOT NULL DEFAULT 'Anonymous',
  amount        numeric(10,2)  NOT NULL,
  is_recurring  boolean        DEFAULT false,
  donation_type text           NOT NULL DEFAULT 'one-time'
                  CHECK (donation_type IN ('one-time','recurring','sponsor')),
  donated_at    timestamptz    DEFAULT now(),
  message       text
);

ALTER TABLE public.donors ENABLE ROW LEVEL SECURITY;

-- Only admin can manage donor records
CREATE POLICY "Donors: admin only"
  ON public.donors FOR ALL TO authenticated
  USING  (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- Table-level grants
GRANT SELECT, INSERT, UPDATE, DELETE ON public.donors TO authenticated;


-- ────────────────────────────────────────
--  5. CONTACT MESSAGES
-- ────────────────────────────────────────
CREATE TABLE public.contact_messages (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  name       text        NOT NULL,
  email      text        NOT NULL,
  subject    text        NOT NULL DEFAULT '',
  message    text        NOT NULL,
  read       boolean     DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;

-- Anyone can submit a contact message (no login needed)
CREATE POLICY "ContactMessages: public insert"
  ON public.contact_messages FOR INSERT
  WITH CHECK (true);

-- Only admin can read / update (mark read) / delete messages
CREATE POLICY "ContactMessages: admin read"
  ON public.contact_messages FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "ContactMessages: admin update"
  ON public.contact_messages FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "ContactMessages: admin delete"
  ON public.contact_messages FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL);

-- Table-level grants
GRANT INSERT                        ON public.contact_messages TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact_messages TO authenticated;


-- ================================================================
--  YOUR AUTHOR
--  Edit the values below to match your details, then this will
--  insert your author profile when the script runs.
--
--  color   — any hex colour shown on the author avatar
--  initials — 2–3 letters displayed inside the avatar circle
-- ================================================================
INSERT INTO public.authors (name, initials, color, role, bio) VALUES
  ('Grace Apenda', 'GA', '#c04a1a', 'Paediatric Pharmacist', 'Pharmacist at Port Moresby General Hospital.');
