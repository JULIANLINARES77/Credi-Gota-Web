import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_prestamos/data/models/cliente.dart';
import 'package:flutter_prestamos/data/models/cuota.dart';
import 'package:flutter_prestamos/data/models/prestamo.dart';
import 'package:flutter_prestamos/logic/providers/gota_provider.dart';
import 'package:flutter_prestamos/logic/services/mora_service.dart';
import 'package:flutter_prestamos/ui/screens/clientes/clientes_screen.dart';

class _MoraProvider extends GotaProvider {
  _MoraProvider({required this.cliente, required this.prestamo});

  final Cliente cliente;
  final Prestamo prestamo;
  late final mora = PrestamoEnMora(
    prestamo: prestamo,
    cliente: cliente,
    cuotasAtrasadas: [
      Cuota(
        id: 1,
        prestamoId: prestamo.id!,
        numeroCuota: 2,
        fechaVencimiento: DateTime(2026, 10, 10),
        montoCuota: 10000,
      ),
    ],
    diasAtraso: 6,
  );

  @override
  List<Cliente> get clientes => [cliente];

  @override
  List<PrestamoEnMora> get moras => [mora];

  @override
  List<Prestamo> prestamosDeCliente(int clienteId) =>
      clienteId == cliente.id ? [prestamo] : const [];

  @override
  Cliente? clientePorId(int id) => id == cliente.id ? cliente : null;

  @override
  List<Cuota> cuotasDePrestamo(int prestamoId) =>
      prestamoId == prestamo.id ? mora.cuotasAtrasadas : const [];
}

void main() {
  testWidgets(
    'el filtro En mora incluye préstamos ACTIVO con cuotas vencidas',
    (tester) async {
      final cliente = Cliente(
        id: 1,
        nombre: 'Cliente con atraso',
        telefono: '3001234567',
        fechaRegistro: DateTime(2026, 10, 1),
      );
      final prestamo = Prestamo(
        id: 1,
        clienteId: 1,
        montoCapital: 100000,
        porcentajeInteres: 10,
        montoInteres: 10000,
        montoTotalPagar: 110000,
        numCuotas: 11,
        valorCuota: 10000,
        frecuencia: 'SEMANAL',
        fechaInicio: DateTime(2026, 10, 1),
        fechaFinEstimada: DateTime(2026, 12, 1),
        estado: 'ACTIVO',
        saldoPendiente: 100000,
        createdAt: DateTime(2026, 10, 1),
      );
      final provider = _MoraProvider(cliente: cliente, prestamo: prestamo);
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<GotaProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: ClientesScreen(filtroInicial: 'En mora'),
          ),
        ),
      );

      expect(find.text('Cliente con atraso'), findsOneWidget);
      expect(find.text('Mora · 6d'), findsOneWidget);
      expect(find.text('No hay clientes para este filtro.'), findsNothing);
    },
  );
}
