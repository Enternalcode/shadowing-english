import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../import_course/domain/import_match.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../text_import/data/lesson_from_text_generator.dart';
import '../data/pattern_ai_service.dart';
import '../data/pattern_book_provider.dart';
import '../domain/sentence_pattern.dart';
import 'widgets/pattern_example_tile.dart';

/// The saved sentence-pattern library: review cards, progressively
/// generate more colloquial examples, or turn a pattern into a real
/// listening/dictation course via the shared TTS pipeline.
class PatternBookDialog extends ConsumerStatefulWidget {
  const PatternBookDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const PatternBookDialog(),
    );
  }

  @override
  ConsumerState<PatternBookDialog> createState() => _PatternBookDialogState();
}

class _PatternBookDialogState extends ConsumerState<PatternBookDialog> {
  String? _busyId;
  String? _busyText;
  String? _notice;

  Future<void> _generateMore(SentencePattern item) async {
    setState(() {
      _busyId = item.id;
      _busyText = '造句中…';
      _notice = null;
    });
    try {
      final List<String> fresh = await ref
          .read(patternAiServiceProvider)
          .generateExamples(
            pattern: item.pattern,
            sourceSentence: item.sourceSentence,
            settings: ref.read(learningSettingsProvider),
          );
      if (!mounted) return;
      final int added = ref
          .read(patternBookProvider.notifier)
          .addExamples(item.id, fresh);
      setState(
        () => _notice = added > 0 ? '「${item.pattern}」新增 $added 句' : '没有新例句了',
      );
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _busyId = null;
          _busyText = null;
        });
      }
    }
  }

  /// Turns the pattern (source sentence + generated examples) into a real
  /// course through the same StepFun TTS + ffmpeg pipeline the text
  /// importer uses, so pattern drills get dictation/shadowing for free.
  Future<void> _generateLesson(SentencePattern item) async {
    final String key = Hive.isBoxOpen('prefs')
        ? Hive.box<String>('prefs').get('stepfun_rt_key') ?? ''
        : '';
    if (key.isEmpty) {
      setState(() => _notice = '先在「文本录入」里填一次 StepFun API Key');
      return;
    }
    final List<String> sentences = <String>[
      item.sourceSentence,
      ...item.examples,
    ];
    setState(() {
      _busyId = item.id;
      _busyText = '生成练习课…';
      _notice = null;
    });
    try {
      final Directory support = await getApplicationSupportDirectory();
      final String slug = slugifyLessonName(item.pattern);
      final Directory outDir = Directory(
        '${support.path}${Platform.pathSeparator}imported_sources'
        '${Platform.pathSeparator}pattern_lessons'
        '${Platform.pathSeparator}${slug}_${DateTime.now().millisecondsSinceEpoch % 100000}',
      );
      final LessonGenerationResult generated =
          await generateLessonFromSentences(
            sentences: sentences,
            apiKey: key,
            voice: 'qingchunshaonv',
            outDir: outDir,
            baseName: slug,
            onStep: (String step) => setState(() => _busyText = step),
          );
      if (!mounted) return;
      final bool ok = await ref
          .read(libraryCatalogProvider.notifier)
          .importCourseFromMatches(
            rows: <ImportMatchRow>[
              ImportMatchRow(
                episodeName: '句式：${item.pattern}',
                videoFile: '$slug.mp4',
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
            sourceLabel: '句式库',
            courseTitle: '句式练习 · ${item.pattern}',
          );
      if (!mounted) return;
      setState(
        () => _notice = ok
            ? '练习课已生成（${generated.clipCount}/${generated.totalCount} 句）→ 课程库可见'
            : '课程注册失败',
      );
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _busyId = null;
          _busyText = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<SentencePattern> patterns = ref.watch(patternBookProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.menu_book_rounded, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    '句式库',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${patterns.length} 个句式',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: patterns.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有收藏的句式\n\n在课程里点字幕行 ··· →「拆解句式」→ 收藏句式',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.7,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: patterns.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (BuildContext context, int i) =>
                            _PatternCard(
                              item: patterns[i],
                              busy: _busyId == patterns[i].id,
                              busyText: _busyId == patterns[i].id
                                  ? _busyText
                                  : null,
                              onGenerateMore: () => _generateMore(patterns[i]),
                              onGenerateLesson: () =>
                                  _generateLesson(patterns[i]),
                              onRemoveExample: (int idx) => ref
                                  .read(patternBookProvider.notifier)
                                  .removeExample(patterns[i].id, idx),
                              onDelete: () => ref
                                  .read(patternBookProvider.notifier)
                                  .removePattern(patterns[i].id),
                            ),
                      ),
              ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _notice!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatternCard extends StatelessWidget {
  const _PatternCard({
    required this.item,
    required this.busy,
    required this.busyText,
    required this.onGenerateMore,
    required this.onGenerateLesson,
    required this.onRemoveExample,
    required this.onDelete,
  });

  final SentencePattern item;
  final bool busy;
  final String? busyText;
  final VoidCallback onGenerateMore;
  final VoidCallback onGenerateLesson;
  final ValueChanged<int> onRemoveExample;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  item.pattern,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.brandGreenDark,
                  ),
                ),
              ),
              IconButton(
                iconSize: 18,
                tooltip: '删除句式',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          if (item.explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.explanation,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              item.sourceSentence,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
          if (item.examples.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            for (int i = 0; i < item.examples.length; i += 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: PatternExampleTile(
                        index: i + 1,
                        sentence: item.examples[i],
                      ),
                    ),
                    InkWell(
                      onTap: () => onRemoveExample(i),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: busy ? null : onGenerateMore,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
                label: const Text('再造几句'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onGenerateLesson,
                icon: const Icon(Icons.graphic_eq_rounded, size: 15),
                label: const Text('生成练习课'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (busy)
                Text(
                  busyText ?? '处理中…',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
