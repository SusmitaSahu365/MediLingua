import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class VitalsSheet extends StatefulWidget {
  final String sessionId;
  const VitalsSheet({super.key, required this.sessionId});

  @override
  State<VitalsSheet> createState() => _VitalsSheetState();
}

class _VitalsSheetState extends State<VitalsSheet> {
  final _systolicCtrl    = TextEditingController();
  final _diastolicCtrl   = TextEditingController();
  final _heartRateCtrl   = TextEditingController();
  final _spo2Ctrl        = TextEditingController();
  final _tempCtrl        = TextEditingController();
  final _weightCtrl      = TextEditingController();
  final _notesCtrl       = TextEditingController();
  bool    _saving = false;
  String? _error;

  @override
  void dispose() {
    _systolicCtrl.dispose(); _diastolicCtrl.dispose();
    _heartRateCtrl.dispose(); _spo2Ctrl.dispose();
    _tempCtrl.dispose(); _weightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Check at least one vital is filled
    final hasAny = [_systolicCtrl, _diastolicCtrl, _heartRateCtrl,
                    _spo2Ctrl, _tempCtrl, _weightCtrl, _notesCtrl]
        .any((c) => c.text.trim().isNotEmpty);

    setState(() { _saving = true; _error = null; });
    try {
      final body = <String, dynamic>{};
      if (_systolicCtrl.text.trim().isNotEmpty)
        body['bp_systolic'] = _systolicCtrl.text.trim();
      if (_diastolicCtrl.text.trim().isNotEmpty)
        body['bp_diastolic'] = _diastolicCtrl.text.trim();
      if (_heartRateCtrl.text.trim().isNotEmpty)
        body['heart_rate'] = _heartRateCtrl.text.trim();
      if (_spo2Ctrl.text.trim().isNotEmpty)
        body['spo2'] = _spo2Ctrl.text.trim();
      if (_tempCtrl.text.trim().isNotEmpty)
        body['temperature'] = _tempCtrl.text.trim();
      if (_weightCtrl.text.trim().isNotEmpty)
        body['weight'] = _weightCtrl.text.trim();
      if (_notesCtrl.text.trim().isNotEmpty)
        body['notes'] = _notesCtrl.text.trim();

      final resp = await http.post(
        Uri.parse('${ApiService.baseUrl}/sessions/${widget.sessionId}/vitals'),
        headers: {
          'Authorization': 'Bearer ${ApiService.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _error = 'Failed to save vitals');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(100)),
            )),

            // Title
            Row(children: [
              const Icon(Icons.monitor_heart_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Patient Vitals',
                      style: TextStyle(fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  Text('All fields optional',
                      style: TextStyle(fontSize: 12,
                          color: AppColors.textSecondary)),
                ]),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 16),

            // Blood Pressure
            const _SectionLabel(label: 'Blood Pressure (mmHg)'),
            Row(children: [
              Expanded(child: _VitalField(
                  controller: _systolicCtrl,
                  label: 'Systolic',
                  hint: '120',
                  keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _VitalField(
                  controller: _diastolicCtrl,
                  label: 'Diastolic',
                  hint: '80',
                  keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 12),

            // Heart Rate + SpO2
            Row(children: [
              Expanded(child: _VitalField(
                  controller: _heartRateCtrl,
                  label: 'Heart Rate (bpm)',
                  hint: '72',
                  keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _VitalField(
                  controller: _spo2Ctrl,
                  label: 'SpO2 (%)',
                  hint: '98',
                  keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 12),

            // Temperature + Weight
            Row(children: [
              Expanded(child: _VitalField(
                  controller: _tempCtrl,
                  label: 'Temperature',
                  hint: '98.6°F',
                  keyboardType: TextInputType.text)),
              const SizedBox(width: 12),
              Expanded(child: _VitalField(
                  controller: _weightCtrl,
                  label: 'Weight (kg)',
                  hint: '70',
                  keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 12),

            // Notes
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Additional Notes',
                hintText: 'e.g. Patient appears pale, mild fever...',
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 12)),
            ],
            const SizedBox(height: 20),

            // Buttons
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Save & Start'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );
}

class _VitalField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  const _VitalField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.keyboardType,
  });
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );
}