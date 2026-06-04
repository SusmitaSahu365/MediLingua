import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'prescription_pad.dart';

class VisitDetailPage extends StatefulWidget {
  final Doctor   doctor;
  final Patient  patient;
  final dynamic  session;
  final int      visitNumber;

  const VisitDetailPage({
    super.key,
    required this.doctor,
    required this.patient,
    required this.session,
    required this.visitNumber,
  });

  @override
  State<VisitDetailPage> createState() => _VisitDetailPageState();
}

class _VisitDetailPageState extends State<VisitDetailPage> {
  bool    _summarizing = false;
  bool    _downloading = false;
  String? _summary;
  String? _error;
  List<Map<String, String?>> _prescriptions = [];

  @override
  void initState() {
    super.initState();
    // Load summary if already exists
    if (widget.session['has_summary'] == true &&
        widget.session['summary'] != null) {
      _summary = widget.session['summary'] as String;
    }
    // Load existing prescriptions if any
    final rxList = widget.session['prescriptions'] as List?;
    if (rxList != null && rxList.isNotEmpty) {
      _prescriptions = rxList.map((rx) => {
        'medicine':     rx['medicine'] as String?,
        'dosage':       rx['dosage'] as String?,
        'frequency':    rx['frequency'] as String?,
        'duration':     rx['duration'] as String?,
        'instructions': rx['instructions'] as String?,
      }).toList();
    }
  }

  // ── Generate summary ─────────────────────────────────────────
  Future<void> _generateSummary() async {
    setState(() { _summarizing = true; _error = null; });
    try {
      final sessionId = widget.session['session_id'] as String;
      final resp = await http.post(
        Uri.parse('${ApiService.baseUrl}/sessions/$sessionId/summary'),
        headers: {'Authorization': 'Bearer ${ApiService.token}'},
      ).timeout(const Duration(minutes: 3));
      if (resp.statusCode == 200) {
        setState(() => _summary = jsonDecode(resp.body)['summary'] as String);
      } else {
        setState(() => _error = 'Summary generation failed');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  // ── Download PDF with type ────────────────────────────────────
  Future<void> _downloadPdf(String type) async {
    setState(() { _downloading = true; _error = null; });
    try {
      final sessionId = widget.session['session_id'] as String;
      final resp = await http.get(
        Uri.parse('${ApiService.baseUrl}/sessions/$sessionId/pdf?type=$type'),
        headers: {'Authorization': 'Bearer ${ApiService.token}'},
      ).timeout(const Duration(minutes: 3));
      if (resp.statusCode == 200) {
        final dir  = await getTemporaryDirectory();
        final name = widget.patient.name.replaceAll(' ', '_');
        final file = File("${dir.path}/visit${widget.visitNumber}_${name}_$type.pdf");
        await file.writeAsBytes(resp.bodyBytes);
        await OpenFile.open(file.path);
      } else {
        setState(() => _error = 'PDF download failed (${resp.statusCode})');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ── PDF options bottom sheet ──────────────────────────────────
  void _showPdfOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(100))),
          const Text('Download PDF',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Visit ${widget.visitNumber}  •  ${widget.patient.name}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          _PdfOptionTile(
            icon: Icons.summarize_rounded,
            title: 'Summary Only',
            subtitle: 'Clinical summary, vitals & prescription',
            color: AppColors.success,
            onTap: () { Navigator.pop(context); _downloadPdf('summary'); },
          ),
          const SizedBox(height: 10),
          _PdfOptionTile(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Transcript Only',
            subtitle: 'Full conversation with speaker labels & timestamps',
            color: AppColors.primary,
            onTap: () { Navigator.pop(context); _downloadPdf('transcript'); },
          ),
          const SizedBox(height: 10),
          _PdfOptionTile(
            icon: Icons.description_rounded,
            title: 'Full Report',
            subtitle: 'Everything — vitals, summary, prescription & transcript',
            color: const Color(0xFF7C3AED),
            onTap: () { Navigator.pop(context); _downloadPdf('full'); },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final segments  = (widget.session['segments'] as List?) ?? [];
    final createdAt = DateTime.tryParse(
        widget.session['created_at'] ?? '')?.toLocal();
    final dateStr   = createdAt != null
        ? '${createdAt.day} ${_month(createdAt.month)} ${createdAt.year}  '
          '${createdAt.hour.toString().padLeft(2, '0')}:'
          '${createdAt.minute.toString().padLeft(2, '0')}'
        : 'Unknown date';

    // Vitals
    final vitalsMap = widget.session['vitals'] as Map?;
    final hasVitals = vitalsMap != null &&
        vitalsMap.values.any((v) => v != null);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Visit ${widget.visitNumber}  •  ${widget.patient.name}'),
          Text(dateStr, style: const TextStyle(fontSize: 11,
              fontWeight: FontWeight.w400, color: AppColors.textSecondary)),
        ]),
        actions: [
          // PDF button — always if transcript exists
          if (segments.isNotEmpty)
            IconButton(
              onPressed: _downloading ? null : _showPdfOptions,
              tooltip: 'Download PDF',
              icon: _downloading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : const Icon(Icons.picture_as_pdf_rounded,
                      color: AppColors.primary),
            ),
          // Summarize / Re-summarize button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _summarizing ? null : _generateSummary,
              style: TextButton.styleFrom(
                backgroundColor: _summary != null
                    ? AppColors.primary.withOpacity(0.08)
                    : AppColors.success.withOpacity(0.1),
                foregroundColor: _summary != null
                    ? AppColors.primary
                    : AppColors.success,
                disabledForegroundColor:
                    AppColors.textSecondary.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),
              icon: _summarizing
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_summary != null
                      ? Icons.refresh_rounded
                      : Icons.auto_awesome_rounded, size: 16),
              label: Text(_summary != null ? 'Re-summarize' : 'Summarize',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [

          // ── Error ─────────────────────────────────────────
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 12))),
                GestureDetector(
                  onTap: () => setState(() => _error = null),
                  child: const Icon(Icons.close,
                      size: 16, color: AppColors.error),
                ),
              ]),
            ),

          // ── Vitals card ───────────────────────────────────
          if (hasVitals) ...[
            _VitalsCard(
                vitals: Map<String, String?>.from(vitalsMap!)),
            const SizedBox(height: 12),
          ],

          // ── Summary card ──────────────────────────────────
          if (_summary != null) ...[
            _SummaryCard(summary: _summary!),
            const SizedBox(height: 12),
          ],

          // ── Prescription section ──────────────────────────
          if (_summary != null) ...[
            _PrescriptionSection(
              prescriptions: _prescriptions,
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrescriptionPad(
                      sessionId: widget.session['session_id'] as String,
                      initialPrescriptions: _prescriptions,
                    ),
                  ),
                );
                if (result != null && mounted) {
                  setState(() => _prescriptions =
                      List<Map<String, String?>>.from(result));
                }
              },
            ),
            const SizedBox(height: 20),
          ],

          // ── Transcript header ─────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              const Icon(Icons.chat_bubble_outline_rounded,
                  size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text('Transcript  •  ${segments.length} turns',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Transcript bubbles ────────────────────────────
          if (segments.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No transcript available',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...segments.map((seg) =>
                _Bubble(seg: seg as Map<String, dynamic>)),
        ],
      ),
    );
  }

  String _month(int m) => [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ][m - 1];
}

// ── Vitals card ────────────────────────────────────────────────
class _VitalsCard extends StatelessWidget {
  final Map<String, String?> vitals;
  const _VitalsCard({required this.vitals});

  @override
  Widget build(BuildContext context) {
    final items = <_VitalItem>[];
    final sys = vitals['bp_systolic'];
    final dia = vitals['bp_diastolic'];
    if (sys != null || dia != null)
      items.add(_VitalItem(Icons.favorite_rounded,
          'Blood Pressure', '${sys ?? '-'}/${dia ?? '-'} mmHg',
          const Color(0xFFE53935)));
    if (vitals['heart_rate'] != null)
      items.add(_VitalItem(Icons.monitor_heart_rounded,
          'Heart Rate', '${vitals['heart_rate']} bpm',
          const Color(0xFFE91E63)));
    if (vitals['spo2'] != null)
      items.add(_VitalItem(Icons.air_rounded,
          'SpO2', '${vitals['spo2']}%', const Color(0xFF1565C0)));
    if (vitals['temperature'] != null)
      items.add(_VitalItem(Icons.thermostat_rounded,
          'Temperature', vitals['temperature']!,
          const Color(0xFFFF6F00)));
    if (vitals['weight'] != null)
      items.add(_VitalItem(Icons.monitor_weight_outlined,
          'Weight', '${vitals['weight']} kg',
          const Color(0xFF2E7D32)));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFF0F4FF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
            ),
          ),
          child: Row(children: [
            const Icon(Icons.monitor_heart_outlined,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Vitals', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: AppColors.primary)),
          ]),
        ),
        // Grid
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10, runSpacing: 10,
            children: items.map((item) => Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: item.color.withOpacity(0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min,
                  children: [
                Icon(item.icon, size: 15, color: item.color),
                const SizedBox(width: 6),
                Column(crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                  Text(item.label, style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: item.color)),
                  Text(item.value, style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
                ]),
              ]),
            )).toList(),
          ),
        ),
        if (vitals['notes'] != null &&
            vitals['notes']!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text('Note: ${vitals['notes']}',
                style: TextStyle(fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary
                        .withOpacity(0.8))),
          ),
      ]),
    );
  }
}

class _VitalItem {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  _VitalItem(this.icon, this.label, this.value, this.color);
}

// ── Summary card — Clinical report style ───────────────────────
class _SummaryCard extends StatelessWidget {
  final String summary;
  const _SummaryCard({required this.summary});

  static const _sectionMeta = {
    'CHIEF COMPLAINT':          [Icons.sick_rounded,             Color(0xFFE53935)],
    'KEY SYMPTOMS':             [Icons.monitor_heart_rounded,     Color(0xFFE91E63)],
    "DOCTOR'S ADVICE":          [Icons.medical_services_rounded,  Color(0xFF1565C0)],
    'MEDICATIONS / TESTS':      [Icons.medication_rounded,        Color(0xFF6A1B9A)],
    'FOLLOW UP':                [Icons.event_repeat_rounded,      Color(0xFF2E7D32)],
    'PATIENT OVERVIEW':         [Icons.person_rounded,            Color(0xFF1565C0)],
    'ALL PAST COMPLAINTS':      [Icons.history_rounded,           Color(0xFFE53935)],
    'MEDICATIONS PRESCRIBED':   [Icons.medication_rounded,        Color(0xFF6A1B9A)],
    "DOCTOR'S ADVICE HISTORY":  [Icons.medical_services_rounded,  Color(0xFF1565C0)],
    'FOLLOW-UP STATUS':         [Icons.event_repeat_rounded,      Color(0xFF2E7D32)],
    'TRENDS / PATTERNS':        [Icons.trending_up_rounded,       Color(0xFFFF6F00)],
  };

  static _findSection(String line) {
    final upper = line.trim().toUpperCase().replaceAll(':', '');
    for (final key in _sectionMeta.keys) {
      if (upper == key || upper.startsWith(key)) {
        return _sectionMeta[key];
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lines = summary.split('\n');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.summarize_rounded,
                  color: Colors.white, size: 16),
              const SizedBox(width: 8),
              const Text('Clinical Summary',
                  style: TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ]),
          ),

          // ── Content ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildContent(lines),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContent(List<String> lines) {
    final widgets = <Widget>[];
    bool firstSection = true;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final sectionMeta = _findSection(trimmed);
      if (sectionMeta != null) {
        if (!firstSection) widgets.add(const SizedBox(height: 14));
        firstSection = false;

        final icon  = sectionMeta[0] as IconData;
        final color = sectionMeta[1] as Color;

        // Section header row
        widgets.add(Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(
            trimmed.replaceAll(':', ''),
            style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.3),
          )),
        ]));
        widgets.add(const SizedBox(height: 6));
        widgets.add(Container(
            height: 1,
            color: AppColors.border));
        widgets.add(const SizedBox(height: 6));
      } else {
        // Content line
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 3),
          child: Text(trimmed,
              style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                  height: 1.6)),
        ));
      }
    }
    return widgets;
  }
}

// ── Prescription section ───────────────────────────────────────
class _PrescriptionSection extends StatelessWidget {
  final List<Map<String, String?>> prescriptions;
  final VoidCallback onTap;
  const _PrescriptionSection({
    required this.prescriptions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with add/edit button
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF3E5F5),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.medication_rounded,
                  size: 16, color: Color(0xFF6A1B9A)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Prescription', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: Color(0xFF6A1B9A))),
              ),
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    prescriptions.isEmpty
                        ? '+ Add'
                        : 'Edit',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),

          // Empty state
          if (prescriptions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No prescription added yet.',
                  style: TextStyle(fontSize: 13,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic)),
            )
          else
            // Medicine list
            ...prescriptions.asMap().entries.map((e) {
              final i  = e.key;
              final rx = e.value;
              final details = <String>[];
              if (rx['dosage'] != null)
                details.add(rx['dosage']!);
              if (rx['frequency'] != null)
                details.add(rx['frequency']!);
              if (rx['duration'] != null)
                details.add(rx['duration']!);
              if (rx['instructions'] != null)
                details.add(rx['instructions']!);

              return Container(
                padding: const EdgeInsets.fromLTRB(
                    14, 10, 14, 10),
                decoration: BoxDecoration(
                  border: i > 0
                      ? const Border(top: BorderSide(
                          color: AppColors.border))
                      : null,
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24, height: 24,
                      margin: const EdgeInsets.only(
                          right: 10, top: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A1B9A)
                            .withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF6A1B9A)))),
                    ),
                    Expanded(child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(rx['medicine'] ?? '',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        if (details.isNotEmpty)
                          const SizedBox(height: 2),
                        if (details.isNotEmpty)
                          Text(details.join('  •  '),
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                      ],
                    )),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── PDF option tile ────────────────────────────────────────────
class _PdfOptionTile extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final Color        color;
  final VoidCallback onTap;
  const _PdfOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
              ],
            )),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: color.withOpacity(0.5)),
          ]),
        ),
      );
}

// ── Transcript bubble ──────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final Map<String, dynamic> seg;
  const _Bubble({required this.seg});

  bool get _isS1 => (seg['speaker'] ?? '') == 'Speaker 1';

  @override
  Widget build(BuildContext context) {
    final speaker      = seg['speaker'] as String? ?? 'Speaker 1';
    final englishText  = seg['english_text'] as String? ?? '';
    final originalText = seg['original_text'] as String? ?? '';
    final lang         = seg['detected_language'] as String? ?? 'English';
    final startTime    = seg['start_time'] as String? ?? '';
    final endTime      = seg['end_time'] as String? ?? '';
    final isTranslated = lang != 'English' &&
        originalText.isNotEmpty && originalText != englishText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: _isS1
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          if (_isS1) ...[
            _Avatar(label: 'S1', color: AppColors.primary),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: _isS1
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(speaker, style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                    if (startTime.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('$startTime – $endTime',
                          style: TextStyle(fontSize: 10,
                              color: AppColors.textSecondary
                                  .withOpacity(0.6))),
                    ],
                    if (isTranslated) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(lang, style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isS1
                        ? AppColors.doctorBubble
                        : AppColors.patientBubble,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: _isS1
                          ? Radius.zero
                          : const Radius.circular(16),
                      bottomRight: _isS1
                          ? const Radius.circular(16)
                          : Radius.zero,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(englishText, style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          height: 1.4)),
                      if (isTranslated) ...[
                        const SizedBox(height: 6),
                        const Divider(height: 1,
                            color: Color(0xFFE0E0E0)),
                        const SizedBox(height: 6),
                        Text(originalText, style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary
                                .withOpacity(0.7),
                            fontStyle: FontStyle.italic,
                            height: 1.3)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!_isS1) ...[
            const SizedBox(width: 8),
            _Avatar(
                label: 'S2',
                color: const Color(0xFFE91E63)),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String label;
  final Color  color;
  const _Avatar({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle),
        child: Center(child: Text(label,
            style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color))),
      );
}