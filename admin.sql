-- =====================================================================
-- Admin portal support: moderation log and safe account deletion.
-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.  (Safe to run again.)
-- These objects are reachable only by your own server (the service role),
-- never by the web page or by normal signed-in users.
-- =====================================================================

-- 1) Moderation log: who suspended or deleted whom, and why
create table if not exists public.admin_actions (
  id uuid primary key default gen_random_uuid(),
  admin_email text not null,
  target_id uuid,
  target_email text,
  action text not null check (action in ('suspend', 'unsuspend', 'delete', 'self_delete')),
  reason text,
  created_at timestamptz not null default now()
);
create index if not exists admin_actions_time on public.admin_actions (created_at desc);
alter table public.admin_actions enable row level security;      -- no policies: nobody but the server can read or write
revoke all on public.admin_actions from anon, authenticated;

-- 2) Files a user uploaded to groups (so the server can erase them from storage)
create or replace function public.user_file_paths(p_uid uuid) returns setof text
language sql stable security definer set search_path = public as
$$ select name from storage.objects where bucket_id = 'group-files' and owner_id = p_uid::text $$;

-- 3) Tidy up groups before an account is deleted:
--    erase the person's messages, hand over admin rights if they were the only admin,
--    and remove groups that would be left empty.
create or replace function public.prepare_account_deletion(p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r record; nxt uuid; nm text := public.uname(p_uid);
begin
  for r in select group_id, role from public.group_members where user_id = p_uid loop
    if r.role = 'admin' and not exists (select 1 from public.group_members where group_id = r.group_id and role = 'admin' and user_id <> p_uid) then
      select user_id into nxt from public.group_members where group_id = r.group_id and user_id <> p_uid order by joined_at limit 1;
      if nxt is null then delete from public.groups where id = r.group_id; continue; end if;
      update public.group_members set role = 'admin' where group_id = r.group_id and user_id = nxt;
      perform public.sys_msg(r.group_id, public.uname(nxt) || ' is now an admin');
    end if;
    delete from public.group_messages where group_id = r.group_id and user_id = p_uid;
    delete from public.group_members where group_id = r.group_id and user_id = p_uid;
    perform public.sys_msg(r.group_id, nm || ' left');
  end loop;
end $$;

revoke all on function public.user_file_paths(uuid), public.prepare_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.user_file_paths(uuid), public.prepare_account_deletion(uuid) to service_role;
