import '../../core/constants/db_constants.dart';

class Prestamo {
  const Prestamo({
    this.id,
    required this.clienteId,
    required this.montoCapital,
    required this.porcentajeInteres,
    required this.montoInteres,
    required this.montoTotalPagar,
    required this.numCuotas,
    required this.valorCuota,
    required this.frecuencia,
    this.diasPersonalizados,
    this.diasCorridos = false,
    this.diasGraciaMora = 3,
    this.tipoRecargoMora = 'PORCENTAJE',
    this.valorRecargoMora = 10,
    this.recargoAcumulable = false,
    required this.fechaInicio,
    required this.fechaFinEstimada,
    this.estado = 'ACTIVO',
    required this.saldoPendiente,
    this.totalPagado = 0,
    required this.createdAt,
  });

  final int? id;
  final int clienteId;
  final double montoCapital;
  final double porcentajeInteres;
  final double montoInteres;
  final double montoTotalPagar;
  final int numCuotas;
  final double valorCuota;
  final String frecuencia;
  final String? diasPersonalizados;
  final bool diasCorridos;
  final int diasGraciaMora;
  final String tipoRecargoMora;
  final double valorRecargoMora;
  final bool recargoAcumulable;
  final DateTime fechaInicio;
  final DateTime fechaFinEstimada;
  final String estado;
  final double saldoPendiente;
  final double totalPagado;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    DbConstants.columnId: id,
    DbConstants.prestamoClienteId: clienteId,
    DbConstants.prestamoMontoCapital: montoCapital,
    DbConstants.prestamoPorcentajeInteres: porcentajeInteres,
    DbConstants.prestamoMontoInteres: montoInteres,
    DbConstants.prestamoMontoTotalPagar: montoTotalPagar,
    DbConstants.prestamoNumCuotas: numCuotas,
    DbConstants.prestamoValorCuota: valorCuota,
    DbConstants.prestamoFrecuencia: frecuencia,
    DbConstants.prestamoDiasPersonalizados: diasPersonalizados,
    DbConstants.prestamoDiasCorridos: diasCorridos ? 1 : 0,
    DbConstants.prestamoDiasGraciaMora: diasGraciaMora,
    DbConstants.prestamoTipoRecargoMora: tipoRecargoMora,
    DbConstants.prestamoValorRecargoMora: valorRecargoMora,
    DbConstants.prestamoRecargoAcumulable: recargoAcumulable ? 1 : 0,
    DbConstants.prestamoFechaInicio: fechaInicio.toIso8601String(),
    DbConstants.prestamoFechaFinEstimada: fechaFinEstimada.toIso8601String(),
    DbConstants.prestamoEstado: estado,
    DbConstants.prestamoSaldoPendiente: saldoPendiente,
    DbConstants.prestamoTotalPagado: totalPagado,
    DbConstants.prestamoCreatedAt: createdAt.toIso8601String(),
  };

  factory Prestamo.fromMap(Map<String, Object?> map) => Prestamo(
    id: (map[DbConstants.columnId] as num?)?.toInt(),
    clienteId: (map[DbConstants.prestamoClienteId] as num).toInt(),
    montoCapital: (map[DbConstants.prestamoMontoCapital] as num).toDouble(),
    porcentajeInteres: (map[DbConstants.prestamoPorcentajeInteres] as num)
        .toDouble(),
    montoInteres: (map[DbConstants.prestamoMontoInteres] as num).toDouble(),
    montoTotalPagar: (map[DbConstants.prestamoMontoTotalPagar] as num)
        .toDouble(),
    numCuotas: (map[DbConstants.prestamoNumCuotas] as num).toInt(),
    valorCuota: (map[DbConstants.prestamoValorCuota] as num).toDouble(),
    frecuencia: map[DbConstants.prestamoFrecuencia] as String,
    diasPersonalizados: map[DbConstants.prestamoDiasPersonalizados] as String?,
    diasCorridos:
        ((map[DbConstants.prestamoDiasCorridos] as num?)?.toInt() ?? 0) != 0,
    diasGraciaMora:
        (map[DbConstants.prestamoDiasGraciaMora] as num?)?.toInt() ?? 3,
    tipoRecargoMora:
        map[DbConstants.prestamoTipoRecargoMora] as String? ?? 'PORCENTAJE',
    valorRecargoMora:
        (map[DbConstants.prestamoValorRecargoMora] as num?)?.toDouble() ?? 10,
    recargoAcumulable:
        ((map[DbConstants.prestamoRecargoAcumulable] as num?)?.toInt() ?? 0) !=
        0,
    fechaInicio: DateTime.parse(map[DbConstants.prestamoFechaInicio] as String),
    fechaFinEstimada: DateTime.parse(
      map[DbConstants.prestamoFechaFinEstimada] as String,
    ),
    estado: map[DbConstants.prestamoEstado] as String,
    saldoPendiente: (map[DbConstants.prestamoSaldoPendiente] as num).toDouble(),
    totalPagado:
        (map[DbConstants.prestamoTotalPagado] as num?)?.toDouble() ?? 0,
    createdAt: DateTime.parse(map[DbConstants.prestamoCreatedAt] as String),
  );

  Prestamo copyWith({
    int? id,
    int? clienteId,
    double? montoCapital,
    double? porcentajeInteres,
    double? montoInteres,
    double? montoTotalPagar,
    int? numCuotas,
    double? valorCuota,
    String? frecuencia,
    String? diasPersonalizados,
    bool? diasCorridos,
    int? diasGraciaMora,
    String? tipoRecargoMora,
    double? valorRecargoMora,
    bool? recargoAcumulable,
    DateTime? fechaInicio,
    DateTime? fechaFinEstimada,
    String? estado,
    double? saldoPendiente,
    double? totalPagado,
    DateTime? createdAt,
  }) => Prestamo(
    id: id ?? this.id,
    clienteId: clienteId ?? this.clienteId,
    montoCapital: montoCapital ?? this.montoCapital,
    porcentajeInteres: porcentajeInteres ?? this.porcentajeInteres,
    montoInteres: montoInteres ?? this.montoInteres,
    montoTotalPagar: montoTotalPagar ?? this.montoTotalPagar,
    numCuotas: numCuotas ?? this.numCuotas,
    valorCuota: valorCuota ?? this.valorCuota,
    frecuencia: frecuencia ?? this.frecuencia,
    diasPersonalizados: diasPersonalizados ?? this.diasPersonalizados,
    diasCorridos: diasCorridos ?? this.diasCorridos,
    diasGraciaMora: diasGraciaMora ?? this.diasGraciaMora,
    tipoRecargoMora: tipoRecargoMora ?? this.tipoRecargoMora,
    valorRecargoMora: valorRecargoMora ?? this.valorRecargoMora,
    recargoAcumulable: recargoAcumulable ?? this.recargoAcumulable,
    fechaInicio: fechaInicio ?? this.fechaInicio,
    fechaFinEstimada: fechaFinEstimada ?? this.fechaFinEstimada,
    estado: estado ?? this.estado,
    saldoPendiente: saldoPendiente ?? this.saldoPendiente,
    totalPagado: totalPagado ?? this.totalPagado,
    createdAt: createdAt ?? this.createdAt,
  );
}
