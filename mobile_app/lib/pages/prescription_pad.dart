import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class PrescriptionPad extends StatefulWidget {
  final String sessionId;
  final List<Map<String, String?>> initialPrescriptions;
  const PrescriptionPad({
    super.key,
    required this.sessionId,
    this.initialPrescriptions = const [],
  });

  @override
  State<PrescriptionPad> createState() => _PrescriptionPadState();
}

class _PrescriptionPadState extends State<PrescriptionPad> {
  final List<_RxItem> _items = [];
  bool    _saving = false;
  String? _error;

  final _freqOptions = [
    'Once daily', 'Twice daily', 'Thrice daily',
    'Every 4 hours', 'Every 6 hours', 'Every 8 hours',
    'As needed', 'At bedtime',
  ];
  final _instrOptions = [
    'Before food', 'After food', 'With food',
    'With water', 'Avoid alcohol', 'Avoid driving',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialPrescriptions.isNotEmpty) {
      for (final rx in widget.initialPrescriptions) {
        _items.add(_RxItem(
          medicine:     TextEditingController(text: rx['medicine']),
          dosage:       TextEditingController(text: rx['dosage']),
          frequency:    rx['frequency'],
          duration:     TextEditingController(text: rx['duration']),
          instructions: rx['instructions'],
        ));
      }
    } else {
      _items.add(_RxItem.empty());
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.medicine.dispose();
      item.dosage.dispose();
      item.duration.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final valid = _items.where((i) => i.medicine.text.trim().isNotEmpty).toList();
    if (valid.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      final prescriptions = valid.map((i) => {
        'medicine':     i.medicine.text.trim(),
        'dosage':       i.dosage.text.trim().isEmpty ? null : i.dosage.text.trim(),
        'frequency':    i.frequency,
        'duration':     i.duration.text.trim().isEmpty ? null : i.duration.text.trim(),
        'instructions': i.instructions,
      }).toList();

      final resp = await http.post(
        Uri.parse('${ApiService.baseUrl}/sessions/${widget.sessionId}/prescriptions'),
        headers: {
          'Authorization': 'Bearer ${ApiService.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'prescriptions': prescriptions}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        if (mounted) Navigator.pop(context, prescriptions);
      } else {
        setState(() => _error = 'Failed to save prescription');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Prescription Pad'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: _saving
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : const Icon(Icons.save_rounded, size: 16),
              label: const Text('Save',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.error.withOpacity(0.08),
              child: Text(_error!,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 12)),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (_, i) => _MedicineCard(
                item: _items[i],
                index: i + 1,
                freqOptions: _freqOptions,
                instrOptions: _instrOptions,
                onRemove: _items.length > 1
                    ? () => setState(() => _items.removeAt(i))
                    : null,
                onChanged: () => setState(() {}),
              ),
            ),
          ),
          // Add medicine button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _items.add(_RxItem.empty())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Another Medicine'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RxItem {
  final TextEditingController medicine;
  final TextEditingController dosage;
  final TextEditingController duration;
  String? frequency;
  String? instructions;

  _RxItem({
    required this.medicine,
    required this.dosage,
    required this.duration,
    this.frequency,
    this.instructions,
  });

  factory _RxItem.empty() => _RxItem(
        medicine: TextEditingController(),
        dosage:   TextEditingController(),
        duration: TextEditingController(),
      );
}

class _MedicineCard extends StatelessWidget {
  final _RxItem item;
  final int     index;
  final List<String> freqOptions;
  final List<String> instrOptions;
  final VoidCallback? onRemove;
  final VoidCallback  onChanged;

  const _MedicineCard({
    required this.item,
    required this.index,
    required this.freqOptions,
    required this.instrOptions,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8, offset: const Offset(0, 3),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text('$index',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 10),
          const Text('Medicine', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
          const Spacer(),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded,
                  color: AppColors.textSecondary, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ]),
        const SizedBox(height: 12),

        // Medicine name
        TextField(
          controller: item.medicine,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Medicine Name *',
            hintText: 'e.g. Paracetamol',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),

        // Dosage + Duration
        Row(children: [
          Expanded(child: TextField(
            controller: item.dosage,
            decoration: const InputDecoration(
              labelText: 'Dosage',
              hintText: 'e.g. 500mg',
            ),
          )),
          const SizedBox(width: 12),
          Expanded(child: TextField(
            controller: item.duration,
            decoration: const InputDecoration(
              labelText: 'Duration',
              hintText: 'e.g. 5 days',
            ),
          )),
        ]),
        const SizedBox(height: 10),

        // Frequency dropdown
        DropdownButtonFormField<String>(
          value: item.frequency,
          decoration: const InputDecoration(labelText: 'Frequency'),
          hint: const Text('Select frequency'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Not specified')),
            ...freqOptions.map((f) => DropdownMenuItem(value: f, child: Text(f))),
          ],
          onChanged: (v) {
            item.frequency = v;
            onChanged();
          },
        ),
        const SizedBox(height: 10),

        // Instructions dropdown
        DropdownButtonFormField<String>(
          value: item.instructions,
          decoration: const InputDecoration(labelText: 'Instructions'),
          hint: const Text('Select instructions'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Not specified')),
            ...instrOptions.map((i) => DropdownMenuItem(value: i, child: Text(i))),
          ],
          onChanged: (v) {
            item.instructions = v;
            onChanged();
          },
        ),
      ]),
    );
  }
}