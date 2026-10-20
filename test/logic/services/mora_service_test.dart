import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_prestamos/data/models/cuota.dart';
import 'package:flutter_prestamos/data/models/prestamo.dart';
import 'package:flutter_prestamos/logic/services/mora_service.dart';

void main() {
  final mora = MoraService(reloj: () => DateTime(2026, 10, 10, 15));
  final prestamoPorcentual = Prestamo(
    clienteId: 1,
    montoCapital: 100000,
    porcentajeInteres: 0,
    montoInteres: 0,
    montoTotalPagar: 100000,
    numCuotas: 2,
    valorCuota: 50000,
    frecuencia: 'DIARIA',
    fechaInicio: DateTime(2026, 10, 1),
    fechaFinEstimada: DateTime(2026, 10, 2),
    saldoPendiente: 100000,
    createdAt: DateTime(2026, 10, 1),
  );
  final cuotaBase = Cuota(
    prestamoId: 1,
    numeroCuota: 1,
    fechaVencimiento: DateTime(2026, 10, 7),
    montoCuota: 50000,
  );

  test('calcula días completos de atraso sin fracción horaria', () {
    expect(mora.calcularDiasAtraso(cuotaBase.fechaVencimiento), 3);
    expect(mora.calcularDiasAtraso(DateTime(2026, 10, 11)), 0);
  });

  test('aplica porcentaje de mora al completar los días de gracia', () {
    expect(
      mora.calcularPenalizacionMora(
        prestamo: prestamoPorcentual,
        cuota: cuotaBase,
      ),
      5000,
    );
    expect(
      mora.calcularPenalizacionMora(
        prestamo: prestamoPorcentual,
        cuota: cuotaBase.copyWith(fechaVencimiento: DateTime(2026, 10, 8)),
      ),
      0,
    );
  });

  test('calcula mora con la fecha histórica seleccionada para el pago', () {
    expect(
      mora.calcularPenalizacionMora(
        prestamo: prestamoPorcentual,
        cuota: cuotaBase,
        fechaReferencia: DateTime(2026, 10, 8),
      ),
      0,
    );
    expect(
      mora.calcularPenalizacionMora(
        prestamo: prestamoPorcentual,
        cuota: cuotaBase,
        fechaReferencia: DateTime(2026, 10, 10),
      ),
      5000,
    );
  });

  test('monto fijo es independiente del valor de cuota', () {
    final prestamoFijo = prestamoPorcentual.copyWith(
      diasGraciaMora: 0,
      tipoRecargoMora: 'MONTO_FIJO',
      valorRecargoMora: 5000,
    );
    expect(
      mora.calcularPenalizacionMora(
        prestamo: prestamoFijo,
        cuota: cuotaBase.copyWith(montoCuota: 900000),
      ),
      5000,
    );
  });

  test('el recargo acumulable se cobra por cada bloque completo de gracia', () {
    final prestamoAcumulable = prestamoPorcentual.copyWith(
      recargoAcumulable: true,
    );
    expect(
      mora.calcularPenalizacionMora(
        prestamo: prestamoAcumulable,
        cuota: cuotaBase.copyWith(fechaVencimiento: DateTime(2026, 10, 4)),
      ),
      10000,
    );
  });

  test('determina el estado pendiente, atrasado, parcial o pagado', () {
    expect(mora.verificarEstadoCuota(cuotaBase), 'ATRASADA');
    expect(
      mora.verificarEstadoCuota(
        cuotaBase.copyWith(fechaVencimiento: DateTime(2026, 10, 10)),
      ),
      'PENDIENTE',
    );
    expect(
      mora.verificarEstadoCuota(cuotaBase.copyWith(montoPagado: 10000)),
      'PARCIAL',
    );
    expect(
      mora.verificarEstadoCuota(cuotaBase.copyWith(montoPagado: 50000)),
      'PAGADA',
    );
  });
}
