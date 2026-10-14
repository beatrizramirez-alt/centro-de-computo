-- Example setup for one campus. Replace the Auth user UUID and campus details.
insert into public.campuses (code, name, municipality)
values ('OAX-01', 'Plantel 01 Santa Lucía', 'Oaxaca de Juárez')
on conflict (code) do nothing;

-- Get the staff UUID in Authentication > Users, then replace the UUID below.
insert into public.staff_profiles (user_id, campus_id, full_name, role)
select '00000000-0000-0000-0000-000000000000'::uuid, id, 'Nombre del responsable', 'campus_manager'
from public.campuses where code = 'OAX-01'
on conflict (user_id) do update set campus_id = excluded.campus_id, full_name = excluded.full_name;

-- Example inventory: 16 computers divided between two labs.
insert into public.computers (campus_id, code, lab_name)
select c.id, 'PC-' || lpad(n::text, 2, '0'), case when n <= 8 then 'Laboratorio A' else 'Laboratorio B' end
from public.campuses c cross join generate_series(1, 16) as n
where c.code = 'OAX-01'
on conflict (campus_id, code) do nothing;

-- Load authorized student enrollments from the official campus roster:
-- insert into public.students (campus_id, enrollment, full_name)
-- select id, 'MATRICULA', 'NOMBRE COMPLETO' from public.campuses where code = 'OAX-01';
