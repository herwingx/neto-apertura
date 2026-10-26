-- Checklist de Apertura Neto: esquema aislado, sin políticas para anon.
-- El acceso se hace solo con las funciones RPC y un código de sesión no adivinable.
create schema if not exists neto_apertura;

create table if not exists neto_apertura.checklists (
  code        text primary key check (char_length(code) between 16 and 64),
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
alter table neto_apertura.checklists enable row level security;
-- Sin policies: anon/authenticated no pueden leer ni escribir directo.
revoke all on schema neto_apertura from anon, authenticated;
revoke all on all tables in schema neto_apertura from anon, authenticated;

create or replace function public.neto_get_checklist(p_code text)
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object('data', data, 'updated_at', updated_at)
  from neto_apertura.checklists where code = p_code;
$$;

create or replace function public.neto_save_checklist(p_code text, p_data jsonb)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare ts timestamptz := now();
begin
  if char_length(p_code) < 16 then raise exception 'codigo invalido'; end if;
  insert into neto_apertura.checklists(code, data, updated_at)
  values (p_code, p_data, ts)
  on conflict (code) do update set data = excluded.data, updated_at = ts;
  return ts;
end $$;

revoke all on function public.neto_get_checklist(text), public.neto_save_checklist(text, jsonb) from public;
grant execute on function public.neto_get_checklist(text), public.neto_save_checklist(text, jsonb) to anon, authenticated;

