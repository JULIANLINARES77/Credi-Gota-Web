import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cliente.dart';
import '../models/cuota.dart';
import '../models/pago.dart';
import '../models/prestamo.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();
  
  SupabaseClient get _db => Supabase.instance.client;

  Future<int> insertarCliente(Cliente cliente) async {
    final response = await _db.from('clientes').insert(cliente.toMap()..remove('id')).select('id').single();
    return response['id'];
  }

  Future<List<Cliente>> obtenerTodosLosClientes() async {
    final response = await _db.from('clientes').select().order('nombre', ascending: true);
    return response.map((json) => Cliente.fromMap(json)).toList();
  }

  Future<Cliente?> obtenerClientePorId(int id) async {
    final response = await _db.from('clientes').select().eq('id', id).maybeSingle();
    return response == null ? null : Cliente.fromMap(response);
  }

  Future<int> actualizarCliente(Cliente cliente) async {
    if (cliente.id == null) return 0;
    final response = await _db.from('clientes').update(cliente.toMap()..remove('id')).eq('id', cliente.id!).select('id');
    return response.length;
  }

  Future<int> eliminarCliente(int id) async {
    final prestamos = await _db.from('prestamos').select('id').eq('cliente_id', id).inFilter('estado', ['ACTIVO', 'MORA']);
    if (prestamos.isNotEmpty) throw StateError('No se puede eliminar el cliente porque tiene préstamos activos. Debe estar a paz y salvo.');
    final response = await _db.from('clientes').update({'activo': 0}).eq('id', id).select('id');
    return response.length;
  }

  Future<bool> clienteEstaPazYSalvo(int clienteId) async {
    final prestamos = await _db.from('prestamos').select('id').eq('cliente_id', clienteId).inFilter('estado', ['ACTIVO', 'MORA']);
    return prestamos.isEmpty;
  }

  Future<int> crearPrestamoConCuotas(Prestamo prestamo, List<Cuota> cuotas) async {
    final cuotasJson = cuotas.map((c) => {
      'numero_cuota': c.numeroCuota,
      'fecha_vencimiento': c.fechaVencimiento.toIso8601String(),
      'monto_cuota': c.montoCuota,
    }).toList();

    final params = prestamo.toMap()..remove('id')..['p_cuotas'] = cuotasJson;
    final response = await _db.rpc('crear_prestamo_con_cuotas', params: params);
    return response as int;
  }

  Future<List<Prestamo>> obtenerPrestamosActivos() async {
    final response = await _db.from('prestamos').select().inFilter('estado', ['ACTIVO', 'MORA']).order('fecha_inicio', ascending: true);
    return response.map((json) => Prestamo.fromMap(json)).toList();
  }

  Future<List<Prestamo>> obtenerTodosLosPrestamos() async {
    final response = await _db.from('prestamos').select().order('fecha_inicio', ascending: false);
    return response.map((json) => Prestamo.fromMap(json)).toList();
  }
  
  Future<Prestamo?> obtenerPrestamoPorId(int id) async {
    final response = await _db.from('prestamos').select().eq('id', id).maybeSingle();
    return response == null ? null : Prestamo.fromMap(response);
  }

  Future<List<Prestamo>> obtenerPrestamosPorCliente(int clienteId) async {
    final response = await _db.from('prestamos').select().eq('cliente_id', clienteId).order('fecha_inicio', ascending: false);
    return response.map((json) => Prestamo.fromMap(json)).toList();
  }

  Future<int> actualizarPrestamo(Prestamo prestamo) async {
    if (prestamo.id == null) return 0;
    final response = await _db.from('prestamos').update(prestamo.toMap()..remove('id')).eq('id', prestamo.id!).select('id');
    return response.length;
  }

  Future<List<Cuota>> obtenerCuotasPorPrestamo(int prestamoId) async {
    final response = await _db.from('cuotas').select().eq('prestamo_id', prestamoId).order('numero_cuota', ascending: true);
    return response.map((json) => Cuota.fromMap(json)).toList();
  }

  Future<List<Cuota>> obtenerTodasLasCuotas() async {
    final response = await _db.from('cuotas').select().order('prestamo_id', ascending: true).order('numero_cuota', ascending: true);
    return response.map((json) => Cuota.fromMap(json)).toList();
  }

  Future<int> actualizarCuota(Cuota cuota) async {
    if (cuota.id == null) return 0;
    final response = await _db.from('cuotas').update(cuota.toMap()..remove('id')).eq('id', cuota.id!).select('id');
    return response.length;
  }
  
  Future<List<Cuota>> obtenerCuotasDelDia(DateTime fecha) async {
     final dateKey = fecha.toIso8601String().substring(0, 10);
     final response = await _db.from('cuotas').select('*, prestamos!inner(estado)')
        .like('fecha_vencimiento', '$dateKey%')
        .neq('estado', 'PAGADA')
        .inFilter('prestamos.estado', ['ACTIVO', 'MORA']);
     return response.map((json) => Cuota.fromMap(json)).toList();
  }
  
  Future<List<Cuota>> obtenerCuotasAtrasadas() async {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final response = await _db.from('cuotas').select('*, prestamos!inner(estado)')
        .lt('fecha_vencimiento', today)
        .neq('estado', 'PAGADA')
        .inFilter('prestamos.estado', ['ACTIVO', 'MORA']);
      return response.map((json) {
        final map = Map<String, Object?>.from(json);
      final dueDate = DateTime.parse(map['fecha_vencimiento'] as String);
        map['estado'] = 'ATRASADA';
        map['dias_atraso'] = DateTime.now().difference(dueDate).inDays;
        return Cuota.fromMap(map);
      }).toList();
  }

  Future<int> registrarPago(Pago pago) async {
    if (pago.monto <= 0) throw ArgumentError.value(pago.monto, 'monto', 'Debe ser mayor que cero.');
    
    final params = {
      'p_cuota_id': pago.cuotaId,
      'p_prestamo_id': pago.prestamoId,
      'p_cliente_id': pago.clienteId,
      'p_monto': pago.monto,
      'p_fecha_hora': pago.fechaHora.toIso8601String(),
      'p_metodo_pago': pago.metodoPago,
      'p_nota': pago.nota,
      'p_registrado_por': pago.registradoPor,
    };

    final response = await _db.rpc('registrar_pago_transaccion', params: params);
    return response as int;
  }

  Future<List<Pago>> obtenerPagosDelDia(DateTime fecha) async {
    final dateKey = fecha.toIso8601String().substring(0, 10);
    final response = await _db.from('pagos').select().like('fecha_hora', '$dateKey%').order('fecha_hora', ascending: false);
    return response.map((json) => Pago.fromMap(json)).toList();
  }

  Future<List<Pago>> obtenerTodosLosPagos() async {
    final response = await _db.from('pagos').select().order('fecha_hora', ascending: false);
    return response.map((json) => Pago.fromMap(json)).toList();
  }

  Future<List<Pago>> obtenerPagosPorPrestamo(int prestamoId) async {
    final response = await _db.from('pagos').select().eq('prestamo_id', prestamoId).order('fecha_hora', ascending: false);
    return response.map((json) => Pago.fromMap(json)).toList();
  }

  Future<Map<String, dynamic>> obtenerResumenDashboard() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final pagosHoy = await _db.from('pagos').select('monto').like('fecha_hora', '$today%');
    final recaudo = pagosHoy.fold<double>(0, (sum, item) => sum + (item['monto'] as num).toDouble());
    
    final prestamos = await _db.from('prestamos').select('saldo_pendiente').inFilter('estado', ['ACTIVO', 'MORA']);
    final totalEnCalle = prestamos.fold<double>(0, (sum, item) => sum + (item['saldo_pendiente'] as num).toDouble());
    
    return {
      'recaudo_hoy': recaudo,
      'total_en_calle': totalEnCalle,
      'ganancia_hoy': 0.0, // Se calcula en el Provider
      'clientes_en_mora': 0,
      'pagos_pendientes_hoy': 0.0,
    };
  }

  Future<Map<String, Object?>?> obtenerConfiguracion() async {
    final response = await _db.from('configuracion').select().limit(1).maybeSingle();
    return response == null ? null : Map<String, Object?>.from(response);
  }

  Future<void> guardarConfiguracion(Map<String, Object?> data) async {
    final payload = Map<String, Object?>.from(data)..remove('id');
    final config = await _db.from('configuracion').select('id').limit(1).maybeSingle();
    if (config == null) {
      await _db.from('configuracion').insert(payload);
    } else {
      await _db.from('configuracion').update(payload).eq('id', config['id']);
    }
  }

  Future<void> guardarHashPin(String? hash) async {
    await guardarConfiguracion({'pin_hash': hash, 'pin_seguridad': null, 'pin_intentos_fallidos': 0, 'pin_bloqueado_hasta': null});
  }

  Future<void> guardarIntentosFallidosPin({required int intentos, DateTime? bloqueadoHasta}) async {
    await guardarConfiguracion({'pin_intentos_fallidos': intentos, 'pin_bloqueado_hasta': bloqueadoHasta?.millisecondsSinceEpoch});
  }
  
  Future<Map<String, Object?>> obtenerEstadisticasPrestamos() async {
    final all = await _db.from('prestamos').select('monto_capital, monto_interes, fecha_inicio');
    final capital = all.fold<double>(0, (sum, item) => sum + (item['monto_capital'] as num).toDouble());
    final interes = all.fold<double>(0, (sum, item) => sum + (item['monto_interes'] as num).toDouble());
    
    final mensuales = <String, Map<String, dynamic>>{};
    for (var p in all) {
      final mes = (p['fecha_inicio'] as String).substring(0, 7);
      mensuales.putIfAbsent(mes, () => {'mes': mes, 'capital': 0.0, 'interes': 0.0, 'prestamos': 0});
      mensuales[mes]!['capital'] += (p['monto_capital'] as num).toDouble();
      mensuales[mes]!['interes'] += (p['monto_interes'] as num).toDouble();
      mensuales[mes]!['prestamos'] += 1;
    }
    
    return {
      'capital_activo': capital,
      'interes_activo': interes,
      'mensuales': mensuales.values.toList()..sort((a, b) => (a['mes'] as String).compareTo(b['mes'] as String)),
    };
  }
  
  Future<String> get databaseFilePath async => 'Supabase PostgreSQL';
  Future<void> close() async {}
}