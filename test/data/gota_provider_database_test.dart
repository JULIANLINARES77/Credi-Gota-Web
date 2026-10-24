import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common/sqflite.dart'
    show OpenDatabaseOptions, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqlite_ffi;

import 'package:flutter_prestamos/core/constants/db_constants.dart';
import 'package:flutter_prestamos/data/database/database_helper.dart';
import 'package:flutter_prestamos/data/models/prestamo.dart';
import 'package:flutter_prestamos/logic/providers/gota_provider.dart';
import 'package:flutter_prestamos/logic/services/calculadora_service.dart';
import 'package:flutter_prestamos/logic/services/database_export_service.dart';
import 'package:flutter_prestamos/logic/services/mora_service.dart';
import 'package:flutter_prestamos/logic/services/pin_hash_service.dart';
import 'package:flutter_prestamos/ui/screens/prestamos/nuevo_prestamo_screen.dart';
import 'package:flutter_prestamos/ui/screens/reportes/pdf_generator.dart';

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pinChannel = MethodChannel('gotacontrol/pin_hash');
  late Directory supportDirectory;
  late GotaProvider provider;

  setUpAll(() {
    sqlite_ffi.sqfliteFfiInit();
    databaseFactory = sqlite_ffi.databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pinChannel, (call) async {
          switch (call.method) {
            case 'hashPin':
              return r'$2a$12$test-hash-for-local-channel-contract';
            case 'verifyPin':
              final arguments = call.arguments as Map<Object?, Object?>;
              return arguments['pin'] == '123456' &&
                  arguments['hash'] ==
                      r'$2a$12$test-hash-for-local-channel-contract';
            default:
              throw PlatformException(code: 'not_implemented');
          }
        });
  });

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp('gotacontrol_db_');
    PathProviderPlatform.instance = _TestPathProvider(supportDirectory.path);
    provider = GotaProvider(reloj: () => DateTime(2026, 9, 30, 12));
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('guarda cliente y lo recupera después de recargar SQLite', () async {
    await provider.cargarDatos();
    await provider.agregarCliente(
      nombre: 'Cliente Persistente',
      telefono: '3001234567',
      cedula: '12345678',
    );

    expect(provider.clientes, hasLength(1));
    expect(provider.clientes.single.nombre, 'Cliente Persistente');

    await provider.cargarDatos();
    expect(provider.clientes, hasLength(1));
    expect(provider.clientes.single.cedula, '12345678');
  });

  test('guarda fecha inicial retroactiva y modo de días corridos', () async {
    await provider.cargarDatos();
    final cliente = await provider.agregarCliente(
      nombre: 'Cliente de prueba retroactiva',
      telefono: '3001234567',
    );
    final conDiasCorridos = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 10000,
      porcentajeInteres: 0,
      numCuotas: 1,
      frecuencia: CalculadoraService.frecuenciaDiaria,
      fechaInicio: DateTime(2026, 1, 31),
      diasCorridos: true,
    );
    final sinDiasCorridos = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 10000,
      porcentajeInteres: 0,
      numCuotas: 1,
      frecuencia: CalculadoraService.frecuenciaDiaria,
      fechaInicio: DateTime(2026, 1, 31),
      diasCorridos: false,
    );

    expect(conDiasCorridos.fechaInicio, DateTime(2026, 1, 31));
    expect(conDiasCorridos.diasCorridos, isTrue);
    expect(
      provider.cuotasDePrestamo(conDiasCorridos.id!).single.fechaVencimiento,
      DateTime(2026, 1, 31),
    );
    expect(sinDiasCorridos.diasCorridos, isFalse);
    expect(
      provider.cuotasDePrestamo(sinDiasCorridos.id!).single.fechaVencimiento,
      DateTime(2026, 2, 2),
    );

    await provider.cargarDatos();
    expect(provider.prestamoPorId(conDiasCorridos.id!)?.diasCorridos, isTrue);
  });

  for (final legacyVersion in [5, 6]) {
    test(
      'repara préstamos v$legacyVersion sin dias_corridos y permite crear préstamos',
      () async {
        await provider.cargarDatos();
        final cliente = await provider.agregarCliente(
          nombre: 'Cliente migración v$legacyVersion',
          telefono: '3001234567',
        );
        final prestamoExistente = await provider.crearPrestamo(
          clienteId: cliente.id!,
          capital: 10000,
          porcentajeInteres: 10,
          numCuotas: 1,
          frecuencia: CalculadoraService.frecuenciaDiaria,
        );

        final db = await DatabaseHelper.instance.database;
        await db.execute(
          'ALTER TABLE ${DbConstants.tablePrestamos} '
          'DROP COLUMN ${DbConstants.prestamoDiasCorridos}',
        );
        await db.execute('PRAGMA user_version = $legacyVersion');
        await DatabaseHelper.instance.close();

        await provider.cargarDatos();

        expect(provider.errorCarga, isNull);
        final columns = await (await DatabaseHelper.instance.database).rawQuery(
          'PRAGMA table_info(${DbConstants.tablePrestamos})',
        );
        expect(
          columns.any(
            (column) => column['name'] == DbConstants.prestamoDiasCorridos,
          ),
          isTrue,
        );
        expect(
          provider.prestamoPorId(prestamoExistente.id!)?.montoCapital,
          10000,
        );

        final diario = await provider.crearPrestamo(
          clienteId: cliente.id!,
          capital: 20000,
          porcentajeInteres: 10,
          numCuotas: 2,
          frecuencia: CalculadoraService.frecuenciaDiaria,
          diasCorridos: true,
        );
        final semanal = await provider.crearPrestamo(
          clienteId: cliente.id!,
          capital: 30000,
          porcentajeInteres: 20,
          numCuotas: 4,
          frecuencia: CalculadoraService.frecuenciaSemanal,
          diasCorridos: false,
        );

        await provider.cargarDatos();
        final diarioGuardado = provider.prestamoPorId(diario.id!)!;
        final semanalGuardado = provider.prestamoPorId(semanal.id!)!;
        expect(diarioGuardado.diasCorridos, isTrue);
        expect(diarioGuardado.montoInteres, 2000);
        expect(diarioGuardado.montoTotalPagar, 22000);
        expect(provider.cuotasDePrestamo(diario.id!), hasLength(2));
        expect(semanalGuardado.diasCorridos, isFalse);
        expect(semanalGuardado.montoInteres, 6000);
        expect(semanalGuardado.montoTotalPagar, 36000);
        expect(provider.cuotasDePrestamo(semanal.id!), hasLength(4));
        expect(
          provider
              .cuotasDePrestamo(semanal.id!)
              .map((cuota) => cuota.montoCuota)
              .reduce((total, monto) => total + monto),
          36000,
        );
      },
    );
  }

  testWidgets('crea y persiste un préstamo desde el formulario diario', (
    tester,
  ) async {
    late final int clienteId;
    await tester.runAsync(() async {
      await provider.cargarDatos();
      final cliente = await provider.agregarCliente(
        nombre: 'Cliente formulario préstamo',
        telefono: '3001234567',
      );
      clienteId = cliente.id!;
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: NuevoPrestamoScreen()),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), '20.000');
    await tester.enterText(find.byType(TextFormField).at(1), '10');
    await tester.enterText(find.byType(TextFormField).at(2), '2');
    final frecuencia = find.byType(DropdownButtonFormField<String>);
    await tester.tap(frecuencia);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Diaria').last);
    await tester.pump(const Duration(milliseconds: 300));
    final diasCorridos = find.byType(SwitchListTile);
    await tester.ensureVisible(diasCorridos);
    await tester.tap(diasCorridos);
    await tester.pump();

    final botonCrear = find.text('Crear préstamo');
    await tester.ensureVisible(botonCrear);
    await tester.tap(botonCrear);
    await tester.pump();
    var prestamos = <Prestamo>[];
    await tester.runAsync(() async {
      for (var intento = 0; intento < 40 && prestamos.isEmpty; intento++) {
        prestamos = await DatabaseHelper.instance.obtenerPrestamosPorCliente(
          clienteId,
        );
        if (prestamos.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(prestamos, hasLength(1));
    final prestamo = prestamos.single;
    expect(prestamo.montoCapital, 20000);
    expect(prestamo.porcentajeInteres, 10);
    expect(prestamo.montoInteres, 2000);
    expect(prestamo.montoTotalPagar, 22000);
    expect(prestamo.frecuencia, CalculadoraService.frecuenciaDiaria);
    expect(prestamo.diasCorridos, isTrue);
    expect(
      await tester.runAsync(
        () => DatabaseHelper.instance.obtenerCuotasPorPrestamo(prestamo.id!),
      ),
      hasLength(2),
    );
  });

  test(
    'separa recaudo e interés proporcional hasta cancelar un préstamo de 1.2 millones',
    () async {
      provider.dispose();
      provider = GotaProvider();
      await provider.cargarDatos();
      final cliente = await provider.agregarCliente(
        nombre: 'Cliente auditoría de reportes',
        telefono: '3001234567',
      );
      final prestamo = await provider.crearPrestamo(
        clienteId: cliente.id!,
        capital: 1000000,
        porcentajeInteres: 20,
        numCuotas: 24,
        frecuencia: CalculadoraService.frecuenciaDiaria,
        diasCorridos: true,
      );
      final cuotas = provider.cuotasDePrestamo(prestamo.id!);
      final fechaPago = DateTime.now();

      expect(prestamo.montoInteres, 200000);
      expect(prestamo.montoTotalPagar, 1200000);
      expect(cuotas, hasLength(24));
      expect(
        cuotas.map((cuota) => cuota.montoCuota).reduce((a, b) => a + b),
        1200000,
      );

      for (final cuota in cuotas.take(20)) {
        await provider.registrarPago(
          prestamoId: prestamo.id!,
          cuotaId: cuota.id!,
          monto: cuota.montoCuota,
          metodoPago: 'EFECTIVO',
          fecha: fechaPago,
        );
      }

      final databaseHelper = DatabaseHelper.instance;
      final recaudoParcial = await databaseHelper.obtenerResumenDashboard();
      expect(recaudoParcial['recaudo_hoy'], closeTo(1000000, 0.01));
      expect(recaudoParcial['ganancia_hoy'], closeTo(166666.67, 0.01));
      await provider.cargarDatos();
      expect(provider.recaudadoHoy, closeTo(1000000, 0.01));
      expect(provider.gananciaHoy, closeTo(166666.67, 0.01));
      expect(provider.prestamoPorId(prestamo.id!)?.saldoPendiente, 200000);
      expect(provider.prestamoPorId(prestamo.id!)?.estado, 'ACTIVO');

      for (final cuota in cuotas.skip(20)) {
        await provider.registrarPago(
          prestamoId: prestamo.id!,
          cuotaId: cuota.id!,
          monto: cuota.montoCuota,
          metodoPago: 'EFECTIVO',
          fecha: fechaPago,
        );
      }

      final resumenFinal = await databaseHelper.obtenerResumenDashboard();
      expect(resumenFinal['recaudo_hoy'], closeTo(1200000, 0.01));
      expect(resumenFinal['ganancia_hoy'], closeTo(200000, 0.01));
      await provider.cargarDatos();
      expect(provider.recaudadoHoy, closeTo(1200000, 0.01));
      expect(provider.gananciaHoy, closeTo(200000, 0.01));
      expect(provider.totalEnCalle, 0);
      expect(provider.prestamoPorId(prestamo.id!)?.saldoPendiente, 0);
      expect(provider.prestamoPorId(prestamo.id!)?.estado, 'PAGADO');
      expect(
        await databaseHelper.obtenerGananciaDelDia(fechaPago),
        closeTo(200000, 0.01),
      );

      for (final reporte in [
        PdfGenerator.reporteDiario(provider, fechaPago),
        PdfGenerator.reporteSemanal(provider, fechaPago),
        PdfGenerator.reporteMensual(provider, fechaPago),
      ]) {
        expect(String.fromCharCodes((await reporte).take(5)), '%PDF-');
      }
    },
  );

  test('registra y persiste pago con fecha retroactiva', () async {
    await provider.cargarDatos();
    final cliente = await provider.agregarCliente(
      nombre: 'Cliente pago retroactivo',
      telefono: '3001234567',
    );
    final prestamo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 10000,
      porcentajeInteres: 0,
      numCuotas: 1,
      frecuencia: CalculadoraService.frecuenciaDiaria,
      fechaInicio: DateTime(2026, 9, 21),
      diasCorridos: true,
    );
    final cuota = provider.cuotasDePrestamo(prestamo.id!).single;
    final fechaPago = DateTime(2026, 9, 23);

    expect(
      await provider.aplicarMoraCuota(
        prestamoId: prestamo.id!,
        cuotaId: cuota.id!,
        fechaReferencia: fechaPago,
      ),
      0,
    );
    await provider.registrarPago(
      prestamoId: prestamo.id!,
      cuotaId: cuota.id!,
      monto: 11000,
      metodoPago: 'EFECTIVO',
      fecha: fechaPago,
    );

    expect(provider.cuotasDePrestamo(prestamo.id!).single.estado, 'PAGADA');
    expect(provider.cuotasDePrestamo(prestamo.id!).single.fechaPago, fechaPago);
    expect(provider.prestamoPorId(prestamo.id!)?.estado, 'PAGADO');
    expect(provider.prestamoPorId(prestamo.id!)?.saldoPendiente, 0);

    await provider.cargarDatos();
    expect(provider.pagos.single.fechaHora, fechaPago);
    expect(provider.cuotasDePrestamo(prestamo.id!).single.estado, 'PAGADA');
  });

  test(
    'consulta totales activos y agrupación mensual capital/interés',
    () async {
      await provider.cargarDatos();
      final cliente = await provider.agregarCliente(
        nombre: 'Cliente estadísticas',
        telefono: '3001234567',
      );
      await provider.crearPrestamo(
        clienteId: cliente.id!,
        capital: 10000,
        porcentajeInteres: 10,
        numCuotas: 1,
        frecuencia: CalculadoraService.frecuenciaDiaria,
        fechaInicio: DateTime(2026, 1, 15),
      );
      await provider.crearPrestamo(
        clienteId: cliente.id!,
        capital: 20000,
        porcentajeInteres: 20,
        numCuotas: 1,
        frecuencia: CalculadoraService.frecuenciaDiaria,
        fechaInicio: DateTime(2026, 2, 15),
      );

      final resumen = await provider.obtenerEstadisticasPrestamos();
      final meses = resumen['mensuales']! as List<Map<String, Object?>>;

      expect(resumen['capital_activo'], 30000);
      expect(resumen['interes_activo'], 5000);
      expect(meses.map((mes) => mes['mes']).toList(), ['2026-01', '2026-02']);
      expect(meses.map((mes) => mes['capital']).toList(), [10000, 20000]);
      expect(meses.map((mes) => mes['interes']).toList(), [1000, 4000]);

      final pdf = await PdfGenerator.reporteEstadisticas(provider);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    },
  );

  test(
    'guarda y actualiza cédula y dirección sin romper préstamos relacionados',
    () async {
      await provider.cargarDatos();
      final cliente = await provider.agregarCliente(
        nombre: 'Cliente con ubicación',
        telefono: '3001112233',
        cedula: '12345678',
        direccion: 'Calle 10 # 20-30, Bogotá',
      );
      final prestamo = await provider.crearPrestamo(
        clienteId: cliente.id!,
        capital: 10000,
        porcentajeInteres: 0,
        numCuotas: 1,
        frecuencia: CalculadoraService.frecuenciaDiaria,
      );

      final actualizado = await provider.actualizarCliente(
        cliente: provider.clientePorId(cliente.id!)!,
        nombre: 'Cliente actualizado',
        telefono: '3112223344',
        cedula: '987654321',
        direccion: 'Carrera 7 # 8-90, Medellín',
      );

      expect(actualizado.id, cliente.id);
      expect(actualizado.fechaRegistro, cliente.fechaRegistro);
      expect(provider.clientePorId(cliente.id!)!.nombre, 'Cliente actualizado');
      expect(provider.clientePorId(cliente.id!)!.telefono, '3112223344');
      expect(provider.clientePorId(cliente.id!)!.cedula, '987654321');
      expect(
        provider.clientePorId(cliente.id!)!.direccion,
        'Carrera 7 # 8-90, Medellín',
      );
      expect(provider.prestamosDeCliente(cliente.id!), hasLength(1));
      expect(provider.prestamosDeCliente(cliente.id!).single.id, prestamo.id);

      await provider.cargarDatos();
      expect(
        provider.clientePorId(cliente.id!)!.direccion,
        'Carrera 7 # 8-90, Medellín',
      );

      final actualizadoSinOpcionales = await provider.actualizarCliente(
        cliente: provider.clientePorId(cliente.id!)!,
        nombre: 'Cliente sin datos opcionales',
        telefono: '3112223344',
      );
      expect(actualizadoSinOpcionales.cedula, isNull);
      expect(actualizadoSinOpcionales.direccion, isNull);
    },
  );

  test(
    'rechaza cliente sin nombre o teléfono y no inserta registros vacíos',
    () async {
      await provider.cargarDatos();

      await expectLater(
        provider.agregarCliente(nombre: '  ', telefono: '3001112233'),
        throwsArgumentError,
      );
      await expectLater(
        provider.agregarCliente(nombre: 'Nombre válido', telefono: '  '),
        throwsArgumentError,
      );

      expect(provider.clientes, isEmpty);
    },
  );

  test(
    'guarda el PIN hasheado y lo valida después de reabrir SQLite',
    () async {
      await provider.cargarDatos();
      await provider.configurarPin('123456');

      final configuracion = await DatabaseHelper.instance
          .obtenerConfiguracion();
      final hash = configuracion?[DbConstants.configuracionPinHash] as String?;
      expect(hash, isNotNull);
      expect(hash, isNot('123456'));
      expect(hash, startsWith(r'$2a$12$'));
      expect(configuracion?[DbConstants.configuracionPinSeguridad], isNull);

      await DatabaseHelper.instance.close();
      provider = GotaProvider(reloj: () => DateTime(2026, 9, 30, 12));
      await provider.cargarDatos();

      expect(provider.pinActivo, isTrue);
      expect(await provider.validarPin('000000'), PinValidationResult.invalid);
      expect(await provider.validarPin('123456'), PinValidationResult.valid);
    },
  );

  test('rechaza PIN vacío o que no tenga entre 4 y 6 dígitos', () async {
    await provider.cargarDatos();

    await expectLater(provider.configurarPin(''), throwsArgumentError);
    await expectLater(provider.configurarPin('12a4'), throwsArgumentError);
    expect(provider.pinActivo, isFalse);
  });

  test('migra una base v1 y elimina el PIN heredado en texto plano', () async {
    final databasePath = path.join(
      supportDirectory.path,
      DbConstants.databaseName,
    );
    final legacyDb = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE configuracion (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre_negocio TEXT,
              telefono_negocio TEXT,
              meta_diaria REAL,
              porcentaje_mora REAL NOT NULL DEFAULT 10,
              dias_gracia_mora INTEGER NOT NULL DEFAULT 3,
              pin_seguridad TEXT,
              moneda TEXT NOT NULL DEFAULT 'COP'
            )
          ''');
          await db.execute('''
            CREATE TABLE prestamos (
              id INTEGER PRIMARY KEY AUTOINCREMENT
            )
          ''');
          await db.execute('''
            CREATE TABLE cuotas (
              id INTEGER PRIMARY KEY AUTOINCREMENT
            )
          ''');
          await db.insert('configuracion', {
            'nombre_negocio': 'Negocio existente',
            'pin_seguridad': '1234',
          });
        },
      ),
    );
    await legacyDb.close();

    final configuracion = await DatabaseHelper.instance.obtenerConfiguracion();

    expect(
      configuracion?[DbConstants.configuracionNombreNegocio],
      'Negocio existente',
    );
    expect(configuracion?[DbConstants.configuracionPinSeguridad], isNull);
    expect(configuracion?[DbConstants.configuracionPinHash], isNull);
    expect(configuracion?[DbConstants.configuracionDireccionNegocio], isNull);
    expect(
      configuracion?[DbConstants.configuracionFrecuenciaRespaldo],
      'daily',
    );
    expect(configuracion?[DbConstants.configuracionUltimoRespaldo], isNull);
    expect(
      configuracion?[DbConstants.configuracionMoraMensualValorRecargo],
      10,
    );
    final columnasPrestamos = await (await DatabaseHelper.instance.database)
        .rawQuery('PRAGMA table_info(${DbConstants.tablePrestamos})');
    expect(
      columnasPrestamos.any(
        (columna) => columna['name'] == DbConstants.prestamoDiasCorridos,
      ),
      isTrue,
    );
  });

  test(
    'valida los ajustes aunque se actualicen fuera de la pantalla',
    () async {
      await provider.cargarDatos();
      await provider.guardarConfiguracion({
        DbConstants.configuracionNombreNegocio: 'Negocio local',
        DbConstants.configuracionTelefonoNegocio: '',
        DbConstants.configuracionDireccionNegocio: '',
        DbConstants.configuracionPorcentajeMora: 100,
        DbConstants.configuracionDiasGraciaMora: 365,
      });

      await expectLater(
        provider.guardarConfiguracion({
          DbConstants.configuracionNombreNegocio: ' ',
        }),
        throwsArgumentError,
      );
      await expectLater(
        provider.guardarConfiguracion({
          DbConstants.configuracionPorcentajeMora: 101,
        }),
        throwsArgumentError,
      );
    },
  );

  test('conserva varios préstamos del mismo cliente y sus cuotas', () async {
    await provider.cargarDatos();
    await provider.agregarCliente(
      nombre: 'Cliente con varios préstamos',
      telefono: '3001234567',
    );
    final cliente = provider.clientes.single;

    final primerPrestamo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 100000,
      porcentajeInteres: 20,
      numCuotas: 4,
      frecuencia: CalculadoraService.frecuenciaSemanal,
    );
    final segundoPrestamo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 200000,
      porcentajeInteres: 10,
      numCuotas: 2,
      frecuencia: CalculadoraService.frecuenciaQuincenal,
    );

    final prestamosCliente = provider.prestamosDeCliente(cliente.id!);
    expect(prestamosCliente, hasLength(2));
    expect(
      prestamosCliente.map((prestamo) => prestamo.id),
      containsAll([primerPrestamo.id, segundoPrestamo.id]),
    );
    expect(provider.cuotasDePrestamo(primerPrestamo.id!), hasLength(4));
    expect(provider.cuotasDePrestamo(segundoPrestamo.id!), hasLength(2));
  });

  test('congela reglas por frecuencia en préstamos y las persiste', () async {
    await provider.cargarDatos();
    final cliente = await provider.agregarCliente(
      nombre: 'Cliente mora',
      telefono: '3001234567',
    );
    await provider.guardarConfiguracion({
      DbConstants.configuracionMoraDiariaDiasGracia: 2,
      DbConstants.configuracionMoraDiariaTipoRecargo: 'MONTO_FIJO',
      DbConstants.configuracionMoraDiariaValorRecargo: 5000.0,
      DbConstants.configuracionMoraDiariaRecargoAcumulable: 1,
    });
    final primero = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 100000,
      porcentajeInteres: 0,
      numCuotas: 2,
      frecuencia: CalculadoraService.frecuenciaDiaria,
    );

    await provider.guardarConfiguracion({
      DbConstants.configuracionMoraDiariaDiasGracia: 5,
      DbConstants.configuracionMoraDiariaValorRecargo: 10000.0,
    });
    final segundo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 100000,
      porcentajeInteres: 0,
      numCuotas: 2,
      frecuencia: CalculadoraService.frecuenciaDiaria,
    );

    expect(primero.diasGraciaMora, 2);
    expect(primero.tipoRecargoMora, 'MONTO_FIJO');
    expect(primero.valorRecargoMora, 5000);
    expect(primero.recargoAcumulable, isTrue);
    expect(segundo.diasGraciaMora, 5);
    expect(segundo.valorRecargoMora, 10000);

    await provider.cargarDatos();
    expect(provider.prestamoPorId(primero.id!)!.diasGraciaMora, 2);
    expect(provider.prestamoPorId(primero.id!)!.valorRecargoMora, 5000);
  });

  test('desactiva la mora semanal solo en préstamos nuevos', () async {
    await provider.cargarDatos();
    final cliente = await provider.agregarCliente(
      nombre: 'Cliente switch mora',
      telefono: '3001234567',
    );
    await provider.guardarConfiguracion({
      DbConstants.configuracionMoraSemanalDiasGracia: 2,
      DbConstants.configuracionMoraSemanalTipoRecargo: 'MONTO_FIJO',
      DbConstants.configuracionMoraSemanalValorRecargo: 5000.0,
      DbConstants.configuracionMoraSemanalRecargoAcumulable: 1,
      DbConstants.configuracionMoraSemanalHabilitada: 0,
    });

    final sinMora = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 100000,
      porcentajeInteres: 0,
      numCuotas: 1,
      frecuencia: CalculadoraService.frecuenciaSemanal,
    );
    expect(sinMora.diasGraciaMora, 0);
    expect(sinMora.valorRecargoMora, 0);
    expect(sinMora.tipoRecargoMora, 'MONTO_FIJO');
    expect(sinMora.recargoAcumulable, isTrue);

    await provider.guardarConfiguracion({
      DbConstants.configuracionMoraSemanalHabilitada: 1,
    });
    final conMora = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 100000,
      porcentajeInteres: 0,
      numCuotas: 1,
      frecuencia: CalculadoraService.frecuenciaSemanal,
    );
    expect(conMora.diasGraciaMora, 2);
    expect(conMora.valorRecargoMora, 5000);
  });

  test('aplica una sola vez el recargo fijo configurado en la cuota', () async {
    await provider.cargarDatos();
    final cliente = await provider.agregarCliente(
      nombre: 'Cliente mora aplicable',
      telefono: '3001234567',
    );
    await provider.guardarConfiguracion({
      DbConstants.configuracionMoraDiariaDiasGracia: 0,
      DbConstants.configuracionMoraDiariaTipoRecargo: 'MONTO_FIJO',
      DbConstants.configuracionMoraDiariaValorRecargo: 5000.0,
      DbConstants.configuracionMoraDiariaRecargoAcumulable: 0,
    });
    final prestamo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 10000,
      porcentajeInteres: 0,
      numCuotas: 1,
      frecuencia: CalculadoraService.frecuenciaDiaria,
    );
    final cuota = provider.cuotasDePrestamo(prestamo.id!).single;
    final mora = MoraService(
      databaseHelper: DatabaseHelper.instance,
      reloj: () => DateTime(2026, 10, 3),
    );

    expect(await mora.aplicarMoraCuota(prestamo: prestamo, cuota: cuota), 5000);
    expect(await mora.aplicarMoraCuota(prestamo: prestamo, cuota: cuota), 0);
    await provider.cargarDatos();
    expect(provider.cuotasDePrestamo(prestamo.id!).single.montoCuota, 15000);
    expect(
      provider.cuotasDePrestamo(prestamo.id!).single.montoPenalizacion,
      5000,
    );
    expect(provider.prestamoPorId(prestamo.id!)!.saldoPendiente, 15000);
  });

  test('crea un préstamo mensual y calcula fechas de calendario', () async {
    await provider.cargarDatos();
    final cliente = await provider.agregarCliente(
      nombre: 'Cliente mensual',
      telefono: '3001234567',
    );
    final prestamo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 100000,
      porcentajeInteres: 0,
      numCuotas: 3,
      frecuencia: CalculadoraService.frecuenciaMensual,
    );

    expect(prestamo.frecuencia, CalculadoraService.frecuenciaMensual);
    expect(
      provider
          .cuotasDePrestamo(prestamo.id!)
          .map((cuota) => cuota.fechaVencimiento),
      [DateTime(2026, 9, 30), DateTime(2026, 10, 30), DateTime(2026, 11, 30)],
    );
  });

  test(
    'detecta mora en préstamos diarios, semanales, quincenales y mensuales',
    () async {
      await provider.cargarDatos();
      const frecuencias = [
        CalculadoraService.frecuenciaDiaria,
        CalculadoraService.frecuenciaSemanal,
        CalculadoraService.frecuenciaQuincenal,
        CalculadoraService.frecuenciaMensual,
      ];

      for (var indice = 0; indice < frecuencias.length; indice++) {
        final cliente = await provider.agregarCliente(
          nombre: 'Cliente mora ${frecuencias[indice]}',
          telefono: '30012345$indice',
        );
        await provider.crearPrestamo(
          clienteId: cliente.id!,
          capital: 100000,
          porcentajeInteres: 20,
          numCuotas: 1,
          frecuencia: frecuencias[indice],
          fechaInicio: DateTime(2026, 8, 1),
        );
      }

      await provider.cargarDatos();
      expect(provider.moras, hasLength(4));
      expect(
        provider.moras.map((mora) => mora.prestamo.frecuencia),
        containsAll(frecuencias),
      );
      expect(provider.moras.every((mora) => mora.diasAtraso > 0), isTrue);
    },
  );

  test('exporta cada tabla a CSV con sus claves de relación', () async {
    await provider.cargarDatos();
    await provider.agregarCliente(
      nombre: 'Cliente CSV',
      telefono: '3001234567',
    );
    final cliente = provider.clientes.single;
    final prestamo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 10000,
      porcentajeInteres: 10,
      numCuotas: 1,
      frecuencia: CalculadoraService.frecuenciaDiaria,
    );
    final cuota = provider.cuotasDePrestamo(prestamo.id!).single;
    await provider.registrarPago(
      prestamoId: prestamo.id!,
      cuotaId: cuota.id!,
      monto: 1000,
      metodoPago: 'EFECTIVO',
      fecha: DateTime(2026, 9, 30, 13),
    );

    final csv = DatabaseExportService.exportarCsv(provider);

    expect(
      csv.keys,
      containsAll(['clientes.csv', 'prestamos.csv', 'cuotas.csv', 'pagos.csv']),
    );
    expect(csv['clientes.csv']!.take(3), [0xEF, 0xBB, 0xBF]);
    expect(
      String.fromCharCodes(csv['prestamos.csv']!),
      contains(',"${cliente.id}"'),
    );
    expect(
      String.fromCharCodes(csv['cuotas.csv']!),
      contains('"${prestamo.id}"'),
    );
    expect(String.fromCharCodes(csv['pagos.csv']!), contains('"${cuota.id}"'));
  });

  test('registra un pago y marca cuota y préstamo pagados', () async {
    await provider.cargarDatos();
    await provider.agregarCliente(
      nombre: 'Cliente de pago',
      telefono: '3001234567',
    );
    final cliente = provider.clientes.single;
    final prestamo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 10000,
      porcentajeInteres: 20,
      numCuotas: 1,
      frecuencia: CalculadoraService.frecuenciaDiaria,
    );
    final cuota = provider.cuotasDePrestamo(prestamo.id!).single;

    final pago = await provider.registrarPago(
      prestamoId: prestamo.id!,
      cuotaId: cuota.id!,
      monto: prestamo.montoTotalPagar,
      metodoPago: 'EFECTIVO',
      fecha: DateTime(2026, 9, 30, 13),
    );

    expect(pago.id, isNotNull);
    expect(provider.prestamoPorId(prestamo.id!)!.estado, 'PAGADO');
    expect(provider.prestamoPorId(prestamo.id!)!.saldoPendiente, 0);
    expect(provider.cuotasDePrestamo(prestamo.id!).single.estado, 'PAGADA');
    expect(provider.pagosDePrestamo(prestamo.id!), hasLength(1));
    expect(provider.pagosHoy, hasLength(1));

    await provider.cargarDatos(mostrarCarga: false);
    expect(provider.cargando, isFalse);
    expect(provider.pagosDePrestamo(prestamo.id!), hasLength(1));
  });

  test('acepta abonos parciales en miles y rechaza importes menores', () async {
    await provider.cargarDatos();
    await provider.agregarCliente(
      nombre: 'Cliente de abono parcial',
      telefono: '3001234567',
    );
    final cliente = provider.clientes.single;
    final prestamo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 900000,
      porcentajeInteres: 0,
      numCuotas: 3,
      frecuencia: CalculadoraService.frecuenciaDiaria,
    );
    final cuotas = provider.cuotasDePrestamo(prestamo.id!);
    final cuota = cuotas.first;
    expect(cuotas.map((item) => item.montoCuota), [300000, 300000, 300000]);
    expect(
      cuotas.fold<double>(0, (total, item) => total + item.montoCuota),
      900000,
    );

    await expectLater(
      provider.registrarPago(
        prestamoId: prestamo.id!,
        cuotaId: cuota.id!,
        monto: 500,
        metodoPago: 'EFECTIVO',
        fecha: DateTime(2026, 9, 30, 13),
      ),
      throwsArgumentError,
    );
    final pago = await provider.registrarPago(
      prestamoId: prestamo.id!,
      cuotaId: cuota.id!,
      monto: 200000,
      metodoPago: 'EFECTIVO',
      fecha: DateTime(2026, 9, 30, 13),
    );

    expect(pago.monto, 200000);
    expect(provider.cuotasDePrestamo(prestamo.id!).first.montoPagado, 200000);
    expect(
      cuota.montoCuota -
          provider.cuotasDePrestamo(prestamo.id!).first.montoPagado,
      100000,
    );
  });

  test('bloquea eliminación con deuda y la permite a paz y salvo', () async {
    await provider.cargarDatos();
    await provider.agregarCliente(
      nombre: 'Cliente protegido',
      telefono: '3001234567',
    );
    final cliente = provider.clientes.single;
    final prestamo = await provider.crearPrestamo(
      clienteId: cliente.id!,
      capital: 10000,
      porcentajeInteres: 0,
      numCuotas: 1,
      frecuencia: CalculadoraService.frecuenciaDiaria,
    );

    expect(await provider.clienteEstaPazYSalvo(cliente.id!), isFalse);
    await expectLater(provider.eliminarCliente(cliente.id!), throwsStateError);
    expect(provider.clientePorId(cliente.id!)!.activo, isTrue);

    final cuota = provider.cuotasDePrestamo(prestamo.id!).single;
    await provider.registrarPago(
      prestamoId: prestamo.id!,
      cuotaId: cuota.id!,
      monto: prestamo.montoTotalPagar,
      metodoPago: 'EFECTIVO',
      fecha: DateTime(2026, 9, 30, 13),
    );
    expect(await provider.clienteEstaPazYSalvo(cliente.id!), isTrue);

    await provider.eliminarCliente(cliente.id!);
    expect(provider.clientePorId(cliente.id!)!.activo, isFalse);
    expect(provider.clientes, isEmpty);
  });
}
