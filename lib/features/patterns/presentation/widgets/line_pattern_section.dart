import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/tappable_word_text.dart';
import '../../data/line_pattern_store.dart';
import '../../data/pattern_book_provider.dart';
import '../../domain/sentence_pattern.dart';
import 'pattern_example_tile.dart';

/// Inline sentence-pattern block rendered directly under a subtitle line —
/// no floating dialog. Collapsed it is a one-row chip ("句式 · accuse sb of
/// doing sth"); tapping expands the full note (pattern, slots, explanation,
/// generated spoken examples with TTS + tap-to-translate, and the save /
/// drill / re-analyze actions). The note persists in Hive.
///
/// Trigger analysis from anywhere via:
///   ref.read(patternAnalysisJobsProvider.notifier).request(
///     key: linePatternKey(episodeId, index), sentence: line.english);
class LinePatternSection extends ConsumerStatefulWidget {
  const LinePatternSection({
    required this.episodeId,
    required this.lineIndex,
    required this.sentence,
    this.courseTitle,
    this.maskTitle = false,
    super.key,
  });

  final String episodeId;
  final int lineIndex;
  final String sentence;
  final String? courseTitle;

  /// Hides the pattern text in the collapsed row — the pattern is part of
  /// the answer, so blind-dictation shows a generic label until expanded.
  final bool maskTitle;

  @override
  ConsumerState<LinePatternSection> createState() => _LinePatternSectionState();
}

class _LinePatternSectionState extends ConsumerState<LinePatternSection> {
  bool _expanded = false;
  bool _wasPending = false;

  String get _key => linePatternKey(widget.episodeId, widget.lineIndex);

  void _save() {
    final LinePatternNote? note = ref.read(linePatternProvider(_key)).value;
    if (note == null) return;
    ref
        .read(patternBookProvider.notifier)
        .addPattern(
          pattern: note.pattern,
          explanation: note.explanation,
          sourceSentence: widget.sentence,
          episodeId: widget.episodeId,
          courseTitle: widget.courseTitle,
          slots: note.slots,
          grammar: note.grammar,
          examples: note.examples,
        );
  }

  @override
  Widget build(BuildContext context) {
    final LinePatternNote? note = ref.watch(linePatternProvider(_key)).value;
    final PatternJobs jobs = ref.watch(patternAnalysisJobsProvider);
    final bool pending = jobs.pending.contains(_key);
    final String? error = jobs.errors[_key];

    // Reveal the result automatically right after a user-triggered dissect.
    if (_wasPending && !pending && note != null) _expanded = true;
    _wasPending = pending;

    if (note == null && !pending && error == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: AppDesignTokens.brandGreen.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppDesignTokens.brandGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: <Widget>[
                  if (pending)
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(
                      Icons.schema_outlined,
                      size: 14,
                      color: AppDesignTokens.brandGreenDark,
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pending
                          ? '正在拆解句式…'
                          : note == null
                          ? '拆解失败，点击展开重试'
                          : widget.maskTitle
                          ? '句式拆解 · 点击查看'
                          : note.pattern,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.brandGreenDark,
                      ),
                    ),
                  ),
                  if (note != null && note.examples.isNotEmpty && !_expanded)
                    Text(
                      '${note.examples.length} 例句',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: AppDesignTokens.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: _expandedBody(note, pending, error),
            ),
        ],
      ),
    );
  }

  void _openWordLookup(String token) => showWordLookupDialog(
    context,
    word: token,
    contextSentence: widget.sentence,
    episodeId: widget.episodeId,
  );

  /// Bold CJK label followed by a word-tappable body — the AI writes grammar /
  /// slot notes mixing Chinese labels with English words ("介词 for 的宾语"),
  /// so every latin token inside is clickable for the dictionary card.
  Widget _tappableLabeled(
    String label,
    String body,
    TextStyle bodyStyle, {
    Color labelColor = AppDesignTokens.brandGreenDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: bodyStyle.copyWith(
            fontWeight: FontWeight.w800,
            color: labelColor,
          ),
        ),
        Expanded(
          child: TappableWordText(
            text: body,
            style: bodyStyle,
            onWordTap: _openWordLookup,
          ),
        ),
      ],
    );
  }

  Widget _expandedBody(LinePatternNote? note, bool pending, String? error) {
    if (note == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (pending)
            const Text(
              'AI 正在提取句式…',
              style: TextStyle(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
              ),
            )
          else ...<Widget>[
            Text(
              error ?? '还没有拆解结果',
              style: const TextStyle(fontSize: 12, color: Color(0xFFD4380D)),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => unawaited(
                ref
                    .read(patternAnalysisJobsProvider.notifier)
                    .request(key: _key, sentence: widget.sentence, force: true),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('重试拆解'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      );
    }

    final bool saved = ref
        .watch(patternBookProvider)
        .any(
          (SentencePattern p) =>
              p.pattern == note.pattern && p.sourceSentence == widget.sentence,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          note.pattern,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.brandGreenDark,
          ),
        ),
        if (note.slots.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          _tappableLabeled(
            '套入：',
            note.slots,
            const TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
          ),
        ],
        if (note.explanation.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          TappableWordText(
            text: note.explanation,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
            onWordTap: _openWordLookup,
          ),
        ],
        if (note.grammar.isNotEmpty) ...<Widget>[
          const SizedBox(height: 5),
          _tappableLabeled(
            '语法：',
            note.grammar,
            const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppDesignTokens.textSecondary,
            ),
            labelColor: const Color(0xFF7C5E10),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: saved ? null : _save,
              icon: Icon(
                saved
                    ? Icons.bookmark_added_rounded
                    : Icons.bookmark_add_rounded,
                size: 15,
              ),
              label: Text(saved ? '已收藏' : '收藏句式'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
            OutlinedButton.icon(
              onPressed: pending
                  ? null
                  : () => unawaited(
                      ref
                          .read(patternAnalysisJobsProvider.notifier)
                          .generateMore(
                            key: _key,
                            note: note,
                            sourceSentence: widget.sentence,
                          ),
                    ),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
              label: const Text('再造几句'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
            TextButton.icon(
              onPressed: pending
                  ? null
                  : () => unawaited(
                      ref
                          .read(patternAnalysisJobsProvider.notifier)
                          .request(
                            key: _key,
                            sentence: widget.sentence,
                            force: true,
                          ),
                    ),
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('重新拆解'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            if (pending)
              const SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            error,
            style: const TextStyle(fontSize: 11, color: Color(0xFFD4380D)),
          ),
        ],
        if (note.examples.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 230),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: note.examples.length,
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: PatternExampleTile(
                  index: i + 1,
                  sentence: note.examples[i],
                  episodeId: widget.episodeId,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
