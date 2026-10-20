# GotaControl

Aplicacion Flutter para gestion local de prestamos en Android, orientada a
operaciones de credito gota a gota y trabajo sin conexion.

## Dependencias

Requiere Flutter 3.44.8 y Dart 3.12.2. Instalar los paquetes con `flutter pub get`.
La lista directa y los comandos estan en [DEPENDENCIAS.txt](DEPENDENCIAS.txt).

## Funcionalidades actuales

- Clientes con nombre, telefono y cedula numericos, direccion opcional,
  edicion y busqueda de la direccion en Google Maps.
- Prestamos diarios, semanales, quincenales, mensuales, lunes-miercoles-
  viernes y frecuencias personalizadas.
- Fechas retroactivas, dias corridos o ajuste al siguiente dia habil,
  festivos colombianos y cuotas sin decimales fraccionarios.
- Pagos completos y parciales, mora configurable por frecuencia, dias de
  gracia, porcentaje o monto fijo y recargo acumulable.
- Reportes diarios, semanales, mensuales, estado de cuenta y estadisticas de
  capital e interes, con visor PDF ampliable.
- Notificaciones locales de cuotas por vencer y de cuotas que ya superaron los
  dias de gracia de mora, ademas de resumen diario configurable.
- PIN local con bloqueo despues de 90 segundos en segundo plano, respaldos
  automaticos y manuales, restauracion e importacion desde Documentos.

## Plataformas

Android usa SQLite local para conservar clientes, préstamos y pagos entre sesiones.
La compilación Web funciona, pero el adaptador SQLite de Android no está conectado
a almacenamiento de navegador. En Web se mostrará un aviso de base de datos no
disponible; no usar la versión Web para registrar operaciones reales.

Para probar la interfaz web sin persistencia, aún no hay un modo mock separado.

## Respaldos locales y recuperación

En Android 10 o posterior, GotaControl crea automáticamente
`Documentos/GotaControl` en el primer inicio y guarda allí las copias completas de
SQLite. Esa carpeta está fuera del almacenamiento privado de la app y permanece
al desinstalarla. Android elimina el permiso privado de acceso al reinstalar,
por lo que, si la base local no existe o está vacía, la app solicita elegir con
el selector seguro del sistema la carpeta `GotaControl` que contiene los
respaldos (o su carpeta principal). Antes de abrir SQLite busca, valida y
restaura la copia más reciente con datos. Si se cancela el selector, se muestra
un aviso y se puede volver a importar desde Ajustes. Los respaldos automáticos
no se crean mientras no existan clientes, préstamos, cuotas ni pagos, para
evitar que una base vacía tape datos recuperables.

En Android 7–9 se mantiene el selector SAF para configurar la carpeta; tras
reinstalar, vuelve a conceder acceso e importa el archivo `.db` desde Ajustes.
En cualquier versión también puedes importar manualmente. La importación valida
integridad y versión, pide confirmación, conserva una copia preventiva y revierte
la sustitución si falla.

Se puede programar el respaldo en segundo plano diariamente, semanalmente o cada
15 días. Android WorkManager ejecuta estas tareas de forma eventual, por lo que
ahorro de batería, políticas del fabricante o detención forzada pueden
retrasarlas. Se guardan las 30 copias automáticas más recientes; las copias
manuales y las creadas antes de importar no se borran. Crear una copia manual
sigue disponible en Ajustes.

Desde Ajustes también se puede imprimir/guardar un PDF de todos los clientes,
préstamos, cuotas y pagos, o compartir cuatro CSV separados para abrirlos en una
hoja de cálculo. En Reportes, los resúmenes diario, semanal y mensual siguen el
período elegido, igual que el PDF. Los archivos exportados y la base SQLite
contienen datos financieros y personales; la carpeta Descargas es accesible al
usuario del dispositivo. El respaldo no está cifrado.

Los límites de Ajustes se validan en la interfaz y en el proveedor local: nombre
de negocio obligatorio (250 caracteres), teléfono opcional (15), dirección
opcional (250), mora entre 0 y 100 % y días de gracia entre 0 y 365.

## Notificaciones locales

GotaControl programa recordatorios locales para las cuotas pendientes: el día
del vencimiento y, si está activada la opción **Alertas de mora**, cuando cada
préstamo supera sus propios días de gracia configurados. Las cuotas que ya
están vencidas generan además una alerta inmediata al sincronizar la app.
También permite programar un resumen diario desde Ajustes. Al crear un
préstamo, registrar un pago o iniciar la app, los recordatorios se sincronizan
con las cuotas y el saldo que aún falta pagar. Para respetar el límite de
alarmas de Android, se mantienen hasta 300 alertas de cuotas próximas, además
del resumen diario; al volver a abrir la app se actualiza esa ventana.

En Android 13 o posterior se debe permitir el permiso de notificaciones del
sistema. El estado se consulta en **Ajustes → Notificaciones**; si está
bloqueado, usa **Abrir ajustes del teléfono** y habilítalo para GotaControl.
Las alertas dentro de la app muestran las cuotas vencidas y las que vencen hoy,
aunque el permiso del sistema para notificaciones esté desactivado. Android y
los modos de ahorro de batería pueden retrasar recordatorios programados.

## PIN de seguridad

En Android, el PIN local se valida con bcrypt (factor de trabajo 12) mediante
`jBCrypt`; solo el hash se guarda en SQLite. El cálculo se ejecuta fuera del hilo
de interfaz. Esto no es autenticación de servidor: quien obtenga una copia de la
base de datos puede intentar adivinar el PIN fuera de la aplicación. No almacenes
datos sincronizados ni consideres el PIN un sustituto del cifrado del dispositivo
y de copias de seguridad protegidas.

## APK Android

En PowerShell, si `JAVA_HOME` apunta a una carpeta inexistente, usa el JDK incluido
con Android Studio durante la compilación:

```powershell
$env:JAVA_HOME = "$env:ProgramFiles\Android\Android Studio\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
flutter build apk --release --obfuscate --split-debug-info=build/symbols
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`. Si no existe
`android/key.properties`, se firma con el certificado debug y no debe publicarse
como una versión de producción. El identificador de aplicación es
`com.ingeniumcode.gotacontrol`; configúralo de forma definitiva antes de publicar.
Conserva `build/symbols` para poder diagnosticar errores de esta compilación
ofuscada. El procedimiento completo, incluyendo ADB, firma, compatibilidad y
errores frecuentes, está en [GUIA_APK.txt](GUIA_APK.txt).

## Calidad y pruebas

Las pruebas cubren persistencia SQLite, migraciones, clientes, pagos parciales
y retroactivos, calculo financiero, mora con reglas por frecuencia, calendario
mensual, reportes, formularios y Google Maps. Antes de generar una release:

```powershell
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

La base local usa SQLite version 7 y los respaldos se validan antes de
restaurarse. No se deben borrar respaldos del dispositivo como parte de una
compilacion o instalacion.

## Docker

```sh
docker build -t gotacontrol-web .
docker run --rm -e PORT=10000 -p 8080:10000 gotacontrol-web
```

Abrir `http://localhost:8080`.

### Render

1. Crear un **Web Service** y conectar el repositorio `JULIANLINARES77/CrediGota`.
2. Elegir **Docker** como runtime y dejar `Dockerfile` y el contexto de build en la raiz.
3. Render construira la imagen y proporcionara `PORT` (por defecto `10000`); Nginx escucha ese puerto.
4. Desplegar. El dominio `onrender.com` puede usarse para la demostracion; se puede asociar un dominio propio desde Render.

El contenedor sirve la versión Web, que actualmente no tiene backend ni adaptador
de base de datos para navegador. No usarla para guardar información real.
