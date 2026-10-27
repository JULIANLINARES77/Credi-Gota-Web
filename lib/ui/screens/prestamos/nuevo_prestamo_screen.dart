import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/miles_input_formatter.dart';
import '../../../data/models/prestamo.dart';
import '../../../logic/providers/gota_provider.dart';
import '../../../logic/services/calculadora_service.dart';
import '../../../logic/services/notificacion_service.dart';
import '../../widgets/cliente_form_dialog.dart';
import '../../widgets/resumen_card.dart';
import 'prestamos_cliente_screen.dart';

class NuevoPrestamoScreen extends StatefulWidget {
  const NuevoPrestamoScreen({super.key});

  @override
  State<NuevoPrestamoScreen> createState() => _NuevoPrestamoScreenState();
}

class _NuevoPrestamoScreenState extends State<NuevoPrestamoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _capital = TextEditingController();
  final _interes = TextEditingController(text: '20');
  final _cuotas = TextEditingController(text: '24');
  final _calculadora = const CalculadoraService();
  Timer? _debounce;
  bool _creandoPrestamo = false;
  bool _diasCorridos = false;
  DateTime _fechaInicio = DateTime.now();
  int? _clienteId;
  String _frecuencia = CalculadoraService.frecuenciaLunesMiercolesViernes;
  final Set<int> _dias = {DateTime.monday, DateTime.wednesday, DateTime.friday};

  static const _opcionesFrecuencia = {
    CalculadoraService.frecuenciaDiaria: 'Diaria',
    CalculadoraService.frecuenciaSemanal: 'Semanal',
    CalculadoraService.frecuenciaQuincenal: 'Quincenal',
    CalculadoraService.frecuenciaMensual: 'Mensual',
    CalculadoraService.frecuenciaLunesMiercolesViernes:
        'Lunes, miércoles y viernes',
    CalculadoraService.frecuenciaPersonalizada: 'Días personalizados',
  };

  @override
  void initState() {
    super.initState();
    _capital.addListener(_actualizar);
    _interes.addListener(_actualizar);
    _cuotas.addListener(_actualizar);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _capital.dispose();
    _interes.dispose();
    _cuotas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<GotaProvider>();
    _clienteId ??= demo.clientes.isEmpty ? null : demo.clientes.first.id;
    final calculo = _calculoPreview();
    final fechas = _fechasPreview();
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo préstamo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const _Paso(titulo: '1. Selecciona el cliente'),
                const SizedBox(height: 10),
                if (demo.clientes.isEmpty)
                  const Text(
                    'Primero agrega un cliente para continuar.',
                    style: TextStyle(color: AppColors.warning),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _clienteId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Cliente',
                          ),
                          items: demo.clientes
                              .where((cliente) => cliente.id != null)
                              .map(
                                (cliente) => DropdownMenuItem(
                                  value: cliente.id,
                                  child: Text(
                                    cliente.nombre,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (valor) =>
                              setState(() => _clienteId = valor),
                          validator: (valor) =>
                              valor == null ? 'Selecciona un cliente' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Crear cliente',
                        onPressed: _crearClienteRapido,
                        icon: const Icon(Icons.person_add_alt_1),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                const _Paso(titulo: '2. Datos del préstamo'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _capital,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(15),
                    const MilesInputFormatter(maxDigits: 12),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Capital prestado',
                    prefixText: '\$ ',
                    hintText: 'Múltiplos de 1.000 (de 10.000 a 100.000.000)',
                  ),
                  validator: _validarCapital,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final campoInteres = TextFormField(
                      controller: _interes,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Interés (%)',
                        suffixText: '%',
                      ),
                      validator: _validarInteres,
                    );
                    final campoCuotas = TextFormField(
                      controller: _cuotas,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Número de cuotas',
                      ),
                      validator: _validarCuotas,
                    );
                    return constraints.maxWidth < 430
                        ? Column(
                            children: [
                              campoInteres,
                              const SizedBox(height: 12),
                              campoCuotas,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: campoInteres),
                              const SizedBox(width: 10),
                              Expanded(child: campoCuotas),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _frecuencia,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Frecuencia de pago',
                  ),
                  items: _opcionesFrecuencia.entries
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.key,
                          child: Text(
                            item.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) =>
                      setState(() => _frecuencia = valor ?? _frecuencia),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _elegirFechaInicio,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    'Fecha de inicio · '
                    '${GotaDateUtils.formatearFecha(_fechaInicio)}',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Días corridos'),
                  subtitle: Text(
                    _diasCorridos
                        ? 'Incluye domingos y festivos colombianos.'
                        : 'Las cuotas pasan al siguiente día hábil si caen en fin de semana o festivo.',
                  ),
                  value: _diasCorridos,
                  onChanged: (valor) => setState(() => _diasCorridos = valor),
                ),
                if (_frecuencia ==
                    CalculadoraService.frecuenciaPersonalizada) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Días de pago',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    children: [
                      for (var dia = 1; dia <= 7; dia++)
                        FilterChip(
                          label: Text(
                            GotaDateUtils.obtenerNombreDia(dia).substring(0, 3),
                          ),
                          selected: _dias.contains(dia),
                          onSelected: (seleccionado) => setState(() {
                            if (seleccionado) {
                              _dias.add(dia);
                            } else {
                              _dias.remove(dia);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                const _Paso(titulo: '3. Resumen'),
                const SizedBox(height: 10),
                if (calculo != null && fechas != null)
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ResumenCard(
                              titulo: 'Total a pagar',
                              valor: GotaDateUtils.formatearMoneda(
                                calculo.montoTotalPagar,
                              ),
                              icono: Icons.account_balance_outlined,
                              color: AppColors.blue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ResumenCard(
                              titulo:
                                  calculo.valorCuota == calculo.valorCuotaMaxima
                                  ? 'Valor de cuota'
                                  : 'Cuotas entre',
                              valor:
                                  calculo.valorCuota == calculo.valorCuotaMaxima
                                  ? GotaDateUtils.formatearMoneda(
                                      calculo.valorCuota,
                                    )
                                  : '${GotaDateUtils.formatearMoneda(calculo.valorCuota)} y ${GotaDateUtils.formatearMoneda(calculo.valorCuotaMaxima)}',
                              icono: Icons.event_repeat,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_month_outlined,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Final estimado · ${GotaDateUtils.formatearFecha(fechas.last)}',
                              ),
                            ),
                            Text(
                              'Ganancia ${GotaDateUtils.formatearMoneda(calculo.montoInteres)}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  const Text(
                    'Completa capital, interés y cuotas para ver el cálculo.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: demo.clientes.isEmpty || _creandoPrestamo
                      ? null
                      : () => _crearPrestamo(demo),
                  icon: _creandoPrestamo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_circle_outline),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      _creandoPrestamo ? 'Guardando...' : 'Crear préstamo',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double? _parsear(String? valor) =>
      double.tryParse((valor ?? '').trim().replaceAll(',', '.'));

  double? _parsearCapital(String? valor) =>
      double.tryParse((valor ?? '').replaceAll('.', '').trim());

  String? _validarCapital(String? valor) {
    final capital = _parsearCapital(valor);
    if (capital == null ||
        !capital.isFinite ||
        capital < 10000 ||
        capital > 100000000) {
      return 'El capital debe estar entre \$10.000 y \$100.000.000';
    }
    if (capital % 1000 != 0) {
      return 'El capital debe ser múltiplo de \$1.000';
    }
    return null;
  }

  String? _validarInteres(String? valor) {
    final interes = _parsear(valor);
    if (interes == null || !interes.isFinite || interes < 0 || interes > 100) {
      return 'El interés debe estar entre 0% y 100%';
    }
    return null;
  }

  String? _validarCuotas(String? valor) {
    final cantidad = int.tryParse(valor ?? '');
    if (cantidad == null || cantidad < 1 || cantidad > 365) {
      return 'El número de cuotas debe estar entre 1 y 365';
    }
    final capital = _parsearCapital(_capital.text);
    final interes = _parsear(_interes.text);
    if (capital != null &&
        capital >= 10000 &&
        capital <= 100000000 &&
        interes != null &&
        interes >= 0 &&
        interes <= 100) {
      try {
        _calculadora.calcularPrestamo(
          capital: capital,
          porcentajeInteres: interes,
          numCuotas: cantidad,
        );
      } on ArgumentError catch (error) {
        if (error.name == 'numCuotas') {
          return 'Cada cuota debe ser de al menos \$1.000';
        }
      }
    }
    return null;
  }

  ResultadoCalculoPrestamo? _calculoPreview() {
    final capital = _parsearCapital(_capital.text);
    final interes = _parsear(_interes.text);
    final cantidad = int.tryParse(_cuotas.text);
    if (capital == null ||
        interes == null ||
        cantidad == null ||
        !capital.isFinite ||
        capital < 10000 ||
        capital > 100000000 ||
        !interes.isFinite ||
        interes < 0 ||
        interes > 100 ||
        cantidad < 1 ||
        cantidad > 365) {
      return null;
    }
    try {
      return _calculadora.calcularPrestamo(
        capital: capital,
        porcentajeInteres: interes,
        numCuotas: cantidad,
      );
    } on Object {
      return null;
    }
  }

  List<DateTime>? _fechasPreview() {
    final cantidad = int.tryParse(_cuotas.text);
    if (cantidad == null ||
        cantidad < 1 ||
        cantidad > 365 ||
        (_frecuencia == CalculadoraService.frecuenciaPersonalizada &&
            _dias.isEmpty)) {
      return null;
    }
    try {
      return _calculadora.generarFechasPago(
        fechaInicio: _fechaInicio,
        numCuotas: cantidad,
        frecuencia: _frecuencia,
        diasPersonalizados:
            _frecuencia == CalculadoraService.frecuenciaPersonalizada
            ? _dias.toList()
            : null,
        diasCorridos: _diasCorridos,
      );
    } on Object {
      return null;
    }
  }

  void _actualizar() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _crearPrestamo(GotaProvider demo) async {
    if (_creandoPrestamo) return;
    if (!_formKey.currentState!.validate()) return;
    if (_clienteId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente.')));
      return;
    }
    if (_frecuencia == CalculadoraService.frecuenciaPersonalizada &&
        _dias.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un día de pago.')),
      );
      return;
    }

    final Prestamo prestamo;
    setState(() => _creandoPrestamo = true);
    try {
      prestamo = await demo.crearPrestamo(
        clienteId: _clienteId!,
        capital: _parsearCapital(_capital.text)!,
        porcentajeInteres: _parsear(_interes.text)!,
        numCuotas: int.parse(_cuotas.text),
        frecuencia: _frecuencia,
        fechaInicio: _fechaInicio,
        diasPersonalizados:
            _frecuencia == CalculadoraService.frecuenciaPersonalizada
            ? _dias.toList()
            : null,
        diasCorridos: _diasCorridos,
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _creandoPrestamo = false);
      final mensaje = error
          .toString()
          .replaceFirst('ArgumentError: ', '')
          .replaceFirst('StateError: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));
      return;
    }
    if (!mounted) return;
    String? errorNotificaciones;
    try {
      await NotificacionService.instance.sincronizarConDatos(demo);
    } on Object catch (error) {
      errorNotificaciones = error.toString();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errorNotificaciones == null
              ? '✅ Préstamo creado correctamente'
              : 'Préstamo creado, pero no se actualizaron las notificaciones: '
                    '$errorNotificaciones',
        ),
        duration: errorNotificaciones == null
            ? const Duration(milliseconds: 1400)
            : const Duration(seconds: 4),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    final clienteId = prestamo.clienteId;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PrestamosClienteScreen(clienteId: clienteId),
      ),
    );
    if (mounted) {
      setState(() => _creandoPrestamo = false);
      _capital.clear();
    }
  }

  Future<void> _elegirFechaInicio() async {
    final hoy = DateTime.now();
    final seleccion = await showDatePicker(
      context: context,
      initialDate: _fechaInicio,
      firstDate: DateTime(2020),
      // Permitimos seleccionar hasta 2 años hacia adelante
      lastDate: DateTime(hoy.year + 2, hoy.month, hoy.day), 
    );
    if (seleccion != null && mounted) {
      setState(
        () => _fechaInicio = DateTime(
          seleccion.year,
          seleccion.month,
          seleccion.day,
        ),
      );
    }
  }

  Future<void> _crearClienteRapido() async {
    final datos = await mostrarClienteFormDialog(context);
    if (datos == null || !mounted) return;

    try {
      final cliente = await context.read<GotaProvider>().agregarCliente(
        nombre: datos.nombre,
        telefono: datos.telefono,
        cedula: datos.cedula,
        direccion: datos.direccion,
      );
      if (!mounted) return;
      setState(() => _clienteId = cliente.id);
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
}

class _Paso extends StatelessWidget {
  const _Paso({required this.titulo});
  final String titulo;
  @override
  Widget build(BuildContext context) => Text(
    titulo,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
  );
}
