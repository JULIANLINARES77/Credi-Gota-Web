import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_prestamos/data/models/cliente.dart';
import 'package:flutter_prestamos/ui/widgets/cliente_form_dialog.dart';

void main() {
  testWidgets('shows optional identity and address fields for a new client', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => mostrarClienteFormDialog(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();

    expect(find.text('Nombre completo'), findsOneWidget);
    expect(find.text('Teléfono'), findsOneWidget);
    expect(find.text('Cédula (opcional)'), findsOneWidget);
    expect(find.text('Dirección (opcional)'), findsOneWidget);
    expect(find.text('Buscar en Google Maps'), findsOneWidget);
    expect(
      find.textContaining('Google recibe el texto ingresado'),
      findsOneWidget,
    );
  });

  testWidgets('prefills fields when editing a client', (tester) async {
    final cliente = Cliente(
      id: 7,
      nombre: 'Cliente existente',
      telefono: '3001234567',
      cedula: '12345678',
      direccion: 'Barrio Centro, Cali',
      fechaRegistro: DateTime(2025, 1, 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  mostrarClienteFormDialog(context, cliente: cliente),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();

    expect(find.text('Editar cliente'), findsOneWidget);
    expect(find.text('Cliente existente'), findsOneWidget);
    expect(find.text('3001234567'), findsOneWidget);
    expect(find.text('12345678'), findsOneWidget);
    expect(find.text('Barrio Centro, Cali'), findsOneWidget);
  });

  testWidgets('filters non-numeric characters from phone and identity fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => mostrarClienteFormDialog(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();

    final phone = find.byType(TextFormField).at(1);
    final identity = find.byType(TextFormField).at(2);
    await tester.enterText(phone, '300ABC-1234');
    await tester.enterText(identity, '1.234-567X');

    expect(find.text('3001234'), findsOneWidget);
    expect(find.text('1234567'), findsOneWidget);
  });
}
