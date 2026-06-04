import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'visit_detail_page.dart';
import 'consultation_page.dart';
import 'edit_doctor_profile_page.dart';
import 'vitals_sheet.dart';

class PatientProfilePage extends StatefulWidget {
  final Doctor  doctor;
  final Patient patient;

  const PatientProfilePage({
    super.key,
    required this.doctor,
    required this.patient,
  });

  @override
  State<PatientProfilePage> createState() => _PatientProfilePageState();
}

class _PatientProfilePageState extends State<PatientProfilePage> {
  bool          _loading        = true;
  bool          _summarizing    = false;
  bool          _downloading     = false;
  String?       _error;
  String?       _crossSummary;
  List<dynamic> _sessions       = [];
  late Patient  _patient;

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await http.get(
        Uri.parse('${ApiService.baseUrl}/patients/${widget.patient.patientId}/sessions'),
        headers: {'Authorization': 'Bearer ${ApiService.token}'},
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _sessions = data['sessions'] as List);
      } else {
        setState(() => _error = 'Failed to load sessions');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCrossSummary() async {
    setState(() { _summarizing = true; _error = null; });
    try {
      final resp = await http.post(
        Uri.parse('${ApiService.baseUrl}/patients/${widget.patient.patientId}/summary'),
        headers: {'Authorization': 'Bearer ${ApiService.token}'},
      ).timeout(const Duration(minutes: 2));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _crossSummary = data['summary'] as String);
      } else {
        setState(() => _error = 'Summary failed');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _downloadAllVisitsPdf(String type) async {
    setState(() { _downloading = true; _error = null; });
    try {
      final pid  = widget.patient.patientId;
      final resp = await http.get(
        Uri.parse('${ApiService.baseUrl}/patients/$pid/summary/pdf?type=$type'),
        headers: {'Authorization': 'Bearer ${ApiService.token}'},
      ).timeout(const Duration(minutes: 3));

      if (resp.statusCode == 200) {
        final dir  = await getTemporaryDirectory();
        final name = widget.patient.name.replaceAll(' ', '_');
        final file = File("${dir.path}/history_${name}_$type.pdf");
        await file.writeAsBytes(resp.bodyBytes);
        await OpenFile.open(file.path);
      } else {
        setState(() => _error = 'PDF download failed');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showAllVisitsPdfOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(100))),
          const Text('Download Patient History PDF',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('${_sessions.length} visits  |  ${widget.patient.name}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          _buildPdfOption(icon: Icons.summarize_rounded,
            title: 'Summary Only',
            subtitle: 'Cross-visit summary with vitals & prescriptions per visit',
            color: AppColors.success,
            onTap: () { Navigator.pop(context); _downloadAllVisitsPdf('summary'); }),
          const SizedBox(height: 10),
          _buildPdfOption(icon: Icons.chat_bubble_outline_rounded,
            title: 'Transcripts Only',
            subtitle: 'All consultation transcripts with speaker labels',
            color: AppColors.primary,
            onTap: () { Navigator.pop(context); _downloadAllVisitsPdf('transcript'); }),
          const SizedBox(height: 10),
          _buildPdfOption(icon: Icons.description_rounded,
            title: 'Full History Report',
            subtitle: 'Everything — summaries, vitals, prescriptions & transcripts',
            color: const Color(0xFF7C3AED),
            onTap: () { Navigator.pop(context); _downloadAllVisitsPdf('full'); }),
        ]),
      ),
    );
  }

  Widget _buildPdfOption({required IconData icon, required String title,
      required String subtitle, required Color color, required VoidCallback onTap}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(title, style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: color)),
            Text(subtitle, style: const TextStyle(fontSize: 12,
                color: AppColors.textSecondary)),
          ])),
          Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5)),
        ]),
      ),
    );

  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Visit'),
        content: const Text('This will permanently delete this consultation, its transcript, summary and prescriptions. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.deleteSession(sessionId);
      await _loadSessions();
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _editPatient() async {
    final result = await showModalBottomSheet<Patient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EditPatientSheet(patient: _patient),
    );
    if (result != null && mounted) {
      setState(() => _patient = result);
    }
  }

  Future<void> _deletePatient() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Patient'),
        content: Text('Delete ${_patient.name}? All consultations, transcripts and data will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.deletePatient(_patient.patientId);
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _startNewConsultation() async {
    try {
      final sessionId = await ApiService.createSession(widget.patient.patientId);
      if (!mounted) return;

      // Show optional vitals sheet — doctor can skip
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => VitalsSheet(sessionId: sessionId),
      );

      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => ConsultationPage(
          doctor: widget.doctor,
          patient: widget.patient,
          sessionId: sessionId,
        ),
      ));
      await _loadSessions();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_patient.name),
        actions: [
          // Edit patient
          IconButton(
            onPressed: _editPatient,
            tooltip: 'Edit Patient',
            icon: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 22),
          ),
          // Delete patient
          IconButton(
            onPressed: _deletePatient,
            tooltip: 'Delete Patient',
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.error, size: 22),
          ),
          if (_sessions.isNotEmpty) ...[
            if (_crossSummary != null)
              IconButton(
                onPressed: _downloading ? null : _showAllVisitsPdfOptions,
                tooltip: 'Download All Visits PDF',
                icon: _downloading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary))
                    : const Icon(Icons.picture_as_pdf_rounded,
                        color: AppColors.primary),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _summarizing ? null : _loadCrossSummary,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                icon: _summarizing
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary))
                    : const Icon(Icons.history_edu_rounded, size: 16),
                label: const Text('All Visits',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewConsultation,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.mic_rounded, color: Colors.white),
        label: const Text('New Consultation',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _loadSessions,
              child: CustomScrollView(
                slivers: [
                  // ── Patient card ──────────────────────────
                  SliverToBoxAdapter(
                    child: _PatientCard(patient: _patient),
                  ),

                  // ── Error ─────────────────────────────────
                  if (_error != null)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 12)),
                      ),
                    ),

                  // ── Cross-visit summary ───────────────────
                  if (_crossSummary != null)
                    SliverToBoxAdapter(
                      child: _CrossSummaryCard(
                        summary: _crossSummary!,
                        visitCount: _sessions.length,
                        onClose: () => setState(() => _crossSummary = null),
                      ),
                    ),

                  // ── Sessions header ───────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(children: [
                        Text('Past Consultations',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${_sessions.length}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                        ),
                      ]),
                    ),
                  ),

                  // ── Empty state ───────────────────────────
                  if (_sessions.isEmpty)
                    SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(children: [
                            Icon(Icons.medical_information_outlined,
                                size: 56,
                                color: AppColors.textSecondary.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            const Text('No consultations yet',
                                style: TextStyle(
                                    fontSize: 15,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            const Text('Tap the mic button to start',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary)),
                          ]),
                        ),
                      ),
                    ),

                  // ── Session list ──────────────────────────
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final s = _sessions[i];
                        return _SessionCard(
                          session: s,
                          index: _sessions.length - i,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VisitDetailPage(
                                doctor: widget.doctor,
                                patient: _patient,
                                session: s,
                                visitNumber: _sessions.length - i,
                              ),
                            ),
                          ),
                          onDelete: () => _deleteSession(
                              s['session_id'] as String),
                        );
                      },
                      childCount: _sessions.length,
                    ),
                  ),

                  const SliverToBoxAdapter(
                      child: SizedBox(height: 100)),
                ],
              ),
            ),
    );
  }
}

// ── Patient info card ──────────────────────────────────────────
class _PatientCard extends StatelessWidget {
  final Patient patient;
  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(patient.name[0].toUpperCase(),
                  style: const TextStyle(fontSize: 22,
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(patient.name, style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('${patient.gender} · ${patient.age} · ${patient.phone}',
                  style: const TextStyle(fontSize: 13,
                      color: AppColors.textSecondary)),
              if ((patient.address ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(patient.address ?? '',
                    style: const TextStyle(fontSize: 12,
                        color: AppColors.textSecondary)),
              ],
            ],
          )),
        ]),
      );
}

// ── Cross-visit summary card ───────────────────────────────────
class _CrossSummaryCard extends StatelessWidget {
  final String summary;
  final int    visitCount;
  final VoidCallback onClose;
  const _CrossSummaryCard({
    required this.summary,
    required this.visitCount,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary.withOpacity(0.08),
                     AppColors.primary.withOpacity(0.03)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.history_edu_rounded,
                color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text('Summary across $visitCount visits',
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800, color: AppColors.primary)),
            const Spacer(),
            GestureDetector(onTap: onClose,
                child: const Icon(Icons.close, size: 18,
                    color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 12),
          Text(summary,
              style: const TextStyle(fontSize: 13,
                  color: AppColors.textPrimary, height: 1.6)),
        ]),
      );
}

// ── Session card ───────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  final dynamic    session;
  final int        index;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _SessionCard({
    required this.session,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final createdAt  = DateTime.tryParse(session['created_at'] ?? '')?.toLocal();
    final dateStr    = createdAt != null
        ? '${createdAt.day} ${_month(createdAt.month)} ${createdAt.year}'
        : 'Unknown date';
    final timeStr    = createdAt != null
        ? '${createdAt.hour.toString().padLeft(2,'0')}:${createdAt.minute.toString().padLeft(2,'0')}'
        : '';
    final turnCount  = session['turn_count'] ?? 0;
    final duration   = session['duration'] ?? '00:00';
    final hasSummary = session['has_summary'] == true;
    final langs      = (session['languages'] as List?)?.cast<String>() ?? [];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          // Visit number badge
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text('V$index',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text('Visit $index  $dateStr',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary))),
                const SizedBox(width: 6),
                Text(timeStr, style: const TextStyle(fontSize: 11,
                    color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _Tag(label: '$turnCount turns', color: AppColors.textSecondary),
                _Tag(label: duration, color: AppColors.textSecondary),
                if (hasSummary)
                  _Tag(label: 'Summarized', color: AppColors.success),
                ...langs.map((l) => _Tag(label: l, color: AppColors.primary)),
              ]),
            ],
          )),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.error, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textSecondary, size: 20),
        ]),
      ),
    );
  }

  String _month(int m) => ['Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'][m-1];
}

class _Tag extends StatelessWidget {
  final String label;
  final Color  color;
  const _Tag({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 10,
            fontWeight: FontWeight.w600, color: color)),
      );
}

// ── Edit Patient Bottom Sheet ──────────────────────────────────
class _EditPatientSheet extends StatefulWidget {
  final Patient patient;
  _EditPatientSheet({required this.patient});
  @override
  State<_EditPatientSheet> createState() => _EditPatientSheetState();
}

class _EditPatientSheetState extends State<_EditPatientSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _dobCtrl;
  late final TextEditingController _addressCtrl;
  late String _gender;
  File?   _imageFile;
  bool    _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl    = TextEditingController(text: widget.patient.name);
    _phoneCtrl   = TextEditingController(text: widget.patient.phone);
    _dobCtrl     = TextEditingController(text: widget.patient.dob);
    _addressCtrl = TextEditingController(text: widget.patient.address);
    _gender      = widget.patient.gender;
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose();
    _dobCtrl.dispose(); _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(100))),
          const Text('Choose Photo', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          if (_imageFile != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              title: const Text('Remove Photo',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                setState(() => _imageFile = null);
                Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await picker.pickImage(
        source: source, imageQuality: 80, maxWidth: 400);
    if (picked != null && mounted) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Name and phone are required');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final updated = await ApiService.updatePatient(Patient(
        patientId: widget.patient.patientId,
        name:      _nameCtrl.text.trim(),
        dob:       _dobCtrl.text,
        gender:    _gender,
        phone:     _phoneCtrl.text.trim(),
        address:   _addressCtrl.text.trim(),
      ));
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
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
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(
            width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.border,
                borderRadius: BorderRadius.circular(100)),
          )),
          Row(children: [
            const Icon(Icons.edit_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Edit Patient',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary))),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 16),

          // Optional patient photo
          Center(child: GestureDetector(
            onTap: _pickImage,
            child: Stack(children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                backgroundImage: _imageFile != null
                    ? FileImage(_imageFile!) as ImageProvider
                    : null,
                child: _imageFile == null
                    ? Text(widget.patient.name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary))
                    : null,
              ),
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Colors.white, size: 12),
                ),
              ),
            ]),
          )),
          const SizedBox(height: 4),
          const Center(child: Text('Tap to add photo (optional)',
              style: TextStyle(fontSize: 11,
                  color: AppColors.textSecondary))),
          const SizedBox(height: 16),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(
                  color: AppColors.error, fontSize: 12)),
            ),
          TextField(controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full Name')),
          const SizedBox(height: 12),
          TextField(controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number')),
          const SizedBox(height: 12),
          TextField(
            controller: _dobCtrl, readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Date of Birth',
              suffixIcon: Icon(Icons.calendar_today_outlined,
                  color: AppColors.textSecondary),
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_dobCtrl.text) ?? DateTime(1990),
                firstDate: DateTime(1920), lastDate: DateTime.now(),
              );
              if (picked != null) {
                _dobCtrl.text =
                    '${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}';
              }
            },
          ),
          const SizedBox(height: 12),
          Row(children: ['Male','Female','Other'].map((g) {
            final sel = _gender == g;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => setState(() => _gender = g),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: sel ? AppColors.primary : AppColors.border,
                        width: 1.5),
                  ),
                  child: Text(g, style: TextStyle(
                      color: sel ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
                ),
              ),
            );
          }).toList()),
          const SizedBox(height: 12),
          TextField(controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Address')),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : const Text('Save Changes'),
            ),
          ),
        ]),
      ),
    );
  }
}