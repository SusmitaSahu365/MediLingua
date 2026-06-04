import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

class AudioService {
  static const int _sampleRate = 16000;
  static const int _chunkDurationMs = 10000;

  final AudioRecorder _recorder = AudioRecorder();
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  StreamSubscription? _audioSub;
  Timer? _pingTimer;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  final void Function(TranscriptSegment segment) onSegment;
  final void Function(String error) onError;

  AudioService({required this.onSegment, required this.onError});

  Future<void> startRecording(String wsUrl) async {
    if (_isRecording) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      onError('Microphone permission denied');
      return;
    }

    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    } catch (e) {
      onError('WebSocket connection failed: $e');
      return;
    }

    _wsSub = _channel!.stream.listen(
      (data) {
        if (data is String) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            if (json['type'] == 'segment') {
              onSegment(TranscriptSegment.fromJson(json));
            } else if (json['type'] == 'error') {
              onError(json['message'] ?? 'Unknown server error');
            }
          } catch (_) {}
        }
      },
      onError: (e) => onError('WebSocket error: $e'),
      onDone: () {},
    );

    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _channel?.sink.add(jsonEncode({'type': 'ping'}));
    });

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );

    final List<int> buffer = [];
    final int bytesPerChunk =
        _sampleRate * (_chunkDurationMs ~/ 1000) * 2; // 16-bit = 2 bytes

    _audioSub = stream.listen(
      (data) {
        buffer.addAll(data);
        while (buffer.length >= bytesPerChunk) {
          final chunkBytes =
              Uint8List.fromList(buffer.sublist(0, bytesPerChunk));
          buffer.removeRange(0, bytesPerChunk);
          final float32 = _int16ToFloat32(chunkBytes);
          _channel?.sink.add(float32.buffer.asUint8List());
        }
      },
      onError: (e) => onError('Audio stream error: $e'),
    );

    _isRecording = true;
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;

    await _audioSub?.cancel();
    _audioSub = null;
    await _recorder.stop();

    _pingTimer?.cancel();
    _pingTimer = null;

    _channel?.sink.add(jsonEncode({'type': 'end'}));
    await Future.delayed(const Duration(milliseconds: 500));

    await _wsSub?.cancel();
    _wsSub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    stopRecording();
    _recorder.dispose();
  }

  Float32List _int16ToFloat32(Uint8List bytes) {
    final int16 = bytes.buffer.asInt16List();
    final float32 = Float32List(int16.length);
    for (int i = 0; i < int16.length; i++) {
      float32[i] = int16[i] / 32768.0;
    }
    return float32;
  }
}