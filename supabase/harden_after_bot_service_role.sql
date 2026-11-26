-- ============================================================================
-- HARDENING FASE 2 (Ejecutar DESPUÉS de agregar SUPABASE_SERVICE_ROLE_KEY
-- al .env del servidor de neto-slack-bot y reiniciar el bot)
-- ============================================================================
-- Paso 1: En el servidor de neto-slack-bot:
--   git pull
--   Agrega SUPABASE_SERVICE_ROLE_KEY=eyJ... en .env
--   Reinicia el servicio del bot (systemctl restart neto-bot / pm2 restart ...)
--
-- Paso 2: Ejecuta este SQL en Supabase SQL Editor para cerrar por completo
--         el acceso `anon` al listado de checklists y a tokens sensibles:
-- ============================================================================

-- 1. Bloquear listado público de checklists a anon (solo ingenieros logueados + bot)
REVOKE EXECUTE ON FUNCTION public.neto_list_checklists(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.neto_list_checklists(integer) TO authenticated, service_role;

-- 2. Restringir escritura en tablas de rutas_sureste solo a usuarios autenticados
DROP POLICY IF EXISTS "Escritura de tiendas autorizada" ON rutas_sureste.tiendas;
CREATE POLICY "Escritura de tiendas solo autenticados"
  ON rutas_sureste.tiendas
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- 3. Proteger rutas_sureste.ingenieros (evitar que anon lea slack_token / telegram_id)
DROP POLICY IF EXISTS "Acceso completo ingenieros" ON rutas_sureste.ingenieros;
CREATE POLICY "Acceso ingenieros solo autenticados"
  ON rutas_sureste.ingenieros
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
