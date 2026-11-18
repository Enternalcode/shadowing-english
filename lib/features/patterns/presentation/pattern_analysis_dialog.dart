import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/line_pattern_store.dart';
import '../data/pattern_ai_service.dart';
import '../data/pattern_book_provider.dart';
import '../domain/sentence_pattern.dart';
import 'widgets/pattern_example_tile.dart';

/// "拆解句式" — dissects one subtitle line into a reusable spoken pattern.
/// The card can be saved to the pattern book, and "再造几句" progressively
/// appends everyday spoken examples drilled on the same pattern.
class PatternAnalysisDialog extends ConsumerStatefulWidget {
  const PatternAnalysisDialog({
    required this.sentence,
    this.episodeId,
    this.lineIndex,
    this.courseTitle,
    super.key,
  });

  final String sentence;
  final String? episodeId;
  final int? lineIndex;
  final String? courseTitle;

  static Future<void> show(
    BuildContext context, {
    required String sentence,
    String? episodeId,
    int? lineIndex,
    String? courseTitle,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PatternAnalysisDialog(
        sentence: sentence,
        episodeId: episodeId,
        lineIndex: lineIndex,
        courseTitle: courseTitle,
      ),
    );
  }

  @override
  ConsumerState<PatternAnalysisDialog> createState() =>
      _PatternAnalysisDialogState();
}

class _PatternAnalysisDialogState extends ConsumerState<PatternAnalysisDialog> {
  PatternAnalysis? _analysis;
  final List<String> _pendingExamples = <String>[];
  String? _savedId;
  bool _analyzing = true;
  bool _generating = false;
  String? _error;

  String? get _lineKey => widget.episodeId == null || widget.lineIndex == null
      ? null
      : linePatternKey(widget.episodeId!, widget.lineIndex!);

  @override
  void initState() {
    super.initState();
    unawaited(_loadOrAnalyze());
  }

  /// Reuses the persisted note when this line was already dissected — reopen
  /// is instant and free. Otherwise calls the AI and archives the result.
  Future<void> _loadOrAnalyze() async {
    final String? key = _lineKey;
    if (key != null) {
      final LinePatternNote? saved = await readLinePatternNote(key);
      if (saved != null && mounted) {
        setState(() {
          _analysis = PatternAnalysis(
            pattern: saved.pattern,
            slots: saved.slots,
            explanation: saved.explanation,
          );
          _pendingExamples.addAll(saved.examples);
          _analyzing = false;
        });
        return;
      }
    }
    if (mounted) await _analyze();
  }

  Future<void> _analyze() async {
    try {
      final PatternAnalysis result = await ref
          .read(patternAiServiceProvider)
          .analyze(
            sentence: widget.sentence,
            settings: ref.read(learningSettingsProvider),
          );
      if (!mounted) return;
      setState(() {
        _analysis = result;
        _analyzing = false;
      });
      final String? key = _lineKey;
      if (key != null) {
        unawaited(
          saveLinePatternNote(
            key,
            LinePatternNote(
              pattern: result.pattern,
              slots: result.slots,
              explanation: result.explanation,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _analyzing = false;
      });
    }
  }

  /// Forces a fresh AI pass over the cached note.
  void _reanalyze() {
    setState(() {
      _analyzing = true;
      _analysis = null;
      _pendingExamples.clear();
      _error = null;
    });
    unawaited(_analyze());
  }

  void _save() {
    final PatternAnalysis? a = _analysis;
    if (a == null || _savedId != null) return;
    final SentencePattern entry = ref
        .read(patternBookProvider.notifier)
        .addPattern(
          pattern: a.pattern,
          explanation: a.explanation,
          sourceSentence: widget.sentence,
          episodeId: widget.episodeId,
          courseTitle: widget.courseTitle,
          slots: a.slots,
          examples: _pendingExamples,
        );
    setState(() => _savedId = entry.id);
  }

  Future<void> _generateMore() async {
    final PatternAnalysis? a = _analysis;
    if (a == null || _generating) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final List<String> fresh = await ref
          .read(patternAiServiceProvider)
          .generateExamples(
            pattern: a.pattern,
            sourceSentence: widget.sentence,
            settings: ref.read(learningSettingsProvider),
          );
      if (!mounted) return;
      if (_savedId != null) {
        ref.read(patternBookProvider.notifier).addExamples(_savedId!, fresh);
      } else {
        final Set<String> have = _pendingExamples
            .map((String e) => e.toLowerCase())
            .toSet();
        for (final String e in fresh) {
          if (have.add(e.toLowerCase())) _pendingExamples.add(e);
        }
        setState(() {});
      }
      final String? key = _lineKey;
      if (key != null) {
        unawaited(
          saveLinePatternNote(
            key,
            LinePatternNote(
              pattern: a.pattern,
              slots: a.slots,
              explanation: a.explanation,
            ),
            newExamples: fresh,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> examples = _savedId == null
        ? _pendingExamples
        : ref
                  .watch(patternBookProvider)
                  .where((SentencePattern p) => p.id == _savedId)
                  .firstOrNull
                  ?.examples ??
              _pendingExamples;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.schema_outlined, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    '句式拆解',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.sentence,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppDesignTokens.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              Expanded(
                child: _analyzing
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            CircularProgressIndicator(strokeWidth: 2.4),
                            SizedBox(height: 10),
                            Text('正在拆解句式…', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      )
                    : _analysis == null
                    ? Center(child: _ErrorText(_error ?? '拆解失败'))
                    : _buildResult(examples),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult(List<String> examples) {
    final PatternAnalysis a = _analysis!;
    return ListView(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppDesignTokens.brandGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppDesignTokens.brandGreen.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                a.pattern,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.brandGreenDark,
                ),
              ),
              if (a.slots.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '套入：${a.slots}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
              if (a.explanation.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  a.explanation,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _savedId == null ? _save : null,
              icon: Icon(
                _savedId == null
                    ? Icons.bookmark_add_rounded
                    : Icons.bookmark_added_rounded,
                size: 16,
              ),
              label: Text(_savedId == null ? '收藏句式' : '已收藏'),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreen,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _generating ? null : _generateMore,
              icon: _generating
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline_rounded, size: 16),
              label: Text(_generating ? '造句中…' : '再造几句（口语版）'),
            ),
            if (_lineKey != null)
              TextButton.icon(
                onPressed: _generating ? null : _reanalyze,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重新拆解'),
              ),
          ],
        ),
        if (examples.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            '同句式例句（贴近生活口语）',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < examples.length; i += 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: PatternExampleTile(index: i + 1, sentence: examples[i]),
            ),
        ],
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Color(0xFFD4380D)),
      ),
    );
  }
}
