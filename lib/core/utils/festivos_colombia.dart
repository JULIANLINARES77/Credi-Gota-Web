class FestivosColombia {
  FestivosColombia._();

  static final Map<int, Set<DateTime>> _festivosPorAnio = {};

  static bool esFestivo(DateTime fecha) => _festivosPorAnio
      .putIfAbsent(fecha.year, () => _crearFestivos(fecha.year))
      .contains(_soloFecha(fecha));

  static Set<DateTime> _crearFestivos(int anio) {
    final festivos = <DateTime>{
      DateTime(anio, 1, 1),
      DateTime(anio, 5, 1),
      DateTime(anio, 7, 20),
      DateTime(anio, 8, 7),
      DateTime(anio, 12, 8),
      DateTime(anio, 12, 25),
      _trasladarALunes(DateTime(anio, 1, 6)),
      _trasladarALunes(DateTime(anio, 3, 19)),
      _trasladarALunes(DateTime(anio, 6, 29)),
      _trasladarALunes(DateTime(anio, 8, 15)),
      _trasladarALunes(DateTime(anio, 10, 12)),
      _trasladarALunes(DateTime(anio, 11, 1)),
      _trasladarALunes(DateTime(anio, 11, 11)),
    };
    final pascua = _domingoPascua(anio);
    festivos
      ..add(_sumarDias(pascua, -3))
      ..add(_sumarDias(pascua, -2))
      ..add(_trasladarALunes(_sumarDias(pascua, 39)))
      ..add(_trasladarALunes(_sumarDias(pascua, 60)))
      ..add(_trasladarALunes(_sumarDias(pascua, 68)));
    return festivos;
  }

  static DateTime _domingoPascua(int anio) {
    final a = anio % 19;
    final b = anio ~/ 100;
    final c = anio % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final mes = (h + l - 7 * m + 114) ~/ 31;
    final dia = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(anio, mes, dia);
  }

  static DateTime _trasladarALunes(DateTime fecha) {
    final diasHastaLunes = (DateTime.monday - fecha.weekday) % 7;
    return _sumarDias(fecha, diasHastaLunes);
  }

  static DateTime _sumarDias(DateTime fecha, int dias) =>
      DateTime(fecha.year, fecha.month, fecha.day + dias);

  static DateTime _soloFecha(DateTime fecha) =>
      DateTime(fecha.year, fecha.month, fecha.day);
}
