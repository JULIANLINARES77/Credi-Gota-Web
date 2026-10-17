class MonedaColombiana {
  MonedaColombiana._();

  static const int unidadNegociacion = 1000;

  static bool esMultiploDeUnidad(double valor) {
    if (!valor.isFinite) return false;
    final unidades = valor / unidadNegociacion;
    return (unidades - unidades.round()).abs() < 0.000000001;
  }

  static double redondearAUnidad(double valor) =>
      (valor / unidadNegociacion).roundToDouble() * unidadNegociacion;
}
