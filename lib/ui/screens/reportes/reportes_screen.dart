import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/cliente.dart';
import '../../../logic/providers/gota_provider.dart';
import '../../../logic/services/calculadora_service.dart';
import 'pdf_generator.dart';

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  String _tipo = 'diario';
  DateTime _fecha = DateTime.now();
  int? _clienteId;
  bool _vistaPrevia = false;
  bool _generando = false;
  bool _pdfAmpliado = false;
  int _pdfPreviewKey = 0;
  Uint8List? _bytesReporte;

  static const _reportes = {
    'diario': ('Reporte diario', Icons.today_outlined),
    'semanal': ('Reporte semanal', Icons.view_week_outlined),
    'mensual': ('Reporte mensual', Icons.bar_chart_outlined),
    'mora': ('Reporte de mora', Icons.warning_amber_outlined),
    'cliente': ('Estado de cuenta', Icons.person_search_outlined),
    'estadisticas': ('Estadísticas del Negocio', Icons.insights_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<GotaProvider>();
    final cliente = _clienteId == null ? null : demo.clientePorId(_clienteId!);
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Text(
                'Selecciona un reporte',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.6,
                children: [
                  for (final entrada in _reportes.entries)
                    _ReporteChoice(
                      titulo: entrada.value.$1,
                      icono: entrada.value.$2,
                      seleccionado: _tipo == entrada.key,
                      onTap: () => setState(() {
                        _tipo = entrada.key;
                        _vistaPrevia = false;
                        _pdfAmpliado = false;
                        _bytesReporte = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_tipo == 'cliente')
                DropdownButtonFormField<int>(
                  initialValue: _clienteId,
                  decoration: const InputDecoration(labelText: 'Cliente'),
                  items: demo.clientes
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.nombre),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) => setState(() {
                    _clienteId = valor;
                    _vistaPrevia = false;
                    _pdfAmpliado = false;
                    _bytesReporte = null;
                  }),
                )
              else if (_tipo != 'estadisticas')
                OutlinedButton.icon(
                  onPressed: _seleccionarFecha,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    _tipo == 'mensual'
                        ? DateFormatUtils.mes(_fecha)
                        : GotaDateUtils.formatearFecha(_fecha),
                  ),
                ),
              const SizedBox(height: 14),
              _ResumenPreview(
                demo: demo,
                tipo: _tipo,
                cliente: cliente,
                fecha: _fecha,
              ),
              const SizedBox(height: 16),
              if (_vistaPrevia) ...[
                SizedBox(
                  height: 620,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        PdfPreview(
                          key: ValueKey(_pdfPreviewKey),
                          build: (_) async =>
                              _bytesReporte ??
                              await _generarBytes(demo, cliente),
                          pdfFileName: 'GotaControl-$_tipo.pdf',
                          canChangeOrientation: false,
                          canChangePageFormat: false,
                          allowPrinting: false,
                          allowSharing: false,
                          onZoomChanged: (ampliado) {
                            if (_pdfAmpliado != ampliado && mounted) {
                              setState(() => _pdfAmpliado = ampliado);
                            }
                          },
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton.filledTonal(
                            tooltip: _pdfAmpliado
                                ? 'Volver al tamaño normal'
                                : 'Ampliar reporte',
                            onPressed: _pdfAmpliado
                                ? _restaurarVistaPdf
                                : _abrirVistaPdfCompleta,
                            icon: Icon(
                              _pdfAmpliado
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _generando
                            ? null
                            : () => _ejecutarAccion(
                                () async => PdfGenerator.imprimir(
                                  await _generarBytes(demo, cliente),
                                ),
                              ),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Imprimir / guardar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _generando
                            ? null
                            : () => _ejecutarAccion(
                                () async => PdfGenerator.compartir(
                                  await _generarBytes(demo, cliente),
                                  nombre: 'GotaControl-$_tipo.pdf',
                                ),
                              ),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Compartir'),
                      ),
                    ),
                  ],
                ),
              ] else
                FilledButton.icon(
                  onPressed:
                      _generando || (_tipo == 'cliente' && cliente == null)
                      ? null
                      : () => _crearVistaPrevia(demo, cliente),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _generando ? 'Generando reporte...' : 'Vista previa PDF',
                    ),
                  ),
                ),
              if (_generando) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (fecha != null) {
      setState(() {
        _fecha = fecha;
        _vistaPrevia = false;
        _pdfAmpliado = false;
        _bytesReporte = null;
      });
    }
  }

  void _restaurarVistaPdf() {
    setState(() {
      _pdfAmpliado = false;
      _pdfPreviewKey++;
    });
  }

  Future<void> _abrirVistaPdfCompleta() async {
    final bytes = _bytesReporte;
    if (bytes == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _VistaPdfCompleta(bytes: bytes, nombre: 'GotaControl-$_tipo.pdf'),
    );
  }

  Future<void> _crearVistaPrevia(GotaProvider demo, Cliente? cliente) async {
    setState(() => _generando = true);
    try {
      final bytes = await _generarBytes(demo, cliente);
      if (!mounted) return;
      setState(() {
        _bytesReporte = bytes;
        _vistaPrevia = true;
        _pdfAmpliado = false;
        _pdfPreviewKey++;
      });
    } on Object catch (error) {
      _mostrarError('No se pudo generar el reporte: $error');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _ejecutarAccion(Future<void> Function() accion) async {
    setState(() => _generando = true);
    try {
      await accion();
    } on Object catch (error) {
      _mostrarError('No se pudo completar la acción del reporte: $error');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<Uint8List> _generarBytes(GotaProvider demo, Cliente? cliente) =>
      switch (_tipo) {
        'diario' => PdfGenerator.reporteDiario(demo, _fecha),
        'semanal' => PdfGenerator.reporteSemanal(demo, _fecha),
        'mensual' => PdfGenerator.reporteMensual(demo, _fecha),
        'mora' => PdfGenerator.reporteMora(demo, _fecha),
        'estadisticas' => PdfGenerator.reporteEstadisticas(demo),
        'cliente' when cliente != null => PdfGenerator.estadoCuenta(
          demo,
          cliente,
        ),
        _ => Future.error(
          StateError('Selecciona un cliente para generar el estado de cuenta.'),
        ),
      };
}

class _VistaPdfCompleta extends StatefulWidget {
  const _VistaPdfCompleta({required this.bytes, required this.nombre});

  final Uint8List bytes;
  final String nombre;

  @override
  State<_VistaPdfCompleta> createState() => _VistaPdfCompletaState();
}

class _VistaPdfCompletaState extends State<_VistaPdfCompleta> {
  bool _pdfAmpliado = false;
  int _pdfPreviewKey = 0;

  void _restaurarVistaPdf() {
    setState(() {
      _pdfAmpliado = false;
      _pdfPreviewKey++;
    });
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: PdfPreview(
              key: ValueKey(_pdfPreviewKey),
              build: (_) async => widget.bytes,
              pdfFileName: widget.nombre,
              canChangeOrientation: false,
              canChangePageFormat: false,
              allowPrinting: false,
              allowSharing: false,
              onZoomChanged: (ampliado) {
                if (_pdfAmpliado != ampliado && mounted) {
                  setState(() => _pdfAmpliado = ampliado);
                }
              },
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filledTonal(
              tooltip: _pdfAmpliado
                  ? 'Volver al tamaño normal'
                  : 'Cerrar vista ampliada',
              onPressed: _pdfAmpliado
                  ? _restaurarVistaPdf
                  : () => Navigator.of(context).pop(),
              icon: Icon(
                _pdfAmpliado ? Icons.fullscreen_exit : Icons.close_fullscreen,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReporteChoice extends StatelessWidget {
  const _ReporteChoice({
    required this.titulo,
    required this.icono,
    required this.seleccionado,
    required this.onTap,
  });
  final String titulo;
  final IconData icono;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: seleccionado
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: seleccionado ? AppColors.primary : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(
            icono,
            color: seleccionado ? AppColors.primary : AppColors.textSecondary,
          ),
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _ResumenPreview extends StatelessWidget {
  const _ResumenPreview({
    required this.demo,
    required this.tipo,
    required this.cliente,
    required this.fecha,
  });
  final GotaProvider demo;
  final String tipo;
  final Cliente? cliente;
  final DateTime fecha;

  @override
  Widget build(BuildContext context) {
    final periodo = _periodo(tipo, fecha);
    final pagosPeriodo = demo.pagos
        .where(
          (pago) =>
              !pago.fechaHora.isBefore(periodo.$1) &&
              pago.fechaHora.isBefore(periodo.$2),
        )
        .toList();
    final recaudoPeriodo = pagosPeriodo.fold(
      0.0,
      (total, pago) => total + pago.monto,
    );
    final gananciaPeriodo = pagosPeriodo.fold(0.0, (total, pago) {
      final prestamo = demo.prestamoPorId(pago.prestamoId);
      final esPenalizacion = demo
          .cuotasDePrestamo(pago.prestamoId)
          .any((cuota) => cuota.id == pago.cuotaId && cuota.esPenalizacion);
      if (prestamo == null || esPenalizacion) return total;
      return total +
          const CalculadoraService().calcularGananciaProporcional(
            montoPagado: pago.monto,
            totalPagar: prestamo.montoTotalPagar,
            interesTotal: prestamo.montoInteres,
          );
    });
    final mesesConPrestamos = demo.prestamos
        .map(
          (prestamo) =>
              '${prestamo.fechaInicio.year}-${prestamo.fechaInicio.month}',
        )
        .toSet();
    final filas = switch (tipo) {
      'diario' => [
        ('Recaudo', GotaDateUtils.formatearMoneda(recaudoPeriodo)),
        ('Ganancia', GotaDateUtils.formatearMoneda(gananciaPeriodo)),
        ('Pagos', '${pagosPeriodo.length}'),
      ],
      'semanal' => [
        (
          'Período',
          '${GotaDateUtils.formatearFecha(periodo.$1)} - '
              '${GotaDateUtils.formatearFecha(periodo.$2.subtract(const Duration(days: 1)))}',
        ),
        ('Recaudo', GotaDateUtils.formatearMoneda(recaudoPeriodo)),
        ('Ganancia', GotaDateUtils.formatearMoneda(gananciaPeriodo)),
        ('Pagos', '${pagosPeriodo.length}'),
      ],
      'mensual' => [
        ('Mes', DateFormatUtils.mes(fecha)),
        ('Recaudo', GotaDateUtils.formatearMoneda(recaudoPeriodo)),
        ('Operaciones registradas', '${pagosPeriodo.length}'),
        ('Interés recibido', GotaDateUtils.formatearMoneda(gananciaPeriodo)),
      ],
      'mora' => [
        ('Préstamos atrasados', '${demo.moras.length}'),
        (
          'Saldo en mora',
          GotaDateUtils.formatearMoneda(
            demo.moras.fold(
              0.0,
              (total, mora) => total + mora.prestamo.saldoPendiente,
            ),
          ),
        ),
      ],
      'estadisticas' => [
        (
          'Capital activo',
          GotaDateUtils.formatearMoneda(
            demo.prestamos.fold(
              0.0,
              (total, prestamo) => total + prestamo.montoCapital,
            ),
          ),
        ),
        (
          'Interés esperado activo',
          GotaDateUtils.formatearMoneda(
            demo.prestamos.fold(
              0.0,
              (total, prestamo) => total + prestamo.montoInteres,
            ),
          ),
        ),
        ('Meses con préstamos', '${mesesConPrestamos.length}'),
      ],
      _ => [
        ('Cliente', cliente?.nombre ?? 'Selecciona un cliente'),
        (
          'Préstamos',
          '${cliente == null ? 0 : demo.prestamosDeCliente(cliente!.id!).length}',
        ),
        (
          'Saldo',
          GotaDateUtils.formatearMoneda(
            cliente == null
                ? 0
                : demo
                      .prestamosDeCliente(cliente!.id!)
                      .fold(
                        0.0,
                        (total, prestamo) => total + prestamo.saldoPendiente,
                      ),
          ),
        ),
      ],
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen del reporte',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final fila in filas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fila.$1,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  Text(
                    fila.$2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  (DateTime, DateTime) _periodo(String tipo, DateTime fecha) {
    final inicioDia = DateTime(fecha.year, fecha.month, fecha.day);
    return switch (tipo) {
      'diario' => (inicioDia, inicioDia.add(const Duration(days: 1))),
      'semanal' => (
        inicioDia.subtract(Duration(days: inicioDia.weekday - DateTime.monday)),
        inicioDia
            .subtract(Duration(days: inicioDia.weekday - DateTime.monday))
            .add(const Duration(days: 7)),
      ),
      'mensual' => (
        DateTime(fecha.year, fecha.month, 1),
        DateTime(fecha.year, fecha.month + 1, 1),
      ),
      _ => (DateTime(1970), DateTime(1970)),
    };
  }
}

class DateFormatUtils {
  DateFormatUtils._();
  static String mes(DateTime fecha) {
    const nombres = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${nombres[fecha.month - 1]} ${fecha.year}';
  }
}
