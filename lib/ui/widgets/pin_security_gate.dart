import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../logic/providers/gota_provider.dart';
import '../../logic/services/pin_hash_service.dart';

class PinSecurityGate extends StatefulWidget {
  const PinSecurityGate({super.key, required this.child});

  final Widget child;

  @override
  State<PinSecurityGate> createState() => _PinSecurityGateState();
}

class _PinSecurityGateState extends State<PinSecurityGate>
    with WidgetsBindingObserver {
  static const _tiempoInactividad = Duration(seconds: 90);

  late final GotaProvider _provider;
  bool _unlocked = false;
  DateTime? _pausadaEn;
  Timer? _bloqueoPorInactividad;

  @override
  void initState() {
    super.initState();
    _provider = context.read<GotaProvider>();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _bloqueoPorInactividad?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_provider.pinActivo || !_unlocked) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pausadaEn ??= DateTime.now();
      _programarBloqueo();
    } else if (state == AppLifecycleState.resumed) {
      final pausadaEn = _pausadaEn;
      _pausadaEn = null;
      _bloqueoPorInactividad?.cancel();
      _bloqueoPorInactividad = null;
      if (pausadaEn != null &&
          DateTime.now().difference(pausadaEn) >= _tiempoInactividad) {
        _bloquear();
      }
    }
  }

  void _programarBloqueo() {
    _bloqueoPorInactividad?.cancel();
    _bloqueoPorInactividad = Timer(_tiempoInactividad, _bloquear);
  }

  void _bloquear() {
    if (!mounted || !_provider.pinActivo || !_unlocked) return;
    setState(() {
      _unlocked = false;
      _pausadaEn = null;
    });
    _bloqueoPorInactividad = null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GotaProvider>();
    if (provider.cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (provider.errorCarga != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'No se pudo cargar la base de datos local.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  provider.errorCarga!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: provider.cargarDatos,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!provider.pinActivo) {
      _unlocked = true;
      return widget.child;
    }
    if (_unlocked) return widget.child;
    return _PinUnlockScreen(
      key: const ValueKey('pin-unlock-screen'),
      provider: provider,
      onUnlocked: () => setState(() => _unlocked = true),
    );
  }
}

class _PinUnlockScreen extends StatefulWidget {
  const _PinUnlockScreen({
    super.key,
    required this.provider,
    required this.onUnlocked,
  });

  final GotaProvider provider;
  final VoidCallback onUnlocked;

  @override
  State<_PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<_PinUnlockScreen> {
  final _pin = TextEditingController();
  Timer? _timer;
  String? _error;
  bool _validando = false;
  int _segundosBloqueo = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 52,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Desbloquear GotaControl',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _pin,
                  autofocus: true,
                  obscureText: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _validar(),
                  decoration: InputDecoration(
                    labelText: 'PIN de seguridad',
                    errorText: _error,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _validando || _segundosBloqueo > 0
                        ? null
                        : _validar,
                    child: _validando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _segundosBloqueo > 0
                                ? 'Intenta en $_segundosBloqueo s'
                                : 'Desbloquear',
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

  Future<void> _validar() async {
    if (_pin.text.length < 4) {
      setState(() => _error = 'Ingresa un PIN de 4 a 6 dígitos.');
      return;
    }
    setState(() {
      _validando = true;
      _error = null;
    });
    try {
      final result = await widget.provider.validarPin(_pin.text);
      if (!mounted) return;
      switch (result) {
        case PinValidationResult.valid:
          widget.onUnlocked();
        case PinValidationResult.invalid:
          setState(() {
            _pin.clear();
            _error = 'PIN incorrecto.';
          });
        case PinValidationResult.locked:
          _pin.clear();
          _iniciarBloqueo();
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'No se pudo validar el PIN. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _validando = false);
    }
  }

  void _iniciarBloqueo() {
    _timer?.cancel();
    void actualizar() {
      final restante = widget.provider.tiempoBloqueoPin?.inSeconds ?? 0;
      setState(() {
        _segundosBloqueo = restante;
        _error = restante > 0
            ? 'Demasiados intentos. Espera $restante segundos.'
            : null;
      });
      if (restante <= 0) _timer?.cancel();
    }

    actualizar();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => actualizar());
  }
}
