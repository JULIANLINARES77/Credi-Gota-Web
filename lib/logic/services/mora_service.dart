import '../../core/constants/db_constants.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/cliente.dart';
import '../../data/models/cuota.dart';
import '../../data/models/prestamo.dart';
import '../../core/utils/moneda_colombiana.dart';
import 'calculadora_service.dart';

class PrestamoEnMora {
  const PrestamoEnMora({
    required this.prestamo,
    required this.cliente,
    required this.cuotasAtrasadas,
    required this.diasAtraso,
  });

  final Prestamo prestamo;
  final Cliente cliente;
  final List<Cuota> cuotasAtrasadas;
  final int diasAtraso;

  List<Cuota> get cuotas => cuotasAtrasadas;
}

class MoraService {
  MoraService({
    DatabaseHelper? databaseHelper,
    DateTime Function()? reloj,
    this.diasGracia = 3,
    this._calculadora = const CalculadoraService(),
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
       _reloj = reloj ?? DateTime.now;

  final DatabaseHelper _databaseHelper;
  final DateTime Function() _reloj;
  final int diasGracia;
  final CalculadoraService _calculadora;

  int calcularDiasAtraso(DateTime fechaVencimiento) {
    final hoy = _soloFecha(_reloj());
    final vencimiento = _soloFecha(fechaVencimiento);
    return hoy.difference(vencimiento).inDays.clamp(0, 1 << 31);
  }

  double calcularPenalizacionMora({
    required Cuota cuota,
    required double porcentajeMora,
    required int diasGracia,
  }) {
    if (!porcentajeMora.isFinite || porcentajeMora < 0) {
      throw ArgumentError.value(
        porcentajeMora,
        'porcentajeMora',
        'Debe ser un valor finito no negativo.',
      );
    }
    if (diasGracia <= 0) {
      throw ArgumentError.value(
        diasGracia,
        'diasGracia',
        'Debe ser mayor que cero.',
      );
    }
    if (calcularDiasAtraso(cuota.fechaVencimiento) < diasGracia) return 0;
    final penalizacion = cuota.montoCuota * porcentajeMora / 100;
    return MonedaColombiana.esMultiploDeUnidad(cuota.montoCuota)
        ? MonedaColombiana.redondearAUnidad(penalizacion)
        : _redondearDosDecimales(penalizacion);
  }

  String verificarEstadoCuota(Cuota cuota) {
    const tolerancia = 0.000001;
    if (cuota.montoPagado >= cuota.montoCuota - tolerancia) return 'PAGADA';
    if (cuota.montoPagado > tolerancia) return 'PARCIAL';
    if (_soloFecha(cuota.fechaVencimiento).isBefore(_soloFecha(_reloj()))) {
      return 'ATRASADA';
    }
    return 'PENDIENTE';
  }

  Future<List<Cuota>> generarCuotasPenalizacion({
    required Prestamo prestamo,
    required int cuotasAtrasadas,
  }) async {
    if (cuotasAtrasadas < 0) {
      throw ArgumentError.value(
        cuotasAtrasadas,
        'cuotasAtrasadas',
        'Los días de atraso no pueden ser negativos.',
      );
    }
    if (prestamo.id == null) {
      throw ArgumentError(
        'El préstamo debe estar guardado en la base de datos.',
      );
    }

    if (diasGracia <= 0) {
      throw StateError('diasGracia debe ser mayor que cero.');
    }
    final penalizacionesObjetivo = cuotasAtrasadas ~/ diasGracia;
    if (penalizacionesObjetivo == 0) return const [];

    final db = await _databaseHelper.database;
    return db.transaction((transaction) async {
      final filasPrestamo = await transaction.query(
        DbConstants.tablePrestamos,
        where: 'id = ?',
        whereArgs: [prestamo.id],
        limit: 1,
      );
      if (filasPrestamo.isEmpty) {
        throw StateError('No existe el préstamo ${prestamo.id}.');
      }
      final prestamoActual = Prestamo.fromMap(filasPrestamo.first);
      if (prestamoActual.estado == 'PAGADO' ||
          prestamoActual.estado == 'CANCELADO') {
        return const [];
      }

      final filasCuotas = await transaction.query(
        DbConstants.tableCuotas,
        where: 'prestamo_id = ?',
        whereArgs: [prestamo.id],
        orderBy: 'numero_cuota ASC',
      );
      final cuotas = filasCuotas.map(Cuota.fromMap).toList();
      final cantidadExistente = cuotas
          .where((cuota) => cuota.esPenalizacion)
          .length;
      final cantidadNueva = penalizacionesObjetivo - cantidadExistente;
      if (cantidadNueva <= 0) return const [];

      final ultimaFecha = cuotas.isEmpty
          ? prestamoActual.fechaFinEstimada
          : cuotas
                .map((cuota) => cuota.fechaVencimiento)
                .reduce((a, b) => a.isAfter(b) ? a : b);
      final diasPersonalizados = prestamoActual.diasPersonalizados
          ?.split(',')
          .map((dia) => int.tryParse(dia.trim()))
          .whereType<int>()
          .toList();
      final fechas = _calculadora.generarFechasPago(
        fechaInicio: ultimaFecha,
        numCuotas: cantidadNueva,
        frecuencia: prestamoActual.frecuencia,
        diasPersonalizados: diasPersonalizados,
      );
      final primerNumero =
          cuotas.fold<int>(
            0,
            (maximo, cuota) =>
                cuota.numeroCuota > maximo ? cuota.numeroCuota : maximo,
          ) +
          1;
      final nuevasCuotas = <Cuota>[];
      final batch = transaction.batch();

      for (var indice = 0; indice < cantidadNueva; indice++) {
        final cuota = Cuota(
          prestamoId: prestamo.id!,
          numeroCuota: primerNumero + indice,
          fechaVencimiento: fechas[indice],
          montoCuota: prestamoActual.valorCuota,
          esPenalizacion: true,
        );
        batch.insert(DbConstants.tableCuotas, cuota.toMap());
        nuevasCuotas.add(cuota);
      }
      await batch.commit(noResult: true);

      final montoAgregado = prestamoActual.valorCuota * cantidadNueva;
      final nuevoSaldo = prestamoActual.saldoPendiente + montoAgregado;
      final nuevaFechaFin = fechas.last;
      await transaction.update(
        DbConstants.tablePrestamos,
        {
          DbConstants.prestamoNumCuotas:
              prestamoActual.numCuotas + cantidadNueva,
          DbConstants.prestamoMontoTotalPagar:
              prestamoActual.montoTotalPagar + montoAgregado,
          DbConstants.prestamoSaldoPendiente: nuevoSaldo,
          DbConstants.prestamoFechaFinEstimada: nuevaFechaFin.toIso8601String(),
          DbConstants.prestamoEstado: 'MORA',
        },
        where: 'id = ?',
        whereArgs: [prestamo.id],
      );
      return nuevasCuotas;
    });
  }

  Future<List<PrestamoEnMora>> obtenerClientesEnMora() async {
    final hoy = _soloFecha(_reloj());
    final prestamos = await _databaseHelper.obtenerPrestamosActivos();
    final enMora = <PrestamoEnMora>[];

    for (final prestamo in prestamos) {
      if (prestamo.id == null) continue;
      final cliente = await _databaseHelper.obtenerClientePorId(
        prestamo.clienteId,
      );
      if (cliente == null) continue;
      final cuotas = await _databaseHelper.obtenerCuotasPorPrestamo(
        prestamo.id!,
      );
      final atrasadas = cuotas.where((cuota) {
        return cuota.estado != 'PAGADA' &&
            _soloFecha(cuota.fechaVencimiento).isBefore(hoy);
      }).toList();
      if (atrasadas.isEmpty) continue;
      final maximoAtraso = atrasadas
          .map((cuota) => calcularDiasAtraso(cuota.fechaVencimiento))
          .reduce((a, b) => a > b ? a : b);
      enMora.add(
        PrestamoEnMora(
          prestamo: prestamo,
          cliente: cliente,
          cuotasAtrasadas: atrasadas,
          diasAtraso: maximoAtraso,
        ),
      );
    }

    enMora.sort((a, b) => b.diasAtraso.compareTo(a.diasAtraso));
    return enMora;
  }

  static DateTime _soloFecha(DateTime fecha) =>
      DateTime(fecha.year, fecha.month, fecha.day);

  static double _redondearDosDecimales(double valor) =>
      (valor * 100).roundToDouble() / 100;
}
