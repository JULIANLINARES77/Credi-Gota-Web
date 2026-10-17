import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/db_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../../logic/providers/gota_provider.dart';
import '../../../logic/services/ajustes_negocio_validator.dart';
import '../../../logic/services/database_export_service.dart';
import '../../../logic/services/local_backup_service.dart';
import '../../../logic/services/notificacion_service.dart';
import '../../../logic/services/pin_hash_service.dart';
import '../reportes/pdf_generator.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _negocio = TextEditingController(text: 'GotaControl');
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final _porcentajeMora = TextEditingController(text: '10');
  final _diasGracia = TextEditingController(text: '3');
  bool _alertasMora = true;
  bool _recordatorioDiario = false;
  TimeOfDay _horaRecordatorio = const TimeOfDay(hour: 8, minute: 0);
  bool _configuracionCargada = false;
  bool _guardando = false;
  bool _respaldoOcupado = false;
  bool _respaldoInicializado = false;
  BackupFrequency _frecuenciaRespaldo = BackupFrequency.daily;
  LocalBackupStatus? _estadoRespaldo;
  String? _errorRespaldo;
  bool? _notificacionesHabilitadas;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_consultarPermisoNotificaciones());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _negocio.dispose();
    _telefono.dispose();
    _direccion.dispose();
    _porcentajeMora.dispose();
    _diasGracia.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_consultarPermisoNotificaciones());
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GotaProvider>();
    final configuracion = provider.configuracion;
    if (!_configuracionCargada && configuracion != null) {
      _configuracionCargada = true;
      _frecuenciaRespaldo = BackupFrequency.fromValue(
        configuracion[DbConstants.configuracionFrecuenciaRespaldo],
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _negocio.text =
              configuracion[DbConstants.configuracionNombreNegocio]
                  as String? ??
              'GotaControl';
          _telefono.text =
              configuracion[DbConstants.configuracionTelefonoNegocio]
                  as String? ??
              '';
          _direccion.text =
              configuracion[DbConstants.configuracionDireccionNegocio]
                  as String? ??
              '';
          _porcentajeMora.text =
              '${configuracion[DbConstants.configuracionPorcentajeMora] ?? 10}';
          _diasGracia.text =
              '${configuracion[DbConstants.configuracionDiasGraciaMora] ?? 3}';
          _alertasMora =
              ((configuracion[DbConstants.configuracionAlertasMora] as num?)
                      ?.toInt() ??
                  1) !=
              0;
          _recordatorioDiario =
              ((configuracion[DbConstants.configuracionRecordatorioDiario]
                          as num?)
                      ?.toInt() ??
                  0) !=
              0;
          final hora =
              (configuracion[DbConstants.configuracionHoraRecordatorio]
                          as String? ??
                      '08:00')
                  .split(':');
          _horaRecordatorio = TimeOfDay(
            hour: int.parse(hora[0]),
            minute: int.parse(hora[1]),
          );
        });
        _inicializarRespaldo();
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _Seccion(
                      titulo: 'Datos del negocio',
                      icono: Icons.storefront_outlined,
                      children: [
                        TextFormField(
                          controller: _negocio,
                          maxLength: AjustesNegocioValidator.maxNombre,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              AjustesNegocioValidator.maxNombre,
                            ),
                          ],
                          validator: (value) => _validarTexto(
                            value,
                            requerido: true,
                            maximo: AjustesNegocioValidator.maxNombre,
                            etiqueta: 'El nombre del negocio',
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Nombre del negocio',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _telefono,
                          keyboardType: TextInputType.phone,
                          maxLength: AjustesNegocioValidator.maxTelefono,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              AjustesNegocioValidator.maxTelefono,
                            ),
                          ],
                          validator: (value) => _validarTexto(
                            value,
                            maximo: AjustesNegocioValidator.maxTelefono,
                            etiqueta: 'El teléfono',
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Teléfono (opcional)',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _direccion,
                          maxLength: AjustesNegocioValidator.maxDireccion,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              AjustesNegocioValidator.maxDireccion,
                            ),
                          ],
                          validator: (value) => _validarTexto(
                            value,
                            maximo: AjustesNegocioValidator.maxDireccion,
                            etiqueta: 'La dirección',
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Dirección (opcional)',
                          ),
                        ),
                      ],
                    ),
                    _Seccion(
                      titulo: 'Configuración de mora',
                      icono: Icons.warning_amber_outlined,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _porcentajeMora,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                maxLength: 6,
                                validator: _validarPorcentajeMora,
                                decoration: const InputDecoration(
                                  labelText: 'Porcentaje de mora',
                                  suffixText: '%',
                                  counterText: '',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _diasGracia,
                                keyboardType: TextInputType.number,
                                maxLength: 3,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                validator: _validarDiasGracia,
                                decoration: const InputDecoration(
                                  labelText: 'Días de gracia',
                                  counterText: '',
                                ),
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Alertas de mora'),
                          value: _alertasMora,
                          onChanged: (valor) =>
                              setState(() => _alertasMora = valor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _Seccion(
                titulo: 'Seguridad',
                icono: Icons.lock_outline,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activar PIN de seguridad'),
                    value: provider.pinActivo,
                    onChanged: (valor) => _cambiarPin(valor, provider),
                  ),
                  if (provider.pinActivo)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _cambiarPin(true, provider),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Cambiar PIN'),
                      ),
                    ),
                ],
              ),
              _Seccion(
                titulo: 'Notificaciones',
                icono: Icons.notifications_none,
                children: [
                  if (defaultTargetPlatform == TargetPlatform.android) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Permiso de Android'),
                      subtitle: Text(
                        _notificacionesHabilitadas == null
                            ? 'Comprobando permiso...'
                            : _notificacionesHabilitadas!
                            ? 'Las notificaciones están permitidas.'
                            : 'Android está bloqueando las notificaciones.',
                      ),
                      trailing: Icon(
                        _notificacionesHabilitadas == true
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        color: _notificacionesHabilitadas == true
                            ? AppColors.primary
                            : AppColors.warning,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _notificacionesHabilitadas == true
                            ? null
                            : _notificacionesHabilitadas == false
                            ? _abrirAjustesNotificaciones
                            : _solicitarPermisoNotificaciones,
                        icon: Icon(
                          _notificacionesHabilitadas == false
                              ? Icons.settings_outlined
                              : Icons.notifications_active_outlined,
                        ),
                        label: Text(
                          _notificacionesHabilitadas == false
                              ? 'Abrir ajustes del teléfono'
                              : 'Permitir notificaciones',
                        ),
                      ),
                    ),
                  ],
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Resumen diario'),
                    value: _recordatorioDiario,
                    onChanged: _alternarRecordatorio,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hora del recordatorio'),
                    subtitle: Text(_horaRecordatorio.format(context)),
                    trailing: IconButton(
                      tooltip: 'Elegir hora',
                      onPressed: _elegirHora,
                      icon: const Icon(Icons.schedule),
                    ),
                    onTap: _elegirHora,
                  ),
                ],
              ),
              _Seccion(
                titulo: 'Respaldo',
                icono: Icons.storage_outlined,
                children: _contenidoRespaldo(provider),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _guardando ? null : () => _guardarAjustes(provider),
                icon: const Icon(Icons.save_outlined),
                label: Text(_guardando ? 'Guardando...' : 'Guardar ajustes'),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'GotaControl · Datos guardados en este dispositivo',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mensaje(String texto) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _consultarPermisoNotificaciones() async {
    try {
      final habilitadas = await NotificacionService.instance
          .notificacionesHabilitadas();
      if (mounted) setState(() => _notificacionesHabilitadas = habilitadas);
    } on Object catch (error) {
      if (mounted) {
        _mensaje('No se pudo consultar el permiso de notificaciones: $error');
      }
    }
  }

  Future<void> _solicitarPermisoNotificaciones() async {
    try {
      final provider = context.read<GotaProvider>();
      final habilitadas = await NotificacionService.instance
          .solicitarPermisoNotificaciones();
      if (mounted) setState(() => _notificacionesHabilitadas = habilitadas);
      if (habilitadas) {
        await NotificacionService.instance.sincronizarConDatos(provider);
        if (mounted) _mensaje('Notificaciones permitidas.');
      } else if (mounted) {
        _mensaje(
          'Android no concedió el permiso. Revisa los ajustes del teléfono.',
        );
      }
    } on Object catch (error) {
      if (mounted) _mensaje('No se pudo solicitar el permiso: $error');
    }
  }

  Future<void> _abrirAjustesNotificaciones() async {
    try {
      final abierto = await NotificacionService.instance
          .abrirAjustesNotificaciones();
      if (!abierto && mounted) {
        _mensaje('No se pudieron abrir los ajustes de notificaciones.');
      }
    } on Object catch (error) {
      if (mounted) _mensaje('No se pudieron abrir los ajustes: $error');
    }
  }

  List<Widget> _contenidoRespaldo(GotaProvider provider) => [
    Text(
      _estadoRespaldo?.automaticDestination == true
          ? 'La app crea automáticamente Documentos/GotaControl. Si la carpeta '
                'Documentos o GotaControl no existe, Android la crea al guardar. '
                'La carpeta y '
                'sus copias quedan fuera de los datos de la app. Al reinstalar, '
                'Android pedirá acceso a la carpeta y se restaurará la copia '
                'válida más reciente antes de abrir la base.'
          : _estadoRespaldo?.hasDestination == true
          ? 'Los respaldos permanecen en la carpeta elegida al desinstalar. '
                'Tras reinstalar, concede acceso de nuevo; en Android 10 o '
                'posterior la app restaurará automáticamente la copia más '
                'reciente con datos. En Android 7–9, impórtala desde Ajustes.'
          : 'Elige una carpeta de Documentos. Android conservará allí las '
                'copias incluso si desinstalas la aplicación.',
      style: const TextStyle(color: AppColors.textSecondary),
    ),
    const SizedBox(height: 8),
    ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Carpeta de respaldos'),
      subtitle: Text(
        _estadoRespaldo?.folderName ??
            (defaultTargetPlatform == TargetPlatform.android
                ? 'Se configura al elegir carpeta'
                : 'No disponible en esta plataforma'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: _respaldoOcupado ? null : _seleccionarCarpetaRespaldo,
        child: Text(
          _estadoRespaldo?.automaticDestination == true ? 'Cambiar' : 'Elegir',
        ),
      ),
    ),
    DropdownButtonFormField<BackupFrequency>(
      initialValue: _frecuenciaRespaldo,
      decoration: const InputDecoration(labelText: 'Respaldo automático'),
      items: [
        for (final frecuencia in BackupFrequency.values)
          DropdownMenuItem(value: frecuencia, child: Text(frecuencia.label)),
      ],
      onChanged: _respaldoOcupado ? null : _cambiarFrecuenciaRespaldo,
    ),
    const SizedBox(height: 8),
    Text(
      _textoUltimoRespaldo(),
      style: const TextStyle(color: AppColors.textSecondary),
    ),
    if (_estadoRespaldo?.lastFile case final String archivo)
      Text(
        archivo,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    if (_estadoRespaldo?.lastError case final String error)
      Text(
        'Último error: $error',
        style: const TextStyle(color: AppColors.error),
      ),
    if (_errorRespaldo case final String error)
      Text(error, style: const TextStyle(color: AppColors.error)),
    const SizedBox(height: 10),
    if (_respaldoOcupado) const LinearProgressIndicator(),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _respaldoOcupado || _estadoRespaldo?.hasDestination != true
              ? null
              : _crearRespaldoManual,
          icon: const Icon(Icons.save_alt),
          label: const Text('Crear respaldo'),
        ),
        OutlinedButton.icon(
          onPressed: _respaldoOcupado || _estadoRespaldo?.hasDestination != true
              ? null
              : () => _importarRespaldo(provider),
          icon: const Icon(Icons.restore),
          label: const Text('Importar base de datos'),
        ),
        OutlinedButton.icon(
          onPressed: _respaldoOcupado ? null : () => _imprimirDatos(provider),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Imprimir / exportar PDF'),
        ),
        OutlinedButton.icon(
          onPressed: _respaldoOcupado ? null : () => _exportarCsv(provider),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('Exportar CSV / Excel'),
        ),
      ],
    ),
    const SizedBox(height: 8),
    const Text(
      'Android puede retrasar los respaldos automáticos por ahorro de batería. '
      'Se conservan las 30 copias automáticas más recientes; las copias '
      'manuales y previas a una restauración no se eliminan.',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
  ];

  String _textoUltimoRespaldo() {
    final fecha = _estadoRespaldo?.lastSuccess;
    if (fecha == null) return 'Todavía no se ha creado un respaldo automático.';
    return 'Último respaldo: ${GotaDateUtils.formatearFechaHora(fecha)}';
  }

  String? _validarTexto(
    String? valor, {
    required int maximo,
    required String etiqueta,
    bool requerido = false,
  }) {
    final texto = valor?.trim() ?? '';
    if (requerido && texto.isEmpty) return '$etiqueta es obligatorio.';
    if (texto.length > maximo) {
      return '$etiqueta no puede superar $maximo caracteres.';
    }
    return null;
  }

  String? _validarPorcentajeMora(String? valor) {
    final porcentaje = double.tryParse(
      (valor ?? '').trim().replaceAll(',', '.'),
    );
    if (porcentaje == null ||
        !porcentaje.isFinite ||
        porcentaje < 0 ||
        porcentaje > AjustesNegocioValidator.maxPorcentajeMora) {
      return 'Ingresa un porcentaje entre 0 y 100.';
    }
    return null;
  }

  String? _validarDiasGracia(String? valor) {
    final dias = int.tryParse((valor ?? '').trim());
    if (dias == null ||
        dias < 0 ||
        dias > AjustesNegocioValidator.maxDiasGracia) {
      return 'Ingresa entre 0 y 365 días.';
    }
    return null;
  }

  Future<void> _inicializarRespaldo() async {
    if (_respaldoInicializado) return;
    _respaldoInicializado = true;
    try {
      final estado = await LocalBackupService.instance.status();
      if (!mounted) return;
      setState(() => _estadoRespaldo = estado);
      if (estado.hasDestination) {
        await LocalBackupService.instance.configureSchedule(
          _frecuenciaRespaldo,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _errorRespaldo = _mensajeErrorRespaldo(error));
    }
  }

  Future<void> _seleccionarCarpetaRespaldo() async {
    setState(() {
      _respaldoOcupado = true;
      _errorRespaldo = null;
    });
    try {
      final estado = await LocalBackupService.instance.selectFolder(
        _frecuenciaRespaldo,
      );
      if (!mounted) return;
      if (estado != null) {
        setState(() => _estadoRespaldo = estado);
        _mensaje('Carpeta elegida. El respaldo automático quedó programado.');
      }
    } on Object catch (error) {
      if (mounted) _mensaje(_mensajeErrorRespaldo(error));
    } finally {
      if (mounted) setState(() => _respaldoOcupado = false);
    }
  }

  Future<void> _cambiarFrecuenciaRespaldo(BackupFrequency? frecuencia) async {
    if (frecuencia == null) return;
    final anterior = _frecuenciaRespaldo;
    setState(() {
      _frecuenciaRespaldo = frecuencia;
      _respaldoOcupado = true;
      _errorRespaldo = null;
    });
    try {
      await context.read<GotaProvider>().guardarConfiguracion({
        DbConstants.configuracionFrecuenciaRespaldo: frecuencia.value,
      });
      await LocalBackupService.instance.configureSchedule(frecuencia);
      final estado = await LocalBackupService.instance.status();
      if (!mounted) return;
      setState(() => _estadoRespaldo = estado);
      _mensaje(
        estado.hasDestination
            ? 'Frecuencia ${frecuencia.label.toLowerCase()} guardada.'
            : 'Frecuencia guardada. Elige una carpeta para activar los respaldos.',
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _frecuenciaRespaldo = anterior;
        _errorRespaldo = _mensajeErrorRespaldo(error);
      });
    } finally {
      if (mounted) setState(() => _respaldoOcupado = false);
    }
  }

  Future<void> _crearRespaldoManual() async {
    setState(() {
      _respaldoOcupado = true;
      _errorRespaldo = null;
    });
    try {
      final archivo = await LocalBackupService.instance.runBackupNow();
      final estado = await LocalBackupService.instance.status();
      if (!mounted) return;
      setState(() => _estadoRespaldo = estado);
      _mensaje('Respaldo creado: $archivo');
    } on Object catch (error) {
      if (mounted) _mensaje(_mensajeErrorRespaldo(error));
    } finally {
      if (mounted) setState(() => _respaldoOcupado = false);
    }
  }

  Future<void> _importarRespaldo(GotaProvider provider) async {
    setState(() {
      _respaldoOcupado = true;
      _errorRespaldo = null;
    });
    ImportableBackup? backup;
    var restaurado = false;
    try {
      final selectedBackup = await LocalBackupService.instance
          .selectImportBackup();
      if (!mounted || selectedBackup == null) return;
      backup = selectedBackup;
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reemplazar la base de datos'),
          content: Text(
            'La copia SQLite v${selectedBackup.version} ocupa '
            '${(selectedBackup.sizeBytes / 1024).toStringAsFixed(0)} KB. '
            'Se guardará primero una copia preventiva de los datos actuales '
            'en la ubicación de respaldo configurada. Después se reemplazará '
            'toda la base actual por la importada. ¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reemplazar y restaurar'),
            ),
          ],
        ),
      );
      if (confirmado != true) return;
      await LocalBackupService.instance.restoreBackup(selectedBackup, provider);
      restaurado = true;
      final frecuencia = BackupFrequency.fromValue(
        provider.configuracion?[DbConstants.configuracionFrecuenciaRespaldo],
      );
      await LocalBackupService.instance.configureSchedule(frecuencia);
      final estado = await LocalBackupService.instance.status();
      if (!mounted) return;
      setState(() {
        _frecuenciaRespaldo = frecuencia;
        _estadoRespaldo = estado;
        _configuracionCargada = false;
      });
      _mensaje('Base de datos restaurada y recargada correctamente.');
    } on Object catch (error) {
      if (mounted) _mensaje(_mensajeErrorRespaldo(error));
    } finally {
      if (backup != null && !restaurado) {
        try {
          await LocalBackupService.instance.discardImportBackup(backup);
        } on Object catch (error) {
          if (mounted) {
            setState(() => _errorRespaldo = _mensajeErrorRespaldo(error));
          }
        }
      }
      if (mounted) setState(() => _respaldoOcupado = false);
    }
  }

  Future<void> _imprimirDatos(GotaProvider provider) async {
    setState(() => _respaldoOcupado = true);
    try {
      final bytes = await PdfGenerator.respaldoCompleto(provider);
      await PdfGenerator.imprimir(bytes);
    } on Object catch (error) {
      if (mounted) _mensaje('No se pudo generar el PDF: $error');
    } finally {
      if (mounted) setState(() => _respaldoOcupado = false);
    }
  }

  Future<void> _exportarCsv(GotaProvider provider) async {
    setState(() => _respaldoOcupado = true);
    try {
      final archivos = DatabaseExportService.exportarCsv(provider);
      await SharePlus.instance.share(
        ShareParams(
          title: 'Exportar datos de GotaControl',
          subject: 'Clientes, préstamos, cuotas y pagos',
          files: [
            for (final archivo in archivos.entries)
              XFile.fromData(
                archivo.value,
                name: archivo.key,
                mimeType: 'text/csv',
              ),
          ],
        ),
      );
    } on Object catch (error) {
      if (mounted) _mensaje('No se pudieron exportar los CSV: $error');
    } finally {
      if (mounted) setState(() => _respaldoOcupado = false);
    }
  }

  String _mensajeErrorRespaldo(Object error) {
    if (error is PlatformException) {
      return error.message ?? 'Android no pudo completar la operación.';
    }
    if (error is UnsupportedError) return error.message ?? 'No compatible.';
    return 'No se pudo completar la operación de respaldo: $error';
  }

  Future<void> _elegirHora() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _horaRecordatorio,
    );
    if (hora != null) {
      setState(() => _horaRecordatorio = hora);
      await _guardarPreferenciasNotificacion();
      if (_recordatorioDiario) await _programarRecordatorio(true);
    }
  }

  Future<void> _alternarRecordatorio(bool valor) async {
    setState(() => _recordatorioDiario = valor);
    await _guardarPreferenciasNotificacion();
    await _programarRecordatorio(valor);
  }

  Future<void> _guardarPreferenciasNotificacion() async {
    final provider = context.read<GotaProvider>();
    try {
      await provider.guardarConfiguracion({
        DbConstants.configuracionRecordatorioDiario: _recordatorioDiario
            ? 1
            : 0,
        DbConstants.configuracionHoraRecordatorio:
            '${_horaRecordatorio.hour.toString().padLeft(2, '0')}:'
            '${_horaRecordatorio.minute.toString().padLeft(2, '0')}',
      });
    } on Object catch (error) {
      if (mounted) _mensaje('No se pudo guardar la preferencia: $error');
    }
  }

  Future<void> _programarRecordatorio(bool habilitado) async {
    final servicio = NotificacionService.instance;
    try {
      if (!habilitado) {
        await servicio.cancelarNotificacion(1);
        return;
      }
      if (!await servicio.notificacionesHabilitadas()) {
        final permitido = await servicio.solicitarPermisoNotificaciones();
        if (!permitido) {
          if (mounted) {
            setState(() => _notificacionesHabilitadas = false);
            _mensaje(
              'Para recibir recordatorios, concede el permiso en los ajustes '
              'del teléfono.',
            );
          }
          return;
        }
        if (mounted) setState(() => _notificacionesHabilitadas = true);
      }
      await servicio.programarNotificacionDiaria(
        hora: _horaRecordatorio,
        mensaje:
            'Revisa el recaudo, la ganancia y las cuotas pendientes de hoy.',
      );
      if (mounted) _mensaje('Recordatorio diario programado.');
    } on Object catch (error) {
      if (mounted) {
        _mensaje('No se pudieron actualizar los recordatorios: $error');
      }
    }
  }

  Future<void> _cambiarPin(bool valor, GotaProvider provider) async {
    if (!valor) {
      final actual = TextEditingController();
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Desactivar PIN'),
          content: TextField(
            controller: actual,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'PIN actual'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Desactivar'),
            ),
          ],
        ),
      );
      if (confirmado == true && mounted) {
        try {
          final resultado = await provider.validarPin(actual.text);
          if (resultado == PinValidationResult.valid) {
            await provider.desactivarPin();
            _mensaje('PIN desactivado.');
          } else {
            _mensaje(
              resultado == PinValidationResult.locked
                  ? 'Demasiados intentos. Espera antes de volver a intentar.'
                  : 'El PIN actual no es correcto.',
            );
          }
        } on Object catch (error) {
          _mensaje('No se pudo desactivar el PIN: $error');
        }
      }
      actual.dispose();
      return;
    }
    final pin = TextEditingController();
    final confirmarPin = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'PIN de 4 a 6 dígitos',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmarPin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(labelText: 'Confirmar PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      if (!RegExp(r'^\d{4,6}$').hasMatch(pin.text)) {
        _mensaje('El PIN debe tener entre 4 y 6 dígitos.');
      } else if (pin.text != confirmarPin.text) {
        _mensaje('Los PIN no coinciden.');
      } else {
        try {
          await provider.configurarPin(pin.text);
          _mensaje('PIN guardado de forma segura en este dispositivo.');
        } on Object catch (error) {
          _mensaje('No se pudo guardar el PIN: $error');
        }
      }
    }
    pin.dispose();
    confirmarPin.dispose();
  }

  Future<void> _guardarAjustes(GotaProvider provider) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final porcentaje = double.tryParse(
      _porcentajeMora.text.trim().replaceAll(',', '.'),
    );
    final dias = int.tryParse(_diasGracia.text.trim());
    if (porcentaje == null || dias == null) return;

    setState(() => _guardando = true);
    try {
      await provider.guardarConfiguracion({
        DbConstants.configuracionNombreNegocio: _negocio.text.trim(),
        DbConstants.configuracionTelefonoNegocio: _telefono.text.trim(),
        DbConstants.configuracionDireccionNegocio: _direccion.text.trim(),
        DbConstants.configuracionPorcentajeMora: porcentaje,
        DbConstants.configuracionDiasGraciaMora: dias,
        DbConstants.configuracionAlertasMora: _alertasMora ? 1 : 0,
        DbConstants.configuracionRecordatorioDiario: _recordatorioDiario
            ? 1
            : 0,
        DbConstants.configuracionHoraRecordatorio:
            '${_horaRecordatorio.hour.toString().padLeft(2, '0')}:'
            '${_horaRecordatorio.minute.toString().padLeft(2, '0')}',
      });
      try {
        await NotificacionService.instance.sincronizarConDatos(provider);
        if (mounted) _mensaje('Ajustes guardados en este dispositivo.');
      } on Object catch (error) {
        if (mounted) {
          _mensaje(
            'Ajustes guardados, pero no se actualizaron los recordatorios: '
            '$error',
          );
        }
      }
    } on Object catch (error) {
      if (mounted) _mensaje('No se pudieron guardar los ajustes: $error');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.titulo,
    required this.icono,
    required this.children,
  });
  final String titulo;
  final IconData icono;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: AppColors.primary, size: 19),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
}
