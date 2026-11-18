import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/settings_provider.dart';
import '../../../shared/data/word_lookup_service.dart';
import '../../../shared/data/word_pronunciation_service.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/tappable_word_text.dart';

/// One generated drill example: numbered English sentence whose words are
/// individually tappable — tap a word to open the same dictionary card used
/// in subtitles (definition + image + real-voice pronunciation + collect).
/// Trailing 🔊 plays the whole sentence; 「译」lazy-translates via the
/// configured provider and caches the result per tile.
class PatternExampleTile extends ConsumerStatefulWidget {
  const PatternExampleTile({
    required this.index,
    required this.sentence,
    this.episodeId,
    super.key,
  });

  final int index;
  final String sentence;
  final String? episodeId;

  @override
  ConsumerState<PatternExampleTile> createState() => _PatternExampleTileState();
}

class _PatternExampleTileState extends ConsumerState<PatternExampleTile> {
  String? _translation;
  bool _translating = false;
  bool _expanded = false;

  void _openWordLookup(String token) => showWordLookupDialog(
    context,
    word: token,
    contextSentence: widget.sentence,
    episodeId: widget.episodeId,
  );

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
              child: TappableWordText(
                text: widget.sentence,
                style: const TextStyle(fontSize: 13, height: 1.4),
                onWordTap: _openWordLookup,
              ),
            ),
            _IconAction(
              tooltip: '朗读整句',
              icon: Icons.volume_up_rounded,
              onTap: () => unawaited(
                ref
                    .read(wordPronunciationServiceProvider)
                    .speak(widget.sentence),
              ),
            ),
            _IconAction(
              tooltip: '翻译整句',
              icon: Icons.translate_rounded,
              onTap: _toggleTranslation,
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
                    _translation ?? '点「译」翻译',
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

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 16, color: AppDesignTokens.brandGreenDark),
        ),
      ),
    );
  }
}
