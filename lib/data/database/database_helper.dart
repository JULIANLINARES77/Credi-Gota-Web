import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../core/utils/moneda_colombiana.dart';
import '../models/cliente.dart';
import '../models/cuota.dart';
import '../models/pago.dart';
import '../models/prestamo.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _moneyTolerance = 0.000001;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final directory = await getApplicationSupportDirectory();
    final databasePath = join(directory.path, DbConstants.databaseName);
    debugPrint('GotaControl: abriendo base SQLite en $databasePath');

    return openDatabase(
      databasePath,
      version: DbConstants.databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('GotaControl: creando esquema SQLite v$version');
    final statements = [
      '''
      CREATE TABLE ${DbConstants.tableClientes} (
        ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.clienteNombre} TEXT NOT NULL,
        ${DbConstants.clienteCedula} TEXT UNIQUE,
        ${DbConstants.clienteTelefono} TEXT NOT NULL,
        ${DbConstants.clienteDireccion} TEXT,
        ${DbConstants.clienteFotoPath} TEXT,
        ${DbConstants.clienteNotas} TEXT,
        ${DbConstants.clienteFechaRegistro} TEXT NOT NULL,
        ${DbConstants.clienteActivo} INTEGER NOT NULL DEFAULT 1
      )
      ''',
      '''
      CREATE TABLE ${DbConstants.tablePrestamos} (
        ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.prestamoClienteId} INTEGER NOT NULL,
        ${DbConstants.prestamoMontoCapital} REAL NOT NULL,
        ${DbConstants.prestamoPorcentajeInteres} REAL NOT NULL,
        ${DbConstants.prestamoMontoInteres} REAL NOT NULL,
        ${DbConstants.prestamoMontoTotalPagar} REAL NOT NULL,
        ${DbConstants.prestamoNumCuotas} INTEGER NOT NULL,
        ${DbConstants.prestamoValorCuota} REAL NOT NULL,
        ${DbConstants.prestamoFrecuencia} TEXT NOT NULL,
        ${DbConstants.prestamoDiasPersonalizados} TEXT,
        ${DbConstants.prestamoFechaInicio} TEXT NOT NULL,
        ${DbConstants.prestamoFechaFinEstimada} TEXT NOT NULL,
        ${DbConstants.prestamoEstado} TEXT NOT NULL,
        ${DbConstants.prestamoSaldoPendiente} REAL NOT NULL,
        ${DbConstants.prestamoTotalPagado} REAL NOT NULL DEFAULT 0,
        ${DbConstants.prestamoCreatedAt} TEXT NOT NULL,
        FOREIGN KEY (${DbConstants.prestamoClienteId})
          REFERENCES ${DbConstants.tableClientes} (${DbConstants.columnId})
          ON DELETE CASCADE
      )
      ''',
      '''
      CREATE TABLE ${DbConstants.tableCuotas} (
        ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.cuotaPrestamoId} INTEGER NOT NULL,
        ${DbConstants.cuotaNumero} INTEGER NOT NULL,
        ${DbConstants.cuotaFechaVencimiento} TEXT NOT NULL,
        ${DbConstants.cuotaMonto} REAL NOT NULL,
        ${DbConstants.cuotaMontoPagado} REAL NOT NULL DEFAULT 0,
        ${DbConstants.cuotaFechaPago} TEXT,
        ${DbConstants.cuotaEstado} TEXT NOT NULL,
        ${DbConstants.cuotaDiasAtraso} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.cuotaEsPenalizacion} INTEGER NOT NULL DEFAULT 0,
        UNIQUE (${DbConstants.cuotaPrestamoId}, ${DbConstants.cuotaNumero}),
        FOREIGN KEY (${DbConstants.cuotaPrestamoId})
          REFERENCES ${DbConstants.tablePrestamos} (${DbConstants.columnId})
          ON DELETE CASCADE
      )
      ''',
      '''
      CREATE TABLE ${DbConstants.tablePagos} (
        ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.pagoCuotaId} INTEGER NOT NULL,
        ${DbConstants.pagoPrestamoId} INTEGER NOT NULL,
        ${DbConstants.pagoClienteId} INTEGER NOT NULL,
        ${DbConstants.pagoMonto} REAL NOT NULL,
        ${DbConstants.pagoFechaHora} TEXT NOT NULL,
        ${DbConstants.pagoMetodoPago} TEXT,
        ${DbConstants.pagoNota} TEXT,
        ${DbConstants.pagoRegistradoPor} TEXT,
        FOREIGN KEY (${DbConstants.pagoCuotaId})
          REFERENCES ${DbConstants.tableCuotas} (${DbConstants.columnId})
          ON DELETE CASCADE,
        FOREIGN KEY (${DbConstants.pagoPrestamoId})
          REFERENCES ${DbConstants.tablePrestamos} (${DbConstants.columnId})
          ON DELETE CASCADE,
        FOREIGN KEY (${DbConstants.pagoClienteId})
          REFERENCES ${DbConstants.tableClientes} (${DbConstants.columnId})
          ON DELETE CASCADE
      )
      ''',
      '''
      CREATE TABLE ${DbConstants.tableConfiguracion} (
        ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.configuracionNombreNegocio} TEXT,
        ${DbConstants.configuracionTelefonoNegocio} TEXT,
        ${DbConstants.configuracionMetaDiaria} REAL,
        ${DbConstants.configuracionPorcentajeMora} REAL NOT NULL DEFAULT 10,
        ${DbConstants.configuracionDiasGraciaMora} INTEGER NOT NULL DEFAULT 3,
        ${DbConstants.configuracionPinSeguridad} TEXT,
        ${DbConstants.configuracionPinHash} TEXT,
        ${DbConstants.configuracionPinIntentosFallidos} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.configuracionPinBloqueadoHasta} INTEGER,
        ${DbConstants.configuracionDireccionNegocio} TEXT,
        ${DbConstants.configuracionAlertasMora} INTEGER NOT NULL DEFAULT 1,
        ${DbConstants.configuracionRecordatorioDiario} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.configuracionHoraRecordatorio} TEXT NOT NULL DEFAULT '08:00',
        ${DbConstants.configuracionFrecuenciaRespaldo} TEXT NOT NULL DEFAULT 'daily',
        ${DbConstants.configuracionUltimoRespaldo} INTEGER,
        ${DbConstants.configuracionMoneda} TEXT NOT NULL DEFAULT 'COP'
      )
      ''',
      'CREATE INDEX ${DbConstants.indexPrestamosCliente} ON '
          '${DbConstants.tablePrestamos} (${DbConstants.prestamoClienteId})',
      'CREATE INDEX ${DbConstants.indexCuotasPrestamoFecha} ON '
          '${DbConstants.tableCuotas} '
          '(${DbConstants.cuotaPrestamoId}, ${DbConstants.cuotaFechaVencimiento})',
      'CREATE INDEX ${DbConstants.indexCuotasFechaEstado} ON '
          '${DbConstants.tableCuotas} '
          '(${DbConstants.cuotaFechaVencimiento}, ${DbConstants.cuotaEstado})',
      'CREATE INDEX ${DbConstants.indexPagosFecha} ON '
          '${DbConstants.tablePagos} (${DbConstants.pagoFechaHora})',
      'CREATE INDEX ${DbConstants.indexPagosPrestamo} ON '
          '${DbConstants.tablePagos} (${DbConstants.pagoPrestamoId})',
    ];

    for (final statement in statements) {
      await db.execute(statement);
    }

    // Fila base de configuración
    await db.insert(DbConstants.tableConfiguracion, {
      DbConstants.configuracionNombreNegocio: 'GotaControl',
      DbConstants.configuracionPorcentajeMora: 10.0,
      DbConstants.configuracionDiasGraciaMora: 3,
      DbConstants.configuracionMoneda: 'COP',
    });
  }

  /// Migraciones versionadas. Añade un bloque `if (oldVersion < N)` por
  /// cada nueva versión del esquema y sube [DbConstants.databaseVersion].
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('GotaControl: migrando base de datos v$oldVersion → v$newVersion');

    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE ${DbConstants.tableConfiguracion} '
        'ADD COLUMN ${DbConstants.configuracionPinHash} TEXT',
      );
      await db.execute(
        'ALTER TABLE ${DbConstants.tableConfiguracion} '
        'ADD COLUMN ${DbConstants.configuracionPinIntentosFallidos} '
        'INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE ${DbConstants.tableConfiguracion} '
        'ADD COLUMN ${DbConstants.configuracionPinBloqueadoHasta} INTEGER',
      );
      await db.update(
        DbConstants.tableConfiguracion,
        {DbConstants.configuracionPinSeguridad: null},
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE ${DbConstants.tableConfiguracion} '
        'ADD COLUMN ${DbConstants.configuracionDireccionNegocio} TEXT',
      );
      await db.execute(
        'ALTER TABLE ${DbConstants.tableConfiguracion} '
        'ADD COLUMN ${DbConstants.configuracionAlertasMora} '
        'INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute(
        'ALTER TABLE ${DbConstants.tableConfiguracion} '
        'ADD COLUMN ${DbConstants.configuracionRecordatorioDiario} '
        'INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE ${DbConstants.tableConfiguracion} '
        'ADD COLUMN ${DbConstants.configuracionHoraRecordatorio} '
        "TEXT NOT NULL DEFAULT '08:00'",
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE ${DbConstants.tableConfiguracion} '
        'ADD COLUMN ${DbConstants.configuracionFrecuenciaRespaldo} '
        "TEXT NOT NULL DEFAULT 'daily'",
      );
      await db.execute(
        'ALTER TABLE ${DbConstants.tableConfiguracion} '
        'ADD COLUMN ${DbConstants.configuracionUltimoRespaldo} INTEGER',
      );
    }
  }

  Future<void> close() async {
    final currentDatabase = _database;
    if (currentDatabase == null) return;
    await currentDatabase.close();
    _database = null;
  }

  Future<String> get databaseFilePath async {
    final directory = await getApplicationSupportDirectory();
    return join(directory.path, DbConstants.databaseName);
  }

  // ─────────────────────────── CLIENTES ───────────────────────────

  Future<int> insertarCliente(Cliente cliente) async {
    final db = await database;
    return db.insert(DbConstants.tableClientes, cliente.toMap());
  }

  Future<List<Cliente>> obtenerTodosLosClientes() async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tableClientes,
      orderBy: '${DbConstants.clienteNombre} COLLATE NOCASE ASC',
    );
    return rows.map(Cliente.fromMap).toList();
  }

  Future<Cliente?> obtenerClientePorId(int id) async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tableClientes,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Cliente.fromMap(rows.first);
  }

  Future<List<Cliente>> buscarClientes(String query) async {
    final db = await database;
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return obtenerTodosLosClientes();
    final rows = await db.query(
      DbConstants.tableClientes,
      where:
          '${DbConstants.clienteNombre} LIKE ? OR ${DbConstants.clienteCedula} LIKE ?',
      whereArgs: ['%$normalizedQuery%', '%$normalizedQuery%'],
      orderBy: '${DbConstants.clienteNombre} COLLATE NOCASE ASC',
    );
    return rows.map(Cliente.fromMap).toList();
  }

  Future<int> actualizarCliente(Cliente cliente) async {
    if (cliente.id == null) return 0;
    final db = await database;
    return db.update(
      DbConstants.tableClientes,
      cliente.toMap()..remove(DbConstants.columnId),
      where: '${DbConstants.columnId} = ?',
      whereArgs: [cliente.id],
    );
  }

  Future<int> eliminarCliente(int id) async {
    final db = await database;
    return db.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        'SELECT COUNT(*) AS total FROM ${DbConstants.tablePrestamos} '
        'WHERE ${DbConstants.prestamoClienteId} = ? '
        'AND ${DbConstants.prestamoEstado} IN (?, ?)',
        [id, 'ACTIVO', 'MORA'],
      );
      final prestamosAbiertos = (rows.first['total'] as num).toInt();
      if (prestamosAbiertos > 0) {
        throw StateError(
          'No se puede eliminar el cliente porque tiene préstamos activos. '
          'Debe estar a paz y salvo.',
        );
      }
      return transaction.update(
        DbConstants.tableClientes,
        {DbConstants.clienteActivo: 0},
        where: '${DbConstants.columnId} = ?',
        whereArgs: [id],
      );
    });
  }

  Future<bool> clienteEstaPazYSalvo(int clienteId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${DbConstants.tablePrestamos} '
      'WHERE ${DbConstants.prestamoClienteId} = ? '
      'AND ${DbConstants.prestamoEstado} IN (?, ?)',
      [clienteId, 'ACTIVO', 'MORA'],
    );
    return (rows.first['total'] as num).toInt() == 0;
  }

  // ─────────────────────────── PRÉSTAMOS ───────────────────────────

  Future<int> crearPrestamoConCuotas(
    Prestamo prestamo,
    List<Cuota> cuotas,
  ) async {
    if (prestamo.numCuotas != cuotas.length) {
      throw ArgumentError('El número de cuotas no coincide con numCuotas.');
    }
    if (prestamo.id != null) {
      throw ArgumentError('El préstamo debe ser nuevo y no tener id.');
    }

    final db = await database;
    final loanId = await db.transaction((transaction) async {
      final insertedLoanId = await transaction.insert(
        DbConstants.tablePrestamos,
        prestamo.toMap(),
      );
      final batch = transaction.batch();
      for (final cuota in cuotas) {
        batch.insert(
          DbConstants.tableCuotas,
          cuota.copyWith(prestamoId: insertedLoanId).toMap(),
        );
      }
      await batch.commit(noResult: true);
      return insertedLoanId;
    });
    debugPrint(
      'GotaControl: préstamo $loanId creado con ${cuotas.length} cuotas',
    );
    return loanId;
  }

  Future<List<Prestamo>> obtenerPrestamosActivos() async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tablePrestamos,
      where: '${DbConstants.prestamoEstado} IN (?, ?)',
      whereArgs: ['ACTIVO', 'MORA'],
      orderBy: '${DbConstants.prestamoFechaInicio} ASC',
    );
    return rows.map(Prestamo.fromMap).toList();
  }

  Future<Prestamo?> obtenerPrestamoPorId(int id) async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tablePrestamos,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Prestamo.fromMap(rows.first);
  }

  Future<List<Prestamo>> obtenerPrestamosPorCliente(int clienteId) async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tablePrestamos,
      where: '${DbConstants.prestamoClienteId} = ?',
      whereArgs: [clienteId],
      orderBy: '${DbConstants.prestamoFechaInicio} DESC',
    );
    return rows.map(Prestamo.fromMap).toList();
  }

  Future<int> actualizarPrestamo(Prestamo prestamo) async {
    if (prestamo.id == null) return 0;
    final db = await database;
    return db.update(
      DbConstants.tablePrestamos,
      prestamo.toMap()..remove(DbConstants.columnId),
      where: '${DbConstants.columnId} = ?',
      whereArgs: [prestamo.id],
    );
  }

  Future<double> obtenerTotalEnCalle() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(${DbConstants.prestamoSaldoPendiente}), 0) AS total '
      'FROM ${DbConstants.tablePrestamos} '
      'WHERE ${DbConstants.prestamoEstado} IN (?, ?)',
      ['ACTIVO', 'MORA'],
    );
    return _asDouble(rows.first['total']);
  }

  // ─────────────────────────── CUOTAS ───────────────────────────

  Future<List<Cuota>> obtenerCuotasPorPrestamo(int prestamoId) async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tableCuotas,
      where: '${DbConstants.cuotaPrestamoId} = ?',
      whereArgs: [prestamoId],
      orderBy: '${DbConstants.cuotaNumero} ASC',
    );
    return rows.map(Cuota.fromMap).toList();
  }

  Future<List<Cuota>> obtenerCuotasDelDia(DateTime fecha) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT c.* FROM ${DbConstants.tableCuotas} c '
      'JOIN ${DbConstants.tablePrestamos} p '
      'ON p.${DbConstants.columnId} = c.${DbConstants.cuotaPrestamoId} '
      'WHERE substr(c.${DbConstants.cuotaFechaVencimiento}, 1, 10) = ? '
      'AND c.${DbConstants.cuotaEstado} != ? '
      'AND p.${DbConstants.prestamoEstado} IN (?, ?) '
      'ORDER BY c.${DbConstants.cuotaFechaVencimiento} ASC',
      [_dateKey(fecha), 'PAGADA', 'ACTIVO', 'MORA'],
    );
    return rows.map(Cuota.fromMap).toList();
  }

  Future<List<Cuota>> obtenerCuotasAtrasadas() async {
    final db = await database;
    final today = _dateKey(DateTime.now());
    final rows = await db.rawQuery(
      'SELECT c.* FROM ${DbConstants.tableCuotas} c '
      'JOIN ${DbConstants.tablePrestamos} p '
      'ON p.${DbConstants.columnId} = c.${DbConstants.cuotaPrestamoId} '
      'WHERE substr(c.${DbConstants.cuotaFechaVencimiento}, 1, 10) < ? '
      'AND c.${DbConstants.cuotaEstado} != ? '
      'AND p.${DbConstants.prestamoEstado} IN (?, ?) '
      'ORDER BY c.${DbConstants.cuotaFechaVencimiento} ASC',
      [today, 'PAGADA', 'ACTIVO', 'MORA'],
    );

    return rows.map((row) {
      final map = Map<String, Object?>.from(row);
      final dueDate = _dateOnly(
        map[DbConstants.cuotaFechaVencimiento] as String,
      );
      final todayDate = _dateOnly(today);
      map[DbConstants.cuotaEstado] = 'ATRASADA';
      map[DbConstants.cuotaDiasAtraso] = todayDate.difference(dueDate).inDays;
      return Cuota.fromMap(map);
    }).toList();
  }

  Future<int> actualizarCuota(Cuota cuota) async {
    if (cuota.id == null) return 0;
    final db = await database;
    return db.update(
      DbConstants.tableCuotas,
      cuota.toMap()..remove(DbConstants.columnId),
      where: '${DbConstants.columnId} = ?',
      whereArgs: [cuota.id],
    );
  }

  // ─────────────────────────── PAGOS ───────────────────────────

  Future<int> registrarPago(Pago pago) async {
    if (pago.monto <= 0) {
      throw ArgumentError.value(
        pago.monto,
        'monto',
        'Debe ser mayor que cero.',
      );
    }
    if (pago.id != null) {
      throw ArgumentError('El pago debe ser nuevo y no tener id.');
    }

    final db = await database;
    final paymentId = await db.transaction((transaction) async {
      final installmentRows = await transaction.query(
        DbConstants.tableCuotas,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [pago.cuotaId],
        limit: 1,
      );
      if (installmentRows.isEmpty) {
        throw StateError('No existe la cuota ${pago.cuotaId}.');
      }

      final installment = Cuota.fromMap(installmentRows.first);
      if (installment.prestamoId != pago.prestamoId) {
        throw ArgumentError('La cuota no pertenece al préstamo indicado.');
      }
      final loanRows = await transaction.query(
        DbConstants.tablePrestamos,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [pago.prestamoId],
        limit: 1,
      );
      if (loanRows.isEmpty) {
        throw StateError('No existe el préstamo ${pago.prestamoId}.');
      }

      final loan = Prestamo.fromMap(loanRows.first);
      if (loan.clienteId != pago.clienteId) {
        throw ArgumentError('El cliente no corresponde al préstamo.');
      }
      if (loan.estado == 'CANCELADO' || loan.estado == 'PAGADO') {
        throw StateError(
          'No se pueden registrar pagos en un préstamo cerrado.',
        );
      }
      if (MonedaColombiana.esMultiploDeUnidad(installment.montoCuota) &&
          !MonedaColombiana.esMultiploDeUnidad(pago.monto)) {
        throw ArgumentError('El pago debe ser múltiplo de \$1.000.');
      }

      final installmentBalance =
          installment.montoCuota - installment.montoPagado;
      if (pago.monto - installmentBalance > _moneyTolerance) {
        throw ArgumentError('El pago supera el saldo pendiente de la cuota.');
      }
      if (pago.monto - loan.saldoPendiente > _moneyTolerance) {
        throw ArgumentError('El pago supera el saldo pendiente del préstamo.');
      }

      final newInstallmentPaid = installment.montoPagado + pago.monto;
      final installmentIsPaid =
          installment.montoCuota - newInstallmentPaid <= _moneyTolerance;
      final newLoanBalance = (loan.saldoPendiente - pago.monto).clamp(
        0.0,
        double.infinity,
      );
      final paymentId = await transaction.insert(
        DbConstants.tablePagos,
        pago.toMap(),
      );

      await transaction.update(
        DbConstants.tableCuotas,
        {
          DbConstants.cuotaMontoPagado: newInstallmentPaid,
          DbConstants.cuotaFechaPago: installmentIsPaid
              ? pago.fechaHora.toIso8601String()
              : null,
          DbConstants.cuotaEstado: installmentIsPaid ? 'PAGADA' : 'PARCIAL',
        },
        where: '${DbConstants.columnId} = ?',
        whereArgs: [pago.cuotaId],
      );

      final overdueRows = await transaction.rawQuery(
        'SELECT COUNT(*) AS total FROM ${DbConstants.tableCuotas} '
        'WHERE ${DbConstants.cuotaPrestamoId} = ? '
        'AND ${DbConstants.cuotaEstado} != ? '
        'AND substr(${DbConstants.cuotaFechaVencimiento}, 1, 10) < ?',
        [pago.prestamoId, 'PAGADA', _dateKey(DateTime.now())],
      );
      final hasOverdueInstallments =
          ((overdueRows.first['total'] as num?)?.toInt() ?? 0) > 0;
      final newLoanState = newLoanBalance <= _moneyTolerance
          ? 'PAGADO'
          : hasOverdueInstallments
          ? 'MORA'
          : 'ACTIVO';

      await transaction.update(
        DbConstants.tablePrestamos,
        {
          DbConstants.prestamoSaldoPendiente: newLoanBalance,
          DbConstants.prestamoTotalPagado: loan.totalPagado + pago.monto,
          DbConstants.prestamoEstado: newLoanState,
        },
        where: '${DbConstants.columnId} = ?',
        whereArgs: [pago.prestamoId],
      );
      return paymentId;
    });
    debugPrint('GotaControl: pago $paymentId registrado');
    return paymentId;
  }

  Future<List<Pago>> obtenerPagosDelDia(DateTime fecha) async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tablePagos,
      where: 'substr(${DbConstants.pagoFechaHora}, 1, 10) = ?',
      whereArgs: [_dateKey(fecha)],
      orderBy: '${DbConstants.pagoFechaHora} DESC',
    );
    return rows.map(Pago.fromMap).toList();
  }

  Future<double> obtenerTotalRecaudadoDelDia(DateTime fecha) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(${DbConstants.pagoMonto}), 0) AS total '
      'FROM ${DbConstants.tablePagos} '
      'WHERE substr(${DbConstants.pagoFechaHora}, 1, 10) = ?',
      [_dateKey(fecha)],
    );
    return _asDouble(rows.first['total']);
  }

  Future<double> obtenerGananciaDelDia(DateTime fecha) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(p.${DbConstants.pagoMonto} * '
      'l.${DbConstants.prestamoMontoInteres} / '
      'NULLIF(l.${DbConstants.prestamoMontoTotalPagar}, 0)), 0) AS ganancia '
      'FROM ${DbConstants.tablePagos} p '
      'JOIN ${DbConstants.tableCuotas} c '
      'ON c.${DbConstants.columnId} = p.${DbConstants.pagoCuotaId} '
      'JOIN ${DbConstants.tablePrestamos} l '
      'ON l.${DbConstants.columnId} = p.${DbConstants.pagoPrestamoId} '
      'WHERE substr(p.${DbConstants.pagoFechaHora}, 1, 10) = ? '
      'AND c.${DbConstants.cuotaEsPenalizacion} = 0',
      [_dateKey(fecha)],
    );
    return _asDouble(rows.first['ganancia']);
  }

  Future<List<Pago>> obtenerPagosPorPrestamo(int prestamoId) async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tablePagos,
      where: '${DbConstants.pagoPrestamoId} = ?',
      whereArgs: [prestamoId],
      orderBy: '${DbConstants.pagoFechaHora} DESC',
    );
    return rows.map(Pago.fromMap).toList();
  }

  // ─────────────────────────── DASHBOARD ───────────────────────────

  Future<Map<String, dynamic>> obtenerResumenDashboard() async {
    final db = await database;
    final today = _dateKey(DateTime.now());
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE((
          SELECT SUM(p.${DbConstants.pagoMonto})
          FROM ${DbConstants.tablePagos} p
          WHERE substr(p.${DbConstants.pagoFechaHora}, 1, 10) = ?
        ), 0) AS recaudo_hoy,
        COALESCE((
          SELECT SUM(p.${DbConstants.pagoMonto} *
            l.${DbConstants.prestamoMontoInteres} /
            NULLIF(l.${DbConstants.prestamoMontoTotalPagar}, 0))
          FROM ${DbConstants.tablePagos} p
          JOIN ${DbConstants.tableCuotas} c
            ON c.${DbConstants.columnId} = p.${DbConstants.pagoCuotaId}
          JOIN ${DbConstants.tablePrestamos} l
            ON l.${DbConstants.columnId} = p.${DbConstants.pagoPrestamoId}
          WHERE substr(p.${DbConstants.pagoFechaHora}, 1, 10) = ?
            AND c.${DbConstants.cuotaEsPenalizacion} = 0
        ), 0) AS ganancia_hoy,
        COALESCE((
          SELECT SUM(l.${DbConstants.prestamoSaldoPendiente})
          FROM ${DbConstants.tablePrestamos} l
          WHERE l.${DbConstants.prestamoEstado} IN ('ACTIVO', 'MORA')
        ), 0) AS total_en_calle,
        (
          SELECT COUNT(DISTINCT l.${DbConstants.prestamoClienteId})
          FROM ${DbConstants.tablePrestamos} l
          JOIN ${DbConstants.tableCuotas} c
            ON c.${DbConstants.cuotaPrestamoId} = l.${DbConstants.columnId}
          WHERE c.${DbConstants.cuotaEstado} != 'PAGADA'
            AND substr(c.${DbConstants.cuotaFechaVencimiento}, 1, 10) < ?
            AND l.${DbConstants.prestamoEstado} IN ('ACTIVO', 'MORA')
        ) AS clientes_en_mora,
        COALESCE((
          SELECT SUM(c.${DbConstants.cuotaMonto} - c.${DbConstants.cuotaMontoPagado})
          FROM ${DbConstants.tableCuotas} c
          JOIN ${DbConstants.tablePrestamos} l
            ON l.${DbConstants.columnId} = c.${DbConstants.cuotaPrestamoId}
          WHERE substr(c.${DbConstants.cuotaFechaVencimiento}, 1, 10) = ?
            AND c.${DbConstants.cuotaEstado} != 'PAGADA'
            AND l.${DbConstants.prestamoEstado} IN ('ACTIVO', 'MORA')
        ), 0) AS pagos_pendientes_hoy
      ''',
      [today, today, today, today],
    );
    final summary = rows.first;
    return {
      'recaudo_hoy': _asDouble(summary['recaudo_hoy']),
      'ganancia_hoy': _asDouble(summary['ganancia_hoy']),
      'total_en_calle': _asDouble(summary['total_en_calle']),
      'clientes_en_mora': (summary['clientes_en_mora'] as num).toInt(),
      'pagos_pendientes_hoy': _asDouble(summary['pagos_pendientes_hoy']),
    };
  }

  // ─────────────────────────── CONFIGURACIÓN ───────────────────────────

  Future<Map<String, Object?>?> obtenerConfiguracion() async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tableConfiguracion,
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<void> guardarConfiguracion(Map<String, Object?> data) async {
    final db = await database;
    final rows = await db.query(
      DbConstants.tableConfiguracion,
      columns: [DbConstants.columnId],
      limit: 1,
    );
    final payload = Map<String, Object?>.from(data)
      ..remove(DbConstants.columnId);

    if (rows.isEmpty) {
      await db.insert(DbConstants.tableConfiguracion, payload);
    } else {
      await db.update(
        DbConstants.tableConfiguracion,
        payload,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [rows.first[DbConstants.columnId]],
      );
    }
  }

  Future<void> guardarHashPin(String? hash) async {
    await guardarConfiguracion({
      DbConstants.configuracionPinHash: hash,
      DbConstants.configuracionPinSeguridad: null,
      DbConstants.configuracionPinIntentosFallidos: 0,
      DbConstants.configuracionPinBloqueadoHasta: null,
    });
  }

  Future<void> guardarIntentosFallidosPin({
    required int intentos,
    DateTime? bloqueadoHasta,
  }) async {
    await guardarConfiguracion({
      DbConstants.configuracionPinIntentosFallidos: intentos,
      DbConstants.configuracionPinBloqueadoHasta:
          bloqueadoHasta?.millisecondsSinceEpoch,
    });
  }

  // ─────────────────────────── HELPERS ───────────────────────────

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime _dateOnly(String dateOrTimestamp) =>
      DateTime.parse('${dateOrTimestamp.substring(0, 10)}T00:00:00');

  static double _asDouble(Object? value) => (value as num?)?.toDouble() ?? 0;
}