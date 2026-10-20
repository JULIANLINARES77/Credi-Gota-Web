import '../../core/constants/db_constants.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/cliente.dart';
import '../../data/models/cuota.dart';
import '../../data/models/prestamo.dart';

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
  MoraService({DatabaseHelper? databaseHelper, DateTime Function()? reloj})
    : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
      _reloj = reloj ?? DateTime.now;

  final DatabaseHelper _databaseHelper;
  final DateTime Function() _reloj;

  int calcularDiasAtraso(
    DateTime fechaVencimiento, {
    DateTime? fechaReferencia,
  }) {
    final hoy = _soloFecha(fechaReferencia ?? _reloj());
    final vencimiento = _soloFecha(fechaVencimiento);
    return hoy.difference(vencimiento).inDays.clamp(0, 1 << 31);
  }

  double calcularPenalizacionMora({
    required Prestamo prestamo,
    required Cuota cuota,
    DateTime? fechaReferencia,
  }) {
    if (prestamo.diasGraciaMora < 0) {
      throw ArgumentError.value(
        prestamo.diasGraciaMora,
        'diasGraciaMora',
        'No puede ser negativo.',
      );
    }
    if (!prestamo.valorRecargoMora.isFinite ||
        prestamo.valorRecargoMora < 0 ||
        !const {
          'PORCENTAJE',
          'MONTO_FIJO',
        }.contains(prestamo.tipoRecargoMora)) {
      throw ArgumentError(
        'La regla de recargo por mora del préstamo no es válida.',
      );
    }
    final diasAtraso = calcularDiasAtraso(
      cuota.fechaVencimiento,
      fechaReferencia: fechaReferencia,
    );
    if (diasAtraso < prestamo.diasGraciaMora || diasAtraso == 0) return 0;

    final periodos = prestamo.recargoAcumulable
        ? (prestamo.diasGraciaMora == 0
              ? diasAtraso
              : diasAtraso ~/ prestamo.diasGraciaMora)
        : 1;
    final cuotaBase = cuota.montoCuota - cuota.montoPenalizacion;
    final recargoUnitario = prestamo.tipoRecargoMora == 'MONTO_FIJO'
        ? prestamo.valorRecargoMora
        : cuotaBase * prestamo.valorRecargoMora / 100;
    return recargoUnitario * periodos;
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

  Future<double> aplicarMoraCuota({
    required Prestamo prestamo,
    required Cuota cuota,
    DateTime? fechaReferencia,
  }) async {
    if (prestamo.id == null) {
      throw ArgumentError(
        'El préstamo debe estar guardado en la base de datos.',
      );
    }
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
        return 0.0;
      }
      final filasCuota = await transaction.query(
        DbConstants.tableCuotas,
        where:
            '${DbConstants.columnId} = ? AND '
            '${DbConstants.cuotaPrestamoId} = ?',
        whereArgs: [cuota.id, prestamo.id],
        limit: 1,
      );
      if (filasCuota.isEmpty) {
        throw StateError('La cuota no pertenece al préstamo indicado.');
      }
      final cuotaActual = Cuota.fromMap(filasCuota.first);
      if (cuotaActual.estado == 'PAGADA' ||
          cuotaActual.montoPagado >= cuotaActual.montoCuota) {
        return 0.0;
      }
      final recargoObjetivo = calcularPenalizacionMora(
        prestamo: prestamoActual,
        cuota: cuotaActual,
        fechaReferencia: fechaReferencia,
      );
      final montoAgregado = recargoObjetivo - cuotaActual.montoPenalizacion;
      if (montoAgregado <= 0) return 0.0;
      await transaction.update(
        DbConstants.tableCuotas,
        {
          DbConstants.cuotaMonto: cuotaActual.montoCuota + montoAgregado,
          DbConstants.cuotaMontoPenalizacion: recargoObjetivo,
        },
        where: '${DbConstants.columnId} = ?',
        whereArgs: [cuotaActual.id],
      );
      await transaction.update(
        DbConstants.tablePrestamos,
        {
          DbConstants.prestamoMontoTotalPagar:
              prestamoActual.montoTotalPagar + montoAgregado,
          DbConstants.prestamoSaldoPendiente:
              prestamoActual.saldoPendiente + montoAgregado,
          DbConstants.prestamoEstado: 'MORA',
        },
        where: '${DbConstants.columnId} = ?',
        whereArgs: [prestamo.id],
      );
      return montoAgregado;
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
}
