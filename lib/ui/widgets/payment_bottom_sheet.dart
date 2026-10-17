import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/miles_input_formatter.dart';
import '../../data/models/cliente.dart';
import '../../data/models/cuota.dart';
import '../../data/models/prestamo.dart';
import '../../logic/providers/gota_provider.dart';
import '../../logic/services/notificacion_service.dart';

class PaymentBottomSheet extends StatefulWidget {
  const PaymentBottomSheet({
    super.key,
    required this.cliente,
    required this.prestamo,
    required this.cuota,
  });

  final Cliente cliente;
  final Prestamo prestamo;
  final Cuota cuota;

  static Future<void> show(
    BuildContext context, {
    required Cliente cliente,
    required Prestamo prestamo,
    required Cuota cuota,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        PaymentBottomSheet(cliente: cliente, prestamo: prestamo, cuota: cuota),
  );

  @override
  State<PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends State<PaymentBottomSheet> {
  late final TextEditingController _montoController;
  final _notaController = TextEditingController();
  DateTime _fecha = DateTime.now();
  String _metodo = 'EFECTIVO';
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final saldo = widget.cuota.montoCuota - widget.cuota.montoPagado;
    // Formatear con separadores de miles igual que MilesInputFormatter
    _montoController = TextEditingController(
      text: _formatearMiles(saldo.round().toString()),
    );
  }

  @override
  void dispose() {
    _montoController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  static String _formatearMiles(String digitos) {
    final buffer = StringBuffer();
    for (var i = 0; i < digitos.length; i++) {
      if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digitos[i]);
    }
    return buffer.toString();
  }

  double? _parsearMonto(String texto) {
    final limpio = texto.replaceAll('.', '').replaceAll(',', '').trim();
    if (limpio.isEmpty) return null;
    return double.tryParse(limpio);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Registrar pago',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              widget.cliente.nombre,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _montoController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                LengthLimitingTextInputFormatter(15),
                const MilesInputFormatter(maxDigits: 12),
              ],
              decoration: InputDecoration(
                labelText: 'Monto recibido',
                prefixText: '\$ ',
                helperText:
                    'Saldo de esta cuota: ${GotaDateUtils.formatearMoneda(widget.cuota.montoCuota - widget.cuota.montoPagado)}',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _elegirFecha,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(GotaDateUtils.formatearFecha(_fecha)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _metodo,
              decoration: const InputDecoration(labelText: 'Método de pago'),
              items: const [
                DropdownMenuItem(value: 'EFECTIVO', child: Text('Efectivo')),
                DropdownMenuItem(value: 'NEQUI', child: Text('Nequi')),
                DropdownMenuItem(value: 'DAVIPLATA', child: Text('Daviplata')),
                DropdownMenuItem(
                  value: 'TRANSFERENCIA',
                  child: Text('Transferencia'),
                ),
              ],
              onChanged: (value) => setState(() => _metodo = value ?? _metodo),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notaController,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _guardando ? null : _confirmar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(_guardando ? 'Guardando...' : 'Confirmar pago'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _elegirFecha() async {
    final seleccion = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (seleccion != null && mounted) setState(() => _fecha = seleccion);
  }

  Future<void> _confirmar() async {
    if (_guardando) return;
    final monto = _parsearMonto(_montoController.text);
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Ingresa un monto válido mayor a cero.');
      return;
    }

    final prestamo = widget.prestamo;
    final cuota = widget.cuota;
    if (prestamo.id == null || cuota.id == null) {
      setState(() => _error = 'Datos del préstamo incompletos.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final provider = context.read<GotaProvider>();
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      await provider.registrarPago(
        prestamoId: prestamo.id!,
        cuotaId: cuota.id!,
        monto: monto,
        metodoPago: _metodo,
        fecha: _fecha,
        nota: _notaController.text.trim().isEmpty
            ? null
            : _notaController.text.trim(),
      );

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Pago registrado correctamente'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      unawaited(_actualizarDatosDespuesDelPago(provider, messenger));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = error
            .toString()
            .replaceFirst('ArgumentError: ', '')
            .replaceFirst('StateError: ', '')
            .replaceFirst('DatabaseException(', '');
      });
    }
  }

  Future<void> _actualizarDatosDespuesDelPago(
    GotaProvider provider,
    ScaffoldMessengerState messenger,
  ) async {
    try {
      await provider.cargarDatos(mostrarCarga: false);
      final errorCarga = provider.errorCarga;
      if (errorCarga != null) {
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'El pago se guardó, pero no se pudo actualizar la información: '
                '$errorCarga',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      await NotificacionService.instance.sincronizarConDatos(provider);
    } on Object catch (error, stackTrace) {
      debugPrint(
        'GotaControl: error actualizando datos tras pago: $error\n$stackTrace',
      );
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'El pago se guardó, pero no se pudieron actualizar las '
              'notificaciones: $error',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
