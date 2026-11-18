import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/settings_provider.dart';
import '../../../shared/data/word_lookup_service.dart';
import '../../../shared/data/word_pronunciation_service.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';

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

  /// Strips edge punctuation for lookup while the original token stays on
  /// screen — "brewing." → brewing, "shop's" → shop's.
  String _lookupWord(String token) =>
      token.replaceAll(RegExp(r"^[^\w'-]+|[^\w'-]+$"), '');

  void _openWordLookup(String token) {
    final String word = _lookupWord(token);
    if (word.isEmpty) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: WordLookupPopupCard.preferredWidth + 16,
              maxHeight: 560,
            ),
            child: WordLookupPopupCard(
              rawWord: word,
              contextSentence: widget.sentence,
              episodeId: widget.episodeId,
              onClose: () => Navigator.of(dialogContext).pop(),
              onPronounce: () => unawaited(
                ref.read(wordPronunciationServiceProvider).speak(word),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
    final List<String> tokens = widget.sentence
        .split(' ')
        .where((String t) => t.isNotEmpty)
        .toList(growable: false);
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
              child: Wrap(
                spacing: 1,
                runSpacing: 1,
                children: <Widget>[
                  for (final String token in tokens)
                    _WordToken(
                      token: token,
                      onTap: () => _openWordLookup(token),
                    ),
                ],
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

class _WordToken extends StatelessWidget {
  const _WordToken({required this.token, required this.onTap});

  final String token;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 1),
        child: Text(
          token,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: Color(0xFF9DB8A6),
          ),
        ),
      ),
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
