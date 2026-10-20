import '../../core/constants/db_constants.dart';

class AjustesNegocioValidator {
  AjustesNegocioValidator._();

  static const int maxNombre = 250;
  static const int maxTelefono = 15;
  static const int maxDireccion = 250;
  static const double maxPorcentajeMora = 100;
  static const int maxDiasGracia = 365;

  static void validar(Map<String, Object?> configuracion) {
    final nombre =
        configuracion[DbConstants.configuracionNombreNegocio] as String? ?? '';
    final telefono =
        configuracion[DbConstants.configuracionTelefonoNegocio] as String? ??
        '';
    final direccion =
        configuracion[DbConstants.configuracionDireccionNegocio] as String? ??
        '';
    final porcentaje =
        (configuracion[DbConstants.configuracionPorcentajeMora] as num?)
            ?.toDouble();
    final diasValue =
        configuracion[DbConstants.configuracionDiasGraciaMora] as num?;
    final dias = diasValue?.toInt();

    if (nombre.trim().isEmpty) {
      throw ArgumentError('El nombre del negocio es obligatorio.');
    }
    if (nombre.trim().length > maxNombre) {
      throw ArgumentError(
        'El nombre del negocio no puede superar 250 caracteres.',
      );
    }
    if (telefono.trim().length > maxTelefono) {
      throw ArgumentError('El teléfono no puede superar 15 caracteres.');
    }
    if (direccion.trim().length > maxDireccion) {
      throw ArgumentError('La dirección no puede superar 250 caracteres.');
    }
    if (porcentaje == null ||
        !porcentaje.isFinite ||
        porcentaje < 0 ||
        porcentaje > maxPorcentajeMora) {
      throw ArgumentError('La mora debe estar entre 0 y 100 %.');
    }
    if (dias == null ||
        diasValue! % 1 != 0 ||
        dias < 0 ||
        dias > maxDiasGracia) {
      throw ArgumentError('Los días de gracia deben estar entre 0 y 365.');
    }

    for (final regla in _reglasMora) {
      if (![
        regla.dias,
        regla.tipo,
        regla.valor,
        regla.acumulable,
      ].any(configuracion.containsKey)) {
        continue;
      }
      final diasRegla = configuracion[regla.dias] as num?;
      final tipo = configuracion[regla.tipo] as String?;
      final valor = (configuracion[regla.valor] as num?)?.toDouble();
      final acumulable = configuracion[regla.acumulable] as num?;
      if (diasRegla == null ||
          diasRegla % 1 != 0 ||
          diasRegla < 0 ||
          diasRegla > maxDiasGracia) {
        throw ArgumentError('Los días de gracia deben estar entre 0 y 365.');
      }
      if (tipo != 'PORCENTAJE' && tipo != 'MONTO_FIJO') {
        throw ArgumentError('El tipo de recargo de mora no es válido.');
      }
      if (valor == null ||
          !valor.isFinite ||
          valor < 0 ||
          (tipo == 'PORCENTAJE' && valor > maxPorcentajeMora) ||
          (tipo == 'MONTO_FIJO' && valor > 100000000)) {
        throw ArgumentError('El valor del recargo de mora no es válido.');
      }
      if (acumulable == null || (acumulable != 0 && acumulable != 1)) {
        throw ArgumentError('La opción de acumulación de mora no es válida.');
      }
    }
  }

  static const _reglasMora = [
    (
      dias: DbConstants.configuracionMoraDiariaDiasGracia,
      tipo: DbConstants.configuracionMoraDiariaTipoRecargo,
      valor: DbConstants.configuracionMoraDiariaValorRecargo,
      acumulable: DbConstants.configuracionMoraDiariaRecargoAcumulable,
    ),
    (
      dias: DbConstants.configuracionMoraSemanalDiasGracia,
      tipo: DbConstants.configuracionMoraSemanalTipoRecargo,
      valor: DbConstants.configuracionMoraSemanalValorRecargo,
      acumulable: DbConstants.configuracionMoraSemanalRecargoAcumulable,
    ),
    (
      dias: DbConstants.configuracionMoraQuincenalDiasGracia,
      tipo: DbConstants.configuracionMoraQuincenalTipoRecargo,
      valor: DbConstants.configuracionMoraQuincenalValorRecargo,
      acumulable: DbConstants.configuracionMoraQuincenalRecargoAcumulable,
    ),
    (
      dias: DbConstants.configuracionMoraMensualDiasGracia,
      tipo: DbConstants.configuracionMoraMensualTipoRecargo,
      valor: DbConstants.configuracionMoraMensualValorRecargo,
      acumulable: DbConstants.configuracionMoraMensualRecargoAcumulable,
    ),
  ];
}
