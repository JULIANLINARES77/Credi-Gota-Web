import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/cliente.dart';
import '../../../data/models/cuota.dart';
import '../../../data/models/prestamo.dart';
import '../../../logic/providers/gota_provider.dart';
import '../../widgets/cliente_card.dart';
import '../../widgets/gotacontrol_logo.dart';
import '../../widgets/payment_bottom_sheet.dart';
import '../../widgets/resumen_card.dart';
import '../prestamos/prestamo_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onNuevoPrestamo,
    required this.onClientes,
    required this.onMora,
    required this.onPrestamos,
  });

  final VoidCallback onNuevoPrestamo;
  final VoidCallback onClientes;
  final VoidCallback onMora;
  final VoidCallback onPrestamos;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _alertasLeidasKey = 'dashboard_alertas_leidas';
  static const _alertasEliminadasKey = 'dashboard_alertas_eliminadas';
  final Set<String> _alertasLeidas = <String>{};
  final Set<String> _alertasEliminadas = <String>{};
  bool _estadoCargado = false;
  Future<void>? _guardadoAlertasPendiente;

  String _claveAlerta(int? cuotaId, String tipo) => '$tipo:${cuotaId ?? 0}';

  bool _visible(String clave) =>
      !_alertasLeidas.contains(clave) && !_alertasEliminadas.contains(clave);

  @override
  void initState() {
    super.initState();
  
    // 2. Cargamos el estado
    _cargarEstadoAlertas();
  }

  Future<void> _cargarEstadoAlertas() async {
    final preferencias = await SharedPreferences.getInstance();
    final hoy = DateTime.now().toIso8601String().substring(
      0,
      10,
    ); // Formato YYYY-MM-DD
    final fechaGuardada = preferencias.getString(
      'dashboard_fecha_ultimo_borrado',
    );

    if (!mounted) return;
    setState(() {
      _alertasLeidas
        ..clear()
        ..addAll(preferencias.getStringList(_alertasLeidasKey) ?? const []);

      // Lógica para las eliminadas:
      if (fechaGuardada == hoy) {
        // Es el mismo día, mantenemos las alertas que ya había borrado
        _alertasEliminadas
          ..clear()
          ..addAll(
            preferencias.getStringList(_alertasEliminadasKey) ?? const [],
          );
      } else {
        // Es un día nuevo (o es la primera vez), reiniciamos los borrados
        _alertasEliminadas.clear();
        preferencias.setString('dashboard_fecha_ultimo_borrado', hoy);
        preferencias.remove(_alertasEliminadasKey);
      }
      _estadoCargado = true;
    });
  }

  Future<void> _guardarEstadoAlertas() async {
    final leidas = _alertasLeidas.toList(growable: false);
    final eliminadas = _alertasEliminadas.toList(growable: false);
    final anterior = _guardadoAlertasPendiente ?? Future<void>.value();
    final siguiente = anterior.then((_) async {
      final preferencias = await SharedPreferences.getInstance();
      await Future.wait([
        preferencias.setStringList(_alertasLeidasKey, leidas),
        preferencias.setStringList(_alertasEliminadasKey, eliminadas),
      ]);
    });
    _guardadoAlertasPendiente = siguiente;
    await siguiente;
  }

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<GotaProvider>();
    if (demo.cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final ancho = MediaQuery.sizeOf(context).width;
    final dosColumnas = ancho > 650;
    final cantidadAlertas = !_estadoCargado
        ? 0
        : demo.cuotasDeHoy
                  .map((cuota) => _claveAlerta(cuota.id, 'hoy'))
                  .where(_visible)
                  .length +
              demo.moras
                  .expand((mora) => mora.cuotasAtrasadas)
                  .map((cuota) => _claveAlerta(cuota.id, 'mora'))
                  .where(_visible)
                  .length;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const GotaControlLogo(size: 40),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppStrings.appName,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  GotaDateUtils.formatearFecha(DateTime.now()),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notificaciones',
            onPressed: () => _mostrarNotificaciones(context, demo),
            icon: Badge(
              isLabelVisible: cantidadAlertas > 0,
              label: Text('$cantidadAlertas'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dashboard-new-loan',
        onPressed: widget.onNuevoPrestamo,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo préstamo'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              if (demo.avisoRespaldoInicio case final String aviso)
                Card(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  child: ListTile(
                    leading: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                    ),
                    title: const Text('Revisa el respaldo'),
                    subtitle: Text(aviso),
                  ),
                ),
              ResumenCard(
                titulo: AppStrings.profitToday,
                valor: GotaDateUtils.formatearMoneda(demo.gananciaHoy),
                icono: Icons.trending_up,
                color: AppColors.primary,
                destacado: true,
                subtitulo: 'Interés proporcional recibido',
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: dosColumnas ? 2.4 : 1.15,
                children: [
                  ResumenCard(
                    titulo: AppStrings.totalOnStreet,
                    valor: GotaDateUtils.formatearMoneda(demo.totalEnCalle),
                    icono: Icons.account_balance_wallet_outlined,
                    color: AppColors.orange,
                  ),
                  ResumenCard(
                    titulo: AppStrings.collectedToday,
                    valor: GotaDateUtils.formatearMoneda(demo.recaudadoHoy),
                    icono: Icons.payments_outlined,
                    color: AppColors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Estadisticas(
                clientes: demo.clientesActivos,
                enMora: demo.clientesEnMora,
                prestamos: demo.prestamosActivos.length,
                onClientes: widget.onClientes,
                onMora: widget.onMora,
                onPrestamos: widget.onPrestamos,
              ),
              const SizedBox(height: 26),
              _TituloSeccion(
                titulo: AppStrings.todayDue,
                contador: demo.cuotasDeHoy.length,
                trailing: IconButton(
                  tooltip: 'Ver lista de clientes',
                  onPressed: widget.onPrestamos,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
              const SizedBox(height: 8),
              if (demo.cuotasDeHoy.isEmpty)
                const _EstadoVacio(
                  mensaje: 'No hay cuotas pendientes para hoy.',
                )
              else
                ...demo.cuotasDeHoy.map((cuota) => _CobroDeHoy(cuota: cuota)),
              const SizedBox(height: 22),
              _TituloSeccion(
                titulo: AppStrings.overdueClients,
                contador: demo.moras.length,
                trailing: IconButton(
                  tooltip: 'Ver clientes en mora',
                  onPressed: widget.onMora,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
              const SizedBox(height: 8),
              if (demo.moras.isEmpty)
                const _EstadoVacio(mensaje: 'No hay préstamos atrasados.')
              else
                ...demo.moras.map(
                  (mora) => ClienteCard(
                    cliente: mora.cliente,
                    saldoPendiente: mora.prestamo.saldoPendiente,
                    estado: 'MORA',
                    diasAtraso: mora.diasAtraso,
                    onTap: () => _abrirDetalle(context, mora.prestamo),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static void _abrirDetalle(BuildContext context, Prestamo prestamo) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PrestamoDetailScreen(prestamoId: prestamo.id!),
      ),
    );
  }

  void _mostrarNotificaciones(BuildContext context, GotaProvider provider) {
    final cuotasVencidas =
        <({Prestamo prestamo, Cliente cliente, Cuota cuota})>[];
    for (final mora in provider.moras) {
      for (final cuota in mora.cuotasAtrasadas) {
        cuotasVencidas.add((
          prestamo: mora.prestamo,
          cliente: mora.cliente,
          cuota: cuota,
        ));
      }
    }
    final cuotasDeHoy = <({Prestamo prestamo, Cliente cliente, Cuota cuota})>[];
    for (final cuota in provider.cuotasDeHoy) {
      final prestamo = provider.prestamoPorId(cuota.prestamoId);
      final cliente = prestamo == null
          ? null
          : provider.clientePorId(prestamo.clienteId);
      if (prestamo != null && cliente != null) {
        cuotasDeHoy.add((prestamo: prestamo, cliente: cliente, cuota: cuota));
      }
    }

    // Marcar como leídas
    setState(() {
      _alertasLeidas.addAll([
        ...cuotasVencidas.map((a) => _claveAlerta(a.cuota.id, 'mora')),
        ...cuotasDeHoy.map((a) => _claveAlerta(a.cuota.id, 'hoy')),
      ]);
    });
    unawaited(_guardarEstadoAlertas());

    final ocultasEnPanel = <String>{};
    String? mensajeEliminacion;
    VoidCallback? deshacerEliminacion;
    Timer? temporizadorMensaje;

    void mostrarMensajeEliminacion(
      String clave,
      VoidCallback deshacer,
      void Function(VoidCallback callback) setSheetState,
    ) {
      temporizadorMensaje?.cancel();
      deshacerEliminacion = () {
        deshacer();
        setSheetState(() {
          mensajeEliminacion = null;
          deshacerEliminacion = null;
        });
      };
      setSheetState(() {
        mensajeEliminacion = clave;
      });
      temporizadorMensaje = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setSheetState(() {
            mensajeEliminacion = null;
            deshacerEliminacion = null;
          });
        }
      });
    }

    final modal = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.78,
              child: Stack(
                children: [
                  Positioned.fill(
                    bottom: mensajeEliminacion != null ? 60 : 0,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Alertas',
                                  style: Theme.of(
                                    sheetContext,
                                  ).textTheme.titleLarge,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar alertas',
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            cuotasVencidas.isEmpty && cuotasDeHoy.isEmpty
                                ? 'No tienes alertas pendientes.'
                                : '${cuotasVencidas.length} cuotas vencidas · ${cuotasDeHoy.length} cuotas para hoy',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (cuotasVencidas.any(
                            (alerta) =>
                                !_alertasEliminadas.contains(
                                  _claveAlerta(alerta.cuota.id, 'mora'),
                                ) &&
                                !ocultasEnPanel.contains(
                                  _claveAlerta(alerta.cuota.id, 'mora'),
                                ),
                          )) ...[
                            const SizedBox(height: 18),
                            Text(
                              'Cuotas vencidas',
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.titleMedium,
                            ),
                            ...cuotasVencidas
                                .where(
                                  (alerta) =>
                                      !_alertasEliminadas.contains(
                                        _claveAlerta(alerta.cuota.id, 'mora'),
                                      ) &&
                                      !ocultasEnPanel.contains(
                                        _claveAlerta(alerta.cuota.id, 'mora'),
                                      ),
                                )
                                .map(
                                  (alerta) => _alertaDeslizable(
                                    clave: _claveAlerta(
                                      alerta.cuota.id,
                                      'mora',
                                    ),
                                    titulo: alerta.cliente.nombre,
                                    icono: Icons.warning_amber_rounded,
                                    color: AppColors.warning,
                                    subtitulo:
                                        'Cuota ${alerta.cuota.numeroCuota} · venció '
                                        '${GotaDateUtils.formatearFecha(alerta.cuota.fechaVencimiento)} · '
                                        '${GotaDateUtils.formatearMoneda(alerta.cuota.montoCuota - alerta.cuota.montoPagado)}',
                                    onTap: () {
                                      Navigator.of(sheetContext).pop();
                                      _abrirDetalle(context, alerta.prestamo);
                                    },
                                    onDismissed: () {
                                      unawaited(
                                        _eliminarAlertaDelPanel(
                                          clave: _claveAlerta(
                                            alerta.cuota.id,
                                            'mora',
                                          ),
                                          ocultasEnPanel: ocultasEnPanel,
                                          setSheetState: setSheetState,
                                          mostrarMensaje: (deshacer) =>
                                              mostrarMensajeEliminacion(
                                                _claveAlerta(
                                                  alerta.cuota.id,
                                                  'mora',
                                                ),
                                                deshacer,
                                                setSheetState,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                          ],
                          if (cuotasDeHoy.any(
                            (alerta) =>
                                !_alertasEliminadas.contains(
                                  _claveAlerta(alerta.cuota.id, 'hoy'),
                                ) &&
                                !ocultasEnPanel.contains(
                                  _claveAlerta(alerta.cuota.id, 'hoy'),
                                ),
                          )) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Cuotas para hoy',
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.titleMedium,
                            ),
                            ...cuotasDeHoy
                                .where(
                                  (alerta) =>
                                      !_alertasEliminadas.contains(
                                        _claveAlerta(alerta.cuota.id, 'hoy'),
                                      ) &&
                                      !ocultasEnPanel.contains(
                                        _claveAlerta(alerta.cuota.id, 'hoy'),
                                      ),
                                )
                                .map(
                                  (alerta) => _alertaDeslizable(
                                    clave: _claveAlerta(alerta.cuota.id, 'hoy'),
                                    titulo: alerta.cliente.nombre,
                                    icono: Icons.event_available_outlined,
                                    color: AppColors.blue,
                                    subtitulo:
                                        'Cuota ${alerta.cuota.numeroCuota} · '
                                        '${GotaDateUtils.formatearMoneda(alerta.cuota.montoCuota - alerta.cuota.montoPagado)}',
                                    onTap: () {
                                      Navigator.of(sheetContext).pop();
                                      _abrirDetalle(context, alerta.prestamo);
                                    },
                                    onDismissed: () {
                                      unawaited(
                                        _eliminarAlertaDelPanel(
                                          clave: _claveAlerta(
                                            alerta.cuota.id,
                                            'hoy',
                                          ),
                                          ocultasEnPanel: ocultasEnPanel,
                                          setSheetState: setSheetState,
                                          mostrarMensaje: (deshacer) =>
                                              mostrarMensajeEliminacion(
                                                _claveAlerta(
                                                  alerta.cuota.id,
                                                  'hoy',
                                                ),
                                                deshacer,
                                                setSheetState,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (mensajeEliminacion != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Material(
                        color: AppColors.elevatedSurface,
                         borderRadius: BorderRadius.circular(8),
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Notificación eliminada',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              TextButton(
                                onPressed: deshacerEliminacion,
                                child: const Text('Deshacer'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    unawaited(modal.whenComplete(() => temporizadorMensaje?.cancel()));
  }

    Future<void> _eliminarAlertaDelPanel({
    required String clave,
    required Set<String> ocultasEnPanel,
    required void Function(VoidCallback callback) setSheetState,
    required void Function(VoidCallback deshacer) mostrarMensaje,
  }) async {
    ocultasEnPanel.add(clave);
    setSheetState(() {});
    setState(() => _alertasEliminadas.add(clave));

    mostrarMensaje(() {
      ocultasEnPanel.remove(clave);
      setSheetState(() {});
      setState(() => _alertasEliminadas.remove(clave));
      unawaited(_guardarEstadoAlertas());
    });

    await _guardarEstadoAlertas();
  }

    Widget _alertaDeslizable({
    required String clave,
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required Color color,
    required VoidCallback onTap,
    required VoidCallback onDismissed,
  }) {
    return Dismissible(
      key: ValueKey('alerta-$clave'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (_) async => true,
      // Fondo al deslizar hacia la IZQUIERDA (de derecha a izquierda)
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        color: AppColors.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      // Fondo al deslizar hacia la DERECHA (de izquierda a derecha) - ¡NUEVO!
      secondaryBackground: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 18),
        color: AppColors.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDismissed(),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icono, color: color),
        title: Text(titulo),
        subtitle: Text(subtitulo),
        onTap: onTap,
      ),
    );
  }
}

class _CobroDeHoy extends StatelessWidget {
  const _CobroDeHoy({required this.cuota});

  final Cuota cuota;

  @override
  Widget build(BuildContext context) {
    final demo = context.read<GotaProvider>();
    final prestamo = demo.prestamoPorId(cuota.prestamoId);
    final cliente = prestamo == null
        ? null
        : demo.clientePorId(prestamo.clienteId);
    if (prestamo == null || cliente == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.surface,
      child: ListTile(
        onTap: () => _DashboardScreenState._abrirDetalle(context, prestamo),
        leading: CircleAvatar(
          backgroundColor: AppColors.warning.withValues(alpha: 0.15),
          child: const Icon(Icons.person_outline, color: AppColors.warning),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                cliente.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              GotaDateUtils.formatearMoneda(
                cuota.montoCuota - cuota.montoPagado,
              ),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        subtitle: Text('Cuota ${cuota.numeroCuota} · ${cliente.telefono}'),
        trailing: IconButton(
          tooltip: 'Cobrar',
          onPressed: () => PaymentBottomSheet.show(
            context,
            cliente: cliente,
            prestamo: prestamo,
            cuota: cuota,
          ),
          icon: const Icon(Icons.payments_outlined, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _Estadisticas extends StatelessWidget {
  const _Estadisticas({
    required this.clientes,
    required this.enMora,
    required this.prestamos,
    required this.onClientes,
    required this.onMora,
    required this.onPrestamos,
  });

  final int clientes;
  final int enMora;
  final int prestamos;
  final VoidCallback onClientes;
  final VoidCallback onMora;
  final VoidCallback onPrestamos;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _DatoCompacto(
        label: 'Clientes',
        valor: '$clientes',
        icono: Icons.people_outline,
        onTap: onClientes,
      ),
      const SizedBox(width: 8),
      _DatoCompacto(
        label: 'En mora',
        valor: '$enMora',
        icono: Icons.warning_amber,
        color: enMora > 0 ? AppColors.error : AppColors.primary,
        onTap: onMora,
      ),
      const SizedBox(width: 8),
      _DatoCompacto(
        label: 'Préstamos',
        valor: '$prestamos',
        icono: Icons.receipt_long_outlined,
        onTap: onPrestamos,
      ),
    ],
  );
}

class _DatoCompacto extends StatelessWidget {
  const _DatoCompacto({
    required this.label,
    required this.valor,
    required this.icono,
    required this.onTap,
    this.color = AppColors.textSecondary,
  });

  final String label;
  final String valor;
  final IconData icono;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, color: color, size: 19),
              const SizedBox(height: 8),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion({required this.titulo, this.contador, this.trailing});

  final String titulo;
  final int? contador;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          titulo,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      if (contador case final contador?)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.elevatedSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$contador',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ?trailing,
    ],
  );
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.mensaje});
  final String mensaje;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      mensaje,
      style: const TextStyle(color: AppColors.textSecondary),
    ),
  );
}
