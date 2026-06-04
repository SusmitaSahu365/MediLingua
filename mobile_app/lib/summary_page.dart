import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class SummaryPage extends StatefulWidget {
  final Consultation consultation;
  final Doctor doctor;
  const SummaryPage({super.key, required this.consultation, required this.doctor});
  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  final List<Prescription> _prescriptions = [];  // empty — doctor adds real ones
  bool _addingPrescription = false;
  bool _saving = false;
  final _medCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _instrCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    for (final c in [_medCtrl,_dosageCtrl,_durationCtrl,_instrCtrl]) c.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String get _duration {
    if (widget.consultation.segments.isEmpty) return '0s';
    final last = widget.consultation.segments.last.endTime;
    final parts = last.split(':');
    if (parts.length != 2) return last;
    final secs = int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!;
    return secs < 60 ? '${secs}s' : '${secs ~/ 60}m ${secs % 60}s';
  }

  String get _lang => widget.consultation.segments.isNotEmpty
      ? widget.consultation.segments.first.detectedLanguage
      : 'English';

  Future<void> _endAndSave() async {
    setState(() => _saving = true);
    try {
      await ApiService.endSession(widget.consultation.sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Consultation saved successfully'),
        backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.consultation;
    final p = c.patient;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Clinical Summary'),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 16),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: _saving ? null : _endAndSave,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                  : const Icon(Icons.save_rounded, size: 16),
              label: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
        ],
      ),
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _anim, curve: Curves.easeOut),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient card
              _Card(child: Row(children: [
                Container(width: 56, height: 56,
                  decoration: BoxDecoration(color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16)),
                  child: Center(child: Text(p.initials, style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 17, color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text('${p.gender} · ${p.age} · ${p.phone}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 3),
                  Text('Visit: ${_formatDate(c.visitDate)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('Completed', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success))),
              ])),
              const SizedBox(height: 12),

              // AI Summary
              _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                      borderRadius: BorderRadius.circular(9)),
                    child: const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white)),
                  const SizedBox(width: 9),
                  const Text('AI Clinical Summary', style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(100)),
                    child: const Text('AI Generated', style: TextStyle(
                        fontSize: 10, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 12),
                Text(c.summary ?? 'No summary generated.',
                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.65)),
              ])),
              const SizedBox(height: 12),

              // Stats
              _Card(
                padding: EdgeInsets.zero,
                child: IntrinsicHeight(child: Row(children: [
                  Expanded(child: _Stat(icon: Icons.timer_outlined, value: _duration,
                      label: 'Duration', color: AppColors.primary)),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(child: _Stat(icon: Icons.chat_bubble_outline_rounded,
                      value: '${c.segments.length}', label: 'Exchanges', color: AppColors.accent)),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(child: _Stat(icon: Icons.translate_rounded, value: _lang,
                      label: 'Language', color: const Color(0xFF7C3AED))),
                ])),
              ),
              const SizedBox(height: 12),

              // Prescriptions
              _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.medication_rounded, size: 14, color: Colors.white)),
                  const SizedBox(width: 8),
                  const Text('Prescriptions', style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _addingPrescription = true),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primary.withOpacity(0.07),
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ]),
                if (_prescriptions.isEmpty && !_addingPrescription) ...[
                  const SizedBox(height: 12),
                  const Text('No prescriptions added yet.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ] else ...[
                  const SizedBox(height: 12),
                  ..._prescriptions.map((p) => _RxItem(p)),
                ],
                if (_addingPrescription) ...[
                  const SizedBox(height: 8),
                  _AddRxForm(
                    medCtrl: _medCtrl, dosageCtrl: _dosageCtrl,
                    durationCtrl: _durationCtrl, instrCtrl: _instrCtrl,
                    onAdd: () {
                      if (_medCtrl.text.isNotEmpty) {
                        setState(() {
                          _prescriptions.add(Prescription(
                            medicineName: _medCtrl.text,
                            dosage: _dosageCtrl.text,
                            duration: _durationCtrl.text,
                            instructions: _instrCtrl.text,
                          ));
                          _addingPrescription = false;
                          for (final c in [_medCtrl,_dosageCtrl,_durationCtrl,_instrCtrl]) c.clear();
                        });
                      }
                    },
                    onCancel: () => setState(() => _addingPrescription = false),
                  ),
                ],
              ])),
              const SizedBox(height: 12),

              // Full Transcript
              _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppColors.textSecondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.receipt_long_rounded,
                        size: 14, color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  const Text('Full Transcript', style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                ]),
                const SizedBox(height: 14),
                if (c.segments.isEmpty)
                  const Text('No transcript available.',
                      style: TextStyle(color: AppColors.textSecondary))
                else
                  ...c.segments.map((s) => _TxRow(s)),
              ])),
              const SizedBox(height: 20),

              // End & Save
              SizedBox(
                width: double.infinity, height: 54,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _endAndSave,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0),
                  icon: _saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, size: 20),
                  label: const Text('End & Save Consultation',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child; final EdgeInsets? padding;
  const _Card({required this.child, this.padding});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border)),
    child: child,
  );
}

class _Stat extends StatelessWidget {
  final IconData icon; final String value, label; final Color color;
  const _Stat({required this.icon, required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 22), const SizedBox(height: 6),
      Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary,
          fontWeight: FontWeight.w500)),
    ]),
  );
}

class _RxItem extends StatelessWidget {
  final Prescription p;
  const _RxItem(this.p);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.13))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 38, height: 38,
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.medication_liquid_rounded, color: Colors.white, size: 18)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.medicineName, style: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text('${p.dosage} · ${p.duration}', style: const TextStyle(
            fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(p.instructions, style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary)),
      ])),
    ]),
  );
}

class _AddRxForm extends StatelessWidget {
  final TextEditingController medCtrl, dosageCtrl, durationCtrl, instrCtrl;
  final VoidCallback onAdd, onCancel;
  const _AddRxForm({required this.medCtrl, required this.dosageCtrl,
      required this.durationCtrl, required this.instrCtrl,
      required this.onAdd, required this.onCancel});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border)),
    child: Column(children: [
      TextField(controller: medCtrl,
          decoration: const InputDecoration(labelText: 'Medicine Name', isDense: true)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: dosageCtrl,
            decoration: const InputDecoration(labelText: 'Dosage', isDense: true))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: durationCtrl,
            decoration: const InputDecoration(labelText: 'Duration', isDense: true))),
      ]),
      const SizedBox(height: 8),
      TextField(controller: instrCtrl,
          decoration: const InputDecoration(labelText: 'Instructions', isDense: true)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: onCancel, child: const Text('Cancel'))),
        const SizedBox(width: 8),
        Expanded(child: ElevatedButton(onPressed: onAdd, child: const Text('Add'))),
      ]),
    ]),
  );
}

class _TxRow extends StatelessWidget {
  final TranscriptSegment s;
  const _TxRow(this.s);
  @override
  Widget build(BuildContext context) {
    final isDoc = s.speaker == 'Doctor';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 60, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: isDoc ? AppColors.primary.withOpacity(0.1) : const Color(0xFFE91E63).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6)),
          child: Text(isDoc ? 'Doctor' : 'Patient', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: isDoc ? AppColors.primary : const Color(0xFFE91E63)))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.englishText, style: const TextStyle(
              fontSize: 13, color: AppColors.textPrimary, height: 1.4)),
          if (s.originalText != s.englishText)
            Text(s.originalText, style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
        ])),
        const SizedBox(width: 8),
        Text(s.startTime, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ]),
    );
  }
}