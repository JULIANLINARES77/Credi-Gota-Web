import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_prestamos/logic/services/google_maps_service.dart';

void main() {
  test('builds a Google Maps search URL with the optional address', () {
    final uri = GoogleMapsService.construirUriBusqueda(
      direccion: 'Calle 10 # 20-30, Bogotá',
    );

    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/search/');
    expect(uri.queryParameters, {
      'api': '1',
      'query': 'Calle 10 # 20-30, Bogotá',
    });
  });

  test('opens a generic Google Maps search when address is empty', () {
    final uri = GoogleMapsService.construirUriBusqueda(direccion: '  ');

    expect(uri.queryParameters, {'api': '1'});
  });
}
