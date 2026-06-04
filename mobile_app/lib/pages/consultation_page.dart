import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ConsultationPage extends StatefulWidget {
  final Doctor  doctor;
  final Patient patient;
  final String  sessionId;

  const ConsultationPage({
    super.key,
    required this.doctor,
    required this.patient,
    required this.sessionId,
  });

  @override
  State<ConsultationPage> createState() => _ConsultationPageState();
}

class _ConsultationPageState extends State<ConsultationPage>
    with TickerProviderStateMixin {
  final AudioRecorder    _recorder = AudioRecorder();
  final ScrollController _scroll   = ScrollController();

  bool    _isRecording   = false;
  bool    _isProcessing  = false;
  bool    _isSummarizing = false;
  String? _error;
  int     _durationSeconds = 0;
  Timer?  _timer;

  final List<Map<String, String>> _turns = [];
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _timer?.cancel();
    _recorder.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _durationLabel {
    final m = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  // ── Start recording ───────────────────────────────────────
  Future<void> _startRecording() async {
    setState(() { _error = null; _durationSeconds = 0; });

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() => _error = 'Microphone permission denied');
      return;
    }

    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/consult_${widget.sessionId}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRecording) setState(() => _durationSeconds++);
    });

    setState(() => _isRecording = true);
  }

  // ── Stop + upload + transcribe (batch) ────────────────────
  Future<void> _stopAndTranscribe() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    setState(() { _isRecording = false; _isProcessing = true; _error = null; });

    if (path == null || path.isEmpty) {
      setState(() { _isProcessing = false; _error = 'Recording failed'; });
      return;
    }

    try {
      final file = File(path);
      if (!await file.exists()) throw Exception('Audio file not found');

      final uri     = Uri.parse('${ApiService.baseUrl}/sessions/${widget.sessionId}/transcribe');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${ApiService.token}';
      request.files.add(await http.MultipartFile.fromPath(
          'audio', path, filename: 'recording.wav'));

      final streamed  = await request.send().timeout(const Duration(minutes: 5));
      final response  = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final segs = data['segments'] as List;
        setState(() {
          _turns.addAll(segs.map((e) => {
            'speaker':           e['speaker']           as String,
            'original_text':     e['original_text']     as String,
            'english_text':      e['english_text']      as String,
            'detected_language': e['detected_language'] as String,
            'start_time':        e['start_time']        as String,
            'end_time':          e['end_time']          as String,
          }));
        });
        _scrollToBottom();
      } else {
        final msg = jsonDecode(response.body)['detail'] ?? 'Transcription failed';
        setState(() => _error = msg);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      try { await File(path).delete(); } catch (_) {}
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Generate summary ──────────────────────────────────────
  Future<void> _generateSummary() async {
    if (_turns.isEmpty) return;
    setState(() { _isSummarizing = true; _error = null; });
    try {
      final resp = await http.post(
        Uri.parse('${ApiService.baseUrl}/sessions/${widget.sessionId}/summary'),
        headers: {'Authorization': 'Bearer ${ApiService.token}'},
      ).timeout(const Duration(minutes: 3));
      if (resp.statusCode == 200) {
        if (mounted) Navigator.pop(context, widget.sessionId);
      } else {
        setState(() => _error = 'Summary generation failed');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSummarizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.patient.name),
          Text(
            '${widget.patient.gender} · ${widget.patient.age} · ${widget.patient.phone}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400,
                color: AppColors.textSecondary),
          ),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton.icon(
              onPressed: (_turns.isNotEmpty && !_isSummarizing &&
                  !_isRecording && !_isProcessing)
                  ? _generateSummary
                  : null,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.success.withOpacity(0.1),
                foregroundColor: AppColors.success,
                disabledForegroundColor: AppColors.textSecondary.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: _isSummarizing
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.success))
                  : const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('Summary',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),

      body: Column(children: [
        // ── Status bar ──────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          color: _isRecording
              ? AppColors.recording.withOpacity(0.06)
              : _isProcessing
                  ? AppColors.primary.withOpacity(0.06)
                  : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            if (_isProcessing)
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary))
            else
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? AppColors.recording
                            .withOpacity(0.4 + 0.6 * _pulse.value)
                        : AppColors.textSecondary.withOpacity(0.3),
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isProcessing
                    ? 'Transcribing + translating...'
                    : _isRecording
                        ? 'Recording · $_durationLabel'
                        : _turns.isNotEmpty
                            ? 'Done · ${_turns.length} turns · tap Summary'
                            : 'Ready — tap mic to record',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: _isRecording
                        ? AppColors.recording
                        : _isProcessing
                            ? AppColors.primary
                            : AppColors.textSecondary),
              ),
            ),
          ]),
        ),
        const Divider(height: 1, color: AppColors.border),

        // ── Error ─────────────────────────────────────────
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.error.withOpacity(0.08),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12))),
              IconButton(
                  icon: const Icon(Icons.close, size: 16, color: AppColors.error),
                  onPressed: () => setState(() => _error = null),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ]),
          ),

        // ── Transcript ─────────────────────────────────────
        Expanded(
          child: _isProcessing
              ? _ProcessingState()
              : _turns.isEmpty
                  ? _EmptyState(isRecording: _isRecording)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      itemCount: _turns.length,
                      itemBuilder: (_, i) => _Bubble(turn: _turns[i]),
                    ),
        ),

        // ── Controls ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              _isRecording
                  ? 'Tap to stop & transcribe'
                  : _isProcessing
                      ? 'Processing with AssemblyAI + Groq...'
                      : _turns.isNotEmpty
                          ? 'Tap mic to record more'
                          : 'Tap mic · speak · tap again to transcribe',
              style: TextStyle(fontSize: 12,
                  color: AppColors.textSecondary.withOpacity(0.8)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _isProcessing
                  ? null
                  : _isRecording
                      ? _stopAndTranscribe
                      : _startRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: _isProcessing
                      ? AppColors.textSecondary.withOpacity(0.3)
                      : _isRecording
                          ? AppColors.recording
                          : AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: (_isRecording
                            ? AppColors.recording
                            : AppColors.primary)
                        .withOpacity(_isProcessing ? 0 : 0.35),
                    blurRadius: 20, offset: const Offset(0, 8),
                  )],
                ),
                child: Icon(
                  _isProcessing
                      ? Icons.hourglass_empty_rounded
                      : _isRecording
                          ? Icons.stop_rounded
                          : Icons.mic_rounded,
                  color: Colors.white, size: 32,
                ),
              ),
            ),
            if (_turns.isNotEmpty && !_isRecording && !_isProcessing)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextButton.icon(
                  onPressed: _startRecording,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Record Again'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ── Processing ─────────────────────────────────────────────────
class _ProcessingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 20),
          const Text('Transcribing...', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('AssemblyAI diarizing · Groq translating',
              style: TextStyle(fontSize: 13,
                  color: AppColors.textSecondary.withOpacity(0.8))),
        ]),
      );
}

// ── Empty state ────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool isRecording;
  const _EmptyState({required this.isRecording});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
            isRecording ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
            size: 64,
            color: (isRecording ? AppColors.recording : AppColors.textSecondary)
                .withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            isRecording
                ? 'Recording...\nStop to get transcript'
                : 'Press mic to start recording\nSpeaker 1 & 2 auto-detected\nHindi / Marathi / Tamil auto-translated',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15,
                color: AppColors.textSecondary, height: 1.6),
          ),
        ]),
      );
}

// ── Bubble ─────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final Map<String, String> turn;
  const _Bubble({required this.turn});

  bool get _isS1 => turn['speaker'] == 'Speaker 1';

  @override
  Widget build(BuildContext context) {
    final speaker      = turn['speaker'] ?? 'Speaker 1';
    final englishText  = turn['english_text'] ?? '';
    final originalText = turn['original_text'] ?? '';
    final detectedLang = turn['detected_language'] ?? 'English';
    final startTime    = turn['start_time'] ?? '';
    final endTime      = turn['end_time'] ?? '';
    final isTranslated = detectedLang != 'English' &&
        originalText.isNotEmpty && originalText != englishText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            _isS1 ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (_isS1) ...[
            _Avatar(label: 'S1', color: AppColors.primary),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  _isS1 ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(speaker, style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
                  if (startTime.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text('$startTime – $endTime',
                        style: TextStyle(fontSize: 10,
                            color: AppColors.textSecondary.withOpacity(0.6))),
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
                      child: Text(detectedLang,
                          style: TextStyle(fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                  ],
                ]),
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
                        fontSize: 14, color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500, height: 1.4)),
                    if (isTranslated) ...[
                      const SizedBox(height: 6),
                      const Divider(height: 1, color: Color(0xFFE0E0E0)),
                      const SizedBox(height: 6),
                      Text(originalText, style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary.withOpacity(0.7),
                          fontStyle: FontStyle.italic,
                          height: 1.3)),
                    ],
                  ]),
                ),
              ],
            ),
          ),
          if (!_isS1) ...[
            const SizedBox(width: 8),
            _Avatar(label: 'S2', color: const Color(0xFFE91E63)),
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
            color: color.withOpacity(0.12), shape: BoxShape.circle),
        child: Center(child: Text(label,
            style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w800, color: color))),
      );
}