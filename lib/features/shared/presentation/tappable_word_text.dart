import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pad/app_design_tokens.dart';
import 'word_lookup_popup.dart';

/// Opens the same dictionary card used by subtitle word taps — definition,
/// image, real-voice pronunciation, collect. [contextSentence] gives the
/// lookup service the surrounding line for a better context meaning.
void showWordLookupDialog(
  BuildContext context,
  WidgetRef ref, {
  required String word,
  String? contextSentence,
  String? episodeId,
}) {
  final String cleaned = word.replaceAll(RegExp(r"^[^\w'-]+|[^\w'-]+$"), '');
  if (cleaned.isEmpty) return;
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
          rawWord: cleaned,
          contextSentence: contextSentence ?? '',
          episodeId: episodeId,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
}

/// Renders a sentence as individually tappable words — English tokens get a
/// dotted underline, a hand cursor and a hover tint so it is obvious they can
/// be clicked for the dictionary card. Non-word tokens (pure punctuation or
/// CJK runs without latin letters) render as plain text.
class TappableWordText extends StatelessWidget {
  const TappableWordText({
    required this.text,
    required this.onWordTap,
    this.style,
    super.key,
  });

  final String text;
  final ValueChanged<String> onWordTap;
  final TextStyle? style;

  static final RegExp _latinWord = RegExp('[a-zA-Z]');

  @override
  Widget build(BuildContext context) {
    final List<String> tokens = text
        .split(RegExp(r'\s+'))
        .where((String t) => t.isNotEmpty)
        .toList(growable: false);
    return Wrap(
      spacing: 1,
      runSpacing: 1,
      children: <Widget>[
        for (final String token in tokens)
          _latinWord.hasMatch(token)
              ? _WordToken(
                  token: token,
                  style: style,
                  onTap: () => onWordTap(token),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 1.5,
                    vertical: 1,
                  ),
                  child: Text(token, style: style),
                ),
      ],
    );
  }
}

class _WordToken extends StatefulWidget {
  const _WordToken({required this.token, required this.onTap, this.style});

  final String token;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  State<_WordToken> createState() => _WordTokenState();
}

class _WordTokenState extends State<_WordToken> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final TextStyle base =
        widget.style ?? const TextStyle(fontSize: 13, height: 1.4);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 1),
          decoration: BoxDecoration(
            color: _hovering
                ? AppDesignTokens.brandGreen.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.token,
            style: base.copyWith(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: _hovering
                  ? AppDesignTokens.brandGreenDark
                  : const Color(0xFF9DB8A6),
            ),
          ),
        ),
      ),
    );
  }
}
