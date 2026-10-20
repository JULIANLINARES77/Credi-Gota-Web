import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/cliente.dart';
import '../../logic/services/google_maps_service.dart';

class ClienteFormData {
  const ClienteFormData({
    required this.nombre,
    required this.telefono,
    required this.cedula,
    required this.direccion,
  });

  final String nombre;
  final String telefono;
  final String? cedula;
  final String? direccion;
}

Future<ClienteFormData?> mostrarClienteFormDialog(
  BuildContext context, {
  Cliente? cliente,
}) => showDialog<ClienteFormData>(
  context: context,
  builder: (_) => _ClienteFormDialog(cliente: cliente),
);

class _ClienteFormDialog extends StatefulWidget {
  const _ClienteFormDialog({this.cliente});

  final Cliente? cliente;

  @override
  State<_ClienteFormDialog> createState() => _ClienteFormDialogState();
}

class _ClienteFormDialogState extends State<_ClienteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _telefono;
  late final TextEditingController _cedula;
  late final TextEditingController _direccion;

  @override
  void initState() {
    super.initState();
    final cliente = widget.cliente;
    _nombre = TextEditingController(text: cliente?.nombre ?? '');
    _telefono = TextEditingController(text: cliente?.telefono ?? '');
    _cedula = TextEditingController(text: cliente?.cedula ?? '');
    _direccion = TextEditingController(text: cliente?.direccion ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _cedula.dispose();
    _direccion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.cliente == null ? 'Nuevo cliente' : 'Editar cliente'),
    scrollable: true,
    content: Form(
      key: _formKey,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nombre,
              autofocus: widget.cliente == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre completo'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'El nombre es obligatorio.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _telefono,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Teléfono'),
              validator: (value) {
                final telefono = value?.trim() ?? '';
                if (telefono.isEmpty) return 'El teléfono es obligatorio.';
                if (!RegExp(r'^\d+$').hasMatch(telefono)) {
                  return 'El teléfono solo puede contener números.';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _cedula,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Cédula (opcional)'),
              validator: (value) {
                final cedula = value?.trim() ?? '';
                if (cedula.isNotEmpty && !RegExp(r'^\d+$').hasMatch(cedula)) {
                  return 'La cédula solo puede contener números.';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _direccion,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Dirección (opcional)',
                hintText: 'Dirección, barrio y municipio',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _buscarEnMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Buscar en Google Maps'),
              ),
            ),
            const Text(
              'Maps se abrirá para buscar el lugar. Regresa y escribe o pega '
              'la dirección; al buscar, Google recibe el texto ingresado.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _guardar,
        child: const Text('Guardar'),
      ),
    ],
  );

  Future<void> _buscarEnMaps() async {
    try {
      await GoogleMapsService.abrirBusqueda(direccion: _direccion.text);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Bad state: ', ''),
          ),
        ),
      );
    }
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ClienteFormData(
        nombre: _nombre.text.trim(),
        telefono: _telefono.text.trim(),
        cedula: _opcional(_cedula.text),
        direccion: _opcional(_direccion.text),
      ),
    );
  }

  static String? _opcional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
