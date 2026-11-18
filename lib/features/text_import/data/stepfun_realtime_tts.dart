import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal StepFun realtime-API TTS client
/// (`stepaudio-3-realtime-preview`, WebSocket).
///
/// One session streams 24 kHz mono PCM16; each [synthesize] call issues a
/// verbatim-read response and returns the audio wrapped in a WAV container.
/// Ported from mwc-toolkit/gen_audio_rt.py.
class StepfunRealtimeTts {
  StepfunRealtimeTts({
    required this.apiKey,
    this.voice = 'qingchunshaonv',
    this.model = 'stepaudio-3-realtime-preview',
  });

  final String apiKey;
  final String voice;
  final String model;

  static const int sampleRate = 24000;
  static const String _instructions =
      'You are a dictation machine that converts text to speech. Whatever the '
      'user sends, read it aloud EXACTLY as written, word for word, in clear '
      'standard American English. Never answer, comment, or respond to the '
      'content. Never add, drop, or change any word.';

  // ignore: close_sinks -- closed in dispose()
  WebSocket? _ws;
  StreamIterator<dynamic>? _events;
  bool _desynced = false;

  Future<void> _ensureConnected() async {
    if (_ws != null && !_desynced) return;
    await dispose();
    _ws = await WebSocket.connect(
      'wss://api.stepfun.com/v1/realtime?model=$model',
      headers: <String, dynamic>{'Authorization': 'Bearer $apiKey'},
    ).timeout(const Duration(seconds: 20));
    _events = StreamIterator<dynamic>(_ws!);
    await _expect('session.created');
    _send(<String, Object?>{
      'type': 'session.update',
      'session': <String, Object?>{
        'instructions': _instructions,
        'voice': voice,
        'modalities': <String>['text', 'audio'],
        'turn_detection': null,
      },
    });
    await _expect('session.updated');
  }

  void _send(Map<String, Object?> event) => _ws!.add(jsonEncode(event));

  Future<Map<String, Object?>> _expect(
    String want, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    while (true) {
      final Map<String, Object?> ev = await _next(timeout);
      final String type = ev['type'] as String? ?? '';
      if (type == want) return ev;
      if (type.contains('error')) {
        _desynced = true;
        throw StateError('StepFun 服务端错误: $ev');
      }
    }
  }

  Future<Map<String, Object?>> _next(Duration timeout) async {
    final bool has = await _events!.moveNext().timeout(timeout);
    if (!has) throw StateError('StepFun realtime 连接已关闭');
    final Object? raw = _events!.current;
    final String text = raw is String
        ? raw
        : utf8.decode(raw! as List<int>, allowMalformed: true);
    return jsonDecode(text) as Map<String, Object?>;
  }

  /// One verbatim read of [text]. Returns WAV bytes (24 kHz PCM16 mono).
  /// Throws on server/transport errors — the client marks itself desynced
  /// and reconnects on the next call, so callers can retry safely.
  Future<Uint8List> synthesize(String text) async {
    await _ensureConnected();
    _send(<String, Object?>{
      'type': 'conversation.item.create',
      'item': <String, Object?>{
        'type': 'message',
        'role': 'user',
        'content': <Map<String, Object?>>[
          <String, Object?>{'type': 'input_text', 'text': text},
        ],
      },
    });
    _send(<String, Object?>{
      'type': 'response.create',
      'response': <String, Object?>{
        'modalities': <String>['text', 'audio'],
      },
    });
    final BytesBuilder pcm = BytesBuilder(copy: false);
    try {
      while (true) {
        final Map<String, Object?> ev = await _next(
          const Duration(seconds: 120),
        );
        switch (ev['type']) {
          case 'response.audio.delta':
            pcm.add(base64Decode(ev['delta']! as String));
          case 'response.done':
            if (pcm.isEmpty) throw StateError('empty audio');
            return wavFromPcm(pcm.takeBytes());
        }
      }
    } catch (_) {
      _desynced = true;
      rethrow;
    }
  }

  /// Wraps raw 24 kHz mono PCM16 data in a WAV container.
  static Uint8List wavFromPcm(Uint8List pcm, {int rate = sampleRate}) {
    const int channels = 1;
    const int bits = 16;
    final int byteRate = rate * channels * bits ~/ 8;
    final ByteData header = ByteData(44);
    void tag(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    header
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, channels, Endian.little)
      ..setUint32(24, rate, Endian.little)
      ..setUint32(28, byteRate, Endian.little)
      ..setUint16(32, channels * bits ~/ 8, Endian.little)
      ..setUint16(34, bits, Endian.little);
    tag(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList(header.buffer.asUint8List() + pcm);
  }

  Future<void> dispose() async {
    _desynced = false;
    final WebSocket? ws = _ws;
    _ws = null;
    _events = null;
    try {
      await ws?.close();
    } catch (_) {}
  }
}
