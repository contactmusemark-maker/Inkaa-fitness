-- ============================================================
-- INKAA FITNESS — Supabase Database Setup
-- Run this in your Supabase SQL Editor
-- ============================================================

-- 1. Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 2. USER PROFILES TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS user_profiles (
  id           TEXT PRIMARY KEY,           -- 'mohan', 'martin', 'samuvel'
  display_name TEXT NOT NULL,
  email        TEXT UNIQUE NOT NULL,
  initials     TEXT NOT NULL DEFAULT '--',
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Insert the 3 users
INSERT INTO user_profiles (id, display_name, email, initials) VALUES
  ('mohan',   'Mohan',   'Mohan@inkaastudio.com',       'MO'),
  ('martin',  'Martin',  'MosesMartin@inkaastudio.com', 'MA'),
  ('samuvel', 'Samuvel', 'Samuvel@inkaastudio.com',     'SA')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 3. USER PROGRESS TABLE (full state blob — real-time sync)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_progress (
  id           UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  data         JSONB NOT NULL DEFAULT '{}',
  updated_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_user_progress_user_id ON user_progress(user_id);

-- ============================================================
-- 4. WORKOUT LOGS TABLE (granular per-exercise logging)
-- ============================================================
CREATE TABLE IF NOT EXISTS workout_logs (
  id            UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  log_date      DATE NOT NULL DEFAULT CURRENT_DATE,
  exercise_name TEXT NOT NULL,
  set_number    INT NOT NULL DEFAULT 1,
  weight_kg     NUMERIC(6,2),
  reps          INT,
  completed     BOOLEAN DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workout_logs_user_date ON workout_logs(user_id, log_date);

-- ============================================================
-- 5. MEAL LOGS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS meal_logs (
  id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  log_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  meal_name   TEXT NOT NULL,
  calories    INT DEFAULT 0,
  protein_g   NUMERIC(6,1) DEFAULT 0,
  carbs_g     NUMERIC(6,1) DEFAULT 0,
  fat_g       NUMERIC(6,1) DEFAULT 0,
  logged_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_meal_logs_user_date ON meal_logs(user_id, log_date);

-- ============================================================
-- 6. MEASUREMENTS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS measurements (
  id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  week_number INT NOT NULL CHECK (week_number BETWEEN 1 AND 12),
  weight_kg   NUMERIC(6,2),
  chest_cm    NUMERIC(6,1),
  waist_cm    NUMERIC(6,1),
  hips_cm     NUMERIC(6,1),
  arms_cm     NUMERIC(6,1),
  thighs_cm   NUMERIC(6,1),
  recorded_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, week_number)
);

CREATE INDEX IF NOT EXISTS idx_measurements_user ON measurements(user_id);

-- ============================================================
-- 7. CHECKIN TABLE (daily task completions)
-- ============================================================
CREATE TABLE IF NOT EXISTS daily_checkins (
  id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  checkin_date DATE NOT NULL DEFAULT CURRENT_DATE,
  tasks_json  JSONB NOT NULL DEFAULT '{}',  -- e.g. {"workout":true,"protein":false,...}
  score       INT DEFAULT 0,
  updated_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, checkin_date)
);

CREATE INDEX IF NOT EXISTS idx_checkins_user_date ON daily_checkins(user_id, checkin_date);

-- ============================================================
-- 8. ROW LEVEL SECURITY (RLS)
-- ============================================================
-- Enable RLS on all tables
ALTER TABLE user_profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_progress   ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_logs    ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_logs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE measurements    ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_checkins  ENABLE ROW LEVEL SECURITY;

-- For the PWA (using anon key with user_id stored in state),
-- we allow all operations. In production, tie these to auth.uid().

-- user_profiles: readable by all (for display), writable only by service role
CREATE POLICY "Public read user profiles"
  ON user_profiles FOR SELECT USING (true);

-- user_progress: each user can read/write their own
CREATE POLICY "Users manage own progress"
  ON user_progress FOR ALL USING (true)
  WITH CHECK (true);

CREATE POLICY "Users manage own workouts"
  ON workout_logs FOR ALL USING (true)
  WITH CHECK (true);

CREATE POLICY "Users manage own meals"
  ON meal_logs FOR ALL USING (true)
  WITH CHECK (true);

CREATE POLICY "Users manage own measurements"
  ON measurements FOR ALL USING (true)
  WITH CHECK (true);

CREATE POLICY "Users manage own checkins"
  ON daily_checkins FOR ALL USING (true)
  WITH CHECK (true);

-- ============================================================
-- 9. REAL-TIME SUBSCRIPTIONS
-- Enable realtime on the progress table so all 3 users can see
-- live updates if you want a shared leaderboard in future.
-- ============================================================
-- In Supabase Dashboard → Database → Replication → user_progress → Enable

-- ============================================================
-- 10. USEFUL VIEWS
-- ============================================================

-- Weekly summary view
CREATE OR REPLACE VIEW weekly_summary AS
SELECT
  u.display_name,
  wl.log_date,
  COUNT(DISTINCT wl.exercise_name) AS exercises_done,
  MAX(wl.weight_kg) AS max_weight_lifted
FROM user_profiles u
LEFT JOIN workout_logs wl ON u.id = wl.user_id
GROUP BY u.display_name, wl.log_date
ORDER BY wl.log_date DESC;

-- Macro summary view
CREATE OR REPLACE VIEW daily_macros AS
SELECT
  u.display_name,
  ml.log_date,
  SUM(ml.calories)  AS total_calories,
  SUM(ml.protein_g) AS total_protein,
  SUM(ml.carbs_g)   AS total_carbs,
  SUM(ml.fat_g)     AS total_fat
FROM user_profiles u
LEFT JOIN meal_logs ml ON u.id = ml.user_id
GROUP BY u.display_name, ml.log_date
ORDER BY ml.log_date DESC;

-- ============================================================
-- 11. INITIAL DATA — Seed user_progress rows
-- ============================================================
INSERT INTO user_progress (user_id, data) VALUES
  ('mohan',   '{"currentWeek":1,"streak":0}'),
  ('martin',  '{"currentWeek":1,"streak":0}'),
  ('samuvel', '{"currentWeek":1,"streak":0}')
ON CONFLICT (user_id) DO NOTHING;

-- ============================================================
-- DONE!
-- After running this script:
-- 1. Go to Supabase → Settings → API
-- 2. Copy "Project URL" and "anon public" key
-- 3. In index.html, replace:
--    const SUPABASE_URL = 'https://your-project.supabase.co';
--    const SUPABASE_ANON_KEY = 'your-anon-key-here';
--    with your actual values.
-- ============================================================
