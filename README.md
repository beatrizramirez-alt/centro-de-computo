# CECyTEO · Control de Centro de Cómputo

Aplicación web para registrar y supervisar el uso de equipos de cómputo por plantel. Incluye panel administrativo, estado por laboratorio, sesiones activas, exportación CSV y estructura de datos multisitio en Supabase.

## Empezar

1. Instala Node.js 20 o posterior.
2. En esta carpeta ejecuta `npm install` y luego `npm run dev`.
3. Abre `http://localhost:3000`. Sin variables de Supabase funciona como vista previa local; los cambios de demostración viven solo mientras la página está abierta.

## Conectar Supabase

1. Crea un proyecto en Supabase.
2. En **SQL Editor**, ejecuta el contenido de `supabase/schema.sql`.
3. En **Authentication → Users**, crea las cuentas del personal. Sustituye el UUID de ejemplo en `supabase/seed.example.sql`, ajusta los datos del plantel y ejecútalo para crear el perfil responsable y 16 equipos de muestra. No se permite el registro público.
4. Copia `.env.example` a `.env.local` y asigna la URL del proyecto y su publishable key. Nunca pongas una `service_role` o secret key en variables `NEXT_PUBLIC_`.
5. Reinicia el servidor local. La tabla `sessions` y `computers` se actualizan mediante Supabase Realtime.

El esquema aplica Row Level Security a todas las tablas expuestas y restringe las filas al plantel asignado al usuario autenticado. Para crear un usuario de personal, el usuario debe existir primero en Supabase Auth y su `user_id` debe asociarse en `staff_profiles`. Carga de inicio recomendada: crear un campus, un perfil responsable, sus equipos y su padrón de alumnos.

## GitHub y Vercel

1. Crea un repositorio GitHub y sube el contenido de esta carpeta.
2. En Vercel importa el repositorio y conserva la configuración detectada de Next.js.
3. En **Project Settings → Environment Variables**, agrega `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY` para Preview y Production.
4. Despliega. Los cambios enviados a la rama de producción vuelven a desplegar la aplicación.

## Flujo y alcance

El alumno selecciona un equipo disponible e ingresa su matrícula en el módulo de registro; el sistema registra la sesión y actualiza su estado. El responsable puede finalizar sesiones, cambiar la disponibilidad del equipo y descargar el reporte de sesiones visibles.

La pantalla actual es un tablero web adaptable y una vista previa funcional. Para operación real, se requiere habilitar autenticación de personal, cargar el padrón oficial y conectar la acción de inicio de sesión del kiosco a una función de servidor que valide matrícula, plantel, equipo y permisos antes de insertar la sesión. El desbloqueo de Windows no se realiza desde una página web: necesita un cliente kiosco/agente instalado y administrado en cada PC, integrado con las políticas del centro. No se incluye captura biométrica; la verificación facial requiere consentimiento, evaluación de privacidad y una implementación institucional aparte.

## Arquitectura

`Kiosco del equipo / panel web → Next.js en Vercel → Supabase Auth + Postgres (RLS) + Realtime`

Cada plantel tiene sus propios equipos, estudiantes y sesiones. Las llaves privadas permanecen del lado del servidor. Para activar un kiosco público, usa una función backend con autenticación de dispositivo y límites de intentos; no habilites escrituras anónimas en las tablas.
