-- Bisociation Casino v3. Run once in the intended Supabase project's SQL Editor.
-- Guest identity comes from Supabase Auth, never from a client-supplied user id.
begin;
create table if not exists public.bc_ideas (
  id uuid primary key,
  creator_id uuid not null references auth.users(id) on delete cascade,
  model text not null check (length(trim(model)) between 1 and 80),
  product text not null check (length(trim(product)) between 1 and 80),
  market text not null check (length(trim(market)) between 1 and 80),
  notes text not null default '' check (length(notes)<=600),
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.bc_ratings (
  idea_id uuid not null references public.bc_ideas(id) on delete cascade,
  voter_id uuid not null references auth.users(id) on delete cascade,
  score integer not null check (score between 1 and 10),
  updated_at timestamptz not null default now(),
  primary key (idea_id, voter_id)
);
create index if not exists bc_ideas_created on public.bc_ideas (created_at desc);
create index if not exists bc_ideas_creator on public.bc_ideas (creator_id,created_at);
alter table public.bc_ideas enable row level security;
alter table public.bc_ratings enable row level security;
-- No direct table grants. Narrow RPCs enforce identity and expose only aggregates.
revoke all on public.bc_ideas, public.bc_ratings from anon, authenticated;

create or replace function public.bc_publish_idea(p_id uuid,p_model text,p_product text,p_market text,p_notes text,p_score integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); existing uuid;
begin
  if actor is null then raise exception 'Please start a guest session.'; end if;
  if p_id is null or p_score is null or p_score not between 1 and 10 then raise exception 'Choose a rating from 1 to 10.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
  select creator_id into existing from public.bc_ideas where id=p_id;
  if found then
    if existing=actor then return p_id; end if;
    raise exception 'Idea identifier already exists.';
  end if;
  if (select count(*) from public.bc_ideas where creator_id=actor and created_at>now()-interval '1 hour')>=30 then
    raise exception 'You have shared 30 ideas this hour. Please try again later.';
  end if;
  insert into public.bc_ideas(id,creator_id,model,product,market,notes)
  values(p_id,actor,trim(p_model),trim(p_product),trim(p_market),coalesce(trim(p_notes),''));
  insert into public.bc_ratings(idea_id,voter_id,score) values(p_id,actor,p_score);
  return p_id;
end $$;
create or replace function public.bc_rate_idea(p_idea uuid,p_score integer)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
  if actor is null then raise exception 'Please start a guest session.'; end if;
  if p_score is null or p_score not between 1 and 10 then raise exception 'Choose a rating from 1 to 10.'; end if;
  if not exists(select 1 from public.bc_ideas where id=p_idea and not hidden) then raise exception 'This idea is no longer available.'; end if;
  insert into public.bc_ratings(idea_id,voter_id,score) values(p_idea,actor,p_score)
  on conflict(idea_id,voter_id) do update set score=excluded.score,updated_at=now();
end $$;
create or replace function public.bc_list_ideas(p_sort text default 'newest',p_offset integer default 0,p_limit integer default 24)
returns table(id uuid,model text,product text,market text,notes text,created_at timestamptz,average_rating numeric,rating_count bigint,my_rating integer)
language sql stable security definer set search_path='' as $$
  select i.id,i.model,i.product,i.market,i.notes,i.created_at,
    coalesce(avg(r.score),0),count(r.score),max(case when r.voter_id=auth.uid() then r.score end)
  from public.bc_ideas i left join public.bc_ratings r on r.idea_id=i.id
  where not i.hidden
  group by i.id
  order by case when p_sort='top' then avg(r.score) end desc nulls last,i.created_at desc,i.id
  limit least(greatest(coalesce(p_limit,24),1),50) offset greatest(coalesce(p_offset,0),0);
$$;
revoke all on function public.bc_publish_idea(uuid,text,text,text,text,integer) from public,anon;
revoke all on function public.bc_rate_idea(uuid,integer) from public,anon;
revoke all on function public.bc_list_ideas(text,integer,integer) from public,anon;
grant execute on function public.bc_publish_idea(uuid,text,text,text,text,integer) to authenticated;
grant execute on function public.bc_rate_idea(uuid,integer) to authenticated;
grant execute on function public.bc_list_ideas(text,integer,integer) to authenticated;
commit;
