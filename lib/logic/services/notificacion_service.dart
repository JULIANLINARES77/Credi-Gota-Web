import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/constants/db_constants.dart';
import '../../data/models/cuota.dart';
import '../../data/models/prestamo.dart';
import '../providers/gota_provider.dart';

typedef _AlertaCuotaPendiente = ({
  int id,
  tz.TZDateTime fecha,
  String titulo,
  String mensaje,
  String payload,
});

class NotificacionService {
  NotificacionService._();

  static final NotificacionService instance = NotificacionService._();
  static const _canalId = 'gota_control_recordatorios';
  static const _notificacionDiariaId = 1;
  static const _maxAlertasProgramadas = 300;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inicializado = false;
  Future<void>? _inicializacion;

  Future<void> inicializarNotificaciones() {
    if (_inicializado) return Future<void>.value();
    return _inicializacion ??= _inicializar().whenComplete(() {
      _inicializacion = null;
    });
  }

  Future<void> _inicializar() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Bogota'));

    const ajustes = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    final resultado = await _plugin.initialize(settings: ajustes);
    _inicializado = resultado ?? false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _canalId,
          'Recordatorios de GotaControl',
          description: 'Vencimientos y resumen diario de cobros.',
          importance: Importance.high,
        ),
      );
      await androidPlugin?.requestNotificationsPermission();
    }
    debugPrint('GotaControl: notificaciones inicializadas=$_inicializado');
  }

  Future<bool> solicitarPermisoNotificaciones() async {
    await _asegurarInicializacion();
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await androidPlugin?.requestNotificationsPermission() ?? false;
  }

  Future<bool> notificacionesHabilitadas() async {
    await _asegurarInicializacion();
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await androidPlugin?.areNotificationsEnabled() ?? false;
  }

  Future<bool> abrirAjustesNotificaciones() async {
    await _asegurarInicializacion();
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await androidPlugin?.openAppNotificationSettings() ?? false;
  }

  Future<void> sincronizarConDatos(GotaProvider provider) async {
    await _asegurarInicializacion();
    final configuracion = provider.configuracion ?? const <String, Object?>{};
    final hora =
        (configuracion[DbConstants.configuracionHoraRecordatorio] as String? ??
                '08:00')
            .split(':');
    final recordatorioDiario =
        ((configuracion[DbConstants.configuracionRecordatorioDiario] as num?)
                ?.toInt() ??
            0) !=
        0;
    final prestamos = provider.prestamosActivos;
    final nombresPorPrestamo = <int, String>{};
    for (final prestamo in prestamos) {
      if (prestamo.id == null) continue;
      final cliente = provider.clientePorId(prestamo.clienteId);
      if (cliente != null) nombresPorPrestamo[prestamo.id!] = cliente.nombre;
    }
    await sincronizarAlertasCuotas(
      prestamos: prestamos,
      cuotas: provider.todasLasCuotas,
      nombresPorPrestamo: nombresPorPrestamo,
      alertasMora:
          ((configuracion[DbConstants.configuracionAlertasMora] as num?)
                  ?.toInt() ??
              1) !=
          0,
    );
    if (recordatorioDiario) {
      await programarNotificacionDiaria(
        hora: TimeOfDay(hour: int.parse(hora[0]), minute: int.parse(hora[1])),
        mensaje:
            'Revisa el recaudo, la ganancia y las cuotas pendientes de hoy.',
      );
    } else {
      await cancelarNotificacion(_notificacionDiariaId);
    }
  }

  Future<void> sincronizarAlertasCuotas({
    required Iterable<Prestamo> prestamos,
    required Iterable<Cuota> cuotas,
    required Map<int, String> nombresPorPrestamo,
    required bool alertasMora,
  }) async {
    await _asegurarInicializacion();
    final prestamosActivos = {
      for (final prestamo in prestamos)
        if (prestamo.id != null &&
            (prestamo.estado == 'ACTIVO' || prestamo.estado == 'MORA'))
          prestamo.id!,
    };
    final candidatas = <_AlertaCuotaPendiente>[];
    final ahora = tz.TZDateTime.now(tz.local);

    for (final cuota in cuotas) {
      final cuotaId = cuota.id;
      final nombreCliente = nombresPorPrestamo[cuota.prestamoId];
      final saldo = cuota.montoCuota - cuota.montoPagado;
      if (cuotaId == null ||
          !prestamosActivos.contains(cuota.prestamoId) ||
          nombreCliente == null ||
          cuota.estado == 'PAGADA' ||
          saldo <= 0) {
        continue;
      }

      final fechaVencimiento = _fechaALasOcho(cuota.fechaVencimiento);
      if (fechaVencimiento.isAfter(ahora)) {
        final id = _idCuota(cuotaId, 0);
        candidatas.add((
          id: id,
          fecha: fechaVencimiento,
          titulo: 'Cuota por vencer',
          mensaje: '$nombreCliente debe pagar ${_formatearPesos(saldo)} hoy.',
          payload: 'cuota:$cuotaId',
        ));
      }

      if (alertasMora) {
        final fechaMora = _fechaALasOcho(
          cuota.fechaVencimiento.add(const Duration(days: 3)),
        );
        if (fechaMora.isAfter(ahora)) {
          final id = _idCuota(cuotaId, 1);
          candidatas.add((
            id: id,
            fecha: fechaMora,
            titulo: 'Cuota en mora',
            mensaje: '$nombreCliente tiene una cuota vencida hace 3 días.',
            payload: 'mora:$cuotaId',
          ));
        }
      }
    }

    candidatas.sort((a, b) => a.fecha.compareTo(b.fecha));
    final seleccionadas = candidatas.take(_maxAlertasProgramadas).toList();
    final idsProgramados = seleccionadas.map((alerta) => alerta.id).toSet();
    final pendientes = await _plugin.pendingNotificationRequests();
    for (final pendiente in pendientes) {
      if (pendiente.id != _notificacionDiariaId &&
          !idsProgramados.contains(pendiente.id)) {
        await _plugin.cancel(id: pendiente.id);
      }
    }
    for (final alerta in seleccionadas) {
      await _programarCuota(
        id: alerta.id,
        fecha: alerta.fecha,
        titulo: alerta.titulo,
        mensaje: alerta.mensaje,
        payload: alerta.payload,
      );
    }
  }

  Future<void> programarNotificacionDiaria({
    required TimeOfDay hora,
    required String mensaje,
  }) async {
    await _asegurarInicializacion();
    final ahora = tz.TZDateTime.now(tz.local);
    var siguiente = tz.TZDateTime(
      tz.local,
      ahora.year,
      ahora.month,
      ahora.day,
      hora.hour,
      hora.minute,
    );
    if (!siguiente.isAfter(ahora)) {
      siguiente = siguiente.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: _notificacionDiariaId,
      title: 'Resumen diario',
      body: mensaje,
      scheduledDate: siguiente,
      notificationDetails: _detalles,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelarNotificacion(int id) async {
    await _plugin.cancel(id: id);
  }

  Future<void> cancelarTodas() async {
    await _plugin.cancelAll();
  }

  Future<void> _asegurarInicializacion() async {
    if (!_inicializado) await inicializarNotificaciones();
  }

  Future<void> _programarCuota({
    required int id,
    required tz.TZDateTime fecha,
    required String titulo,
    required String mensaje,
    required String payload,
  }) => _plugin.zonedSchedule(
    id: id,
    title: titulo,
    body: mensaje,
    scheduledDate: fecha,
    notificationDetails: _detalles,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    payload: payload,
  );

  NotificationDetails get _detalles => const NotificationDetails(
    android: AndroidNotificationDetails(
      _canalId,
      'Recordatorios de GotaControl',
      channelDescription: 'Vencimientos y resumen diario de cobros.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  tz.TZDateTime _fechaALasOcho(DateTime fecha) =>
      tz.TZDateTime(tz.local, fecha.year, fecha.month, fecha.day, 8);

  int _idCuota(int cuotaId, int tipo) => cuotaId * 2 + 10 + tipo;

  String _formatearPesos(double monto) => '\$${monto.toStringAsFixed(0)}';
}
