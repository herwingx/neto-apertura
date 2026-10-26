# 🛒 Neto Apertura · Checklist de Soporte Técnico e Infraestructura

Aplicación web moderna (PWA) e interactiva diseñada específicamente para **Ingenieros de Soporte Técnico en campo de Tiendas Neto**, para asegurar una apertura completa, ordenada, estandarizada y sin omisiones.

Diseñada para ser operada con **una sola mano desde el smartphone** en el rack o frente a las cajas registradoras, con funcionamiento **100% offline**, respuesta táctil con vibración háptica, guardado automático en local y sincronización en la nube vía **Supabase**.

---

## 📱 Experiencia Mobile-First & PWA en Android

- **Navegación Táctil con Pulgar (Bottom Navigation)**: Barra de navegación inferior nativa con 4 módulos clave:
  1. 📋 **Checklist**: Fases de apertura con selector horizontal deslizable de estaciones (`Rack`, `WS_GERENTE`, `WS_CAJA01`, `WS_CAJA02`, `Radio`, `Cierre`).
  2. 🖲️ **Equipos**: Matriz táctil ergonómica con vista por estación y matriz global con alternancia rápida de estados: `Ok` (Verde), `N/A` (Gris), `Falla` (Rojo), `Sin Eq.` (Ámbar).
  3. 🏪 **Tienda & Red**: Registro de sucursal, proveedor ISP, SpeedTest, modelos de hardware, versiones y responsables.
  4. 📤 **Reporte WhatsApp**: Generador instantáneo de reportes con botón de copia rápida y envío directo a WhatsApp.
- **Filtro Rápido "Solo pendientes"**: Oculta con un toque los ítems completados para agilizar la entrega final a Calidad Operativa.
- **Feedback Háptico (`navigator.vibrate`)**: Confirmación física sutil por vibración al marcar casillas o cambiar estados de periféricos.
- **Instalación Directa como PWA en Android (WebAPK)**:
  - Soporte de evento nativo `beforeinstallprompt` con botón directo `📲 Instalar`.
  - Iconos oficiales adaptados: `192x192`, `512x512` y `512x512 maskable` para recorte circular en Android.
  - Funcionamiento 100% offline en sótanos o bodegas sin señal telefónica gracias al Service Worker v2.
- **Diseño con Tailwind CSS**: Paleta de alto contraste optimizada para bodegas oscuras con ahorro de batería en pantallas OLED (Slate 950 + Azul y Naranja corporativo Neto).

---

## 🚀 Fases Secuenciales de Apertura

1. **Rack de Comunicaciones y Red**: Fortinet, Switch, peinado y encinchado, ISP/Módem provisional, No-Break.
2. **WS_GERENTE (Caja Gerente)**: No-Break, peinado, imagen SO, periféricos, antivirus, secuencia de 3 scripts de usuario cambios, activación de tienda, Hydra, Slack, impresión de plantilla de escáner, IP/DNS, fecha y hora de red, USB 3.0 sin ahorro, script activación PAX, instalador de POS con Coord. de Sistemas, validación con Calidad Operativa, recargas 1060 y script final.
3. **WS_CAJA01 (Caja 1)**: Con No-Break, perforación y base para PAX, escáner con hoja impresa en Gerente, SO, periféricos, Hydra, Slack, IP/DNS, flujo completo PAX (PAX Config → Componente Transaccional → Reiniciar servicio PAX → Paydroid Software Refresh con APK de Hydra), POS, Calidad Operativa y script final.
4. **WS_CAJA02 (Caja 2)**: Recordatorio visual destacado de que **por diseño arquitectónico y eléctrico NO lleva No-Break**, con todo el flujo de perforación, PAX, SO, Hydra, Paydroid y POS.
5. **Radio Neto**: Colocación de bocinas, cableado hacia amplificador en caja y prueba de audio.
6. **Cierre y Resguardo de Equipos**: Cubrir y proteger equipos tras validación con Calidad Operativa, apagar y desconectar para entrega de obra.

---

## 🛠️ Desarrollo & Compilación de Tailwind CSS

Este proyecto utiliza **Tailwind CSS v4** compilado estáticamente para garantizar cero latencia y funcionamiento 100% offline sin dependencias de CDN en producción.

### Comandos de desarrollo:

```bash
# Instalar dependencias
npm install

# Compilar CSS minificado para producción
npm run build:css

# Modo observador durante desarrollo
npm run watch:css
```

---

## 🗄️ Esquema de Base de Datos en Supabase

El esquema PostgreSQL crea un esquema aislado con RLS y dos funciones RPC seguras:

```sql
create schema if not exists neto_apertura;

create table if not exists neto_apertura.checklists (
  code        text primary key check (char_length(code) between 10 and 64),
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

alter table neto_apertura.checklists enable row level security;
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
  if char_length(p_code) < 10 then raise exception 'codigo invalido'; end if;
  insert into neto_apertura.checklists(code, data, updated_at)
  values (p_code, p_data, ts)
  on conflict (code) do update set data = excluded.data, updated_at = ts;
  return ts;
end $$;

revoke all on function public.neto_get_checklist(text), public.neto_save_checklist(text, jsonb) from public;
grant execute on function public.neto_get_checklist(text), public.neto_save_checklist(text, jsonb) to anon, authenticated;
```

---

## 📦 Despliegue en GitHub Pages

Este proyecto se ejecuta en GitHub Pages en la cuenta `@herwingx`:

URL: `https://herwingx.github.io/neto-apertura/`
