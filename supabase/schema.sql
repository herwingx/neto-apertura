-- ============================================================================
-- Checklist de Apertura Neto + Integración con Rutas Sureste (Supabase)
-- ============================================================================
-- Esquema aislado `neto_apertura` con RLS activado (sin políticas directas).
-- El acceso se realiza exclusivamente mediante RPCs con validación de permisos.
-- ============================================================================

create schema if not exists neto_apertura;

create table if not exists neto_apertura.checklists (
  code        text primary key check (char_length(code) between 10 and 64),
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

alter table neto_apertura.checklists enable row level security;
revoke all on schema neto_apertura from anon, authenticated;
revoke all on all tables in schema neto_apertura from anon, authenticated;

-- 1. Obtener checklist por código de sesión
create or replace function public.neto_get_checklist(p_code text)
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object('data', data, 'updated_at', updated_at)
  from neto_apertura.checklists where code = p_code;
$$;

-- 2. Guardar / actualizar checklist por código de sesión
create or replace function public.neto_save_checklist(p_code text, p_data jsonb)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare ts timestamptz := now();
begin
  if char_length(p_code) < 10 then raise exception 'codigo invalido'; end if;
  insert into neto_apertura.checklists(code, data, updated_at)
  values (p_code, p_data, ts)
  on conflict (code) do update set data = excluded.data, updated_at = ts;
  return ts;
end $$;

-- 3. Listar checklists recientes (usado por App Web y Bot de Telegram)
create or replace function public.neto_list_checklists(p_limit integer default 15)
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object('code', code, 'data', data, 'updated_at', updated_at)
      order by updated_at desc
    ),
    '[]'::jsonb
  )
  from (
    select code, data, updated_at
    from neto_apertura.checklists
    order by updated_at desc
    limit greatest(1, least(coalesce(p_limit, 15), 50))
  ) sub;
$$;

-- 4. Registrar / actualizar tienda de apertura en rutas_sureste.tiendas
--    SEGURIDAD: Solo usuarios autenticados (@soyneto.com) o service_role.
--    Resuelve automáticamente ingeniero_id, region_id, zona_id, fecha_verificacion y geom (PostGIS).
create or replace function public.neto_upsert_tienda_apertura(
  p_eco text,
  p_ceco text,
  p_nombre text,
  p_estado text default 'Chiapas'::text,
  p_region text default 'CHIAPAS'::text,
  p_zona text default ''::text,
  p_ingeniero text default ''::text,
  p_coords text default ''::text,
  p_lat double precision default null::double precision,
  p_lng double precision default null::double precision
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'rutas_sureste', 'extensions'
as $$
declare
  v_uid uuid := auth.uid();
  v_eco text := coalesce(nullif(trim(p_eco), ''), '0');
  v_ceco text := coalesce(nullif(trim(p_ceco), ''), '0');
  v_nombre text := upper(trim(coalesce(p_nombre, '')));
  v_estado text := coalesce(nullif(trim(p_estado), ''), 'Chiapas');
  v_region text := upper(coalesce(nullif(trim(p_region), ''), 'CHIAPAS'));
  v_zona text := upper(trim(coalesce(p_zona, '')));
  v_ingeniero text := upper(trim(coalesce(p_ingeniero, '')));
  v_coords text := trim(coalesce(p_coords, ''));
  v_lat double precision := p_lat;
  v_lng double precision := p_lng;
  v_ingeniero_id integer;
  v_region_id integer;
  v_zona_id integer;
  v_existing_id bigint;
  v_action text := 'inserted';
  v_result_id bigint;
begin
  if v_uid is null and current_setting('request.jwt.claim.role', true) is distinct from 'service_role' then
    raise exception 'Autenticación requerida: inicia sesión con tu cuenta @soyneto.com para registrar tiendas';
  end if;

  if v_nombre = '' then
    raise exception 'El nombre de la tienda es obligatorio';
  end if;

  if v_coords = '' and v_lat is not null and v_lng is not null then
    v_coords := round(v_lat::numeric, 7)::text || ',' || round(v_lng::numeric, 7)::text;
  end if;

  if (v_lat is null or v_lng is null) and v_coords ~ '^\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*$' then
    v_lat := split_part(v_coords, ',', 1)::double precision;
    v_lng := split_part(v_coords, ',', 2)::double precision;
  end if;

  -- Resolver ingeniero_id (por auth_id primero, luego por nombre)
  if v_uid is not null then
    select id, upper(nombre) into v_ingeniero_id, v_ingeniero
    from rutas_sureste.ingenieros where auth_id = v_uid limit 1;
  end if;
  if v_ingeniero_id is null and v_ingeniero <> '' then
    select id, upper(nombre) into v_ingeniero_id, v_ingeniero
    from rutas_sureste.ingenieros
    where upper(trim(nombre)) = v_ingeniero or upper(trim(nombre)) like '%' || v_ingeniero || '%'
    limit 1;
  end if;

  -- Resolver region_id y zona_id
  select id into v_region_id from rutas_sureste.regiones where upper(trim(nombre)) = v_region limit 1;
  if v_region_id is null then
    select id into v_region_id from rutas_sureste.regiones where upper(trim(nombre)) = 'SURESTE' limit 1;
  end if;
  if v_zona <> '' then
    select id into v_zona_id from rutas_sureste.zonas
    where upper(trim(nombre)) = v_zona or upper(trim(nombre)) like '%' || v_zona || '%'
    order by (upper(trim(nombre)) = v_zona) desc limit 1;
  end if;

  if v_eco <> '0' and v_eco <> '-' then
    select id into v_existing_id from rutas_sureste.tiendas where eco = v_eco limit 1;
  end if;
  if v_existing_id is null then
    select id into v_existing_id from rutas_sureste.tiendas where upper(trim(nombre)) = v_nombre limit 1;
  end if;

  if v_existing_id is not null then
    v_action := 'updated';
    update rutas_sureste.tiendas set
      eco = case when v_eco <> '0' and v_eco <> '-' then v_eco else eco end,
      ceco = case when v_ceco <> '0' then v_ceco else ceco end,
      nombre = v_nombre,
      estado = v_estado,
      region = v_region,
      region_id = coalesce(v_region_id, region_id),
      zona = case when v_zona <> '' then v_zona else zona end,
      zona_id = coalesce(v_zona_id, zona_id),
      ingeniero = case when v_ingeniero <> '' then v_ingeniero else ingeniero end,
      ingeniero_id = coalesce(v_ingeniero_id, ingeniero_id),
      coords = case when v_coords <> '' then v_coords else coords end,
      lat = coalesce(v_lat, lat),
      lng = coalesce(v_lng, lng),
      verificada = case when v_lat is not null and v_lng is not null then true else verificada end,
      fecha_verificacion = case when v_lat is not null and v_lng is not null then current_date else fecha_verificacion end,
      geom = case when v_lat is not null and v_lng is not null then extensions.ST_SetSRID(extensions.ST_MakePoint(v_lng, v_lat), 4326) else geom end,
      updated_at = now()
    where id = v_existing_id
    returning id into v_result_id;
  else
    insert into rutas_sureste.tiendas (
      eco, ceco, nombre, coords, lat, lng, estado, region, region_id, empresa,
      zona, zona_id, ingeniero, ingeniero_id, verificada, fecha_verificacion, geom
    ) values (
      v_eco, v_ceco, v_nombre, v_coords, v_lat, v_lng, v_estado, v_region, v_region_id, 'SURESTE',
      v_zona, v_zona_id, v_ingeniero, v_ingeniero_id, (v_lat is not null and v_lng is not null),
      case when v_lat is not null and v_lng is not null then current_date else null end,
      case when v_lat is not null and v_lng is not null then extensions.ST_SetSRID(extensions.ST_MakePoint(v_lng, v_lat), 4326) else null end
    )
    returning id into v_result_id;
  end if;

  return jsonb_build_object(
    'ok', true, 'action', v_action, 'id', v_result_id, 'eco', v_eco, 'ceco', v_ceco,
    'nombre', v_nombre, 'zona', v_zona, 'zona_id', v_zona_id,
    'region', v_region, 'region_id', v_region_id,
    'ingeniero', v_ingeniero, 'ingeniero_id', v_ingeniero_id, 'estado', v_estado
  );
end $$;

-- Permisos estrictos
revoke all on function public.neto_get_checklist(text), public.neto_save_checklist(text, jsonb), public.neto_list_checklists(integer) from public;
grant execute on function public.neto_get_checklist(text), public.neto_save_checklist(text, jsonb), public.neto_list_checklists(integer) to anon, authenticated, service_role;

-- Escritura en tabla maestra de tiendas: SOLO autenticados o service_role (NUNCA anon)
revoke all on function public.neto_upsert_tienda_apertura(text, text, text, text, text, text, text, text, double precision, double precision) from public, anon;
grant execute on function public.neto_upsert_tienda_apertura(text, text, text, text, text, text, text, text, double precision, double precision) to authenticated, service_role;
