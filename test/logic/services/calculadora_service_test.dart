import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_prestamos/core/utils/festivos_colombia.dart';
import 'package:flutter_prestamos/logic/services/calculadora_service.dart';

void main() {
  const calculadora = CalculadoraService();

  group('calcularPrestamo', () {
    test(
      'calcula interés simple y mantiene los importes en miles de pesos',
      () {
        final resultado = calculadora.calcularPrestamo(
          capital: 1000000,
          porcentajeInteres: 20,
          numCuotas: 24,
        );

        expect(resultado.montoInteres, 200000);
        expect(resultado.montoTotalPagar, 1200000);
        expect(resultado.valorCuota, 50000);
        expect(resultado.valoresCuota, List<double>.filled(24, 50000));
        expect(resultado.gananciaDiariaPromedio, 8333.33);
      },
    );

    test('distribuye el residuo entre cuotas sin alterar el total', () {
      final resultado = calculadora.calcularPrestamo(
        capital: 1000000,
        porcentajeInteres: 0,
        numCuotas: 3,
      );

      expect(resultado.valoresCuota, [334000, 333000, 333000]);
      expect(resultado.valoresCuota.reduce((a, b) => a + b), 1000000);
      expect(
        resultado.valoresCuota.every((valor) => valor % 1000 == 0),
        isTrue,
      );
      expect(resultado.valorCuotaMaxima, 334000);
    });

    test('rechaza valores fuera de rango', () {
      expect(
        () => calculadora.calcularPrestamo(
          capital: 0,
          porcentajeInteres: 20,
          numCuotas: 4,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculadora.calcularPrestamo(
          capital: 9999,
          porcentajeInteres: 20,
          numCuotas: 4,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculadora.calcularPrestamo(
          capital: 100500,
          porcentajeInteres: 20,
          numCuotas: 4,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculadora.calcularPrestamo(
          capital: 100000001,
          porcentajeInteres: 20,
          numCuotas: 4,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculadora.calcularPrestamo(
          capital: 10000,
          porcentajeInteres: -1,
          numCuotas: 4,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculadora.calcularPrestamo(
          capital: 10000,
          porcentajeInteres: 0,
          numCuotas: 11,
        ),
        throwsArgumentError,
      );
      expect(
        calculadora
            .calcularPrestamo(
              capital: 10000,
              porcentajeInteres: 0,
              numCuotas: 1,
            )
            .valorCuota,
        10000,
      );
      expect(
        calculadora
            .calcularPrestamo(
              capital: 100000000,
              porcentajeInteres: 100,
              numCuotas: 365,
            )
            .montoTotalPagar,
        200000000,
      );
      expect(
        () => calculadora.calcularPrestamo(
          capital: 10000,
          porcentajeInteres: 101,
          numCuotas: 4,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculadora.calcularPrestamo(
          capital: 10000,
          porcentajeInteres: 20,
          numCuotas: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculadora.calcularPrestamo(
          capital: 10000,
          porcentajeInteres: 20,
          numCuotas: 366,
        ),
        throwsArgumentError,
      );
    });

    test('prorratea interés y capital sobre un pago parcial', () {
      expect(
        calculadora.calcularGananciaProporcional(
          montoPagado: 50000,
          totalPagar: 1200000,
          interesTotal: 200000,
        ),
        closeTo(8333.333333, 0.000001),
      );
      expect(
        calculadora.calcularCapitalRecuperado(
          montoPagado: 50000,
          totalPagar: 1200000,
          capital: 1000000,
        ),
        closeTo(41666.666667, 0.000001),
      );
    });

    test('conserva el total de interés y capital al sumar pagos parciales', () {
      const pagos = [100000.0, 300000.0, 400000.0, 400000.0];
      final interes = pagos.fold(
        0.0,
        (total, pago) =>
            total +
            calculadora.calcularGananciaProporcional(
              montoPagado: pago,
              totalPagar: 1200000,
              interesTotal: 200000,
            ),
      );
      final capital = pagos.fold(
        0.0,
        (total, pago) =>
            total +
            calculadora.calcularCapitalRecuperado(
              montoPagado: pago,
              totalPagar: 1200000,
              capital: 1000000,
            ),
      );

      expect(interes, closeTo(200000, 0.000001));
      expect(capital, closeTo(1000000, 0.000001));
    });
  });

  group('generarFechasPago', () {
    final lunes = DateTime(2026, 9, 28);

    test('genera fechas lunes, miércoles y viernes', () {
      final fechas = calculadora.generarFechasPago(
        fechaInicio: lunes,
        numCuotas: 4,
        frecuencia: CalculadoraService.frecuenciaLunesMiercolesViernes,
      );

      expect(fechas, [
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 7),
      ]);
    });

    test('respeta días personalizados y elimina duplicados', () {
      final fechas = calculadora.generarFechasPago(
        fechaInicio: lunes,
        numCuotas: 3,
        frecuencia: CalculadoraService.frecuenciaPersonalizada,
        diasPersonalizados: [2, 5, 2],
      );

      expect(fechas, [
        DateTime(2026, 9, 29),
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 6),
      ]);
    });

    test('diaria puede omitir domingos cuando se configura', () {
      final fechas = calculadora.generarFechasPago(
        fechaInicio: DateTime(2026, 10, 3),
        numCuotas: 2,
        frecuencia: CalculadoraService.frecuenciaDiaria,
        saltarDomingos: true,
      );

      expect(fechas, [DateTime(2026, 10, 5), DateTime(2026, 10, 6)]);
    });

    test('desplaza cuotas que caen en domingos o festivos colombianos', () {
      final fechas = calculadora.generarFechasPago(
        fechaInicio: DateTime(2026, 7, 18),
        numCuotas: 2,
        frecuencia: CalculadoraService.frecuenciaDiaria,
        saltarFestivos: true,
      );

      expect(fechas, [DateTime(2026, 7, 21), DateTime(2026, 7, 22)]);
    });

    test(
      'mantiene festivos en el calendario si la opción está desactivada',
      () {
        final fechas = calculadora.generarFechasPago(
          fechaInicio: DateTime(2025, 12, 31),
          numCuotas: 1,
          frecuencia: CalculadoraService.frecuenciaDiaria,
        );

        expect(fechas, [DateTime(2026, 1, 1)]);
      },
    );

    test('dias corridos conserva domingos y festivos en todas las cuotas', () {
      final fechas = calculadora.generarFechasPago(
        fechaInicio: DateTime(2026, 7, 18),
        numCuotas: 3,
        frecuencia: CalculadoraService.frecuenciaDiaria,
        diasCorridos: true,
      );

      expect(fechas, [
        DateTime(2026, 7, 19),
        DateTime(2026, 7, 20),
        DateTime(2026, 7, 21),
      ]);
    });

    test('dias no corridos desplaza domingo y festivo', () {
      final fechas = calculadora.generarFechasPago(
        fechaInicio: DateTime(2026, 7, 18),
        numCuotas: 2,
        frecuencia: CalculadoraService.frecuenciaDiaria,
        diasCorridos: false,
      );

      expect(fechas, [DateTime(2026, 7, 21), DateTime(2026, 7, 22)]);
    });

    test('dias no corridos también desplaza cuotas del sábado', () {
      final fechas = calculadora.generarFechasPago(
        fechaInicio: DateTime(2026, 10, 16),
        numCuotas: 1,
        frecuencia: CalculadoraService.frecuenciaDiaria,
        diasCorridos: false,
      );

      expect(fechas, [DateTime(2026, 10, 19)]);
    });

    test('semanal conserva weekday y quincenal suma quince días', () {
      final semanales = calculadora.generarFechasPago(
        fechaInicio: lunes,
        numCuotas: 2,
        frecuencia: CalculadoraService.frecuenciaSemanal,
      );
      final quincenales = calculadora.generarFechasPago(
        fechaInicio: lunes,
        numCuotas: 2,
        frecuencia: CalculadoraService.frecuenciaQuincenal,
      );

      expect(semanales, [DateTime(2026, 10, 5), DateTime(2026, 10, 12)]);
      expect(quincenales, [DateTime(2026, 10, 13), DateTime(2026, 10, 28)]);
    });

    test('mensual conserva el día y ajusta fechas de fin de mes', () {
      final fechas = calculadora.generarFechasPago(
        fechaInicio: DateTime(2026, 1, 31),
        numCuotas: 4,
        frecuencia: CalculadoraService.frecuenciaMensual,
      );

      expect(fechas, [
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
        DateTime(2026, 5, 31),
      ]);
    });

    test('calcula la fecha de finalización de la última cuota', () {
      expect(
        calculadora.calcularFechaFin(
          fechaInicio: lunes,
          numCuotas: 4,
          frecuencia: CalculadoraService.frecuenciaLunesMiercolesViernes,
        ),
        DateTime(2026, 10, 7),
      );
    });

    test('valida el número de cuotas y los días personalizados', () {
      expect(
        () => calculadora.generarFechasPago(
          fechaInicio: lunes,
          numCuotas: 0,
          frecuencia: CalculadoraService.frecuenciaDiaria,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculadora.generarFechasPago(
          fechaInicio: lunes,
          numCuotas: 2,
          frecuencia: CalculadoraService.frecuenciaPersonalizada,
          diasPersonalizados: [8],
        ),
        throwsArgumentError,
      );
    });
  });

  group('FestivosColombia', () {
    test('reconoce festivos fijos y Semana Santa', () {
      expect(FestivosColombia.esFestivo(DateTime(2026, 1, 1)), isTrue);
      expect(FestivosColombia.esFestivo(DateTime(2026, 7, 20)), isTrue);
      expect(FestivosColombia.esFestivo(DateTime(2026, 12, 25)), isTrue);
      expect(FestivosColombia.esFestivo(DateTime(2026, 4, 2)), isTrue);
      expect(FestivosColombia.esFestivo(DateTime(2026, 4, 3)), isTrue);
    });

    test('reconoce los festivos trasladados al lunes por Ley Emiliani', () {
      expect(FestivosColombia.esFestivo(DateTime(2026, 1, 12)), isTrue);
      expect(FestivosColombia.esFestivo(DateTime(2026, 1, 6)), isFalse);
    });
  });
}
