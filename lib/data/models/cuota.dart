import '../../core/constants/db_constants.dart';

class Cuota {
  const Cuota({
    this.id,
    required this.prestamoId,
    required this.numeroCuota,
    required this.fechaVencimiento,
    required this.montoCuota,
    this.montoPagado = 0,
    this.fechaPago,
    this.estado = 'PENDIENTE',
    this.diasAtraso = 0,
    this.esPenalizacion = false,
    this.montoPenalizacion = 0,
  });

  final int? id;
  final int prestamoId;
  final int numeroCuota;
  final DateTime fechaVencimiento;
  final double montoCuota;
  final double montoPagado;
  final DateTime? fechaPago;
  final String estado;
  final int diasAtraso;
  final bool esPenalizacion;
  final double montoPenalizacion;

  Map<String, Object?> toMap() => {
    DbConstants.columnId: id,
    DbConstants.cuotaPrestamoId: prestamoId,
    DbConstants.cuotaNumero: numeroCuota,
    DbConstants.cuotaFechaVencimiento: fechaVencimiento.toIso8601String(),
    DbConstants.cuotaMonto: montoCuota,
    DbConstants.cuotaMontoPagado: montoPagado,
    DbConstants.cuotaFechaPago: fechaPago?.toIso8601String(),
    DbConstants.cuotaEstado: estado,
    DbConstants.cuotaDiasAtraso: diasAtraso,
    DbConstants.cuotaEsPenalizacion: esPenalizacion ? 1 : 0,
    DbConstants.cuotaMontoPenalizacion: montoPenalizacion,
  };

  factory Cuota.fromMap(Map<String, Object?> map) => Cuota(
    id: (map[DbConstants.columnId] as num?)?.toInt(),
    prestamoId: (map[DbConstants.cuotaPrestamoId] as num).toInt(),
    numeroCuota: (map[DbConstants.cuotaNumero] as num).toInt(),
    fechaVencimiento: DateTime.parse(
      map[DbConstants.cuotaFechaVencimiento] as String,
    ),
    montoCuota: (map[DbConstants.cuotaMonto] as num).toDouble(),
    montoPagado: (map[DbConstants.cuotaMontoPagado] as num?)?.toDouble() ?? 0,
    fechaPago: map[DbConstants.cuotaFechaPago] == null
        ? null
        : DateTime.parse(map[DbConstants.cuotaFechaPago] as String),
    estado: map[DbConstants.cuotaEstado] as String,
    diasAtraso: (map[DbConstants.cuotaDiasAtraso] as num?)?.toInt() ?? 0,
    esPenalizacion:
        ((map[DbConstants.cuotaEsPenalizacion] as num?)?.toInt() ?? 0) != 0,
    montoPenalizacion:
        (map[DbConstants.cuotaMontoPenalizacion] as num?)?.toDouble() ?? 0,
  );

  Cuota copyWith({
    int? id,
    int? prestamoId,
    int? numeroCuota,
    DateTime? fechaVencimiento,
    double? montoCuota,
    double? montoPagado,
    DateTime? fechaPago,
    String? estado,
    int? diasAtraso,
    bool? esPenalizacion,
    double? montoPenalizacion,
  }) => Cuota(
    id: id ?? this.id,
    prestamoId: prestamoId ?? this.prestamoId,
    numeroCuota: numeroCuota ?? this.numeroCuota,
    fechaVencimiento: fechaVencimiento ?? this.fechaVencimiento,
    montoCuota: montoCuota ?? this.montoCuota,
    montoPagado: montoPagado ?? this.montoPagado,
    fechaPago: fechaPago ?? this.fechaPago,
    estado: estado ?? this.estado,
    diasAtraso: diasAtraso ?? this.diasAtraso,
    esPenalizacion: esPenalizacion ?? this.esPenalizacion,
    montoPenalizacion: montoPenalizacion ?? this.montoPenalizacion,
  );
}
