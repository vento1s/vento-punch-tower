-- 펀치 타워 랭킹 서버 맞추기 (v51 게임용) · VENTO AI STUDIO
-- 언제 쓰나: supabase-secure.sql(다른 버전)을 실행했거나, 어느 SQL을 실행했는지 헷갈릴 때.
-- 실행하면 서버가 지금 배포된 v51 게임과 정확히 맞는 모양이 돼요.
-- supabase-v51-secure.sql 과 같은 내용이지만, 기록을 지우지 않아요. 여러 번 실행해도 괜찮아요.
-- Supabase > SQL Editor 에 전부 붙여넣고 Run.

begin;

-- 0) 다른 버전에서 만든 함수 지우기 (v51 함수와 이름만 같고 모양이 다름)
drop function if exists public.punch_tower_start(text);
drop function if exists public.punch_tower_submit(uuid, text, text, int, numeric);
drop function if exists public.punch_tower_board(int, text[]);
drop function if exists public.punch_tower_ip();
drop function if exists public.punch_tower_cfg_min_spf();

-- 2) 새 컬럼
alter table public.punch_tower_scores add column if not exists player_id text;
alter table public.punch_tower_scores add column if not exists run_key text;
alter table public.punch_tower_scores add column if not exists hidden boolean not null default false;
alter table public.punch_tower_scores add column if not exists score bigint
  generated always as (floor::bigint * 1000 * case diff when 'easy' then 1 when 'normal' then 2 when 'hard' then 3 when 'master' then 5 else 1 end) stored;
-- 예전 기록 살리기: 플레이어 표시가 없는 기록은 기록마다 따로 'legacy_' 플레이어로 붙임
update public.punch_tower_scores
   set player_id = left('legacy_' || coalesce(nullif(regexp_replace(client_id, '[^A-Za-z0-9]', '', 'g'), ''), replace(id::text, '-', '')), 40)
 where player_id is null;
update public.punch_tower_scores s set player_id = rpad(player_id, 8, '0') where char_length(player_id) < 8;
update public.punch_tower_scores s set run_key = s.client_id
 where s.run_key is null and s.client_id ~ '^[A-Za-z0-9]{4,24}$'
   and not exists (select 1 from public.punch_tower_scores o where o.client_id = s.client_id and o.id <> s.id)
   and not exists (select 1 from public.punch_tower_scores o where o.run_key = s.client_id);
alter table public.punch_tower_scores alter column player_id set not null;
alter table public.punch_tower_scores drop constraint if exists punch_tower_scores_player_check;
alter table public.punch_tower_scores add constraint punch_tower_scores_player_check check (player_id ~ '^[A-Za-z0-9_-]{8,40}$');

drop index if exists public.punch_tower_scores_rank_idx;
create index if not exists punch_tower_scores_best_idx on public.punch_tower_scores (player_id, score desc, secs asc);
create index if not exists punch_tower_scores_score_idx on public.punch_tower_scores (score desc, secs asc) where not hidden;
create unique index if not exists punch_tower_scores_run_key_idx on public.punch_tower_scores (run_key);

-- 3) 판 토큰 표 (게임은 직접 못 봄)
create table if not exists public.punch_tower_runs (
  id         uuid primary key default gen_random_uuid(),
  player_id  text not null,
  diff       text not null check (diff in ('easy', 'normal', 'hard', 'master')),
  started_at timestamptz not null default now(),
  used_at    timestamptz
);
-- 다른 버전(supabase-secure.sql)으로 만들어진 표도 v51 모양으로 맞춤
alter table public.punch_tower_runs add column if not exists player_id text;
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'punch_tower_runs' and column_name = 'ip_hash') then
    alter table public.punch_tower_runs drop column ip_hash;
  end if;
end $$;
delete from public.punch_tower_runs where player_id is null;   -- 옛 판 토큰(쓸모없음)만 지움
alter table public.punch_tower_runs alter column player_id set not null;
create index if not exists punch_tower_runs_player_idx on public.punch_tower_runs (player_id, started_at desc);
create index if not exists punch_tower_runs_started_idx on public.punch_tower_runs (started_at);
alter table public.punch_tower_runs enable row level security;
revoke all on public.punch_tower_runs from anon, authenticated;

-- 4) 직접 쓰기·읽기 막기 (관리자 대시보드는 그대로 됨)
drop policy if exists "punch tower: anyone can read" on public.punch_tower_scores;
drop policy if exists "punch tower: anyone can add" on public.punch_tower_scores;
revoke all on public.punch_tower_scores from anon, authenticated;

-- 5) 함수들
create or replace function public.punch_tower_start(p_player text, p_diff text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_player is null or p_player !~ '^[A-Za-z0-9_-]{8,40}$' then raise exception 'bad_player'; end if;
  if p_diff not in ('easy', 'normal', 'hard', 'master') then raise exception 'bad_diff'; end if;
  -- 1분에 30판 넘게 시작하면 거절 (재시작 연타는 충분히 허용)
  if (select count(*) from punch_tower_runs where player_id = p_player and started_at > now() - interval '1 minute') >= 30 then
    raise exception 'slow_down';
  end if;
  delete from punch_tower_runs where started_at < now() - interval '1 day';   -- 오래된 토큰 청소
  insert into punch_tower_runs (player_id, diff) values (p_player, p_diff) returning id into v_id;
  return v_id;
end $$;

create or replace function public.punch_tower_submit(p_run uuid, p_player text, p_key text, p_name text, p_floor int, p_secs numeric)
returns int language plpgsql security definer set search_path = public as $$
declare
  MIN_SECS_PER_FLOOR constant numeric := 0.4;   -- 층당 최소 시간(초). 사람이 아무리 빨라도 이보다 빠를 수 없는 값
  r punch_tower_runs%rowtype;
  v_elapsed numeric;
  v_name text := btrim(coalesce(p_name, ''));
  v_score bigint;
  v_rank int;
begin
  select * into r from punch_tower_runs where id = p_run for update;
  if not found or r.player_id is distinct from p_player then raise exception 'bad_run'; end if;
  if r.used_at is not null then raise exception 'used_run'; end if;
  v_elapsed := extract(epoch from now() - r.started_at);
  if v_elapsed > 6 * 3600 then raise exception 'old_run'; end if;
  if p_floor is null or p_floor < 1 or p_floor > 9999 then raise exception 'bad_floor'; end if;
  if p_secs is null or p_secs < 1 or p_secs >= 86400 then raise exception 'bad_time'; end if;
  if p_secs > v_elapsed + 3 then raise exception 'bad_time'; end if;                 -- 판 시작보다 긴 기록은 불가
  if p_secs < p_floor * MIN_SECS_PER_FLOOR then raise exception 'too_fast'; end if;
  if char_length(v_name) < 1 or char_length(v_name) > 8 or v_name ~ '[[:cntrl:]<>]' then raise exception 'bad_name'; end if;
  if p_key is null or p_key !~ '^[A-Za-z0-9]{4,24}$' then raise exception 'bad_key'; end if;
  if exists (select 1 from punch_tower_scores where player_id = p_player and created_at > now() - interval '5 seconds') then
    raise exception 'slow_down';
  end if;

  update punch_tower_runs set used_at = now() where id = p_run;
  insert into punch_tower_scores (client_id, run_key, player_id, name, diff, floor, secs)
    values (p_key, p_key, p_player, v_name, r.diff, p_floor, round(p_secs, 1))
    returning score into v_score;

  -- 이번 판 순위 = 다른 플레이어 최고 기록 중 이번 판보다 높은 수 + 1
  select 1 + count(*) into v_rank from (
    select distinct on (player_id) score, secs from punch_tower_scores
    where not hidden and player_id <> p_player
    order by player_id, score desc, secs asc
  ) b where b.score > v_score or (b.score = v_score and b.secs <= round(p_secs, 1));
  return v_rank;
end $$;

create or replace function public.punch_tower_board(p_player text, p_limit int default 20)
returns json language sql stable security definer set search_path = public as $$
  with best as (
    select distinct on (player_id) player_id, run_key, name, diff, floor, secs, score, created_at
    from punch_tower_scores where not hidden
    order by player_id, score desc, secs asc, created_at asc
  ), ranked as (
    select *, row_number() over (order by score desc, secs asc, created_at asc) as rk from best
  )
  select json_build_object(
    'top', coalesce((select json_agg(t order by t.rk) from
             (select rk, player_id, run_key, name, diff, floor, secs from ranked where rk <= least(greatest(coalesce(p_limit, 20), 1), 50)) t), '[]'::json),
    'me',  (select row_to_json(m) from (select rk, player_id, run_key, name, diff, floor, secs from ranked where player_id = p_player) m)
  );
$$;

revoke all on function public.punch_tower_start(text, text) from public;
revoke all on function public.punch_tower_submit(uuid, text, text, text, int, numeric) from public;
revoke all on function public.punch_tower_board(text, int) from public;
grant execute on function public.punch_tower_start(text, text) to anon, authenticated;
grant execute on function public.punch_tower_submit(uuid, text, text, text, int, numeric) to anon, authenticated;
grant execute on function public.punch_tower_board(text, int) to anon, authenticated;

commit;

notify pgrst, 'reload schema';

-- (선택) 예전 기록을 지우고 새로 시작하려면, 따로 아래 한 줄만 실행하세요. 되돌릴 수 없어요.
-- delete from public.punch_tower_scores;
