-- MaxWord Supabase schema v2
-- Safe to run on a FRESH project, or RE-RUN on top of the v1 schema — every
-- statement is idempotent (create-if-not-exists / drop-then-create).
-- Paste this whole file into Project > SQL Editor > New query > Run.

create extension if not exists "pgcrypto";

-- ============================================================
-- PROFILES
-- ============================================================
create table if not exists profiles (
  username text primary key,
  pin_hash text not null,
  security_question text not null,
  security_answer_hash text not null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- ROOMS
-- ============================================================
create table if not exists rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  creator_username text not null references profiles(username),
  is_open boolean not null default true,   -- true = any member can invite; false = admins only
  created_at timestamptz not null default now()
);

create table if not exists room_members (
  room_id uuid not null references rooms(id) on delete cascade,
  username text not null references profiles(username),
  role text not null default 'member',     -- 'admin' | 'member'
  joined_at timestamptz not null default now(),
  primary key (room_id, username)
);

-- ============================================================
-- ROUNDS (12 words, mixed category, tied to a room)
-- ============================================================
create table if not exists rounds (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms(id) on delete cascade,
  creator_username text not null references profiles(username),
  target_username text references profiles(username),   -- set = this is a direct dare-back/callout at one person
  word_ids jsonb not null,                 -- array of 12 word ids
  status text not null default 'open',     -- 'open' (dare, <2 played) | 'locked' (2+ played, counts) | 'expired'
  created_at timestamptz not null default now(),
  expires_at timestamptz not null          -- always created_at + 3 days
);
alter table rounds add column if not exists target_username text references profiles(username);

-- ============================================================
-- ROUND SCORES  (12 questions, 83 pts each correct, 996 max)
-- ============================================================
create table if not exists round_scores (
  round_id uuid not null references rounds(id) on delete cascade,
  username text not null references profiles(username),
  correct_count int not null,
  total_count int not null default 12,
  score_points int not null default 0,     -- correct_count * 83
  played_at timestamptz not null default now(),
  primary key (round_id, username)
);
alter table round_scores add column if not exists score_points int not null default 0;
alter table round_scores alter column total_count set default 12;

-- ============================================================
-- REACTIONS  (low-effort "nice!" on someone's played round — quiet-player hook)
-- ============================================================
create table if not exists reactions (
  round_id uuid not null references rounds(id) on delete cascade,
  target_username text not null references profiles(username),  -- whose score this reacts to
  from_username text not null references profiles(username),
  emoji text not null default '👏',
  created_at timestamptz not null default now(),
  primary key (round_id, target_username, from_username)
);

-- ============================================================
-- STREAKS  (consecutive days played, global per user)
-- ============================================================
create table if not exists streaks (
  username text primary key references profiles(username),
  current_streak int not null default 0,
  best_streak int not null default 0,
  last_played_date date
);

-- ============================================================
-- BADGES (game-wide, not per-category)
-- badge_key values used by the app:
--   'flawless_scroll'   - 12/12 in a single round
--   'showed_up'         - played your first round ever (participation, not skill)
--   'streak_3' / 'streak_7' / 'streak_30' - consecutive-day streak milestones
--   'monthly_champion'  - #1 on a room's monthly leaderboard when the month closed
-- room_id is null for global/account-level badges (e.g. showed_up, streaks)
-- ============================================================
create table if not exists badges (
  username text not null references profiles(username),
  badge_key text not null,
  room_id uuid references rooms(id) on delete cascade,
  earned_at timestamptz not null default now(),
  primary key (username, badge_key, room_id)
);

-- ============================================================
-- PUSH SUBSCRIPTIONS
-- ============================================================
create table if not exists push_subscriptions (
  username text not null references profiles(username),
  endpoint text not null,
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  primary key (username, endpoint)
);

-- ============================================================
-- VIEWS — leaderboard logic (AVERAGE score, not best; monthly + all-time only)
-- A round only counts once 2+ people have played it.
-- ============================================================
drop view if exists scoring_rounds;
create view scoring_rounds as
select round_id from round_scores group by round_id having count(*) >= 2;

drop view if exists room_leaderboard_alltime;
create view room_leaderboard_alltime as
select rs.username, ru.room_id,
  avg(rs.score_points)::numeric(10,1) as avg_score,
  count(*) as rounds_played
from round_scores rs
join rounds ru on ru.id = rs.round_id
where rs.round_id in (select round_id from scoring_rounds)
group by rs.username, ru.room_id;

drop view if exists room_leaderboard_monthly;
create view room_leaderboard_monthly as
select rs.username, ru.room_id,
  date_trunc('month', rs.played_at) as month,
  avg(rs.score_points)::numeric(10,1) as avg_score,
  count(*) as rounds_played
from round_scores rs
join rounds ru on ru.id = rs.round_id
where rs.round_id in (select round_id from scoring_rounds)
group by rs.username, ru.room_id, date_trunc('month', rs.played_at);

drop view if exists global_leaderboard_alltime;
create view global_leaderboard_alltime as
select rs.username,
  avg(rs.score_points)::numeric(10,1) as avg_score,
  count(*) as rounds_played
from round_scores rs
where rs.round_id in (select round_id from scoring_rounds)
group by rs.username;

drop view if exists global_leaderboard_monthly;
create view global_leaderboard_monthly as
select rs.username,
  date_trunc('month', rs.played_at) as month,
  avg(rs.score_points)::numeric(10,1) as avg_score,
  count(*) as rounds_played
from round_scores rs
where rs.round_id in (select round_id from scoring_rounds)
group by rs.username, date_trunc('month', rs.played_at);

-- ============================================================
-- ROW LEVEL SECURITY
-- NOTE (MVP caveat): custom username+PIN login, not Supabase Auth, so there's
-- no auth.uid() to key policies off. Permissive by design — fine for a
-- friend-group game. See README for the migration path if this ever needs
-- real protection.
-- ============================================================
alter table profiles enable row level security;
alter table rooms enable row level security;
alter table room_members enable row level security;
alter table rounds enable row level security;
alter table round_scores enable row level security;
alter table reactions enable row level security;
alter table streaks enable row level security;
alter table badges enable row level security;
alter table push_subscriptions enable row level security;

drop policy if exists "anon read profiles" on profiles;
create policy "anon read profiles" on profiles for select using (true);
drop policy if exists "anon insert profiles" on profiles;
create policy "anon insert profiles" on profiles for insert with check (true);
drop policy if exists "anon update profiles" on profiles;
create policy "anon update profiles" on profiles for update using (true) with check (true);

drop policy if exists "anon all rooms" on rooms;
create policy "anon all rooms" on rooms for all using (true) with check (true);
drop policy if exists "anon all room_members" on room_members;
create policy "anon all room_members" on room_members for all using (true) with check (true);
drop policy if exists "anon all rounds" on rounds;
create policy "anon all rounds" on rounds for all using (true) with check (true);
drop policy if exists "anon all round_scores" on round_scores;
create policy "anon all round_scores" on round_scores for all using (true) with check (true);
drop policy if exists "anon all reactions" on reactions;
create policy "anon all reactions" on reactions for all using (true) with check (true);
drop policy if exists "anon all streaks" on streaks;
create policy "anon all streaks" on streaks for all using (true) with check (true);
drop policy if exists "anon all badges" on badges;
create policy "anon all badges" on badges for all using (true) with check (true);
drop policy if exists "anon all push_subscriptions" on push_subscriptions;
create policy "anon all push_subscriptions" on push_subscriptions for all using (true) with check (true);
