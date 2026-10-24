import 'package:flutter/foundation.dart';

import '../../core/constants/db_constants.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/cliente.dart';
import '../../data/models/cuota.dart';
import '../../data/models/pago.dart';
import '../../data/models/prestamo.dart';
import '../services/calculadora_service.dart';
import '../services/mora_service.dart';
import '../services/ajustes_negocio_validator.dart';
import '../services/pin_hash_service.dart';

class GotaProvider extends ChangeNotifier {
  GotaProvider({
    DatabaseHelper? databaseHelper,
    this._calculadora = const CalculadoraService(),
    this._pinHashService = const PinHashService(),
    DateTime Function()? reloj,
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
       _reloj = reloj ?? DateTime.now;

  final DatabaseHelper _databaseHelper;
  final CalculadoraService _calculadora;
  final PinHashService _pinHashService;
  final DateTime Function() _reloj;

  List<Cliente> _clientes = [];
  List<Prestamo> _prestamos = [];
  Map<int, List<Cuota>> _cuotasPorPrestamo = {};
  List<Pago> _pagosHoy = [];
  List<Pago> _pagos = [];
  Map<String, dynamic> _resumenDashboard = {};
  Map<String, Object?>? _configuracion;
  List<PrestamoEnMora> _moras = [];
  bool cargando = true;
  String? errorCarga;
  String? avisoRespaldoInicio;

  bool _disposed = false;
  bool _sincronizandoMora = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  void mostrarAvisoRespaldoInicio(String mensaje) {
    avisoRespaldoInicio = mensaje;
    _safeNotify();
  }

  List<Cliente> get clientes =>
      List.unmodifiable(_clientes.where((cliente) => cliente.activo));

  List<Cliente> get clientesRegistrados => List.unmodifiable(_clientes);

  List<Prestamo> get prestamos => List.unmodifiable(_prestamos);

  List<Prestamo> get prestamosActivos => List.unmodifiable(
    _prestamos.where(
      (prestamo) => prestamo.estado == 'ACTIVO' || prestamo.estado == 'MORA',
    ),
  );

  List<Pago> get pagos => List.unmodifiable(_pagos);
  List<Pago> get pagosHoy => List.unmodifiable(_pagosHoy);
  Map<String, dynamic> get resumenDashboard =>
      Map.unmodifiable(_resumenDashboard);
  Map<String, Object?>? get configuracion =>
      _configuracion == null ? null : Map.unmodifiable(_configuracion!);
  bool get pinActivo {
    final hash = _configuracion?[DbConstants.configuracionPinHash] as String?;
    return hash != null && hash.isNotEmpty;
  }

  List<PrestamoEnMora> get moras => List.unmodifiable(_moras);

  double get totalEnCalle => _valorDouble(_resumenDashboard['total_en_calle']);
  double get recaudadoHoy => _valorDouble(_resumenDashboard['recaudo_hoy']);
  double get gananciaHoy => _valorDouble(_resumenDashboard['ganancia_hoy']);
  int get clientesActivos => clientes.length;
  int get clientesEnMora =>
      _moras.map((mora) => mora.cliente.id).toSet().length;

  List<Cuota> get cuotasDeHoy {
    final hoy = _soloFecha(_reloj());
    return List.unmodifiable(
      _cuotasPorPrestamo.values.expand((cuotas) => cuotas).where((cuota) {
        final estadoPrestamo = _prestamoPorId(cuota.prestamoId)?.estado;
        return cuota.estado != 'PAGADA' &&
            _mismaFecha(cuota.fechaVencimiento, hoy) &&
            (estadoPrestamo == 'ACTIVO' || estadoPrestamo == 'MORA');
      }),
    );
  }

  List<Cuota> get todasLasCuotas =>
      List.unmodifiable(_cuotasPorPrestamo.values.expand((cuotas) => cuotas));

  Future<void> cargarDatos({bool mostrarCarga = true}) async {
    if (mostrarCarga) cargando = true;
    errorCarga = null;
    if (mostrarCarga) _safeNotify();

    try {
      final clientes = await _databaseHelper.obtenerTodosLosClientes();
      final prestamosActivos = await _databaseHelper.obtenerPrestamosActivos();
      final prestamosPorId = <int, Prestamo>{
        for (final prestamo in prestamosActivos)
          if (prestamo.id != null) prestamo.id!: prestamo,
      };

      for (final cliente in clientes) {
        if (cliente.id == null) continue;
        final prestamosCliente = await _databaseHelper
            .obtenerPrestamosPorCliente(cliente.id!);
        for (final prestamo in prestamosCliente) {
          if (prestamo.id != null) prestamosPorId[prestamo.id!] = prestamo;
        }
      }

      final prestamos = prestamosPorId.values.toList()
        ..sort((a, b) => b.fechaInicio.compareTo(a.fechaInicio));
      final cuotasPorPrestamo = <int, List<Cuota>>{};
      final pagosPorId = <int, Pago>{};

      for (final prestamo in prestamos) {
        final id = prestamo.id;
        if (id == null) continue;
        cuotasPorPrestamo[id] = await _databaseHelper.obtenerCuotasPorPrestamo(
          id,
        );
        for (final pago in await _databaseHelper.obtenerPagosPorPrestamo(id)) {
          if (pago.id != null) pagosPorId[pago.id!] = pago;
        }
      }

      final pagosHoy = await _databaseHelper.obtenerPagosDelDia(_reloj());
      for (final pago in pagosHoy) {
        if (pago.id != null) pagosPorId[pago.id!] = pago;
      }

      final resumen = await _databaseHelper.obtenerResumenDashboard();
      resumen['ganancia_hoy'] = pagosHoy.fold<double>(0, (total, pago) {
        final prestamo = prestamosPorId[pago.prestamoId];
        final cuota = (cuotasPorPrestamo[pago.prestamoId] ?? const <Cuota>[])
            .where((item) => item.id == pago.cuotaId)
            .firstOrNull;
        if (prestamo == null || cuota?.esPenalizacion == true) return total;
        return total +
            _calculadora.calcularGananciaProporcional(
              montoPagado: pago.monto,
              totalPagar: prestamo.montoTotalPagar,
              interesTotal: prestamo.montoInteres,
            );
      });
      final configuracion = await _databaseHelper.obtenerConfiguracion();
      final clientesPorId = {
        for (final cliente in clientes)
          if (cliente.id != null) cliente.id!: cliente,
      };
      final moras = _construirMoras(
        prestamos: prestamos,
        clientesPorId: clientesPorId,
        cuotasPorPrestamo: cuotasPorPrestamo,
      );

      _clientes = clientes;
      _prestamos = prestamos;
      _cuotasPorPrestamo = cuotasPorPrestamo;
      _pagosHoy = pagosHoy;
      _pagos = pagosPorId.values.toList()
        ..sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
      _resumenDashboard = resumen;
      _configuracion = configuracion;
      _moras = moras;

      if (!_sincronizandoMora) {
        _sincronizandoMora = true;
        try {
          var moraAplicada = false;
          final servicio = MoraService(
            databaseHelper: _databaseHelper,
            reloj: _reloj,
          );
          for (final prestamo in prestamos) {
            final id = prestamo.id;
            if (id == null ||
                (prestamo.estado != 'ACTIVO' && prestamo.estado != 'MORA')) {
              continue;
            }
            for (final cuota in cuotasPorPrestamo[id] ?? const <Cuota>[]) {
              if (cuota.estado == 'PAGADA' ||
                  !_soloFecha(
                    cuota.fechaVencimiento,
                  ).isBefore(_soloFecha(_reloj()))) {
                continue;
              }
              final aplicado = await servicio.aplicarMoraCuota(
                prestamo: prestamo,
                cuota: cuota,
                fechaReferencia: _reloj(),
              );
              moraAplicada = moraAplicada || aplicado > 0;
            }
          }
          if (moraAplicada) {
            await cargarDatos(mostrarCarga: false);
            return;
          }
        } finally {
          _sincronizandoMora = false;
        }
      }
    } on Object catch (error, stackTrace) {
      errorCarga = error.toString();
      debugPrint('GotaControl: error cargando SQLite: $error\n$stackTrace');
    } finally {
      if (mostrarCarga) cargando = false;
      _safeNotify();
    }
  }

  Future<Cliente> agregarCliente({
    required String nombre,
    required String telefono,
    String? cedula,
    String? direccion,
  }) async {
    final nombreLimpio = nombre.trim();
    final telefonoLimpio = telefono.trim();
    final cedulaLimpia = cedula?.trim();
    final direccionLimpia = direccion?.trim();

    if (nombreLimpio.isEmpty || telefonoLimpio.isEmpty) {
      throw ArgumentError('Nombre y teléfono son obligatorios.');
    }

    final nuevoCliente = Cliente(
      nombre: nombreLimpio,
      telefono: telefonoLimpio,
      cedula: _textoOpcional(cedulaLimpia),
      direccion: _textoOpcional(direccionLimpia),
      fechaRegistro: _reloj(),
    );

    try {
      final clienteId = await _databaseHelper.insertarCliente(nuevoCliente);
      await cargarDatos();
      return nuevoCliente.copyWith(id: clienteId);
    } on Object catch (error, stackTrace) {
      debugPrint('GotaControl: error al insertar cliente: $error\n$stackTrace');
      errorCarga = _mensajeAmigable('No se pudo guardar el cliente', error);
      _safeNotify();
      rethrow;
    }
  }

  Future<Cliente> actualizarCliente({
    required Cliente cliente,
    required String nombre,
    required String telefono,
    String? cedula,
    String? direccion,
  }) async {
    if (cliente.id == null) {
      throw ArgumentError('El cliente debe tener un identificador.');
    }
    final nombreLimpio = nombre.trim();
    final telefonoLimpio = telefono.trim();
    if (nombreLimpio.isEmpty || telefonoLimpio.isEmpty) {
      throw ArgumentError('Nombre y teléfono son obligatorios.');
    }

    final clienteActualizado = Cliente(
      id: cliente.id,
      nombre: nombreLimpio,
      telefono: telefonoLimpio,
      cedula: _textoOpcional(cedula),
      direccion: _textoOpcional(direccion),
      fotoPath: cliente.fotoPath,
      notas: cliente.notas,
      fechaRegistro: cliente.fechaRegistro,
      activo: cliente.activo,
    );
    try {
      final filasActualizadas = await _databaseHelper.actualizarCliente(
        clienteActualizado,
      );
      if (filasActualizadas != 1) {
        throw StateError('No se encontró el cliente que deseas actualizar.');
      }
      await cargarDatos();
      return clienteActualizado;
    } on Object catch (error, stackTrace) {
      debugPrint(
        'GotaControl: error al actualizar cliente: $error\n$stackTrace',
      );
      errorCarga = _mensajeAmigable('No se pudo actualizar el cliente', error);
      _safeNotify();
      rethrow;
    }
  }

  Future<void> eliminarCliente(int id) async {
    try {
      await _databaseHelper.eliminarCliente(id);
    } on Object catch (error, stackTrace) {
      debugPrint('GotaControl: error al eliminar cliente: $error\n$stackTrace');
      errorCarga = _mensajeAmigable('No se pudo eliminar el cliente', error);
      _safeNotify();
      rethrow;
    }
    await cargarDatos();
  }

  Future<bool> clienteEstaPazYSalvo(int clienteId) =>
      _databaseHelper.clienteEstaPazYSalvo(clienteId);

  static String? _textoOpcional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> configurarPin(String pin) async {
    final hash = await _pinHashService.hash(pin);
    await _databaseHelper.guardarHashPin(hash);
    _configuracion = await _databaseHelper.obtenerConfiguracion();
    errorCarga = null;
    _safeNotify();
  }

  Future<void> desactivarPin() async {
    await _databaseHelper.guardarHashPin(null);
    _configuracion = await _databaseHelper.obtenerConfiguracion();
    errorCarga = null;
    _safeNotify();
  }

  Future<PinValidationResult> validarPin(String pin) async {
    final configuracion =
        _configuracion ?? await _databaseHelper.obtenerConfiguracion();
    final hash = configuracion?[DbConstants.configuracionPinHash] as String?;
    if (hash == null || hash.isEmpty) return PinValidationResult.invalid;

    final lockUntilValue =
        configuracion?[DbConstants.configuracionPinBloqueadoHasta] as num?;
    final lockUntil = lockUntilValue == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lockUntilValue.toInt());
    final ahora = _reloj();
    if (lockUntil != null && lockUntil.isAfter(ahora)) {
      return PinValidationResult.locked;
    }

    if (await _pinHashService.verify(pin, hash)) {
      await _databaseHelper.guardarIntentosFallidosPin(intentos: 0);
      _configuracion = await _databaseHelper.obtenerConfiguracion();
      _safeNotify();
      return PinValidationResult.valid;
    }

    final intentosActuales =
        (configuracion?[DbConstants.configuracionPinIntentosFallidos] as num?)
            ?.toInt() ??
        0;
    final intentos = intentosActuales + 1;
    final bloqueado = intentos >= 5;
    await _databaseHelper.guardarIntentosFallidosPin(
      intentos: bloqueado ? 0 : intentos,
      bloqueadoHasta: bloqueado ? ahora.add(const Duration(seconds: 30)) : null,
    );
    _configuracion = await _databaseHelper.obtenerConfiguracion();
    _safeNotify();
    return bloqueado ? PinValidationResult.locked : PinValidationResult.invalid;
  }

  Duration? get tiempoBloqueoPin {
    final timestamp =
        _configuracion?[DbConstants.configuracionPinBloqueadoHasta] as num?;
    if (timestamp == null) return null;
    final restante = DateTime.fromMillisecondsSinceEpoch(
      timestamp.toInt(),
    ).difference(_reloj());
    return restante.isNegative || restante == Duration.zero ? null : restante;
  }

  Future<void> guardarConfiguracion(Map<String, Object?> cambios) async {
    const camposValidados = {
      DbConstants.configuracionNombreNegocio,
      DbConstants.configuracionTelefonoNegocio,
      DbConstants.configuracionDireccionNegocio,
      DbConstants.configuracionPorcentajeMora,
      DbConstants.configuracionDiasGraciaMora,
      DbConstants.configuracionMoraDiariaDiasGracia,
      DbConstants.configuracionMoraDiariaTipoRecargo,
      DbConstants.configuracionMoraDiariaValorRecargo,
      DbConstants.configuracionMoraDiariaRecargoAcumulable,
      DbConstants.configuracionMoraSemanalDiasGracia,
      DbConstants.configuracionMoraSemanalTipoRecargo,
      DbConstants.configuracionMoraSemanalValorRecargo,
      DbConstants.configuracionMoraSemanalRecargoAcumulable,
      DbConstants.configuracionMoraQuincenalDiasGracia,
      DbConstants.configuracionMoraQuincenalTipoRecargo,
      DbConstants.configuracionMoraQuincenalValorRecargo,
      DbConstants.configuracionMoraQuincenalRecargoAcumulable,
      DbConstants.configuracionMoraMensualDiasGracia,
      DbConstants.configuracionMoraMensualTipoRecargo,
      DbConstants.configuracionMoraMensualValorRecargo,
      DbConstants.configuracionMoraMensualRecargoAcumulable,
    };
    if (cambios.keys.any(camposValidados.contains)) {
      final configuracionActual =
          _configuracion ?? await _databaseHelper.obtenerConfiguracion() ?? {};
      AjustesNegocioValidator.validar({...configuracionActual, ...cambios});
    }
    await _databaseHelper.guardarConfiguracion(cambios);
    _configuracion = await _databaseHelper.obtenerConfiguracion();
    errorCarga = null;
    _safeNotify();
  }

  Future<Prestamo> crearPrestamo({
    required int clienteId,
    required double capital,
    required double porcentajeInteres,
    required int numCuotas,
    required String frecuencia,
    List<int>? diasPersonalizados,
    DateTime? fechaInicio,
    bool diasCorridos = true,
    bool? saltarFestivos,
  }) async {
    final cliente = clientePorId(clienteId);
    if (cliente == null || !cliente.activo) {
      throw StateError('Selecciona un cliente activo.');
    }

    final calculo = _calculadora.calcularPrestamo(
      capital: capital,
      porcentajeInteres: porcentajeInteres,
      numCuotas: numCuotas,
    );
    final configuracion =
        _configuracion ?? await _databaseHelper.obtenerConfiguracion() ?? {};
    final mora = _reglaMoraFrecuencia(frecuencia, configuracion);
    final fechaInicioEfectiva = _soloFecha(fechaInicio ?? _reloj());
    final diasCorridosEfectivos = saltarFestivos == null
        ? diasCorridos
        : !saltarFestivos;
    final fechas = _calculadora.generarFechasPago(
      fechaInicio: fechaInicioEfectiva,
      numCuotas: numCuotas,
      frecuencia: frecuencia,
      diasPersonalizados: diasPersonalizados,
      diasCorridos: diasCorridosEfectivos,
    );
    final prestamo = Prestamo(
      clienteId: clienteId,
      montoCapital: capital,
      porcentajeInteres: porcentajeInteres,
      montoInteres: calculo.montoInteres,
      montoTotalPagar: calculo.montoTotalPagar,
      numCuotas: numCuotas,
      valorCuota: calculo.valorCuota,
      frecuencia: frecuencia,
      diasPersonalizados: diasPersonalizados?.join(','),
      diasCorridos: diasCorridosEfectivos,
      diasGraciaMora: mora.diasGracia,
      tipoRecargoMora: mora.tipoRecargo,
      valorRecargoMora: mora.valorRecargo,
      recargoAcumulable: mora.acumulable,
      fechaInicio: fechaInicioEfectiva,
      fechaFinEstimada: fechas.last,
      estado: 'ACTIVO',
      saldoPendiente: calculo.montoTotalPagar,
      totalPagado: 0,
      createdAt: _reloj(),
    );
    final cuotas = [
      for (var indice = 0; indice < fechas.length; indice++)
        Cuota(
          prestamoId: 0,
          numeroCuota: indice + 1,
          fechaVencimiento: fechas[indice],
          montoCuota: calculo.valoresCuota[indice],
        ),
    ];

    try {
      final prestamoId = await _databaseHelper.crearPrestamoConCuotas(
        prestamo,
        cuotas,
      );
      await cargarDatos();
      return _prestamoPorId(prestamoId) ?? prestamo.copyWith(id: prestamoId);
    } on Object catch (error, stackTrace) {
      debugPrint('GotaControl: error al crear préstamo: $error\n$stackTrace');
      errorCarga = _mensajeAmigable('No se pudo crear el préstamo', error);
      _safeNotify();
      rethrow;
    }
  }

  _ReglaMora _reglaMoraFrecuencia(
    String frecuencia,
    Map<String, Object?> configuracion,
  ) {
    final prefijo = switch (frecuencia.trim().toUpperCase()) {
      CalculadoraService.frecuenciaDiaria => 'diaria',
      CalculadoraService.frecuenciaSemanal => 'semanal',
      CalculadoraService.frecuenciaQuincenal => 'quincenal',
      CalculadoraService.frecuenciaMensual => 'mensual',
      CalculadoraService.frecuenciaLunesMiercolesViernes ||
      CalculadoraService.frecuenciaPersonalizada => 'diaria',
      final otra => throw ArgumentError.value(
        otra,
        'frecuencia',
        'Frecuencia de mora no válida.',
      ),
    };
    final frecuenciaKeys = switch (prefijo) {
      'diaria' => (
        DbConstants.configuracionMoraDiariaDiasGracia,
        DbConstants.configuracionMoraDiariaTipoRecargo,
        DbConstants.configuracionMoraDiariaValorRecargo,
        DbConstants.configuracionMoraDiariaRecargoAcumulable,
        DbConstants.configuracionMoraDiariaHabilitada,
      ),
      'semanal' => (
        DbConstants.configuracionMoraSemanalDiasGracia,
        DbConstants.configuracionMoraSemanalTipoRecargo,
        DbConstants.configuracionMoraSemanalValorRecargo,
        DbConstants.configuracionMoraSemanalRecargoAcumulable,
        DbConstants.configuracionMoraSemanalHabilitada,
      ),
      'quincenal' => (
        DbConstants.configuracionMoraQuincenalDiasGracia,
        DbConstants.configuracionMoraQuincenalTipoRecargo,
        DbConstants.configuracionMoraQuincenalValorRecargo,
        DbConstants.configuracionMoraQuincenalRecargoAcumulable,
        DbConstants.configuracionMoraQuincenalHabilitada,
      ),
      _ => (
        DbConstants.configuracionMoraMensualDiasGracia,
        DbConstants.configuracionMoraMensualTipoRecargo,
        DbConstants.configuracionMoraMensualValorRecargo,
        DbConstants.configuracionMoraMensualRecargoAcumulable,
        DbConstants.configuracionMoraMensualHabilitada,
      ),
    };
    final habilitada =
        ((configuracion[frecuenciaKeys.$5] as num?)?.toInt() ?? 1) != 0;
    final regla = _ReglaMora(
      diasGracia: habilitada
          ? (configuracion[frecuenciaKeys.$1] as num?)?.toInt() ??
                (configuracion[DbConstants.configuracionDiasGraciaMora] as num?)
                    ?.toInt() ??
                3
          : 0,
      tipoRecargo: configuracion[frecuenciaKeys.$2] as String? ?? 'PORCENTAJE',
      valorRecargo: habilitada
          ? (configuracion[frecuenciaKeys.$3] as num?)?.toDouble() ??
                (configuracion[DbConstants.configuracionPorcentajeMora] as num?)
                    ?.toDouble() ??
                10
          : 0,
      acumulable:
          ((configuracion[frecuenciaKeys.$4] as num?)?.toInt() ?? 0) != 0,
      habilitada: habilitada,
    );
    if (regla.diasGracia < 0 ||
        !regla.valorRecargo.isFinite ||
        regla.valorRecargo < 0 ||
        !const {'PORCENTAJE', 'MONTO_FIJO'}.contains(regla.tipoRecargo)) {
      throw StateError('La regla de mora configurada no es válida.');
    }
    return regla;
  }

  Future<double> aplicarMoraCuota({
    required int prestamoId,
    required int cuotaId,
    DateTime? fechaReferencia,
  }) async {
    final prestamo = _prestamoPorId(prestamoId);
    Cuota? cuota;
    for (final item in _cuotasPorPrestamo[prestamoId] ?? const <Cuota>[]) {
      if (item.id == cuotaId) {
        cuota = item;
        break;
      }
    }
    if (prestamo == null || cuota == null) {
      throw StateError('No se encontró el préstamo o la cuota.');
    }

    final servicio = MoraService(
      databaseHelper: _databaseHelper,
      reloj: _reloj,
    );
    final aplicado = await servicio.aplicarMoraCuota(
      prestamo: prestamo,
      cuota: cuota,
      fechaReferencia: fechaReferencia,
    );
    if (aplicado > 0) {
      final cuotas = _cuotasPorPrestamo[prestamoId]!;
      final indiceCuota = cuotas.indexWhere((item) => item.id == cuotaId);
      if (indiceCuota >= 0) {
        _cuotasPorPrestamo[prestamoId] = [
          ...cuotas.take(indiceCuota),
          cuota.copyWith(
            montoCuota: cuota.montoCuota + aplicado,
            montoPenalizacion: cuota.montoPenalizacion + aplicado,
          ),
          ...cuotas.skip(indiceCuota + 1),
        ];
      }
      final indicePrestamo = _prestamos.indexWhere(
        (item) => item.id == prestamoId,
      );
      if (indicePrestamo >= 0) {
        _prestamos[indicePrestamo] = prestamo.copyWith(
          montoTotalPagar: prestamo.montoTotalPagar + aplicado,
          saldoPendiente: prestamo.saldoPendiente + aplicado,
          estado: 'MORA',
        );
      }
      _moras = _construirMoras(
        prestamos: _prestamos,
        clientesPorId: {
          for (final cliente in _clientes)
            if (cliente.id != null) cliente.id!: cliente,
        },
        cuotasPorPrestamo: _cuotasPorPrestamo,
      );
      _safeNotify();
    }
    return aplicado;
  }

  Future<Map<String, Object?>> obtenerEstadisticasPrestamos() =>
      _databaseHelper.obtenerEstadisticasPrestamos();

  Future<Pago> registrarPago({
    required int prestamoId,
    required int cuotaId,
    required double monto,
    required String metodoPago,
    required DateTime fecha,
    String? nota,
  }) async {
    final prestamo = _prestamoPorId(prestamoId);
    if (prestamo == null || prestamo.id == null) {
      throw StateError('No se encontró el préstamo.');
    }

    final cliente = clientePorId(prestamo.clienteId);
    if (cliente == null || cliente.id == null) {
      throw StateError('No se encontró el cliente del préstamo.');
    }
    final pago = Pago(
      cuotaId: cuotaId,
      prestamoId: prestamoId,
      clienteId: cliente.id!,
      monto: monto,
      fechaHora: fecha,
      metodoPago: metodoPago,
      nota: nota,
      registradoPor: 'App',
    );

    try {
      final pagoId = await _databaseHelper.registrarPago(pago);
      final pagoRegistrado = pago.copyWith(id: pagoId);
      _actualizarPagoEnMemoria(pagoRegistrado, prestamo);
      _safeNotify();
      return pagoRegistrado;
    } on Object catch (error, stackTrace) {
      debugPrint('GotaControl: error al registrar pago: $error\n$stackTrace');
      rethrow;
    }
  }

  void _actualizarPagoEnMemoria(Pago pago, Prestamo prestamo) {
    final cuotas = _cuotasPorPrestamo[pago.prestamoId];
    final indiceCuota = cuotas?.indexWhere((cuota) => cuota.id == pago.cuotaId);
    final pagoTotalCuota =
        cuotas != null && indiceCuota != null && indiceCuota >= 0
        ? cuotas[indiceCuota].montoPagado + pago.monto
        : null;

    if (cuotas != null && indiceCuota != null && indiceCuota >= 0) {
      final cuota = cuotas[indiceCuota];
      final quedaPagada = cuota.montoCuota - pagoTotalCuota! <= 0.000001;
      _cuotasPorPrestamo[pago.prestamoId] = [
        ...cuotas.take(indiceCuota),
        cuota.copyWith(
          montoPagado: pagoTotalCuota,
          fechaPago: quedaPagada ? pago.fechaHora : null,
          estado: quedaPagada ? 'PAGADA' : 'PARCIAL',
        ),
        ...cuotas.skip(indiceCuota + 1),
      ];
    }

    final saldoPendiente = (prestamo.saldoPendiente - pago.monto).clamp(
      0.0,
      double.infinity,
    );
    final tieneMora = (_cuotasPorPrestamo[pago.prestamoId] ?? const <Cuota>[])
        .any(
          (cuota) =>
              cuota.estado != 'PAGADA' &&
              _soloFecha(
                cuota.fechaVencimiento,
              ).isBefore(_soloFecha(DateTime.now())),
        );
    final indicePrestamo = _prestamos.indexWhere(
      (item) => item.id == pago.prestamoId,
    );
    final prestamoActualizado = prestamo.copyWith(
      saldoPendiente: saldoPendiente,
      totalPagado: prestamo.totalPagado + pago.monto,
      estado: saldoPendiente <= 0.000001
          ? 'PAGADO'
          : tieneMora
          ? 'MORA'
          : 'ACTIVO',
    );
    if (indicePrestamo >= 0) _prestamos[indicePrestamo] = prestamoActualizado;

    _pagos
      ..add(pago)
      ..sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    if (_mismaFecha(pago.fechaHora, _reloj())) {
      _pagosHoy
        ..add(pago)
        ..sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    }
    _moras = _construirMoras(
      prestamos: _prestamos,
      clientesPorId: {
        for (final cliente in _clientes)
          if (cliente.id != null) cliente.id!: cliente,
      },
      cuotasPorPrestamo: _cuotasPorPrestamo,
    );
  }

  Cliente? clientePorId(int id) {
    for (final cliente in _clientes) {
      if (cliente.id == id) return cliente;
    }
    return null;
  }

  Prestamo? prestamoPorId(int id) => _prestamoPorId(id);

  List<Prestamo> prestamosDeCliente(int clienteId) => List.unmodifiable(
    _prestamos.where((prestamo) => prestamo.clienteId == clienteId),
  );

  List<Cuota> cuotasDePrestamo(int prestamoId) =>
      List.unmodifiable(_cuotasPorPrestamo[prestamoId] ?? const <Cuota>[]);

  List<Pago> pagosDePrestamo(int prestamoId) =>
      List.unmodifiable(_pagos.where((pago) => pago.prestamoId == prestamoId));

  Prestamo? _prestamoPorId(int id) {
    for (final prestamo in _prestamos) {
      if (prestamo.id == id) return prestamo;
    }
    return null;
  }

  List<PrestamoEnMora> _construirMoras({
    required List<Prestamo> prestamos,
    required Map<int, Cliente> clientesPorId,
    required Map<int, List<Cuota>> cuotasPorPrestamo,
  }) {
    final hoy = _soloFecha(_reloj());
    final moras = <PrestamoEnMora>[];
    for (final prestamo in prestamos) {
      if (prestamo.id == null ||
          (prestamo.estado != 'ACTIVO' && prestamo.estado != 'MORA')) {
        continue;
      }
      final cliente = clientesPorId[prestamo.clienteId];
      if (cliente == null) continue;
      final cuotasAtrasadas =
          (cuotasPorPrestamo[prestamo.id] ?? const <Cuota>[])
              .where(
                (cuota) =>
                    cuota.estado != 'PAGADA' &&
                    _soloFecha(cuota.fechaVencimiento).isBefore(hoy),
              )
              .toList();
      if (cuotasAtrasadas.isEmpty) continue;
      final diasAtraso = cuotasAtrasadas
          .map(
            (cuota) =>
                hoy.difference(_soloFecha(cuota.fechaVencimiento)).inDays,
          )
          .reduce((a, b) => a > b ? a : b);
      moras.add(
        PrestamoEnMora(
          prestamo: prestamo,
          cliente: cliente,
          cuotasAtrasadas: cuotasAtrasadas,
          diasAtraso: diasAtraso,
        ),
      );
    }
    moras.sort((a, b) => b.diasAtraso.compareTo(a.diasAtraso));
    return moras;
  }

  static DateTime _soloFecha(DateTime fecha) =>
      DateTime(fecha.year, fecha.month, fecha.day);

  static bool _mismaFecha(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static double _valorDouble(Object? valor) => (valor as num?)?.toDouble() ?? 0;

  static String _mensajeAmigable(String prefijo, Object error) {
    final texto = error.toString();
    if (texto.contains('UNIQUE constraint failed')) {
      if (texto.contains('cedula')) {
        return 'Ya existe un cliente con esa cédula.';
      }
      return 'Ya existe un registro con esos datos.';
    }
    if (texto.contains('FOREIGN KEY constraint failed')) {
      return 'No se puede completar: hay una referencia inválida.';
    }
    if (texto.contains('database is locked')) {
      return 'La base de datos está ocupada. Intenta de nuevo.';
    }
    if (texto.contains('no such table')) {
      return 'La base de datos no está inicializada correctamente.';
    }
    return '$prefijo: $texto';
  }
}

class _ReglaMora {
  const _ReglaMora({
    required this.diasGracia,
    required this.tipoRecargo,
    required this.valorRecargo,
    required this.acumulable,
    required this.habilitada,
  });

  final int diasGracia;
  final String tipoRecargo;
  final double valorRecargo;
  final bool acumulable;
  final bool habilitada;
}
