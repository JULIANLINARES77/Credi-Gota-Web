import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common/sqflite.dart'
    show OpenDatabaseOptions, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqlite_ffi;

import 'package:flutter_prestamos/core/constants/db_constants.dart';
import 'package:flutter_prestamos/data/database/database_helper.dart';
import 'package:flutter_prestamos/logic/providers/gota_provider.dart';
import 'package:flutter_prestamos/logic/services/calculadora_service.dart';
import 'package:flutter_prestamos/logic/services/database_export_service.dart';
import 'package:flutter_prestamos/logic/services/pin_hash_service.dart';

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

  test('guarda el PIN hasheado y lo valida después de reabrir SQLite', () async {
    await provider.cargarDatos();
    await provider.configurarPin('123456');

    final configuracion = await DatabaseHelper.instance.obtenerConfiguracion();
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
  });

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
          await db.insert('configuracion', {
            'nombre_negocio': 'Negocio existente',
            'pin_seguridad': '1234',
          });
        },
      ),
    );
    await legacyDb.close();

    final configuracion = await DatabaseHelper.instance.obtenerConfiguracion();

    expect(configuracion?[DbConstants.configuracionNombreNegocio], 'Negocio existente');
    expect(configuracion?[DbConstants.configuracionPinSeguridad], isNull);
    expect(configuracion?[DbConstants.configuracionPinHash], isNull);
    expect(configuracion?[DbConstants.configuracionDireccionNegocio], isNull);
    expect(
      configuracion?[DbConstants.configuracionFrecuenciaRespaldo],
      'daily',
    );
    expect(configuracion?[DbConstants.configuracionUltimoRespaldo], isNull);
  });

  test('valida los ajustes aunque se actualicen fuera de la pantalla', () async {
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
  });

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
    expect(prestamosCliente.map((prestamo) => prestamo.id), containsAll([
      primerPrestamo.id,
      segundoPrestamo.id,
    ]));
    expect(provider.cuotasDePrestamo(primerPrestamo.id!), hasLength(4));
    expect(provider.cuotasDePrestamo(segundoPrestamo.id!), hasLength(2));
  });

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
      monto: 100,
      metodoPago: 'EFECTIVO',
      fecha: DateTime(2026, 9, 30, 13),
    );

    final csv = DatabaseExportService.exportarCsv(provider);

    expect(csv.keys, containsAll([
      'clientes.csv',
      'prestamos.csv',
      'cuotas.csv',
      'pagos.csv',
    ]));
    expect(csv['clientes.csv']!.take(3), [0xEF, 0xBB, 0xBF]);
    expect(
      String.fromCharCodes(csv['prestamos.csv']!),
      contains(',"${cliente.id}"'),
    );
    expect(
      String.fromCharCodes(csv['cuotas.csv']!),
      contains('"${prestamo.id}"'),
    );
    expect(
      String.fromCharCodes(csv['pagos.csv']!),
      contains('"${cuota.id}"'),
    );
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
