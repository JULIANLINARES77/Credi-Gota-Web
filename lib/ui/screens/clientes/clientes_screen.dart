import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/cliente.dart';
import '../../../logic/providers/gota_provider.dart';
import '../../widgets/cliente_card.dart';
import '../../widgets/cliente_form_dialog.dart';
import '../prestamos/prestamos_cliente_screen.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key, this.filtroInicial = 'Todos'});

  final String filtroInicial;

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  final _busqueda = TextEditingController();
  late String _filtro;

  @override
  void initState() {
    super.initState();
    _filtro = widget.filtroInicial;
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<GotaProvider>();
    final prestamoIdsEnMora = demo.moras
        .map((mora) => mora.prestamo.id)
        .whereType<int>()
        .toSet();
    final clientes = demo.clientes.where((cliente) {
      if (!cliente.activo) return false;
      final id = cliente.id;
      if (id == null) return false;

      final consulta = _busqueda.text.trim().toLowerCase();
      final coincide =
          cliente.nombre.toLowerCase().contains(consulta) ||
          (cliente.cedula ?? '').toLowerCase().contains(consulta) ||
          cliente.telefono.toLowerCase().contains(consulta);
      if (!coincide) return false;

      final prestamos = demo.prestamosDeCliente(id);
      return switch (_filtro) {
        'En mora' => prestamos.any(
          (prestamo) => prestamoIdsEnMora.contains(prestamo.id),
        ),
        'Pagados' =>
          prestamos.isNotEmpty &&
              prestamos.every((prestamo) => prestamo.estado == 'PAGADO'),
        'Con préstamos' => prestamos.any(
          (prestamo) => prestamo.estado != 'CANCELADO',
        ),
        'Al día' => prestamos.any((prestamo) => prestamo.estado == 'ACTIVO'),
        _ => true,
      };
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Nuevo cliente',
            onPressed: _agregarCliente,
            icon: const Icon(Icons.person_add_alt_1),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _busqueda,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, cédula o teléfono',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busqueda.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar',
                            onPressed: () {
                              _busqueda.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final filtro in [
                      'Todos',
                      'Al día',
                      'En mora',
                      'Con préstamos',
                      'Pagados',
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(filtro),
                          selected: _filtro == filtro,
                          onSelected: (_) => setState(() => _filtro = filtro),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: clientes.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay clientes para este filtro.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: clientes.length,
                        itemBuilder: (context, index) =>
                            _clienteListTile(clientes[index], demo),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'clients-add-client',
        tooltip: 'Agregar cliente',
        onPressed: _agregarCliente,
        child: const Icon(Icons.person_add_alt_1),
      ),
    );
  }

  Widget _clienteListTile(Cliente cliente, GotaProvider demo) {
    final clienteId = cliente.id;
    if (clienteId == null) return const SizedBox.shrink();

    final prestamos = demo.prestamosDeCliente(clienteId);
    final prestamosActivos = prestamos
        .where(
          (prestamo) =>
              prestamo.estado == 'ACTIVO' || prestamo.estado == 'MORA',
        )
        .toList();
    final saldoPendiente = prestamosActivos.fold(
      0.0,
      (saldo, prestamo) => saldo + prestamo.saldoPendiente,
    );
    final prestamosEnMora = demo.moras
        .where((mora) => mora.cliente.id == clienteId)
        .toList();
    final diasAtraso = prestamosEnMora.isEmpty
        ? null
        : prestamosEnMora
              .map((mora) => mora.diasAtraso)
              .reduce((a, b) => a > b ? a : b);
    final cuotasPendientes =
        prestamosActivos
            .where((prestamo) => prestamo.id != null)
            .expand((prestamo) => demo.cuotasDePrestamo(prestamo.id!))
            .where((cuota) => cuota.estado != 'PAGADA')
            .toList()
          ..sort((a, b) => a.fechaVencimiento.compareTo(b.fechaVencimiento));
    final cuotaSiguiente = cuotasPendientes.firstOrNull;
    final estado = prestamosEnMora.isNotEmpty
        ? 'MORA'
        : prestamosActivos.isNotEmpty
        ? 'ACTIVO'
        : prestamos.isNotEmpty &&
              prestamos.every((prestamo) => prestamo.estado == 'PAGADO')
        ? 'PAGADO'
        : 'PENDIENTE';
    final card = ClienteCard(
      cliente: cliente,
      saldoPendiente: saldoPendiente,
      estado: estado,
      diasAtraso: diasAtraso,
      proximoPago: cuotaSiguiente?.fechaVencimiento,
      cantidadPrestamosActivos: prestamosActivos.length,
      onTap: () => _abrirPrestamosCliente(clienteId),
      onEditar: () => _modificarCliente(cliente),
      onBuscarMaps: cliente.direccion?.trim().isNotEmpty == true
          ? () => ClienteCard.abrirMaps(context, cliente.direccion!)
          : null,
      onEliminar: () => _eliminarCliente(cliente),
    );
    return Dismissible(
      key: ValueKey('cliente-$clienteId'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmarEliminacion(cliente),
      onDismissed: (_) => _desactivarCliente(cliente),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.person_off_outlined, color: Colors.white),
      ),
      child: card,
    );
  }

  Future<bool> _confirmarEliminacion(Cliente cliente) async {
    final clienteId = cliente.id;
    if (clienteId == null) return false;

    final provider = context.read<GotaProvider>();
    final estaPazYSalvo = await provider.clienteEstaPazYSalvo(clienteId);
    if (!mounted) return false;

    if (!estaPazYSalvo) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No se puede eliminar'),
          content: Text(
            'No se puede eliminar a ${cliente.nombre} porque tiene préstamos activos. Debe estar a paz y salvo.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return false;
    }

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Eliminar cliente'),
            content: Text(
              '¿Deseas eliminar a ${cliente.nombre}? Se conservará el historial financiero.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _eliminarCliente(Cliente cliente) async {
    if (!await _confirmarEliminacion(cliente) || !mounted) return;
    await _desactivarCliente(cliente);
  }

  Future<void> _modificarCliente(Cliente cliente) async {
    final datos = await mostrarClienteFormDialog(context, cliente: cliente);
    if (datos == null || !mounted) return;
    try {
      await context.read<GotaProvider>().actualizarCliente(
        cliente: cliente,
        nombre: datos.nombre,
        telefono: datos.telefono,
        cedula: datos.cedula,
        direccion: datos.direccion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente actualizado correctamente.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final mensaje = error
          .toString()
          .replaceFirst('ArgumentError: ', '')
          .replaceFirst('StateError: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));
    }
  }

  Future<void> _desactivarCliente(Cliente cliente) async {
    final clienteId = cliente.id;
    if (clienteId == null) return;
    try {
      await context.read<GotaProvider>().eliminarCliente(clienteId);
    } on Object catch (error) {
      if (!mounted) return;
      await context.read<GotaProvider>().cargarDatos();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _agregarCliente() async {
    final datos = await mostrarClienteFormDialog(context);
    if (datos == null || !mounted) return;
    try {
      await context.read<GotaProvider>().agregarCliente(
        nombre: datos.nombre,
        telefono: datos.telefono,
        cedula: datos.cedula,
        direccion: datos.direccion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente guardado correctamente.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final mensaje = error
          .toString()
          .replaceFirst('ArgumentError: ', '')
          .replaceFirst('StateError: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));
    }
  }

  void _abrirPrestamosCliente(int clienteId) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PrestamosClienteScreen(clienteId: clienteId),
      ),
    );
  }
}
