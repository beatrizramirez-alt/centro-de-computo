-- CECyTEO · Control de Centro de Cómputo
-- Apply in Supabase SQL Editor. All operational records are protected by RLS.
create extension if not exists pgcrypto;

create type public.staff_role as enum ('admin', 'campus_manager', 'technician');
create type public.computer_state as enum ('available', 'in_use', 'maintenance', 'offline');
create type public.session_state as enum ('active', 'finished', 'cancelled');

create table public.campuses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  municipality text,
  created_at timestamptz not null default now()
);

create table public.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  campus_id uuid references public.campuses(id) on delete set null,
  full_name text not null,
  role public.staff_role not null default 'campus_manager',
  created_at timestamptz not null default now()
);

create table public.computers (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  code text not null,
  lab_name text not null default 'Laboratorio A',
  hostname text,
  state public.computer_state not null default 'available',
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  unique (campus_id, code)
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  enrollment text not null,
  full_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (campus_id, enrollment)
);

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  computer_id uuid not null references public.computers(id) on delete restrict,
  student_id uuid not null references public.students(id) on delete restrict,
  started_by uuid references auth.users(id) on delete set null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  status public.session_state not null default 'active',
  notes text,
  check ((status = 'active' and ended_at is null) or (status <> 'active' and ended_at is not null))
);

create unique index sessions_one_active_per_computer on public.sessions(computer_id) where status = 'active';
create unique index sessions_one_active_per_student on public.sessions(student_id) where status = 'active';
create index sessions_campus_started_idx on public.sessions(campus_id, started_at desc);
create index sessions_started_by_idx on public.sessions(started_by);
create index computers_campus_state_idx on public.computers(campus_id, state);
create index students_campus_enrollment_idx on public.students(campus_id, enrollment);
create index staff_profiles_campus_idx on public.staff_profiles(campus_id);

create function public.my_campus_id() returns uuid
language sql stable security invoker set search_path = ''
as $$ select campus_id from public.staff_profiles where user_id = (select auth.uid()) $$;

alter table public.campuses enable row level security;
alter table public.staff_profiles enable row level security;
alter table public.computers enable row level security;
alter table public.students enable row level security;
alter table public.sessions enable row level security;

revoke all on public.campuses, public.staff_profiles, public.computers, public.students, public.sessions from anon;
grant select on public.campuses, public.staff_profiles, public.computers, public.students, public.sessions to authenticated;
grant insert, update, delete on public.computers, public.students, public.sessions to authenticated;

create policy "staff see own profile" on public.staff_profiles for select to authenticated using (user_id = (select auth.uid()));
create policy "staff see assigned campus" on public.campuses for select to authenticated using (id = (select public.my_campus_id()));
create policy "staff see campus computers" on public.computers for select to authenticated using (campus_id = (select public.my_campus_id()));
create policy "staff create campus computers" on public.computers for insert to authenticated with check (campus_id = (select public.my_campus_id()));
create policy "staff update campus computers" on public.computers for update to authenticated using (campus_id = (select public.my_campus_id())) with check (campus_id = (select public.my_campus_id()));
create policy "staff delete campus computers" on public.computers for delete to authenticated using (campus_id = (select public.my_campus_id()));
create policy "staff see campus students" on public.students for select to authenticated using (campus_id = (select public.my_campus_id()));
create policy "staff add campus students" on public.students for insert to authenticated with check (campus_id = (select public.my_campus_id()));
create policy "staff update campus students" on public.students for update to authenticated using (campus_id = (select public.my_campus_id())) with check (campus_id = (select public.my_campus_id()));
create policy "staff remove campus students" on public.students for delete to authenticated using (campus_id = (select public.my_campus_id()));
create policy "staff see campus sessions" on public.sessions for select to authenticated using (campus_id = (select public.my_campus_id()));
create policy "staff create campus sessions" on public.sessions for insert to authenticated with check (campus_id = (select public.my_campus_id()) and started_by = (select auth.uid()));
create policy "staff update campus sessions" on public.sessions for update to authenticated using (campus_id = (select public.my_campus_id())) with check (campus_id = (select public.my_campus_id()));

-- Atomic session actions: validate campus, avoid double booking, and sync equipment state.
create function public.start_session(p_enrollment text, p_computer_code text)
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare v_campus uuid; v_student uuid; v_computer uuid; v_session uuid;
begin
  select campus_id into v_campus from public.staff_profiles where user_id = (select auth.uid());
  if v_campus is null then raise exception 'El usuario no tiene un plantel asignado.'; end if;
  select id into v_student from public.students where campus_id = v_campus and enrollment = p_enrollment and active;
  if v_student is null then raise exception 'No se encontró una matrícula activa en este plantel.'; end if;
  select id into v_computer from public.computers where campus_id = v_campus and code = p_computer_code and state = 'available' for update;
  if v_computer is null then raise exception 'El equipo no está disponible.'; end if;
  insert into public.sessions (campus_id, computer_id, student_id, started_by)
  values (v_campus, v_computer, v_student, (select auth.uid())) returning id into v_session;
  update public.computers set state = 'in_use' where id = v_computer;
  return v_session;
end;
$$;

create function public.finish_session(p_session_id uuid)
returns void language plpgsql security invoker set search_path = ''
as $$
declare v_computer uuid; v_campus uuid;
begin
  select computer_id, campus_id into v_computer, v_campus from public.sessions
  where id = p_session_id and status = 'active' and campus_id = (select public.my_campus_id()) for update;
  if v_computer is null then raise exception 'No se encontró una sesión activa en este plantel.'; end if;
  update public.sessions set status = 'finished', ended_at = now() where id = p_session_id;
  update public.computers set state = 'available' where id = v_computer and campus_id = v_campus;
end;
$$;

revoke all on function public.start_session(text, text), public.finish_session(uuid) from public, anon;
grant execute on function public.start_session(text, text), public.finish_session(uuid) to authenticated;

-- Real-time updates for authenticated staff dashboard clients.
alter publication supabase_realtime add table public.computers;
alter publication supabase_realtime add table public.sessions;
