import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../import_course/domain/import_match.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../text_import/data/lesson_from_text_generator.dart';
import '../domain/story.dart';

/// Runs a saved story's spoken lines through the StepFun TTS + packager
/// pipeline and registers the result as a course. Returns a human-readable
/// status message. On desktop ffmpeg renders an mp4 with the first page
/// photo as the still frame; elsewhere the wav fallback keeps it audio-only.
Future<String> generateStoryLesson({
  required WidgetRef ref,
  required StoryRecord story,
  void Function(String step)? onStep,
}) async {
  final String key = Hive.isBoxOpen('prefs')
      ? Hive.box<String>('prefs').get('stepfun_rt_key') ?? ''
      : '';
  if (key.isEmpty) {
    throw StateError('先在「文本录入」里填一次 StepFun API Key');
  }
  final List<String> sentences = story.practiceSentences;
  if (sentences.isEmpty) throw StateError('没有可合成的句子');

  final Directory support = await getApplicationSupportDirectory();
  final String slug = slugifyLessonName(story.title);
  final Directory outDir = Directory(
    '${support.path}${Platform.pathSeparator}imported_sources'
    '${Platform.pathSeparator}story_lessons'
    '${Platform.pathSeparator}${slug}_${DateTime.now().millisecondsSinceEpoch % 100000}',
  );
  final String cover = story.pages
      .map((StoryPage p) => p.imagePath)
      .firstWhere((String p) => p.isNotEmpty, orElse: () => '');
  final LessonGenerationResult generated = await generateLessonFromSentences(
    sentences: sentences,
    apiKey: key,
    voice: 'qingchunshaonv',
    outDir: outDir,
    baseName: slug,
    imagePath: cover.isEmpty ? null : cover,
    onStep: onStep,
  );
  final String mediaName = generated.pkg.videoPath
      .split(Platform.pathSeparator)
      .last;
  final bool ok = await ref
      .read(libraryCatalogProvider.notifier)
      .importCourseFromMatches(
        rows: <ImportMatchRow>[
          ImportMatchRow(
            episodeName: '绘本带读：${story.title}',
            videoFile: mediaName,
            videoPath: generated.pkg.videoPath,
            subtitleTracks: <String, ImportSubtitleTrack>{
              'en': ImportSubtitleTrack(
                languageCode: 'en',
                languageLabel: '英文',
                path: generated.pkg.subtitlePath,
              ),
            },
          ),
        ],
        videoFolder: outDir.path,
        subtitleFolder: outDir.path,
        sourceLabel: '绘本带读',
        courseTitle: '绘本带读 · ${story.title}',
      );
  if (!ok) throw StateError('课程注册失败');
  return '练习课已生成（${generated.clipCount}/${generated.totalCount} 句）→ 课程库可见';
}
