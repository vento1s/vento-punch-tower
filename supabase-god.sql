-- v137: GOD MODE (갓 모드) on the ranking board, score x8.
-- Run once in the Supabase SQL editor (project imqnhqsofpvssefcrbkq). Additive: old clients keep working.
begin;
alter table public.punch_tower_scores drop constraint punch_tower_scores_diff_check;
alter table public.punch_tower_scores add constraint punch_tower_scores_diff_check check (diff in ('easy','normal','hard','master','god'));
alter table public.punch_tower_runs drop constraint punch_tower_runs_diff_check;
alter table public.punch_tower_runs add constraint punch_tower_runs_diff_check check (diff in ('easy','normal','hard','master','god'));

-- the score column is generated: rebuild it with the god multiplier (and its two indexes)
drop index if exists public.punch_tower_scores_best_idx;
drop index if exists public.punch_tower_scores_score_idx;
alter table public.punch_tower_scores drop column score;
alter table public.punch_tower_scores add column score bigint
  generated always as (floor::bigint * 1000 * case diff when 'easy' then 1 when 'normal' then 2 when 'hard' then 3 when 'master' then 5 when 'god' then 8 else 1 end) stored;
create index punch_tower_scores_best_idx on public.punch_tower_scores (player_id, score desc, secs);
create index punch_tower_scores_score_idx on public.punch_tower_scores (score desc, secs) where (not hidden);

create or replace function public.punch_tower_start(p_player text, p_diff text)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_id uuid;
begin
  if p_player is null or p_player !~ '^[A-Za-z0-9_-]{8,40}$' then raise exception 'bad_player'; end if;
  if p_diff not in ('easy', 'normal', 'hard', 'master', 'god') then raise exception 'bad_diff'; end if;
  -- 1분에 30판 넘게 시작하면 거절 (재시작 연타는 충분히 허용)
  if (select count(*) from punch_tower_runs where player_id = p_player and started_at > now() - interval '1 minute') >= 30 then
    raise exception 'slow_down';
  end if;
  delete from punch_tower_runs where started_at < now() - interval '1 day';   -- 오래된 토큰 청소
  insert into punch_tower_runs (player_id, diff) values (p_player, p_diff) returning id into v_id;
  return v_id;
end $function$;
commit;
