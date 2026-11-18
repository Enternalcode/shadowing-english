import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pad/app_design_tokens.dart';
import 'word_lookup_popup.dart';

/// Global dictionary entry point: a search field on top of the same
/// [WordLookupPopupCard] used by subtitle word taps, so looking up a word is
/// one identical experience everywhere in the app. Open from anywhere via
/// [DictionarySearchDialog.show].
class DictionarySearchDialog extends StatefulWidget {
  const DictionarySearchDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const DictionarySearchDialog(),
    );
  }

  @override
  State<DictionarySearchDialog> createState() => _DictionarySearchDialogState();
}

class _DictionarySearchDialogState extends State<DictionarySearchDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _word;

  void _submit() {
    final String word = _controller.text.trim().replaceAll(
      RegExp(r"^[^\w'-]+|[^\w'-]+$"),
      '',
    );
    if (word.isEmpty) return;
    setState(() => _word = word);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double cardMaxHeight = (MediaQuery.sizeOf(context).height - 210)
        .clamp(220.0, 520.0);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(
              maxWidth: WordLookupPopupCard.preferredWidth + 16,
            ),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 8),
                const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppDesignTokens.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(LogicalKeyboardKey.enter): _submit,
                      const SingleActivator(LogicalKeyboardKey.numpadEnter):
                          _submit,
                    },
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        hintText: '输入单词查词典，回车查询',
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _submit,
                  tooltip: '查询',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.translate_rounded,
                    color: AppDesignTokens.brandGreenDark,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: _word == null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.appWhite.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      '和字幕点词共用同一套词典：离线 ECDICT 释义 + 词图例句 + 真人发音，可查短语与生词收藏。',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  )
                : WordLookupPopupCard(
                    key: ValueKey<String>(_word!),
                    rawWord: _word!,
                    contextSentence: '',
                    maxHeight: cardMaxHeight,
                    onClose: () => Navigator.of(context).pop(),
                  ),
          ),
        ],
      ),
    );
  }
}
