-- Additive upgrade: keep all existing ideas and promising ratings unchanged.
-- Separate votes let players score either dimension first; missing is not zero.
begin;
create table if not exists public.bc_ridiculous_ratings (
  idea_id uuid not null references public.bc_ideas(id) on delete cascade,
  voter_id uuid not null references auth.users(id) on delete cascade,
  score integer not null check (score between 1 and 10),
  updated_at timestamptz not null default now(),
  primary key (idea_id, voter_id)
);
alter table public.bc_ridiculous_ratings enable row level security;
revoke all on public.bc_ridiculous_ratings from public,anon,authenticated;

create or replace function public.bc_publish_idea_v2(p_id uuid,p_model text,p_product text,p_market text,p_notes text,p_score integer,p_ridiculous_score integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result uuid;
begin
  if actor is null then raise exception 'Please start a guest session.'; end if;
  if p_ridiculous_score is null or p_ridiculous_score not between 1 and 10 then raise exception 'Choose a ridiculous rating from 1 to 10.'; end if;
  result:=public.bc_publish_idea(p_id,p_model,p_product,p_market,p_notes,p_score);
  if not exists(select 1 from public.bc_ideas where id=result and not hidden) then raise exception 'This idea is no longer available.'; end if;
  insert into public.bc_ridiculous_ratings(idea_id,voter_id,score) values(result,actor,p_ridiculous_score)
    on conflict(idea_id,voter_id) do nothing;
  return result;
end $$;

create or replace function public.bc_rate_idea_v2(p_idea uuid,p_metric text,p_score integer)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
  if actor is null then raise exception 'Please start a guest session.'; end if;
  if p_metric is null or p_metric not in ('promising','ridiculous') then raise exception 'Choose a valid rating scale.'; end if;
  if p_score is null or p_score not between 1 and 10 then raise exception 'Choose a rating from 1 to 10.'; end if;
  if p_metric='promising' then
    perform public.bc_rate_idea(p_idea,p_score);
  else
    if not exists(select 1 from public.bc_ideas where id=p_idea and not hidden) then raise exception 'This idea is no longer available.'; end if;
    insert into public.bc_ridiculous_ratings(idea_id,voter_id,score) values(p_idea,actor,p_score)
      on conflict(idea_id,voter_id) do update set score=excluded.score,updated_at=now();
  end if;
end $$;

create or replace function public.bc_list_ideas_v2(p_sort text default 'newest',p_offset integer default 0,p_limit integer default 24)
returns table(id uuid,model text,product text,market text,notes text,created_at timestamptz,average_rating numeric,rating_count bigint,my_rating integer,average_ridiculous_rating numeric,ridiculous_rating_count bigint,my_ridiculous_rating integer)
language sql stable security definer set search_path='' as $$
  with promising as (
    select r.idea_id,avg(r.score) as average,count(*) as votes,max(case when r.voter_id=auth.uid() then r.score end) as own
    from public.bc_ratings r group by r.idea_id
  ), ridiculous as (
    select r.idea_id,avg(r.score) as average,count(*) as votes,max(case when r.voter_id=auth.uid() then r.score end) as own
    from public.bc_ridiculous_ratings r group by r.idea_id
  )
  select i.id,i.model,i.product,i.market,i.notes,i.created_at,
    p.average,coalesce(p.votes,0),p.own,r.average,coalesce(r.votes,0),r.own
  from public.bc_ideas i left join promising p on p.idea_id=i.id left join ridiculous r on r.idea_id=i.id
  where not i.hidden
  order by case when p_sort='top' then p.average when p_sort='ridiculous' then r.average end desc nulls last,i.created_at desc,i.id
  limit least(greatest(coalesce(p_limit,24),1),50) offset greatest(coalesce(p_offset,0),0);
$$;

revoke all on function public.bc_publish_idea_v2(uuid,text,text,text,text,integer,integer) from public,anon;
revoke all on function public.bc_rate_idea_v2(uuid,text,integer) from public,anon;
revoke all on function public.bc_list_ideas_v2(text,integer,integer) from public,anon;
grant execute on function public.bc_publish_idea_v2(uuid,text,text,text,text,integer,integer) to authenticated;
grant execute on function public.bc_rate_idea_v2(uuid,text,integer) to authenticated;
grant execute on function public.bc_list_ideas_v2(text,integer,integer) to authenticated;
commit;
