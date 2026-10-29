-- College roster claim and admin-approved identity changes.
create extension if not exists vector with schema extensions;

create table public.student_roster (
  id uuid primary key default gen_random_uuid(),
  roll_no text not null unique check (roll_no = upper(btrim(roll_no))),
  full_name text not null check (length(btrim(full_name)) > 0),
  college_email text not null unique,
  claimed_by uuid unique references auth.users(id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index student_roster_email_normalized_idx
  on public.student_roster (lower(btrim(college_email)));

create table public.student_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  roster_id uuid not null unique references public.student_roster(id),
  created_at timestamptz not null default now()
);

create table public.college_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.face_enrollments (
  user_id uuid primary key references auth.users(id) on delete cascade,
  embedding extensions.vector(192) not null,
  model_version text not null default 'mobile_face_net_192_v1',
  enrolled_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.identity_change_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  requested_roll_no text,
  requested_full_name text,
  requested_face_embedding extensions.vector(192),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  check (num_nonnulls(requested_roll_no, requested_full_name, requested_face_embedding) > 0)
);

create index identity_change_requests_pending_idx
  on public.identity_change_requests (requested_at) where status = 'pending';

create table public.identity_change_audit (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.identity_change_requests(id),
  user_id uuid not null references auth.users(id),
  changed_by uuid not null references auth.users(id),
  change_type text not null,
  old_value text,
  new_value text,
  changed_at timestamptz not null default now()
);

alter table public.student_roster enable row level security;
alter table public.student_profiles enable row level security;
alter table public.college_admins enable row level security;
alter table public.face_enrollments enable row level security;
alter table public.identity_change_requests enable row level security;
alter table public.identity_change_audit enable row level security;

create policy "students read their claimed roster row" on public.student_roster
  for select to authenticated using (claimed_by = (select auth.uid()));
create policy "students read own profile" on public.student_profiles
  for select to authenticated using (user_id = (select auth.uid()));
create policy "admins read profiles" on public.student_profiles
  for select to authenticated
  using (exists (select 1 from public.college_admins a where a.user_id = (select auth.uid())));
create policy "admins read own admin record" on public.college_admins
  for select to authenticated using (user_id = (select auth.uid()));
create policy "students read own face enrollment" on public.face_enrollments
  for select to authenticated using (user_id = (select auth.uid()));
create policy "admins read face enrollment status" on public.face_enrollments
  for select to authenticated
  using (exists (select 1 from public.college_admins a where a.user_id = (select auth.uid())));
create policy "students read own change requests" on public.identity_change_requests
  for select to authenticated using (user_id = (select auth.uid()));
create policy "admins read change requests" on public.identity_change_requests
  for select to authenticated
  using (exists (select 1 from public.college_admins a where a.user_id = (select auth.uid())));
create policy "admins read identity audit" on public.identity_change_audit
  for select to authenticated
  using (exists (select 1 from public.college_admins a where a.user_id = (select auth.uid())));

revoke all on public.student_roster, public.student_profiles, public.college_admins,
  public.face_enrollments, public.identity_change_requests, public.identity_change_audit
  from anon, authenticated;
grant select on public.student_roster, public.student_profiles, public.college_admins,
  public.face_enrollments, public.identity_change_requests, public.identity_change_audit
  to authenticated;

create or replace function public.is_college_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.college_admins a where a.user_id = (select auth.uid()));
$$;

create or replace function public.claim_student_identity(p_roll_no text, p_full_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
  v_roster public.student_roster%rowtype;
begin
  if v_uid is null or v_email = '' then
    raise exception 'Sign in with your college email before registering.' using errcode = '28000';
  end if;
  if length(btrim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'Enter your full name.' using errcode = '22023';
  end if;
  if exists (select 1 from public.student_profiles p where p.user_id = v_uid) then
    raise exception 'This account already has a locked student identity.' using errcode = '23505';
  end if;
  select * into v_roster from public.student_roster r
    where r.roll_no = upper(btrim(coalesce(p_roll_no, '')))
      and lower(btrim(r.college_email)) = v_email
      and lower(btrim(r.full_name)) = lower(btrim(p_full_name))
      and r.claimed_by is null
    for update;
  if not found then
    raise exception 'Name, roll number, and signed-in college email did not match an available roster entry. Contact your administrator.' using errcode = '42501';
  end if;
  update public.student_roster set claimed_by = v_uid, claimed_at = now()
    where id = v_roster.id and claimed_by is null;
  if not found then raise exception 'This roster entry has already been claimed.' using errcode = '23505'; end if;
  insert into public.student_profiles(user_id, roster_id) values (v_uid, v_roster.id);
  return jsonb_build_object('roll_no', v_roster.roll_no, 'full_name', v_roster.full_name, 'has_face', false);
end;
$$;

create or replace function public.save_initial_face_enrollment(p_embedding double precision[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_vector extensions.vector(192);
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode = '28000'; end if;
  if not exists (select 1 from public.student_profiles p where p.user_id = v_uid) then
    raise exception 'Claim your roster entry before enrolling a face.' using errcode = '42501';
  end if;
  if p_embedding is null or coalesce(array_length(p_embedding, 1), 0) <> 192 then
    raise exception 'Face model must return exactly 192 values.' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_embedding) x where x is null or x::text in ('NaN', 'Infinity', '-Infinity')) then
    raise exception 'Face model returned invalid values.' using errcode = '22023';
  end if;
  v_vector := ('[' || array_to_string(p_embedding, ',') || ']')::extensions.vector(192);
  insert into public.face_enrollments(user_id, embedding) values (v_uid, v_vector);
exception when unique_violation then
  raise exception 'A face is already enrolled. Request an administrator-approved replacement.' using errcode = '23505';
end;
$$;

create or replace function public.request_identity_change(
  p_reason text, p_roll_no text default null, p_full_name text default null,
  p_embedding double precision[] default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_vector extensions.vector(192);
  v_id uuid;
  v_count integer := (p_roll_no is not null)::integer + (p_full_name is not null)::integer + (p_embedding is not null)::integer;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode = '28000'; end if;
  if not exists (select 1 from public.student_profiles p where p.user_id = v_uid) then
    raise exception 'Complete student registration before requesting an identity change.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Explain why this change is needed.' using errcode = '22023'; end if;
  if v_count = 0 then raise exception 'Choose a change to request.' using errcode = '22023'; end if;
  if exists (select 1 from public.identity_change_requests r where r.user_id = v_uid and r.status = 'pending') then
    raise exception 'You already have a pending identity change request.' using errcode = '23505';
  end if;
  if p_embedding is not null then
    if coalesce(array_length(p_embedding, 1), 0) <> 192 then raise exception 'Face model must return exactly 192 values.' using errcode = '22023'; end if;
    if exists (select 1 from unnest(p_embedding) x where x is null or x::text in ('NaN', 'Infinity', '-Infinity')) then raise exception 'Face model returned invalid values.' using errcode = '22023'; end if;
    v_vector := ('[' || array_to_string(p_embedding, ',') || ']')::extensions.vector(192);
  end if;
  if p_roll_no is not null and length(btrim(p_roll_no)) = 0 then raise exception 'Roll number cannot be blank.' using errcode = '22023'; end if;
  if p_full_name is not null and length(btrim(p_full_name)) < 2 then raise exception 'Name must contain at least two characters.' using errcode = '22023'; end if;
  insert into public.identity_change_requests(user_id, requested_roll_no, requested_full_name, requested_face_embedding, reason)
    values (v_uid, upper(btrim(p_roll_no)), nullif(btrim(p_full_name), ''), v_vector, btrim(p_reason)) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.list_pending_identity_changes()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_college_admin() then raise exception 'Administrator access required.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', r.id, 'user_id', r.user_id, 'roll_no', roster.roll_no,
    'full_name', roster.full_name, 'requested_roll_no', r.requested_roll_no,
    'requested_full_name', r.requested_full_name,
    'face_change', r.requested_face_embedding is not null,
    'reason', r.reason, 'requested_at', r.requested_at
  ) order by r.requested_at)
  from public.identity_change_requests r
  join public.student_profiles p on p.user_id = r.user_id
  join public.student_roster roster on roster.id = p.roster_id
  where r.status = 'pending'), '[]'::jsonb);
end;
$$;

create or replace function public.review_identity_change(p_request_id uuid, p_approve boolean, p_review_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_admin uuid := auth.uid();
  v_request public.identity_change_requests%rowtype;
  v_profile public.student_profiles%rowtype;
  v_roster public.student_roster%rowtype;
begin
  if v_admin is null or not public.is_college_admin() then raise exception 'Administrator access required.' using errcode = '42501'; end if;
  select * into v_request from public.identity_change_requests where id = p_request_id and status = 'pending' for update;
  if not found then raise exception 'Request is no longer pending.' using errcode = 'P0002'; end if;
  select * into v_profile from public.student_profiles where user_id = v_request.user_id for update;
  select * into v_roster from public.student_roster where id = v_profile.roster_id for update;
  if p_approve then
    if v_request.requested_roll_no is not null then
      update public.student_roster set roll_no = upper(btrim(v_request.requested_roll_no)) where id = v_roster.id;
      insert into public.identity_change_audit(request_id,user_id,changed_by,change_type,old_value,new_value)
        values (v_request.id,v_request.user_id,v_admin,'roll_no',v_roster.roll_no,upper(btrim(v_request.requested_roll_no)));
    end if;
    if v_request.requested_full_name is not null then
      update public.student_roster set full_name = btrim(v_request.requested_full_name) where id = v_roster.id;
      insert into public.identity_change_audit(request_id,user_id,changed_by,change_type,old_value,new_value)
        values (v_request.id,v_request.user_id,v_admin,'full_name',v_roster.full_name,btrim(v_request.requested_full_name));
    end if;
    if v_request.requested_face_embedding is not null then
      if exists (select 1 from public.face_enrollments f where f.user_id = v_request.user_id) then
        insert into public.identity_change_audit(request_id,user_id,changed_by,change_type,old_value,new_value)
          values (v_request.id,v_request.user_id,v_admin,'face_embedding','previous enrollment','replacement approved');
      end if;
      insert into public.face_enrollments(user_id,embedding,updated_at)
        values (v_request.user_id,v_request.requested_face_embedding,now())
        on conflict (user_id) do update set embedding = excluded.embedding, updated_at = now(), model_version = 'mobile_face_net_192_v1';
    end if;
  end if;
  update public.identity_change_requests set status = case when p_approve then 'approved' else 'rejected' end,
    reviewed_by = v_admin, reviewed_at = now(), review_note = nullif(btrim(p_review_note), '') where id = v_request.id;
end;
$$;

revoke all on function public.is_college_admin() from public, anon;
revoke all on function public.claim_student_identity(text,text) from public, anon;
revoke all on function public.save_initial_face_enrollment(double precision[]) from public, anon;
revoke all on function public.request_identity_change(text,text,text,double precision[]) from public, anon;
revoke all on function public.list_pending_identity_changes() from public, anon;
revoke all on function public.review_identity_change(uuid,boolean,text) from public, anon;
grant execute on function public.is_college_admin() to authenticated;
grant execute on function public.claim_student_identity(text,text) to authenticated;
grant execute on function public.save_initial_face_enrollment(double precision[]) to authenticated;
grant execute on function public.request_identity_change(text,text,text,double precision[]) to authenticated;
grant execute on function public.list_pending_identity_changes() to authenticated;
grant execute on function public.review_identity_change(uuid,boolean,text) to authenticated;
