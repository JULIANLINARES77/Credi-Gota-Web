import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_prestamos/data/models/cliente.dart';
import 'package:flutter_prestamos/data/models/cuota.dart';
import 'package:flutter_prestamos/data/models/prestamo.dart';
import 'package:flutter_prestamos/logic/providers/gota_provider.dart';
import 'package:flutter_prestamos/logic/services/mora_service.dart';
import 'package:flutter_prestamos/ui/screens/dashboard/dashboard_screen.dart';

class _DashboardProvider extends GotaProvider {
  _DashboardProvider({required this.cliente, required this.prestamo})
    : super() {
    cargando = false;
  }

  final Cliente cliente;
  final Prestamo prestamo;

  final Cuota cuotaVencida = Cuota(
    id: 1,
    prestamoId: 1,
    numeroCuota: 1,
    fechaVencimiento: DateTime.now().subtract(const Duration(days: 1)),
    montoCuota: 10000,
    estado: 'ATRASADA',
  );
  final Cuota cuotaDeHoy = Cuota(
    id: 2,
    prestamoId: 1,
    numeroCuota: 2,
    fechaVencimiento: DateTime.now(),
    montoCuota: 12000,
  );

  @override
  List<Prestamo> get prestamosActivos => [prestamo];

  @override
  List<PrestamoEnMora> get moras => [
    PrestamoEnMora(
      prestamo: prestamo,
      cliente: cliente,
      cuotasAtrasadas: [cuotaVencida],
      diasAtraso: 1,
    ),
  ];

  @override
  List<Cuota> get cuotasDeHoy => [cuotaDeHoy];

  @override
  double get gananciaHoy => 0;

  @override
  double get totalEnCalle => 0;

  @override
  double get recaudadoHoy => 0;

  @override
  int get clientesActivos => 1;

  @override
  int get clientesEnMora => 1;

  @override
  Cliente? clientePorId(int id) => id == cliente.id ? cliente : null;

  @override
  Prestamo? prestamoPorId(int id) => id == prestamo.id ? prestamo : null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('muestra alertas vencidas y cuotas que vencen hoy', (
    tester,
  ) async {
    final cliente = Cliente(
      id: 1,
      nombre: 'Ana Pérez',
      telefono: '3000000000',
      fechaRegistro: DateTime.now(),
    );
    final prestamo = Prestamo(
      id: 1,
      clienteId: 1,
      montoCapital: 10000,
      porcentajeInteres: 0,
      montoInteres: 0,
      montoTotalPagar: 22000,
      numCuotas: 2,
      valorCuota: 11000,
      frecuencia: 'SEMANAL',
      fechaInicio: DateTime.now().subtract(const Duration(days: 8)),
      fechaFinEstimada: DateTime.now().add(const Duration(days: 8)),
      saldoPendiente: 22000,
      createdAt: DateTime.now(),
    );
    final provider = _DashboardProvider(cliente: cliente, prestamo: prestamo);
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<GotaProvider>.value(
        value: provider,
        child: MaterialApp(
          home: DashboardScreen(
            onNuevoPrestamo: () {},
            onClientes: () {},
            onMora: () {},
            onPrestamos: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Notificaciones'));
    await tester.pumpAndSettle();

    expect(find.text('Cuotas vencidas'), findsOneWidget);
    expect(find.text('Cuotas para hoy'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsNWidgets(3));
    expect(
      find.textContaining('1 cuota vencida · 1 cuota para hoy'),
      findsOneWidget,
    );
  });

  testWidgets('elimina a ambos lados, muestra deshacer y persiste al reabrir', (
    tester,
  ) async {
    final cliente = Cliente(
      id: 1,
      nombre: 'Ana Pérez',
      telefono: '3000000000',
      fechaRegistro: DateTime.now(),
    );
    final prestamo = Prestamo(
      id: 1,
      clienteId: 1,
      montoCapital: 10000,
      porcentajeInteres: 0,
      montoInteres: 0,
      montoTotalPagar: 22000,
      numCuotas: 2,
      valorCuota: 11000,
      frecuencia: 'SEMANAL',
      fechaInicio: DateTime.now().subtract(const Duration(days: 8)),
      fechaFinEstimada: DateTime.now().add(const Duration(days: 8)),
      saldoPendiente: 22000,
      createdAt: DateTime.now(),
    );
    final provider = _DashboardProvider(cliente: cliente, prestamo: prestamo);
    addTearDown(provider.dispose);

    Widget app() => ChangeNotifierProvider<GotaProvider>.value(
      value: provider,
      child: MaterialApp(
        home: DashboardScreen(
          onNuevoPrestamo: () {},
          onClientes: () {},
          onMora: () {},
          onPrestamos: () {},
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Notificaciones'));
    await tester.pumpAndSettle();

    final primeraAlerta = find.byType(Dismissible).first;
    await tester.drag(primeraAlerta, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Notificación eliminada'), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(find.byType(Dismissible), findsNWidgets(2));

    await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('alerta-mora:1')), findsNothing);
    expect(find.text('Notificación eliminada'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar alertas'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Notificaciones'));
    await tester.pumpAndSettle();
    expect(find.byType(Dismissible), findsOneWidget);

    await tester.drag(find.byType(Dismissible).first, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Notificación eliminada'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Notificación eliminada'), findsNothing);
  });
}
