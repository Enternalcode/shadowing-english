import 'dart:io';
import 'dart:typed_data';

import 'stepfun_realtime_tts.dart';

/// Result of packaging a text lesson: a playable mp4 plus the SRT that
/// carries sentence timing, ready to register as a course episode.
class PackagedTextLesson {
  const PackagedTextLesson({
    required this.videoPath,
    required this.subtitlePath,
    required this.sentenceCount,
    required this.totalSeconds,
  });

  final String videoPath;
  final String subtitlePath;
  final int sentenceCount;
  final double totalSeconds;
}

/// Concatenates per-sentence WAV clips into `full.wav`, writes the matching
/// `full.srt`, then renders an mp4 via ffmpeg — the image as a still frame
/// when provided, otherwise a dark waveform video.
Future<PackagedTextLesson> packageTextLesson({
  required Directory outDir,
  required String baseName,
  required List<({String text, Uint8List wav})> clips,
  String? imagePath,
}) async {
  if (clips.isEmpty) {
    throw ArgumentError('没有可打包的句子音频');
  }
  await outDir.create(recursive: true);

  // Concat PCM payloads (our own WAVs: 44-byte header, 24 kHz mono PCM16).
  final BytesBuilder allPcm = BytesBuilder(copy: false);
  final List<int> endsMs = <int>[];
  int cursorMs = 0;
  for (int i = 0; i < clips.length; i++) {
    final Uint8List wav = clips[i].wav;
    final Uint8List pcm = wav.length > 44 ? wav.sublist(44) : wav;
    allPcm.add(pcm);
    cursorMs += pcm.length ~/ (StepfunRealtimeTts.sampleRate * 2 ~/ 1000);
    endsMs.add(cursorMs);
    await File(
      '${outDir.path}${Platform.pathSeparator}sent_${(i + 1).toString().padLeft(2, '0')}.wav',
    ).writeAsBytes(wav);
  }
  final File fullWav = File('${outDir.path}${Platform.pathSeparator}full.wav');
  await fullWav.writeAsBytes(StepfunRealtimeTts.wavFromPcm(allPcm.takeBytes()));

  final StringBuffer srt = StringBuffer();
  int start = 0;
  for (int i = 0; i < clips.length; i++) {
    srt
      ..writeln('${i + 1}')
      ..writeln('${_srtTs(start)} --> ${_srtTs(endsMs[i])}')
      ..writeln(clips[i].text)
      ..writeln();
    start = endsMs[i];
  }
  final File srtFile = File('${outDir.path}${Platform.pathSeparator}full.srt');
  await srtFile.writeAsString(srt.toString());

  // Copy the picked image into the managed dir so cleanup is automatic.
  String? coverPath;
  if (imagePath != null && imagePath.isNotEmpty) {
    coverPath =
        '${outDir.path}${Platform.pathSeparator}cover${imagePath.substring(imagePath.lastIndexOf('.'))}';
    await File(imagePath).copy(coverPath);
  }

  String videoPath = '${outDir.path}${Platform.pathSeparator}$baseName.mp4';
  final bool rendered = await _renderVideo(
    wavPath: fullWav.path,
    mp4Path: videoPath,
    imagePath: coverPath,
  );
  if (!rendered) {
    // No ffmpeg on this platform (Android): the concatenated wav still
    // plays as the episode's media track, subtitles included.
    videoPath = fullWav.path;
  }

  return PackagedTextLesson(
    videoPath: videoPath,
    subtitlePath: srtFile.path,
    sentenceCount: clips.length,
    totalSeconds: cursorMs / 1000,
  );
}

Future<bool> _renderVideo({
  required String wavPath,
  required String mp4Path,
  String? imagePath,
}) async {
  final List<String> args = imagePath != null
      ? <String>[
          '-y',
          '-hide_banner',
          '-loglevel',
          'error',
          '-loop',
          '1',
          '-i',
          imagePath,
          '-i',
          wavPath,
          '-vf',
          'scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0x0f172a',
          '-c:v',
          'libx264',
          '-tune',
          'stillimage',
          '-pix_fmt',
          'yuv420p',
          '-c:a',
          'aac',
          '-b:a',
          '128k',
          '-shortest',
          '-movflags',
          '+faststart',
          mp4Path,
        ]
      : <String>[
          '-y',
          '-hide_banner',
          '-loglevel',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=size=1280x720:rate=25:color=0x0f172a',
          '-i',
          wavPath,
          '-filter_complex',
          '[1:a]showwaves=s=1280x360:mode=cline:rate=25:colors=0x38bdf8[v];[0:v][v]overlay=0:180',
          '-shortest',
          '-c:v',
          'libx264',
          '-pix_fmt',
          'yuv420p',
          '-preset',
          'veryfast',
          '-c:a',
          'aac',
          '-b:a',
          '128k',
          '-movflags',
          '+faststart',
          mp4Path,
        ];
  const List<String> candidates = <String>[
    'ffmpeg',
    r'D:\Softwares\ffmpeg-7.1.1-full_build\bin\ffmpeg.exe',
  ];
  Object? lastError;
  for (final String exe in candidates) {
    try {
      final ProcessResult r = await Process.run(exe, args);
      if (r.exitCode == 0) return true;
      lastError = '${r.stderr}'.trim();
      break; // ffmpeg ran but failed — retrying another binary won't help
    } on ProcessException {
      lastError = '$exe 不在 PATH';
    }
  }
  stderr.writeln('ffmpeg 渲染失败: $lastError');
  return false;
}

String _srtTs(int ms) {
  final int h = ms ~/ 3600000;
  final int m = (ms % 3600000) ~/ 60000;
  final int s = (ms % 60000) ~/ 1000;
  final int rem = ms % 1000;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')},${rem.toString().padLeft(3, '0')}';
}
