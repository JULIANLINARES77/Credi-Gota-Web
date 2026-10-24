import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/cuota.dart';

class CuotaRow extends StatelessWidget {
  const CuotaRow({
    super.key,
    required this.cuota,
    required this.onPagar,
    this.diasAtraso = 0,
  });

  final Cuota cuota;
  final VoidCallback onPagar;
  final int diasAtraso;

  @override
  Widget build(BuildContext context) {
    final pagada = cuota.estado == 'PAGADA';
    final parcial = cuota.estado == 'PARCIAL';
    final atrasada = !pagada && diasAtraso > 0;
    final color = pagada
        ? AppColors.primary
        : atrasada
        ? AppColors.error
        : parcial
        ? AppColors.warning
        : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: pagada || atrasada ? 0.08 : 0.025),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${cuota.numeroCuota}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GotaDateUtils.formatearFecha(cuota.fechaVencimiento),
                  style: TextStyle(
                    decoration: pagada ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (cuota.esPenalizacion)
                  const Text(
                    'Penalización',
                    style: TextStyle(color: AppColors.warning, fontSize: 11),
                  ),
                if (atrasada)
                  Text(
                    '$diasAtraso días atraso',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  GotaDateUtils.formatearMoneda(
                    cuota.montoCuota - cuota.montoPenalizacion,
                  ),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    decoration: pagada ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (atrasada && cuota.montoPenalizacion > 0)
                  Text(
                    '+ Mora: ${GotaDateUtils.formatearMoneda(cuota.montoPenalizacion)}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (pagada)
            const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
          else
            IconButton(
              tooltip: 'Registrar pago',
              onPressed: onPagar,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.payments_outlined,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }
}
