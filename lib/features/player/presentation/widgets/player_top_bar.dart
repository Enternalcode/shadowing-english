import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/presentation/dictionary_search_dialog.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/tappable_word_text.dart';

class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    required this.courseTitle,
    required this.episodeTitle,
    this.episodeName,
    this.streakText = '0 Day Streak',
    required this.onBack,
    this.onTranscriptPressed,
    this.onLearningGuidePressed,
    this.onStatsPressed,
    super.key,
  });

  final String courseTitle;
  final String episodeTitle;
  final String? episodeName;
  final String streakText;
  final VoidCallback onBack;
  final VoidCallback? onTranscriptPressed;
  final VoidCallback? onLearningGuidePressed;
  final VoidCallback? onStatsPressed;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.paddingOf(context).top;
    final double windowControlsInset =
        defaultTargetPlatform == TargetPlatform.macOS ? 28 : 0;
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 1180;
    final bool tiny = width < 820;
    final bool phone = width < 600;
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final double contentHeight = math.max(
      tiny ? 52 : (compact ? 60 : 72),
      textScaler.scale(tiny ? 18 : (compact ? 20 : 24)) * 1.4 +
          textScaler.scale(11) * 1.4 +
          12,
    );

    return Container(
      height: contentHeight + topInset + windowControlsInset,
      padding: EdgeInsets.fromLTRB(
        tiny ? 12 : (compact ? 16 : 22),
        topInset + windowControlsInset + (tiny ? 2 : 6),
        tiny ? 12 : (compact ? 16 : 22),
        0,
      ),
      color: Colors.transparent,
      child: Row(
        children: <Widget>[
          Tooltip(
            message: '返回上一页',
            child: TextButton(
              onPressed: onBack,
              style: TextButton.styleFrom(
                backgroundColor: AppDesignTokens.appWhite,
                foregroundColor: AppDesignTokens.brandGreenDark,
                minimumSize: Size(tiny ? 38 : 44, tiny ? 38 : 44),
                padding: EdgeInsets.zero,
                side: const BorderSide(color: AppDesignTokens.borderGray),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tiny ? 12 : 14),
                ),
                elevation: 0,
              ),
              child: Icon(Icons.arrow_back_rounded, size: tiny ? 16 : 18),
            ),
          ),
          SizedBox(width: tiny ? 8 : (compact ? 10 : 12)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          phone ? episodeTitle : '英语学习空间',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          courseTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: tiny ? 18 : (compact ? 20 : 24),
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF172033),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!phone) SizedBox(width: tiny ? 8 : 10),
                  if (!phone)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: tiny ? 8 : 10,
                        vertical: tiny ? 3 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        episodeTitle,
                        style: TextStyle(
                          fontSize: tiny ? 10 : 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF047857),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _PlayerTopStatus(
            episodeName: episodeName,
            streakText: streakText,
            onTranscriptPressed: onTranscriptPressed,
            onLearningGuidePressed: onLearningGuidePressed,
            onStatsPressed: onStatsPressed,
          ),
        ],
      ),
    );
  }
}

class _PlayerTopStatus extends StatelessWidget {
  const _PlayerTopStatus({
    required this.streakText,
    this.episodeName,
    this.onTranscriptPressed,
    this.onLearningGuidePressed,
    this.onStatsPressed,
  });

  final String? episodeName;
  final String streakText;
  final VoidCallback? onTranscriptPressed;
  final VoidCallback? onLearningGuidePressed;
  final VoidCallback? onStatsPressed;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 1180;
    final bool phone = MediaQuery.sizeOf(context).width < 600;

    if (phone) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: () => DictionarySearchDialog.show(context),
            tooltip: '查词典',
            icon: const Icon(Icons.search_rounded),
          ),
          if (onTranscriptPressed != null)
            IconButton(
              onPressed: onTranscriptPressed,
              tooltip: '全文阅读',
              icon: const Icon(Icons.menu_book_outlined),
            ),
          if (onLearningGuidePressed != null)
            IconButton(
              onPressed: onLearningGuidePressed,
              tooltip: '怎么学',
              icon: const Icon(Icons.school_outlined),
            ),
          IconButton(
            onPressed: onStatsPressed,
            tooltip: '查看学习统计',
            icon: const Icon(Icons.timer_outlined),
          ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 320 : 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (episodeName != null && episodeName!.isNotEmpty)
            Flexible(
              child: Text(
                '场景 · ${episodeName!}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          if (episodeName != null && episodeName!.isNotEmpty)
            const SizedBox(width: 14),
          Tooltip(
            message: streakText,
            child: const Icon(
              Icons.local_fire_department_outlined,
              size: 22,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 10),
          const _DictSearchField(),
          if (onTranscriptPressed != null)
            TextButton.icon(
              onPressed: onTranscriptPressed,
              icon: const Icon(
                Icons.menu_book_outlined,
                size: 18,
                color: AppDesignTokens.brandGreenDark,
              ),
              label: const Text('全文阅读'),
              style: TextButton.styleFrom(
                foregroundColor: AppDesignTokens.brandGreenDark,
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (onLearningGuidePressed != null)
            TextButton.icon(
              onPressed: onLearningGuidePressed,
              icon: const Icon(Icons.school_outlined, size: 18),
              label: const Text('怎么学'),
              style: TextButton.styleFrom(
                foregroundColor: AppDesignTokens.brandGreenDark,
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            onPressed: onStatsPressed,
            tooltip: '查看学习统计',
            icon: const Icon(
              Icons.timer_outlined,
              size: 22,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact inline dictionary lookup living in the top bar — type a word,
/// hit Enter, the shared dictionary card opens. No intermediate dialog.
class _DictSearchField extends StatefulWidget {
  const _DictSearchField();

  @override
  State<_DictSearchField> createState() => _DictSearchFieldState();
}

class _DictSearchFieldState extends State<_DictSearchField> {
  final TextEditingController _controller = TextEditingController();

  void _submit() {
    final String word = _controller.text.trim().replaceAll(
      RegExp(r"^[^\w'-]+|[^\w'-]+$"),
      '',
    );
    if (word.isEmpty) return;
    _controller.clear();
    showWordLookupDialog(context, word: word);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 34,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _submit(),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: '查词',
          hintStyle: const TextStyle(
            fontSize: 13,
            color: AppDesignTokens.textSecondary,
          ),
          isDense: true,
          filled: true,
          fillColor: AppDesignTokens.appWhite,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 28,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 16,
            color: AppDesignTokens.textSecondary,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: AppDesignTokens.borderGray),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: AppDesignTokens.borderGray),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(
              color: AppDesignTokens.brandGreen,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
