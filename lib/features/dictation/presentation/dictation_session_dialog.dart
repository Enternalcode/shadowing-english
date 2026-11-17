import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/dictation_stats_store.dart';
import '../domain/dictation_diff.dart';

class DictationLine {
  const DictationLine({required this.english, this.chinese = ''});

  final String english;
  final String chinese;
}

/// Sentence-level blind dictation: listen → type (spaces optional) → Enter to
/// check → word-level diff → Enter again for the next line. Mirrors the
/// english-trainer blind-listen interaction, fully local.
class DictationSessionDialog extends ConsumerStatefulWidget {
  const DictationSessionDialog({
    required this.lines,
    required this.onPlayLine,
    this.startIndex = 0,
    super.key,
  });

  final List<DictationLine> lines;
  final void Function(int index) onPlayLine;
  final int startIndex;

  @override
  ConsumerState<DictationSessionDialog> createState() =>
      _DictationSessionDialogState();
}

class _DictationSessionDialogState
    extends ConsumerState<DictationSessionDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  int _index = 0;
  bool _checked = false;
  bool _showAnswer = false;
  bool _finished = false;
  DictationScore? _score;
  DictationDayStats? _today;

  int _sessionAttempts = 0;
  int _sessionCorrect = 0;
  int _sessionTotal = 0;
  final Map<String, int> _sessionErrors = <String, int>{};

  DictationLine get _line => widget.lines[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex.clamp(0, widget.lines.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLine(_index));
    _refreshToday();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _refreshToday() async {
    final DictationDayStats stats = await ref
        .read(dictationStatsStoreProvider)
        .today();
    if (mounted) setState(() => _today = stats);
  }

  void _openLine(int index) {
    setState(() {
      _index = index;
      _checked = false;
      _showAnswer = false;
      _score = null;
      _controller.clear();
    });
    widget.onPlayLine(index);
    _focusNode.requestFocus();
  }

  void _primaryAction() {
    if (_finished) return;
    if (!_checked) {
      _check();
    } else {
      _advance();
    }
  }

  void _check() {
    final DictationScore score = scoreDictation(
      _line.english,
      _controller.text,
    );
    setState(() {
      _checked = true;
      _showAnswer = true;
      _score = score;
      _sessionAttempts++;
      _sessionCorrect += score.correct;
      _sessionTotal += score.total;
      for (final String w in score.wrongWords) {
        _sessionErrors[w] = (_sessionErrors[w] ?? 0) + 1;
      }
      for (final String w in score.missedWords) {
        _sessionErrors[w] = (_sessionErrors[w] ?? 0) + 1;
      }
    });
    unawaited(
      ref
          .read(dictationStatsStoreProvider)
          .record(
            correct: score.correct,
            total: score.total,
            wrongWords: score.wrongWords,
            missedWords: score.missedWords,
          )
          .then((_) => _refreshToday()),
    );
    _focusNode.requestFocus();
  }

  void _advance() {
    if (_index + 1 < widget.lines.length) {
      _openLine(_index + 1);
    } else {
      setState(() => _finished = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: _finished ? _buildSummary() : _buildSession(),
        ),
      ),
    );
  }

  Widget _buildSession() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '听写练习',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 8),
            Text(
              '${_index + 1} / ${widget.lines.length}',
              style: const TextStyle(color: AppDesignTokens.textSecondary),
            ),
            const Spacer(),
            IconButton(
              tooltip: '重播本句',
              onPressed: () => widget.onPlayLine(_index),
              icon: const Icon(Icons.volume_up_rounded),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _checked
              ? '继续输入可重新校验，Enter 进入下一句'
              : '听音频输入句子，可以不打空格；Enter 校验',
          style: const TextStyle(
            fontSize: 12,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) {
            if (_checked) setState(() => _checked = false);
          },
          onSubmitted: (_) => _primaryAction(),
          decoration: const InputDecoration(
            hintText: '输入听到的内容…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_score != null && _checked) ...<Widget>[
                  _ScoreHeader(score: _score!),
                  const SizedBox(height: 10),
                  _DiffRow(
                    label: '正确',
                    words: _score!.answerRow,
                    isAnswer: true,
                  ),
                  const SizedBox(height: 4),
                  _DiffRow(label: '你的', words: _score!.userRow, isAnswer: false),
                  const SizedBox(height: 12),
                ],
                if (_showAnswer)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2FBEA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _line.english,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: () => setState(() => _showAnswer = !_showAnswer),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: Text(_showAnswer ? '隐藏答案' : '显示答案'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _primaryAction,
              child: Text(_checked ? '下一句 (Enter)' : '校验 (Enter)'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _StatsFooter(
          sessionAttempts: _sessionAttempts,
          sessionPercent: _sessionTotal == 0
              ? 0
              : (_sessionCorrect * 100 / _sessionTotal).round(),
          today: _today,
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final int pct = _sessionTotal == 0
        ? 0
        : (_sessionCorrect * 100 / _sessionTotal).round();
    final List<MapEntry<String, int>> errors =
        _sessionErrors.entries.toList(growable: false)..sort(
          (MapEntry<String, int> a, MapEntry<String, int> b) =>
              b.value.compareTo(a.value),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          '本组完成',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        Text('完成 $_sessionAttempts 次校验 · 平均正确率 $pct%'),
        const SizedBox(height: 16),
        if (errors.isNotEmpty) ...<Widget>[
          const Text('错词回顾', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (final MapEntry<String, int> e in errors.take(12))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('$e.key  ×$e.value'),
                  ),
              ],
            ),
          ),
        ] else
          const Expanded(child: Center(child: Text('全部听对，继续保持。'))),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () {
                setState(() => _finished = false);
                _openLine(0);
              },
              child: const Text('再来一遍'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.score});

  final DictationScore score;

  @override
  Widget build(BuildContext context) {
    final int pct = score.percent;
    final Color color = pct >= 80
        ? const Color(0xFF1A7F37)
        : pct >= 50
        ? const Color(0xFFB26A00)
        : const Color(0xFFD13438);
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$pct 分',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '听对 ${score.correct}/${score.total} 词',
          style: const TextStyle(color: AppDesignTokens.textSecondary),
        ),
      ],
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.label,
    required this.words,
    required this.isAnswer,
  });

  final String label;
  final List<MarkedWord> words;
  final bool isAnswer;

  static const Color _ok = Color(0xFF1A7F37);
  static const Color _wrong = Color(0xFFD13438);
  static const Color _miss = Color(0xFFB26A00);

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) {
      return Text(
        '$label：${isAnswer ? '' : '（没打）'}',
        style: const TextStyle(color: AppDesignTokens.textSecondary),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(color: AppDesignTokens.textSecondary),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              for (final MarkedWord w in words) _wordChip(w),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wordChip(MarkedWord w) {
    const TextStyle base = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );
    switch (w.mark) {
      case WordMark.ok:
        return Text(
          w.text,
          style: base.copyWith(color: isAnswer ? null : _ok),
        );
      case WordMark.wrong:
        return Text(w.text, style: base.copyWith(color: _wrong));
      case WordMark.miss:
        return Text(
          w.text,
          style: base.copyWith(
            color: _miss,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dashed,
            decorationColor: _miss,
          ),
        );
      case WordMark.extra:
        return Text(
          w.text,
          style: base.copyWith(
            color: _wrong,
            decoration: TextDecoration.lineThrough,
            decorationColor: _wrong,
          ),
        );
    }
  }
}

class _StatsFooter extends StatelessWidget {
  const _StatsFooter({
    required this.sessionAttempts,
    required this.sessionPercent,
    required this.today,
  });

  final int sessionAttempts;
  final int sessionPercent;
  final DictationDayStats? today;

  @override
  Widget build(BuildContext context) {
    final DictationDayStats? t = today;
    return Text(
      '本次 $sessionAttempts 句 · 平均 $sessionPercent%'
      '${t == null ? '' : ' ｜ 今日 ${t.attempts} 句 · ${t.percent}%'}',
      style: const TextStyle(
        fontSize: 12,
        color: AppDesignTokens.textSecondary,
      ),
    );
  }
}
