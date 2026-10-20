import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_prestamos/logic/providers/gota_provider.dart';
import 'package:flutter_prestamos/ui/screens/prestamos/nuevo_prestamo_screen.dart';

void main() {
  testWidgets('permite elegir días corridos o desplazar festivos', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => GotaProvider()..cargando = false,
        child: const MaterialApp(home: NuevoPrestamoScreen()),
      ),
    );

    final selector = find.byType(SwitchListTile);
    expect(selector, findsOneWidget);
    expect(find.textContaining('Fecha de inicio ·'), findsOneWidget);
    expect(find.text('Días corridos'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(selector).value, isFalse);

    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(selector).value, isTrue);
  });

  testWidgets('valida capital, interés y cuotas con los límites QA', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => GotaProvider()..cargando = false,
        child: const MaterialApp(home: NuevoPrestamoScreen()),
      ),
    );

    final campos = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    final validarCapital = campos[0].validator!;
    final validarInteres = campos[1].validator!;
    final validarCuotas = campos[2].validator!;

    expect(validarCapital('9.999'), contains('10.000'));
    expect(validarCapital('100.000.001'), contains('100.000.000'));
    expect(validarCapital('10.500'), contains('múltiplo de \$1.000'));
    expect(validarCapital('10.000'), isNull);
    expect(validarCapital('100.000.000'), isNull);

    expect(validarInteres('101'), 'El interés debe estar entre 0% y 100%');
    expect(validarInteres('-1'), 'El interés debe estar entre 0% y 100%');
    expect(validarInteres('0'), isNull);
    expect(validarInteres('100'), isNull);

    expect(
      validarCuotas('366'),
      'El número de cuotas debe estar entre 1 y 365',
    );
    expect(validarCuotas('0'), 'El número de cuotas debe estar entre 1 y 365');
    expect(validarCuotas('1'), isNull);
    expect(validarCuotas('365'), isNull);
  });
}
