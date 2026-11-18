import 'dart:io';
import 'dart:typed_data';

import 'stepfun_realtime_tts.dart';
import 'text_lesson_packager.dart';

class LessonGenerationResult {
  const LessonGenerationResult({
    required this.pkg,
    required this.failed,
    required this.clipCount,
    required this.totalCount,
  });

  final PackagedTextLesson pkg;
  final List<String> failed;
  final int clipCount;
  final int totalCount;
}

/// Synthesizes each sentence with StepFun realtime TTS (3 attempts per
/// sentence, self-reconnecting client) and packages the result into an
/// mp4 + srt lesson under [outDir]. Shared by the text-import dialog and
/// the pattern book's "生成练习课".
Future<LessonGenerationResult> generateLessonFromSentences({
  required List<String> sentences,
  required String apiKey,
  required String voice,
  required Directory outDir,
  required String baseName,
  String? imagePath,
  void Function(String step)? onStep,
}) async {
  final StepfunRealtimeTts tts = StepfunRealtimeTts(
    apiKey: apiKey,
    voice: voice,
  );
  final List<({String text, Uint8List wav})> clips =
      <({String text, Uint8List wav})>[];
  final List<String> failed = <String>[];
  try {
    for (int i = 0; i < sentences.length; i++) {
      final String s = sentences[i];
      onStep?.call('合成 ${i + 1}/${sentences.length}：$s');
      Uint8List? wav;
      String lastErr = '';
      for (int attempt = 0; attempt < 3 && wav == null; attempt++) {
        try {
          wav = await tts.synthesize(s);
        } catch (e) {
          lastErr = '$e'.replaceAll('\n', ' ');
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
      if (wav == null) {
        failed.add('${i + 1}. $s — $lastErr');
      } else {
        clips.add((text: s, wav: wav));
      }
    }
    if (clips.isEmpty) {
      throw StateError(
        '全部句子合成失败${failed.isNotEmpty ? '：${failed.first}' : ''}',
      );
    }

    onStep?.call('ffmpeg 打包视频…');
    final PackagedTextLesson pkg = await packageTextLesson(
      outDir: outDir,
      baseName: baseName,
      clips: clips,
      imagePath: imagePath,
    );
    return LessonGenerationResult(
      pkg: pkg,
      failed: failed,
      clipCount: clips.length,
      totalCount: sentences.length,
    );
  } finally {
    await tts.dispose();
  }
}

/// Filesystem-safe slug for lesson directories and file names.
String slugifyLessonName(String s) {
  final String t = s
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return t.isEmpty ? 'text_lesson' : t;
}
