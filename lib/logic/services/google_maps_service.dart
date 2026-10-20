import 'package:url_launcher/url_launcher.dart';

class GoogleMapsService {
  GoogleMapsService._();

  static Uri construirUriBusqueda({String? direccion}) {
    final consulta = direccion?.trim();
    return Uri.https(
      'www.google.com',
      '/maps/search/',
      {
        'api': '1',
        if (consulta != null && consulta.isNotEmpty) 'query': consulta,
      },
    );
  }

  static Future<void> abrirBusqueda({String? direccion}) async {
    final uri = construirUriBusqueda(direccion: direccion);
    final abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!abierto) {
      throw StateError('No se pudo abrir Google Maps en este dispositivo.');
    }
  }
}
