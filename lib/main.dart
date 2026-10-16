import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_colors.dart';
import 'core/constants/db_constants.dart';
import 'core/constants/app_strings.dart';
import 'logic/providers/gota_provider.dart';
import 'logic/services/local_backup_service.dart';
import 'logic/services/notificacion_service.dart';
import 'ui/screens/main_shell.dart';
import 'ui/widgets/pin_security_gate.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Captura errores del framework Flutter (build, layout, paint, etc.)
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('GotaControl [FlutterError]: ${details.exception}');
        debugPrintStack(stackTrace: details.stack);
      };
      ErrorWidget.builder = (_) => const Material(
        color: AppColors.background,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Ocurrió un error al mostrar esta pantalla. Reinicia la app o '
              'vuelve a intentarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ),
      );

      // Captura errores asíncronos de la plataforma (Android/iOS)
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        debugPrint('GotaControl [PlatformDispatcher]: $error');
        debugPrintStack(stackTrace: stack);
        return true;
      };

      final provider = GotaProvider();
      var falloRecuperacionAutomatica = false;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await LocalBackupService.instance.restoreLatestBackupIfMissing();
        } on Object catch (error, stackTrace) {
          falloRecuperacionAutomatica = true;
          debugPrint(
            'GotaControl: no se pudo recuperar el respaldo previo: $error',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      await provider.cargarDatos();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final estadoRespaldo = await LocalBackupService.instance.status();
          if (falloRecuperacionAutomatica ||
              (estadoRespaldo.lastError != null &&
                  estadoRespaldo.lastSuccess == null)) {
            provider.mostrarAvisoRespaldoInicio(
              'No se pudo validar la copia más reciente. No se programó una '
              'copia nueva para proteger los respaldos existentes. Revisa '
              'Ajustes → Respaldo e importa una copia válida.',
            );
          } else {
            final frecuencia = BackupFrequency.fromValue(
              provider.configuracion?[DbConstants
                  .configuracionFrecuenciaRespaldo],
            );
            await LocalBackupService.instance.configureSchedule(frecuencia);
          }
        } on Object catch (error, stackTrace) {
          debugPrint('GotaControl: no se pudo programar el respaldo: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      runApp(
        ChangeNotifierProvider.value(
          value: provider,
          child: const GotaControlApp(),
        ),
      );

      if (!kIsWeb) {
        try {
          final notificaciones = NotificacionService.instance;
          await notificaciones.inicializarNotificaciones();
          await notificaciones.sincronizarConDatos(provider);
        } on Object catch (error, stackTrace) {
          debugPrint('GotaControl: no se sincronizaron notificaciones: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    },
    (Object error, StackTrace stack) {
      debugPrint('GotaControl [Zona no capturada]: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}

class GotaControlApp extends StatelessWidget {
  const GotaControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      surface: AppColors.surface,
      primary: AppColors.primary,
      error: AppColors.error,
    );
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colors,
        scaffoldBackgroundColor: AppColors.background,
        cardColor: AppColors.surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          type: BottomNavigationBarType.fixed,
        ),
        dividerColor: AppColors.divider,
      ),
      home: const PinSecurityGate(child: MainShell()),
    );
  }
}
