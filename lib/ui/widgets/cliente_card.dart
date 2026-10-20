import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/cliente.dart';
import '../../logic/services/google_maps_service.dart';

class ClienteCard extends StatelessWidget {
  const ClienteCard({
    super.key,
    required this.cliente,
    required this.saldoPendiente,
    required this.estado,
    this.diasAtraso,
    this.proximoPago,
    this.onTap,
    this.onLlamar,
    this.onWhatsApp,
    this.onEditar,
    this.onBuscarMaps,
    this.onEliminar,
    this.cantidadPrestamosActivos,
  });

  final Cliente cliente;
  final double saldoPendiente;
  final String estado;
  final int? diasAtraso;
  final DateTime? proximoPago;
  final VoidCallback? onTap;
  final VoidCallback? onLlamar;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onEditar;
  final VoidCallback? onBuscarMaps;
  final VoidCallback? onEliminar;
  final int? cantidadPrestamosActivos;

  Color get _estadoColor => switch (estado) {
    'MORA' => AppColors.error,
    'PENDIENTE' => AppColors.warning,
    _ => AppColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: _estadoColor.withValues(alpha: 0.16),
                    child: Text(
                      _iniciales(cliente.nombre),
                      style: TextStyle(
                        color: _estadoColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          cliente.telefono,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        if (cliente.cedula?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            'C.C. ${cliente.cedula}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _EstadoBadge(
                              text: diasAtraso != null && diasAtraso! > 0
                                  ? 'Mora · ${diasAtraso}d'
                                  : estado,
                              color: _estadoColor,
                            ),
                            if (proximoPago != null)
                              Text(
                                'Próximo ${GotaDateUtils.formatearFecha(proximoPago!)}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            if (cantidadPrestamosActivos != null)
                              Text(
                                '$cantidadPrestamosActivos ${cantidadPrestamosActivos == 1 ? 'préstamo activo' : 'préstamos activos'}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        GotaDateUtils.formatearMoneda(saldoPendiente),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Llamar',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                onLlamar ?? () => _llamar(cliente.telefono),
                            icon: const Icon(Icons.call_outlined, size: 19),
                          ),
                          IconButton(
                            tooltip: 'WhatsApp',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                onWhatsApp ?? () => _whatsapp(cliente.telefono),
                            icon: const Icon(Icons.chat_outlined, size: 19),
                          ),
                          if (onEliminar != null)
                            IconButton(
                              tooltip: 'Eliminar cliente',
                              visualDensity: VisualDensity.compact,
                              onPressed: onEliminar,
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 19,
                                color: AppColors.error,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              if (cliente.direccion?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Dirección: ${cliente.direccion}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              if (onEditar != null || onBuscarMaps != null) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 0,
                  children: [
                    if (onEditar != null)
                      TextButton.icon(
                        onPressed: onEditar,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Modificar'),
                      ),
                    if (onBuscarMaps != null)
                      TextButton.icon(
                        onPressed: onBuscarMaps,
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('Buscar en Google Maps'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _iniciales(String nombre) => nombre
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((parte) => parte.isEmpty ? '' : parte[0].toUpperCase())
      .join();

  static Future<void> _llamar(String telefono) async {
    await launchUrl(
      Uri(scheme: 'tel', path: telefono.replaceAll(RegExp(r'\s+'), '')),
    );
  }

  static Future<void> _whatsapp(String telefono) async {
    final numero = telefono.replaceAll(RegExp(r'\D'), '');
    final numeroColombiano = numero.startsWith('57') ? numero : '57$numero';
    await launchUrl(
      Uri.parse('https://wa.me/$numeroColombiano'),
      mode: LaunchMode.externalApplication,
    );
  }

  static Future<void> abrirMaps(
    BuildContext context,
    String direccion,
  ) async {
    try {
      await GoogleMapsService.abrirBusqueda(direccion: direccion);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }
}

class _EstadoBadge extends StatelessWidget {
  const _EstadoBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}
