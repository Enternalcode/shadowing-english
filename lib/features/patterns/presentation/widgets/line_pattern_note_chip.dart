import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../data/line_pattern_store.dart';
import '../pattern_analysis_dialog.dart';

/// Inline "已拆解" block rendered under a subtitle line once its pattern has
/// been analyzed. Persists in Hive, so the note survives restarts and appears
/// wherever the line is listed. Tap re-opens the full analysis dialog.
class LinePatternNoteChip extends ConsumerWidget {
  const LinePatternNoteChip({
    required this.episodeId,
    required this.lineIndex,
    required this.sentence,
    this.courseTitle,
    super.key,
  });

  final String episodeId;
  final int lineIndex;
  final String sentence;
  final String? courseTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<LinePatternNote?> note = ref.watch(
      linePatternProvider(linePatternKey(episodeId, lineIndex)),
    );
    final LinePatternNote? value = note.value;
    if (value == null) return const SizedBox.shrink();
    return InkWell(
      onTap: () => unawaited(
        PatternAnalysisDialog.show(
          context,
          sentence: sentence,
          episodeId: episodeId,
          lineIndex: lineIndex,
          courseTitle: courseTitle,
        ),
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            Row(
              children: <Widget>[
                const Icon(
                  Icons.schema_outlined,
                  size: 14,
                  color: AppDesignTokens.brandGreenDark,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    value.pattern,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.brandGreenDark,
                    ),
                  ),
                ),
                if (value.examples.isNotEmpty)
                  Text(
                    '${value.examples.length} 例句',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
              ],
            ),
            if (value.explanation.isNotEmpty) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                value.explanation,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
