import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/date_utils.dart';
import '../../../data/models/cliente.dart';
import '../../../logic/providers/gota_provider.dart';
import '../../../logic/services/calculadora_service.dart';

class PdfGenerator {
  PdfGenerator._();

  static const _verde = PdfColor.fromInt(0xFF087A42);
  static const _gris = PdfColor.fromInt(0xFF60646C);
  static final _calculadora = const CalculadoraService();
  static final Future<pw.ThemeData> _temaPdf = _cargarTemaPdf();

  static Future<pw.ThemeData> _cargarTemaPdf() async {
    final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    return pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
  }

  static Future<Uint8List> reporteDiario(GotaProvider demo, DateTime fecha) {
    final pagos = demo.pagos
        .where((pago) => _mismaFecha(pago.fechaHora, fecha))
        .toList();
    final ganancia = pagos.fold(0.0, (total, pago) {
      final prestamo = demo.prestamoPorId(pago.prestamoId);
      if (prestamo == null ||
          _esPenalizacion(demo, pago.prestamoId, pago.cuotaId)) {
        return total;
      }
      return total +
          _calculadora.calcularGananciaProporcional(
            montoPagado: pago.monto,
            totalPagar: prestamo.montoTotalPagar,
            interesTotal: prestamo.montoInteres,
          );
    });
    final capitalRecuperado = pagos.fold(0.0, (total, pago) {
      final prestamo = demo.prestamoPorId(pago.prestamoId);
      if (prestamo == null ||
          _esPenalizacion(demo, pago.prestamoId, pago.cuotaId)) {
        return total;
      }
      return total +
          _calculadora.calcularCapitalRecuperado(
            montoPagado: pago.monto,
            totalPagar: prestamo.montoTotalPagar,
            capital: prestamo.montoCapital,
          );
    });
    final moras = demo.moras;
    final manana = DateTime(fecha.year, fecha.month, fecha.day + 1);
    final proximos = demo.todasLasCuotas.where(
      (cuota) =>
          cuota.estado != 'PAGADA' &&
          _mismaFecha(cuota.fechaVencimiento, manana),
    );

    return _documento('Reporte diario', fecha, [
      _resumen([
        (
          'Recaudo total',
          _pesos(pagos.fold(0.0, (total, pago) => total + pago.monto)),
        ),
        ('Ganancia en interés', _pesos(ganancia)),
        ('Capital recuperado', _pesos(capitalRecuperado)),
        ('Pagos registrados', '${pagos.length}'),
      ]),
      _titulo('Pagos recibidos'),
      _tabla(
        ['Cliente', 'Monto', 'Hora', 'Método'],
        pagos
            .map(
              (pago) => [
                demo.clientePorId(pago.clienteId)?.nombre ?? 'Cliente',
                _pesos(pago.monto),
                '${pago.fechaHora.hour.toString().padLeft(2, '0')}:${pago.fechaHora.minute.toString().padLeft(2, '0')}',
                pago.metodoPago ?? 'Sin método',
              ],
            )
            .toList(),
      ),
      _titulo('Clientes en mora'),
      _tabla(
        ['Cliente', 'Teléfono', 'Días', 'Saldo'],
        moras
            .map(
              (mora) => [
                mora.cliente.nombre,
                mora.cliente.telefono,
                '${mora.diasAtraso}',
                _pesos(mora.prestamo.saldoPendiente),
              ],
            )
            .toList(),
      ),
      _titulo('Vencimientos de mañana'),
      _tabla(
        ['Cliente', 'Cuota', 'Valor'],
        proximos.map((cuota) {
          final prestamo = demo.prestamoPorId(cuota.prestamoId);
          final cliente = prestamo == null
              ? null
              : demo.clientePorId(prestamo.clienteId);
          return [
            cliente?.nombre ?? 'Cliente no disponible',
            '${cuota.numeroCuota}',
            _pesos(cuota.montoCuota - cuota.montoPagado),
          ];
        }).toList(),
      ),
    ]);
  }

  static Future<Uint8List> estadoCuenta(GotaProvider demo, Cliente cliente) {
    final prestamos = demo.prestamosDeCliente(cliente.id!);
    final widgets = <pw.Widget>[
      _resumen([
        ('Cliente', cliente.nombre),
        ('Cédula', cliente.cedula ?? 'No registrada'),
        ('Teléfono', cliente.telefono),
      ]),
    ];
    for (final prestamo in prestamos) {
      widgets.addAll([
        _titulo('Préstamo ${prestamo.id}'),
        _resumen([
          ('Capital', _pesos(prestamo.montoCapital)),
          ('Interés', _pesos(prestamo.montoInteres)),
          ('Total', _pesos(prestamo.montoTotalPagar)),
          ('Saldo', _pesos(prestamo.saldoPendiente)),
          (
            'Próxima fecha',
            GotaDateUtils.formatearFecha(prestamo.fechaFinEstimada),
          ),
        ]),
        _tabla(
          ['#', 'Vencimiento', 'Valor', 'Pagado', 'Estado'],
          demo
              .cuotasDePrestamo(prestamo.id!)
              .map(
                (cuota) => [
                  '${cuota.numeroCuota}',
                  GotaDateUtils.formatearFecha(cuota.fechaVencimiento),
                  _pesos(cuota.montoCuota),
                  _pesos(cuota.montoPagado),
                  cuota.estado,
                ],
              )
              .toList(),
        ),
      ]);
    }
    if (prestamos.isEmpty) {
      widgets.add(_texto('Este cliente aún no tiene préstamos.'));
    }
    return _documento('Estado de cuenta', DateTime.now(), widgets);
  }

  static Future<Uint8List> reporteMora(GotaProvider demo, DateTime fecha) =>
      _documento('Reporte de mora', fecha, [
        _resumen([
          ('Préstamos atrasados', '${demo.moras.length}'),
          (
            'Saldo total en mora',
            _pesos(
              demo.moras.fold(
                0.0,
                (total, mora) => total + mora.prestamo.saldoPendiente,
              ),
            ),
          ),
        ]),
        _tabla(
          ['Cliente', 'Teléfono', 'Días de atraso', 'Cuotas vencidas', 'Saldo'],
          demo.moras
              .map(
                (mora) => [
                  mora.cliente.nombre,
                  mora.cliente.telefono,
                  '${mora.diasAtraso}',
                  '${mora.cuotas.length}',
                  _pesos(mora.prestamo.saldoPendiente),
                ],
              )
              .toList(),
        ),
      ]);

  static Future<Uint8List> reporteEstadisticas(GotaProvider demo) async {
    final estadisticas = await demo.obtenerEstadisticasPrestamos();
    final meses = (estadisticas['mensuales'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    return _documento('Estadísticas del Negocio', DateTime.now(), [
      _resumen([
        (
          'Capital total prestado activo',
          _pesos((estadisticas['capital_activo'] as num?)?.toDouble() ?? 0),
        ),
        (
          'Interés total esperado activo',
          _pesos((estadisticas['interes_activo'] as num?)?.toDouble() ?? 0),
        ),
        ('Meses registrados', '${meses.length}'),
      ]),
      _titulo('Comparativa mensual de préstamos originados'),
      if (meses.isEmpty)
        _texto('No hay préstamos registrados para comparar.')
      else
        _tabla(
          ['Mes', 'Préstamos', 'Capital prestado', 'Interés esperado'],
          meses
              .map(
                (mes) => [
                  _nombreMes(mes['mes'] as String? ?? ''),
                  '${(mes['prestamos'] as num?)?.toInt() ?? 0}',
                  _pesos((mes['capital'] as num?)?.toDouble() ?? 0),
                  _pesos((mes['interes'] as num?)?.toDouble() ?? 0),
                ],
              )
              .toList(),
        ),
      _texto(
        'La comparativa agrupa los préstamos por su fecha de inicio e incluye '
        'el capital y el interés pactado, no los pagos recaudados.',
      ),
    ]);
  }

  static Future<Uint8List> reporteSemanal(GotaProvider demo, DateTime fecha) {
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    final inicio = dia.subtract(Duration(days: dia.weekday - DateTime.monday));
    final fin = inicio.add(const Duration(days: 7));
    final pagos = demo.pagos
        .where(
          (pago) =>
              !pago.fechaHora.isBefore(inicio) && pago.fechaHora.isBefore(fin),
        )
        .toList();
    final total = pagos.fold(0.0, (suma, pago) => suma + pago.monto);
    final ganancia = pagos.fold(0.0, (suma, pago) {
      final prestamo = demo.prestamoPorId(pago.prestamoId);
      if (prestamo == null ||
          _esPenalizacion(demo, pago.prestamoId, pago.cuotaId)) {
        return suma;
      }
      return suma +
          _calculadora.calcularGananciaProporcional(
            montoPagado: pago.monto,
            totalPagar: prestamo.montoTotalPagar,
            interesTotal: prestamo.montoInteres,
          );
    });
    return _documento('Reporte semanal', fecha, [
      _resumen([
        (
          'Periodo',
          '${GotaDateUtils.formatearFecha(inicio)} - ${GotaDateUtils.formatearFecha(fin.subtract(const Duration(days: 1)))}',
        ),
        ('Recaudo semanal', _pesos(total)),
        ('Ganancia en interés', _pesos(ganancia)),
        ('Pagos registrados', '${pagos.length}'),
      ]),
      _tabla(
        ['Fecha', 'Cliente', 'Monto', 'Método'],
        pagos
            .map(
              (pago) => [
                GotaDateUtils.formatearFecha(pago.fechaHora),
                demo.clientePorId(pago.clienteId)?.nombre ?? 'Cliente',
                _pesos(pago.monto),
                pago.metodoPago ?? 'Sin método',
              ],
            )
            .toList(),
      ),
    ]);
  }

  static Future<Uint8List> reporteMensual(GotaProvider demo, DateTime fecha) {
    final inicio = DateTime(fecha.year, fecha.month, 1);
    final fin = DateTime(fecha.year, fecha.month + 1, 1);
    final pagos = demo.pagos
        .where(
          (pago) =>
              !pago.fechaHora.isBefore(inicio) && pago.fechaHora.isBefore(fin),
        )
        .toList();
    final dias = DateTime(fecha.year, fecha.month + 1, 0).day;
    final recaudoPorDia = List<double>.generate(
      dias,
      (indice) => pagos
          .where((pago) => pago.fechaHora.day == indice + 1)
          .fold(0.0, (total, pago) => total + pago.monto),
    );
    final maximo = recaudoPorDia.fold(0.0, (a, b) => a > b ? a : b);
    final ganancia = pagos.fold(0.0, (total, pago) {
      final prestamo = demo.prestamoPorId(pago.prestamoId);
      if (prestamo == null ||
          _esPenalizacion(demo, pago.prestamoId, pago.cuotaId)) {
        return total;
      }
      return total +
          _calculadora.calcularGananciaProporcional(
            montoPagado: pago.monto,
            totalPagar: prestamo.montoTotalPagar,
            interesTotal: prestamo.montoInteres,
          );
    });
    return _documento('Reporte mensual', fecha, [
      _resumen([
        (
          'Recaudo del mes',
          _pesos(pagos.fold(0.0, (total, pago) => total + pago.monto)),
        ),
        ('Ganancia del mes', _pesos(ganancia)),
        ('Pagos recibidos', '${pagos.length}'),
      ]),
      _titulo('Recaudo por día'),
      pw.Wrap(
        spacing: 3,
        runSpacing: 7,
        children: [
          for (var indice = 0; indice < recaudoPorDia.length; indice++)
            pw.Container(
              width: 15,
              height: 100,
              alignment: pw.Alignment.bottomCenter,
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 9,
                    height: maximo == 0
                        ? 2
                        : (recaudoPorDia[indice] / maximo * 72)
                              .clamp(2, 72)
                              .toDouble(),
                    color: recaudoPorDia[indice] > 0
                        ? _verde
                        : PdfColors.grey300,
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '${indice + 1}',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ],
              ),
            ),
        ],
      ),
      _titulo('Pagos del mes'),
      _tabla(
        ['Fecha', 'Cliente', 'Monto', 'Método'],
        pagos
            .map(
              (pago) => [
                GotaDateUtils.formatearFecha(pago.fechaHora),
                demo.clientePorId(pago.clienteId)?.nombre ?? 'Cliente',
                _pesos(pago.monto),
                pago.metodoPago ?? 'Sin método',
              ],
            )
            .toList(),
      ),
    ]);
  }

  static Future<Uint8List> respaldoCompleto(GotaProvider provider) {
    final clientesPorId = {
      for (final cliente in provider.clientesRegistrados)
        if (cliente.id != null) cliente.id!: cliente,
    };
    final filasPrestamos = provider.prestamos
        .map(
          (prestamo) => [
            '${prestamo.id ?? ''}',
            clientesPorId[prestamo.clienteId]?.nombre ?? 'Cliente eliminado',
            _pesos(prestamo.montoCapital),
            _pesos(prestamo.saldoPendiente),
            prestamo.estado,
          ],
        )
        .toList();
    final filasCuotas = provider.todasLasCuotas
        .map(
          (cuota) => [
            '${cuota.prestamoId}',
            '${cuota.numeroCuota}',
            GotaDateUtils.formatearFecha(cuota.fechaVencimiento),
            _pesos(cuota.montoCuota),
            _pesos(cuota.montoPagado),
            cuota.estado,
          ],
        )
        .toList();
    final filasPagos = provider.pagos
        .map(
          (pago) => [
            '${pago.id ?? ''}',
            clientesPorId[pago.clienteId]?.nombre ?? 'Cliente eliminado',
            '${pago.prestamoId}',
            _pesos(pago.monto),
            GotaDateUtils.formatearFechaHora(pago.fechaHora),
            pago.metodoPago ?? 'Sin método',
          ],
        )
        .toList();

    return _documento('Respaldo completo de datos', DateTime.now(), [
      _resumen([
        ('Clientes', '${provider.clientesRegistrados.length}'),
        ('Préstamos', '${provider.prestamos.length}'),
        ('Cuotas', '${provider.todasLasCuotas.length}'),
        ('Pagos', '${provider.pagos.length}'),
      ]),
      _titulo('Clientes'),
      _tabla(
        ['ID', 'Nombre', 'Cédula', 'Teléfono', 'Dirección'],
        provider.clientesRegistrados
            .map(
              (cliente) => [
                '${cliente.id ?? ''}',
                cliente.nombre,
                cliente.cedula ?? '',
                cliente.telefono,
                cliente.direccion ?? '',
              ],
            )
            .toList(),
      ),
      _titulo('Préstamos'),
      _tabla(['ID', 'Cliente', 'Capital', 'Saldo', 'Estado'], filasPrestamos),
      _titulo('Cuotas'),
      _tabla([
        'Préstamo',
        'N.º',
        'Vencimiento',
        'Valor',
        'Pagado',
        'Estado',
      ], filasCuotas),
      _titulo('Pagos'),
      _tabla([
        'ID',
        'Cliente',
        'Préstamo',
        'Monto',
        'Fecha',
        'Método',
      ], filasPagos),
    ]);
  }

  static Future<void> imprimir(Uint8List bytes) => Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'GotaControl-reporte.pdf',
  );

  static Future<void> compartir(
    Uint8List bytes, {
    String nombre = 'GotaControl-reporte.pdf',
  }) => SharePlus.instance.share(
    ShareParams(
      title: 'Reporte GotaControl',
      subject: 'Reporte de préstamos',
      files: [XFile.fromData(bytes, name: nombre, mimeType: 'application/pdf')],
    ),
  );

  static Future<Uint8List> _documento(
    String titulo,
    DateTime fecha,
    List<pw.Widget> contenido,
  ) async {
    final documento = pw.Document(theme: await _temaPdf);
    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            'GotaControl · ${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 8, color: _gris),
          ),
        ),
        build: (_) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'GotaControl',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: _verde,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                GotaDateUtils.formatearFechaHora(DateTime.now()),
                style: const pw.TextStyle(fontSize: 8, color: _gris),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            titulo,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            GotaDateUtils.formatearFecha(fecha),
            style: const pw.TextStyle(fontSize: 10, color: _gris),
          ),
          pw.SizedBox(height: 18),
          ...contenido,
        ],
      ),
    );
    return documento.save();
  }

  static pw.Widget _resumen(List<(String, String)> datos) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    margin: const pw.EdgeInsets.only(bottom: 14),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Column(
      children: [
        for (final dato in datos)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  dato.$1,
                  style: const pw.TextStyle(fontSize: 9, color: _gris),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Text(
                    dato.$2,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  static pw.Widget _titulo(String texto) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 7),
    child: pw.Text(
      texto,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _tabla(List<String> encabezados, List<List<String>> filas) {
    if (filas.isEmpty) return _texto('Sin registros para este periodo.');
    return pw.TableHelper.fromTextArray(
      headers: encabezados,
      data: filas,
      headerDecoration: const pw.BoxDecoration(color: _verde),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    );
  }

  static pw.Widget _texto(String texto) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Text(texto, style: const pw.TextStyle(fontSize: 9, color: _gris)),
  );

  static String _pesos(double valor) => GotaDateUtils.formatearMoneda(valor);

  static String _nombreMes(String mes) {
    final partes = mes.split('-');
    if (partes.length != 2) return mes;
    final anio = int.tryParse(partes[0]);
    final numeroMes = int.tryParse(partes[1]);
    if (anio == null || numeroMes == null || numeroMes < 1 || numeroMes > 12) {
      return mes;
    }
    const nombres = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${nombres[numeroMes - 1]} $anio';
  }

  static bool _mismaFecha(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _esPenalizacion(GotaProvider demo, int prestamoId, int cuotaId) =>
      demo
          .cuotasDePrestamo(prestamoId)
          .any((cuota) => cuota.id == cuotaId && cuota.esPenalizacion);
}
