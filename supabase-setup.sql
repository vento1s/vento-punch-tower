-- 펀치 타워 랭킹 테이블 (VENTO AI STUDIO)
-- 벤토 스케이트파크와 같은 Supabase 프로젝트에 게임 전용 표 하나만 추가합니다. 다른 표는 건드리지 않아요.
-- Supabase 대시보드 > SQL Editor 에 전부 붙여넣고 Run.

create table if not exists public.punch_tower_scores (
  id         uuid primary key default gen_random_uuid(),
  client_id  text not null check (char_length(client_id) between 4 and 24),
  name       text not null check (char_length(btrim(name)) between 1 and 8),
  diff       text not null check (diff in ('easy', 'normal', 'hard', 'master')),
  floor      int  not null check (floor between 1 and 50),
  secs       numeric(6,1) not null check (secs >= 1 and secs < 3600),
  created_at timestamptz not null default now()
);

create index if not exists punch_tower_scores_rank_idx on public.punch_tower_scores (diff, floor desc, secs asc);

-- 누구나 기록을 읽고 추가할 수 있지만, 고치거나 지우는 건 대시보드(관리자)에서만.
alter table public.punch_tower_scores enable row level security;

drop policy if exists "punch tower: anyone can read" on public.punch_tower_scores;
create policy "punch tower: anyone can read" on public.punch_tower_scores
  for select to anon, authenticated using (true);

drop policy if exists "punch tower: anyone can add" on public.punch_tower_scores;
create policy "punch tower: anyone can add" on public.punch_tower_scores
  for insert to anon, authenticated with check (true);

grant select, insert on public.punch_tower_scores to anon, authenticated;
