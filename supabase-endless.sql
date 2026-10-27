-- 펀치 타워 무한 모드 업데이트 (VENTO AI STUDIO)
-- 탑이 50층에서 끝나지 않게 바뀌어서, 51층 이상 기록도 저장되도록 제한을 넓힙니다.
-- Supabase > SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 괜찮아요.

alter table public.punch_tower_scores drop constraint if exists punch_tower_scores_floor_check;
alter table public.punch_tower_scores add constraint punch_tower_scores_floor_check check (floor between 1 and 9999);

alter table public.punch_tower_scores drop constraint if exists punch_tower_scores_secs_check;
alter table public.punch_tower_scores add constraint punch_tower_scores_secs_check check (secs >= 1 and secs < 86400);

-- (선택) 예전 50층 규칙 기록을 모두 지우고 새로 시작하려면 아래 줄의 맨 앞 -- 를 지우고 실행하세요. 되돌릴 수 없어요.
-- delete from public.punch_tower_scores;
