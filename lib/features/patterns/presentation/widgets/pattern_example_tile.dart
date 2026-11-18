import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/settings_provider.dart';
import '../../../shared/data/word_lookup_service.dart';
import '../../../shared/data/word_pronunciation_service.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';

/// One generated drill example: numbered English sentence, 🔊 button for TTS,
/// and tap-to-translate (lazy, cached per tile) via the configured provider.
class PatternExampleTile extends ConsumerStatefulWidget {
  const PatternExampleTile({
    required this.index,
    required this.sentence,
    super.key,
  });

  final int index;
  final String sentence;

  @override
  ConsumerState<PatternExampleTile> createState() => _PatternExampleTileState();
}

class _PatternExampleTileState extends ConsumerState<PatternExampleTile> {
  String? _translation;
  bool _translating = false;
  bool _expanded = false;

  Future<void> _toggleTranslation() async {
    if (_translating) return;
    if (_translation != null) {
      setState(() => _expanded = !_expanded);
      return;
    }
    setState(() {
      _translating = true;
      _expanded = true;
    });
    try {
      final String? zh = await ref
          .read(wordLookupServiceProvider)
          .translateSentence(
            sentence: widget.sentence,
            settings: ref.read(learningSettingsProvider),
          );
      if (!mounted) return;
      setState(() => _translation = zh ?? '（翻译失败，请检查翻译接口配置）');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${widget.index}.',
              style: const TextStyle(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: _toggleTranslation,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    widget.sentence,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () => unawaited(
                ref
                    .read(wordPronunciationServiceProvider)
                    .speak(widget.sentence),
              ),
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.volume_up_rounded,
                  size: 16,
                  color: AppDesignTokens.brandGreenDark,
                ),
              ),
            ),
          ],
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 2),
            child: _translating
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _translation ?? '点句子翻译',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                      height: 1.4,
                    ),
                  ),
          ),
      ],
    );
  }
}
