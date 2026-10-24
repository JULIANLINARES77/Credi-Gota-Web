import '../../core/utils/festivos_colombia.dart';
import '../../core/utils/moneda_colombiana.dart';

class ResultadoCalculoPrestamo {
  const ResultadoCalculoPrestamo({
    required this.montoInteres,
    required this.montoTotalPagar,
    required this.valorCuota,
    required this.valoresCuota,
    required this.gananciaDiariaPromedio,
  });

  final double montoInteres;
  final double montoTotalPagar;
  final double valorCuota;
  final List<double> valoresCuota;
  final double gananciaDiariaPromedio;

  double get valorCuotaMaxima => valoresCuota.reduce((a, b) => a > b ? a : b);
}

class CalculadoraService {
  const CalculadoraService();

  static const frecuenciaDiaria = 'DIARIA';
  static const frecuenciaSemanal = 'SEMANAL';
  static const frecuenciaQuincenal = 'QUINCENAL';
  static const frecuenciaMensual = 'MENSUAL';
  static const frecuenciaLunesMiercolesViernes = 'LUN_MIE_VIE';
  static const frecuenciaPersonalizada = 'PERSONALIZADA';

  ResultadoCalculoPrestamo calcularPrestamo({
    required double capital,
    required double porcentajeInteres,
    required int numCuotas,
  }) {
    if (!capital.isFinite || capital < 10000 || capital > 100000000) {
      throw ArgumentError.value(
        capital,
        'capital',
        'El capital debe estar entre 10000 y 100000000 COP.',
      );
    }
    if (!MonedaColombiana.esMultiploDeUnidad(capital)) {
      throw ArgumentError.value(
        capital,
        'capital',
        'El capital debe ser un múltiplo de \$1.000.',
      );
    }
    if (!porcentajeInteres.isFinite ||
        porcentajeInteres < 0 ||
        porcentajeInteres > 100) {
      throw ArgumentError.value(
        porcentajeInteres,
        'porcentajeInteres',
        'El interés debe estar entre 0% y 100%.',
      );
    }
    if (numCuotas < 1 || numCuotas > 365) {
      throw ArgumentError.value(
        numCuotas,
        'numCuotas',
        'El número de cuotas debe estar entre 1 y 365.',
      );
    }

    final montoInteres = MonedaColombiana.redondearAUnidad(
      capital * (porcentajeInteres / 100),
    );
    final montoTotalPagar = capital + montoInteres;
    final totalEnUnidades =
        (montoTotalPagar / MonedaColombiana.unidadNegociacion).round();
    if (numCuotas > totalEnUnidades) {
      throw ArgumentError.value(
        numCuotas,
        'numCuotas',
        'Cada cuota debe ser de al menos \$1.000.',
      );
    }
    final unidadesPorCuota = totalEnUnidades ~/ numCuotas;
    final unidadesAdicionales = totalEnUnidades % numCuotas;
    final valoresCuota = List<double>.unmodifiable([
      for (var indice = 0; indice < numCuotas; indice++)
        (unidadesPorCuota + (indice < unidadesAdicionales ? 1 : 0)) *
            MonedaColombiana.unidadNegociacion.toDouble(),
    ]);
    final valorCuota = valoresCuota.last;
    final gananciaDiariaPromedio = _redondearDosDecimales(
      montoInteres / numCuotas,
    );

    if (!montoInteres.isFinite || !montoTotalPagar.isFinite) {
      throw ArgumentError('El resultado del cálculo excede el rango válido.');
    }

    return ResultadoCalculoPrestamo(
      montoInteres: montoInteres,
      montoTotalPagar: montoTotalPagar,
      valorCuota: valorCuota,
      valoresCuota: valoresCuota,
      gananciaDiariaPromedio: gananciaDiariaPromedio,
    );
  }

  DateTime calcularFechaFin({
    required DateTime fechaInicio,
    required int numCuotas,
    required String frecuencia,
    List<int>? diasPersonalizados,
    bool saltarDomingos = false,
    bool? diasCorridos,
    bool? saltarFestivos,
  }) => generarFechasPago(
    fechaInicio: fechaInicio,
    numCuotas: numCuotas,
    frecuencia: frecuencia,
    diasPersonalizados: diasPersonalizados,
    saltarDomingos: saltarDomingos,
    diasCorridos: diasCorridos,
    saltarFestivos: saltarFestivos,
  ).last;

  double calcularGananciaProporcional({
    required double montoPagado,
    required double totalPagar,
    required double interesTotal,
  }) => _calcularProporcional(
    montoPagado: montoPagado,
    totalPagar: totalPagar,
    baseTotal: interesTotal,
    nombreBase: 'interesTotal',
  );

  double calcularCapitalRecuperado({
    required double montoPagado,
    required double totalPagar,
    required double capital,
  }) => _calcularProporcional(
    montoPagado: montoPagado,
    totalPagar: totalPagar,
    baseTotal: capital,
    nombreBase: 'capital',
  );

  List<DateTime> generarFechasPago({
    required DateTime fechaInicio,
    required int numCuotas,
    required String frecuencia,
    List<int>? diasPersonalizados,
    bool saltarDomingos = false,
    bool? diasCorridos,
    bool? saltarFestivos,
  }) {
    if (numCuotas <= 0) {
      throw ArgumentError.value(
        numCuotas,
        'numCuotas',
        'Debe ser mayor que cero.',
      );
    }

    final frecuenciaNormalizada = frecuencia.trim().toUpperCase();
    final diasPermitidos = switch (frecuenciaNormalizada) {
      frecuenciaLunesMiercolesViernes => const [
        DateTime.monday,
        DateTime.wednesday,
        DateTime.friday,
      ],
      frecuenciaPersonalizada => _validarDiasPersonalizados(diasPersonalizados),
      _ => null,
    };

    if (frecuenciaNormalizada != frecuenciaDiaria &&
        frecuenciaNormalizada != frecuenciaSemanal &&
        frecuenciaNormalizada != frecuenciaQuincenal &&
        frecuenciaNormalizada != frecuenciaMensual &&
        diasPermitidos == null) {
      throw ArgumentError.value(
        frecuencia,
        'frecuencia',
        'Frecuencia no válida.',
      );
    }

    final fechas = <DateTime>[];
    var fechaActual = fechaInicio;
    final diasCorridosEfectivos =
        diasCorridos ?? !(saltarDomingos || saltarFestivos == true);
    final saltarDomingosEfectivo = diasCorridos == null
        ? saltarDomingos
        : !diasCorridosEfectivos;
    final saltarFestivosEfectivo = diasCorridos == null
        ? saltarFestivos == true
        : !diasCorridosEfectivos;

    switch (frecuenciaNormalizada) {
      case frecuenciaDiaria:
        while (fechas.length < numCuotas) {
          final esFinDeSemana =
              fechaActual.weekday == DateTime.saturday ||
              fechaActual.weekday == DateTime.sunday;
          if ((!diasCorridosEfectivos && esFinDeSemana) ||
              (saltarDomingosEfectivo &&
                  fechaActual.weekday == DateTime.sunday)) {
            fechaActual = _sumarDiasCalendario(fechaActual, 1);
            continue;
          }
          fechas.add(fechaActual);
          fechaActual = _sumarDiasCalendario(fechaActual, 1);
        }
      case frecuenciaSemanal:
        for (var i = 0; i < numCuotas; i++) {
          fechas.add(fechaActual);
          fechaActual = _sumarDiasCalendario(fechaActual, 7);
        }
      case frecuenciaQuincenal:
        for (var i = 0; i < numCuotas; i++) {
          fechas.add(fechaActual);
          fechaActual = _sumarDiasCalendario(fechaActual, 15);
        }
      case frecuenciaMensual:
        fechas.add(fechaInicio);
        for (var indice = 1; indice < numCuotas; indice++) {
          fechaActual = _sumarMesesDesde(fechaInicio, indice);
          fechas.add(fechaActual);
        }
      case frecuenciaLunesMiercolesViernes:
      case frecuenciaPersonalizada:
        for (var i = 0; i < numCuotas; i++) {
          fechaActual = _primerDiaHabilDesde(fechaActual, diasPermitidos!);
          fechas.add(fechaActual);
          fechaActual = _sumarDiasCalendario(fechaActual, 1);
        }
    }

    if (!saltarFestivosEfectivo) return fechas;

    final fechasAjustadas = <DateTime>[];
    for (final fecha in fechas) {
      var fechaAjustada = fecha;
      while ((diasCorridos == false
              ? fechaAjustada.weekday == DateTime.saturday ||
                    fechaAjustada.weekday == DateTime.sunday
              : fechaAjustada.weekday == DateTime.sunday) ||
          FestivosColombia.esFestivo(fechaAjustada) ||
          (fechasAjustadas.isNotEmpty &&
              !fechaAjustada.isAfter(fechasAjustadas.last))) {
        fechaAjustada = _sumarDiasCalendario(fechaAjustada, 1);
      }
      fechasAjustadas.add(fechaAjustada);
    }

    return fechasAjustadas;
  }

  List<int> _validarDiasPersonalizados(List<int>? dias) {
    if (dias == null || dias.isEmpty) {
      throw ArgumentError.value(
        dias,
        'diasPersonalizados',
        'Debe incluir al menos un día de la semana.',
      );
    }
    if (dias.any((dia) => dia < DateTime.monday || dia > DateTime.sunday)) {
      throw ArgumentError.value(
        dias,
        'diasPersonalizados',
        'Los días deben estar entre 1 (lunes) y 7 (domingo).',
      );
    }
    return dias.toSet().toList()..sort();
  }

  DateTime _primerDiaHabilDesde(DateTime fecha, List<int> diasPermitidos) {
    var candidato = fecha;
    while (!diasPermitidos.contains(candidato.weekday)) {
      candidato = _sumarDiasCalendario(candidato, 1);
    }
    return candidato;
  }

  DateTime _sumarDiasCalendario(DateTime fecha, int dias) {
    if (fecha.isUtc) {
      return DateTime.utc(
        fecha.year,
        fecha.month,
        fecha.day + dias,
        fecha.hour,
        fecha.minute,
        fecha.second,
        fecha.millisecond,
        fecha.microsecond,
      );
    }

    return DateTime(
      fecha.year,
      fecha.month,
      fecha.day + dias,
      fecha.hour,
      fecha.minute,
      fecha.second,
      fecha.millisecond,
      fecha.microsecond,
    );
  }

  DateTime _sumarMesesDesde(DateTime fecha, int meses) {
    final mesAbsoluto = fecha.month - 1 + meses;
    final anio = fecha.year + mesAbsoluto ~/ 12;
    final mes = mesAbsoluto % 12 + 1;
    final ultimoDia = DateTime(anio, mes + 1, 0).day;
    final dia = fecha.day > ultimoDia ? ultimoDia : fecha.day;
    if (fecha.isUtc) {
      return DateTime.utc(
        anio,
        mes,
        dia,
        fecha.hour,
        fecha.minute,
        fecha.second,
        fecha.millisecond,
        fecha.microsecond,
      );
    }
    return DateTime(
      anio,
      mes,
      dia,
      fecha.hour,
      fecha.minute,
      fecha.second,
      fecha.millisecond,
      fecha.microsecond,
    );
  }

  double _redondearDosDecimales(double valor) =>
      (valor * 100).roundToDouble() / 100;

  double _calcularProporcional({
    required double montoPagado,
    required double totalPagar,
    required double baseTotal,
    required String nombreBase,
  }) {
    if (!montoPagado.isFinite || montoPagado < 0) {
      throw ArgumentError.value(
        montoPagado,
        'montoPagado',
        'Debe ser un valor finito no negativo.',
      );
    }
    if (!totalPagar.isFinite || totalPagar <= 0) {
      throw ArgumentError.value(
        totalPagar,
        'totalPagar',
        'Debe ser mayor que cero.',
      );
    }
    if (!baseTotal.isFinite || baseTotal < 0) {
      throw ArgumentError.value(
        baseTotal,
        nombreBase,
        'Debe ser un valor finito no negativo.',
      );
    }
    return montoPagado / totalPagar * baseTotal;
  }
}
