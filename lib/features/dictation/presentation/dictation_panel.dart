import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart';

import '../../phrases/presentation/phrase_book_provider.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/word_lookup_popup.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/dictation_stats_store.dart';
import '../domain/dictation_diff.dart';

class DictationLine {
  const DictationLine({
    required this.english,
    this.chinese = '',
    this.time = '',
    this.lineKey = '',
  });

  final String english;
  final String chinese;
  final String time;
  final String lineKey;
}

/// Embedded sentence-level blind dictation: replaces the transcript panel so
/// subtitles stay hidden by default (盲听). Listen → type (spaces optional) →
/// Enter to check → word-level diff → Enter again for the next line. A header
/// toggle reveals the full transcript with only the active line masked.
class DictationPanel extends ConsumerStatefulWidget {
  const DictationPanel({
    required this.lines,
    required this.onPlayLine,
    required this.onExit,
    this.startIndex = 0,
    this.episodeId = '',
    this.course = '',
    this.episode = '',
    this.onTypingStarted,
    super.key,
  });

  final List<DictationLine> lines;
  final void Function(int index) onPlayLine;
  final VoidCallback onExit;
  final int startIndex;
  final String episodeId;
  final String course;
  final String episode;
  final VoidCallback? onTypingStarted;

  @override
  ConsumerState<DictationPanel> createState() => _DictationPanelState();
}

class _DictationPanelState extends ConsumerState<DictationPanel> {
  /// Typed letters live in [_typed], our own state fed by hardware key
  /// events (qwerty-learner style) — no TextField, so IME composition
  /// cancels, dialogs and focus loss can never wipe the input.
  final FocusNode _focusNode = FocusNode();
  String _typed = '';

  late List<int> _order;
  int _pos = 0;
  bool _checked = false;
  bool _showAnswer = false;
  bool _showSubtitles = false;
  bool _hintLetters = false;
  bool _finished = false;
  DictationScore? _score;
  DictationDayStats? _today;
  final Set<int> _revealed = <int>{};
  final Set<int> _seen = <int>{};
  final Set<int> _wrongLines = <int>{};
  final Set<int> _recorded = <int>{};
  final Map<int, int> _lineBest = <int, int>{};
  final Map<int, int> _lineRejectCount = <int, int>{};
  final Map<int, Set<String>> _lineErrorWords = <int, Set<String>>{};
  int _streak = 0;
  int _lastDelta = 0;
  double _keyVolume = 90;
  double _sfxVolume = 90;
  int _prevLetterCount = 0;
  int? _rejectedAt;
  Timer? _rejectTimer;
  final Player _sfx = Player();
  final Player _keySfx = Player();
  final Player _keyErr = Player();

  int _sessionAttempts = 0;
  int _sessionCorrect = 0;
  int _sessionTotal = 0;
  final Map<String, int> _sessionErrors = <String, int>{};

  int get _index => _order[_pos];
  DictationLine get _line => widget.lines[_index];

  @override
  void initState() {
    super.initState();
    _order = List<int>.generate(widget.lines.length, (int i) => i);
    _pos = _order.indexOf(widget.startIndex.clamp(0, widget.lines.length - 1));
    if (_pos < 0) _pos = 0;
    _loadVolumes();
    unawaited(_applyVolume());
    unawaited(
      _keySfx.open(Media('asset:///assets/sfx/qw_click.wav'), play: false),
    );
    unawaited(
      _keyErr.open(Media('asset:///assets/sfx/qw_beep.wav'), play: false),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPos(_pos));
    _refreshToday();
  }

  @override
  void didUpdateWidget(covariant DictationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startIndex != oldWidget.startIndex) {
      _jumpToLine(widget.startIndex.clamp(0, widget.lines.length - 1));
    }
  }

  @override
  void dispose() {
    _rejectTimer?.cancel();
    unawaited(_keyErr.dispose());
    unawaited(_keySfx.dispose());
    unawaited(_sfx.dispose());
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _refreshToday() async {
    final DictationDayStats stats = await ref
        .read(dictationStatsStoreProvider)
        .today();
    if (mounted) setState(() => _today = stats);
  }

  void _openPos(int pos) {
    setState(() {
      _pos = pos;
      _checked = false;
      _showAnswer = false;
      _hintLetters = false;
      _score = null;
      _lastDelta = 0;
      _typed = '';
      _prevLetterCount = 0;
      _rejectedAt = null;
      _rejectTimer?.cancel();
    });
    widget.onPlayLine(_order[pos]);
    _focusNode.requestFocus();
  }

  /// Peek-list tap: jump within the active order, falling back to the full
  /// list when the tapped line isn't in a wrong-lines subset.
  void _jumpToLine(int lineIndex) {
    int pos = _order.indexOf(lineIndex);
    if (pos < 0) {
      _order = List<int>.generate(widget.lines.length, (int i) => i);
      pos = lineIndex;
    }
    _openPos(pos);
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
    final DictationScore score = scoreDictation(_line.english, _typed);
    final int pct = score.percent;
    final int? prevBest = _lineBest[_index];
    setState(() {
      _checked = true;
      _showAnswer = true;
      _score = score;
      _revealed.add(_index);
      _lastDelta = prevBest != null && pct > prevBest ? pct - prevBest : 0;
      if (prevBest == null || pct > prevBest) _lineBest[_index] = pct;
      if (pct == 100) {
        _wrongLines.remove(_index);
      } else {
        _wrongLines.add(_index);
      }
      if (_seen.add(_index)) {
        _streak = pct == 100 ? _streak + 1 : 0;
      }
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
      _playSfx(
        pct == 100 ? (_streak >= 3 ? 'combo.wav' : 'ding.wav') : 'blip.wav',
      ),
    );
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
    if (_pos + 1 < _order.length) {
      _openPos(_pos + 1);
    } else {
      setState(() => _finished = true);
    }
  }

  Future<void> _playSfx(String name) async {
    try {
      await _sfx.open(Media('asset:///assets/sfx/$name'));
    } catch (_) {}
  }

  void _speakWord(String word) {
    unawaited(ref.read(wordPronunciationServiceProvider).speak(word));
  }

  void _keySound(bool correct) {
    final Player p = correct ? _keySfx : _keyErr;
    unawaited(p.seek(Duration.zero).then((_) => p.play()));
  }

  Future<void> _applyVolume() async {
    await _keySfx.setVolume(_keyVolume);
    await _keyErr.setVolume(_sfxVolume);
    await _sfx.setVolume(_sfxVolume);
  }

  void _loadVolumes() {
    if (!Hive.isBoxOpen('prefs')) return;
    final Box<String> prefs = Hive.box<String>('prefs');
    _keyVolume =
        double.tryParse(prefs.get('dictation_key_volume') ?? '') ?? _keyVolume;
    _sfxVolume =
        double.tryParse(prefs.get('dictation_sfx_volume') ?? '') ?? _sfxVolume;
  }

  void _saveVolumes() {
    if (!Hive.isBoxOpen('prefs')) return;
    unawaited(
      Hive.box<String>('prefs').putAll(<String, String>{
        'dictation_key_volume': '$_keyVolume',
        'dictation_sfx_volume': '$_sfxVolume',
      }),
    );
  }

  /// Hardware-key input, qwerty-learner style: the panel owns the typed
  /// string directly, so dialogs, IME state and focus loss can't reset it.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _primaryAction();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final String label = key.keyLabel;
    if (label.length == 1 && _isLetterRune(label.codeUnitAt(0))) {
      _typeChar(label.toLowerCase());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _typeChar(String ch) => _acceptTyped(_typed + ch);

  void _backspace() {
    if (_typed.isEmpty) return;
    _rejectTimer?.cancel();
    _rejectedAt = null;
    _typed = _typed.substring(0, _typed.length - 1);
    _prevLetterCount = _typed.length;
    if (_checked) {
      _checked = false;
      _score = null;
    }
    setState(() {});
  }

  /// qwerty-learner feel: every accepted letter clicks into its slot; the
  /// first wrong letter beeps, shows red ~240ms, then the input rolls back
  /// to just before it so the letter has to be re-typed.
  void _acceptTyped(String next) {
    final String typedL = _lettersOf(next);
    final String expL = _lettersOf(_line.english);
    if (_checked) {
      _checked = false;
      _score = null;
    }

    // Reinforcement pass: once the sentence is fully typed, the next
    // keystroke starts it over (qwerty-learner lets you retype a word).
    if (expL.isNotEmpty &&
        _prevLetterCount == expL.length &&
        typedL.length > expL.length) {
      _typed = typedL.substring(expL.length);
      _prevLetterCount = _typed.length;
      setState(() {});
      return;
    }

    if (_prevLetterCount == 0 && typedL.isNotEmpty) {
      widget.onTypingStarted?.call();
    }

    int? wrongAt;
    for (int i = 0; i < typedL.length; i++) {
      if (i >= expL.length ||
          typedL[i].toLowerCase() != expL[i].toLowerCase()) {
        wrongAt = i;
        break;
      }
    }

    _typed = next;

    if (wrongAt != null) {
      _keySound(false);
      _recordRejection(wrongAt);
      if (_rejectedAt != wrongAt) {
        _rejectedAt = wrongAt;
        _rejectTimer?.cancel();
        _rejectTimer = Timer(
          const Duration(milliseconds: 240),
          _rollbackRejection,
        );
      }
    } else {
      _rejectedAt = null;
      _rejectTimer?.cancel();
      if (typedL.length > _prevLetterCount) _keySound(true);
    }
    _prevLetterCount = typedL.length;
    setState(() {});
    if (wrongAt == null && typedL.isNotEmpty && typedL.length == expL.length) {
      _check();
    }
  }

  /// qwerty-learner's wrongCount: every rejected keypress bumps the count for
  /// the line and remembers which word it landed on. At 3+ misses a tip bar
  /// offers to save the whole sentence plus its trouble words.
  void _recordRejection(int letterIndex) {
    final int idx = _index;
    _lineRejectCount[idx] = (_lineRejectCount[idx] ?? 0) + 1;
    final String word = _wordAtLetter(_line.english, letterIndex);
    if (word.isNotEmpty) {
      (_lineErrorWords[idx] ??= <String>{}).add(word);
    }
  }

  String _wordAtLetter(String line, int letterIndex) {
    final List<String> words = dictationTokens(line);
    int cursor = 0;
    for (final String word in words) {
      final int len = _lettersOf(word).length;
      if (len > 0 && letterIndex < cursor + len) return word;
      cursor += len;
    }
    return '';
  }

  /// Save the current line to the phrase book and every word the user
  /// stumbled on to the word book (favorited), same as collecting from
  /// subtitles.
  void _recordLine() {
    final DictationLine line = _line;
    ref
        .read(phraseBookProvider.notifier)
        .addPhraseIfMissing(
          english: line.english,
          chinese: line.chinese,
          course: widget.course,
          episode: widget.episode,
          time: line.time,
          episodeId: widget.episodeId.isEmpty ? null : widget.episodeId,
          note: '听写错句',
        );
    final Set<String> words = _lineErrorWords[_index] ?? <String>{};
    int saved = 0;
    for (final String word in words) {
      final bool ok = ref
          .read(wordBookProvider.notifier)
          .addFavoriteWord(
            rawWord: word,
            episodeId: widget.episodeId,
            course: widget.course,
            episode: widget.episode,
            time: line.time,
            lineKey: line.lineKey.isEmpty ? line.time : line.lineKey,
            sentence: line.english,
            chinese: line.chinese,
          );
      if (ok) saved++;
    }
    setState(() => _recorded.add(_index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved > 0 ? '已记录本句 + $saved 个错词（短语库/生词本）' : '已记录本句到短语库',
          ),
        ),
      );
    _focusNode.requestFocus();
  }

  /// Tap a hidden word slot → dictionary card for that word, same lookup
  /// surface as tapping a word in the subtitle list.
  void _showWordLookup(String word) {
    final DictationLine line = _line;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: WordLookupPopupCard(
            rawWord: word,
            contextSentence: line.english,
            episodeId: widget.episodeId.isEmpty ? null : widget.episodeId,
            contextTime: line.time.isEmpty ? null : line.time,
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            onClose: () => Navigator.of(ctx).pop(),
            onFavorite: () {
              ref
                  .read(wordBookProvider.notifier)
                  .addFavoriteWord(
                    rawWord: word,
                    episodeId: widget.episodeId,
                    course: widget.course,
                    episode: widget.episode,
                    time: line.time,
                    lineKey: line.lineKey.isEmpty ? line.time : line.lineKey,
                    sentence: line.english,
                    chinese: line.chinese,
                  );
            },
            onCollect: () {
              ref
                  .read(phraseBookProvider.notifier)
                  .addPhraseIfMissing(
                    english: line.english,
                    chinese: line.chinese,
                    course: widget.course,
                    episode: widget.episode,
                    time: line.time,
                    episodeId: widget.episodeId.isEmpty
                        ? null
                        : widget.episodeId,
                  );
            },
          ),
        ),
      ).then((_) => _focusNode.requestFocus()),
    );
  }

  void _rollbackRejection() {
    final int? at = _rejectedAt;
    _rejectedAt = null;
    if (at == null) return;
    if (_typed.length > at) {
      _typed = _typed.substring(0, at);
    }
    _prevLetterCount = _lettersOf(_typed).length;
    setState(() {});
  }

  void _showVolumeDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext context) => StatefulBuilder(
          builder: (BuildContext context, StateSetter setD) => AlertDialog(
            title: const Text('音效音量'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('打字音效', style: TextStyle(fontSize: 13)),
                  Slider(
                    value: _keyVolume,
                    max: 100,
                    divisions: 20,
                    label: '${_keyVolume.round()}',
                    onChanged: (double v) {
                      setD(() => _keyVolume = v);
                      setState(() {});
                      unawaited(_applyVolume());
                      _saveVolumes();
                    },
                  ),
                  const Text('反馈音效（对错/判分）', style: TextStyle(fontSize: 13)),
                  Slider(
                    value: _sfxVolume,
                    max: 100,
                    divisions: 20,
                    label: '${_sfxVolume.round()}',
                    onChanged: (double v) {
                      setD(() => _sfxVolume = v);
                      setState(() {});
                      unawaited(_applyVolume());
                      _saveVolumes();
                    },
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ).then((_) => _focusNode.requestFocus()),
    );
  }

  void _retryWrongLines() {
    setState(() {
      _order = _wrongLines.toList()..sort();
      _wrongLines.clear();
      _revealed.clear();
      _seen.clear();
      _streak = 0;
      _finished = false;
    });
    _openPos(0);
  }

  void _restartAll() {
    setState(() {
      _order = List<int>.generate(widget.lines.length, (int i) => i);
      _wrongLines.clear();
      _revealed.clear();
      _seen.clear();
      _streak = 0;
      _finished = false;
    });
    _openPos(0);
  }

  @override
  Widget build(BuildContext context) {
    return _finished ? _buildSummary() : _buildSession();
  }

  Widget _buildSession() {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.tab): () =>
            widget.onPlayLine(_index),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () {
          if (_pos > 0) _openPos(_pos - 1);
        },
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  '听写练习',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_pos + 1} / ${_order.length}',
                  style: const TextStyle(color: AppDesignTokens.textSecondary),
                ),
                const Spacer(),
                _SubtitleToggle(
                  visible: _showSubtitles,
                  onChanged: (bool v) {
                    setState(() => _showSubtitles = v);
                    _focusNode.requestFocus();
                  },
                ),
                IconButton(
                  tooltip: '上一句',
                  onPressed: _pos > 0 ? () => _openPos(_pos - 1) : null,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton(
                  tooltip: '重播本句',
                  onPressed: () => widget.onPlayLine(_index),
                  icon: const Icon(Icons.volume_up_rounded),
                ),
                IconButton(
                  tooltip: '下一句',
                  onPressed: _pos + 1 < _order.length
                      ? () => _openPos(_pos + 1)
                      : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                IconButton(
                  tooltip: '音效音量',
                  onPressed: _showVolumeDialog,
                  icon: const Icon(Icons.tune_rounded),
                ),
                IconButton(
                  tooltip: '退出听写',
                  onPressed: widget.onExit,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              _checked
                  ? '继续输入可重新校验，Enter 下一句'
                  : _showSubtitles
                  ? '听音后直接敲键盘（错键会弹回）；Enter 校验 · Tab 重播'
                  : '盲听后直接敲键盘，错键会自动弹回；Enter 校验 · Tab 重播 · Shift+Tab 上一句',
              style: const TextStyle(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _showSubtitles ? _buildPeekList() : _buildBlindArea(),
            ),
            const SizedBox(height: 8),
            if (_score != null && _checked) ...<Widget>[
              _ScoreHeader(score: _score!, delta: _lastDelta, streak: _streak),
              const SizedBox(height: 6),
              _DiffRow(
                label: '正确',
                words: _score!.answerRow,
                isAnswer: true,
                onSpeakWord: _speakWord,
              ),
              const SizedBox(height: 2),
              _DiffRow(
                label: '你的',
                words: _score!.userRow,
                isAnswer: false,
                onSpeakWord: _speakWord,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: _showAnswer
                      ? null
                      : () {
                          setState(() => _hintLetters = !_hintLetters);
                          _focusNode.requestFocus();
                        },
                  icon: const Icon(Icons.abc_rounded, size: 18),
                  label: Text(_hintLetters ? '收回提示' : '提示首字母'),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showAnswer = !_showAnswer;
                      if (_showAnswer) _revealed.add(_index);
                    });
                    _focusNode.requestFocus();
                  },
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
            const SizedBox(height: 4),
            _StatsFooter(
              sessionAttempts: _sessionAttempts,
              sessionPercent: _sessionTotal == 0
                  ? 0
                  : (_sessionCorrect * 100 / _sessionTotal).round(),
              streak: _streak,
              today: _today,
            ),
          ],
        ),
      ),
    );
  }

  /// Blind mode: the current line stays hidden; only word slots are shown.
  Widget _buildBlindArea() {
    if (_showAnswer) {
      return Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF2FBEA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _line.english,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_line.chinese.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  _line.chinese,
                  style: const TextStyle(color: AppDesignTokens.textSecondary),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final int wordCount = dictationTokens(_line.english).length;
    return Column(
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focusNode.requestFocus();
              widget.onPlayLine(_index);
            },
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.headphones_rounded,
                    size: 36,
                    color: AppDesignTokens.textSecondary,
                  ),
                  const SizedBox(height: 10),
                  _SlotLine(
                    line: _line.english,
                    typed: _typed,
                    reveal: _showAnswer,
                    showFirstLetters: _hintLetters,
                    cursorIndex: _checked || _showAnswer
                        ? -1
                        : _lettersOf(_typed).length,
                    onWordTap: _showWordLookup,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$wordCount 词 · 点此处或 Tab 重播',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if ((_lineRejectCount[_index] ?? 0) >= 3 && !_recorded.contains(_index))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD591)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '这句已错 ${_lineRejectCount[_index]} 次，值得记下来',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _recordLine,
                    child: const Text('记录本句+错词'),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () {
                  _focusNode.requestFocus();
                  widget.onPlayLine(_index);
                },
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('重播 (Tab)'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _primaryAction,
                child: Text(_checked ? '下一句 (Enter)' : '校验 (Enter)'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Subtitles visible: full transcript, only the active line stays masked
  /// until it is checked; tapping a line jumps the session to it.
  Widget _buildPeekList() {
    return ListView.builder(
      itemCount: widget.lines.length,
      itemBuilder: (BuildContext context, int i) {
        final DictationLine line = widget.lines[i];
        final bool active = i == _index;
        final bool masked = active && !_revealed.contains(i);
        return InkWell(
          onTap: () => _jumpToLine(i),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFEFF6FF) : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 26,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      color: active
                          ? const Color(0xFF2563EB)
                          : AppDesignTokens.textSecondary,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w400,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (masked)
                        _MaskedText(
                          line: line.english,
                          active: active,
                          showLetters: _hintLetters,
                        )
                      else
                        Text(
                          line.english,
                          style: TextStyle(
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      if (line.chinese.isNotEmpty)
                        Text(
                          line.chinese,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                    child: Text('${e.key}  ×${e.value}'),
                  ),
              ],
            ),
          ),
        ] else
          const Expanded(child: Center(child: Text('全部听对，继续保持。'))),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            if (_wrongLines.isNotEmpty)
              TextButton.icon(
                onPressed: _retryWrongLines,
                icon: const Icon(Icons.replay_rounded, size: 16),
                label: Text('只练错句 (${_wrongLines.length})'),
              ),
            TextButton(onPressed: _restartAll, child: const Text('再来一遍')),
            const SizedBox(width: 8),
            FilledButton(onPressed: widget.onExit, child: const Text('完成')),
          ],
        ),
      ],
    );
  }
}

bool _isLetterRune(int r) =>
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x30 && r <= 0x39);

String _lettersOf(String s) =>
    String.fromCharCodes(s.runes.where(_isLetterRune));

/// qwerty-learner-style letter slots: typed letters land in the next slot
/// and turn green/red against the expected letter, live; on reveal the
/// remaining cells show the expected letters.
class _SlotLine extends StatelessWidget {
  const _SlotLine({
    required this.line,
    required this.typed,
    this.reveal = false,
    this.showFirstLetters = false,
    this.cursorIndex = -1,
    this.onWordTap,
  });

  final String line;
  final String typed;
  final bool reveal;
  final bool showFirstLetters;
  final int cursorIndex;
  final ValueChanged<String>? onWordTap;

  static const Color _ok = Color(0xFF1A7F37);
  static const Color _wrong = Color(0xFFD13438);
  static const Color _hint = Color(0xFF2563EB);
  static const Color _empty = Color(0xFFCBD5E1);

  @override
  Widget build(BuildContext context) {
    final List<String> words = dictationTokens(line);
    final String typedLetters = _lettersOf(typed);
    int g = 0;
    final List<Widget> groups = <Widget>[];
    for (final String word in words) {
      final List<int> letters = word.runes.where(_isLetterRune).toList();
      final List<Widget> cells = <Widget>[];
      for (int i = 0; i < letters.length; i++) {
        cells.add(
          _cell(
            g++,
            String.fromCharCode(letters[i]),
            typedLetters,
            wordStart: i == 0,
          ),
        );
      }
      final Widget group = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: cells),
      );
      groups.add(
        onWordTap == null
            ? group
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onWordTap!(word),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: group,
                ),
              ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      runSpacing: 8,
      children: groups,
    );
  }

  Widget _cell(
    int idx,
    String expected,
    String typedLetters, {
    required bool wordStart,
  }) {
    String text = '';
    Color fg = AppDesignTokens.textSecondary;
    Color border = _empty;
    if (idx < typedLetters.length) {
      final String t = typedLetters[idx];
      final bool ok = t.toLowerCase() == expected.toLowerCase();
      text = t;
      fg = ok ? _ok : _wrong;
      border = fg;
    } else if (reveal) {
      text = expected;
      fg = AppDesignTokens.textPrimary;
    } else if (showFirstLetters && wordStart) {
      text = expected;
      fg = _hint;
      border = _hint;
    }
    final bool atCursor =
        idx == cursorIndex && idx >= typedLetters.length && !reveal;
    return Container(
      width: 15,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: atCursor ? const Color(0xFF46A302) : border,
            width: 2,
          ),
        ),
      ),
      child: atCursor
          ? const _BlinkCaret()
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 110),
              transitionBuilder: (Widget child, Animation<double> a) =>
                  ScaleTransition(
                    scale: a,
                    child: FadeTransition(opacity: a, child: child),
                  ),
              child: Text(
                text,
                key: ValueKey<String>('$idx:$text'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
    );
  }
}

/// Blinking vertical bar marking the next slot to fill, like the caret in
/// a text field - makes the current input position obvious at a glance.
class _BlinkCaret extends StatefulWidget {
  const _BlinkCaret();

  @override
  State<_BlinkCaret> createState() => _BlinkCaretState();
}

class _BlinkCaretState extends State<_BlinkCaret> {
  late final Timer _timer = Timer.periodic(const Duration(milliseconds: 530), (
    _,
  ) {
    if (mounted) setState(() => _visible = !_visible);
  });
  bool _visible = true;

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _visible ? 1 : 0.12,
    duration: const Duration(milliseconds: 120),
    child: Container(
      width: 2,
      height: 16,
      decoration: BoxDecoration(
        color: const Color(0xFF46A302),
        borderRadius: BorderRadius.circular(1),
      ),
    ),
  );
}

class _SubtitleToggle extends StatelessWidget {
  const _SubtitleToggle({required this.visible, required this.onChanged});

  final bool visible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: visible ? '隐藏字幕（盲听）' : '显示字幕',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(!visible),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: visible ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                visible ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
                size: 16,
                color: visible
                    ? const Color(0xFF2563EB)
                    : AppDesignTokens.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                visible ? '字幕开' : '盲听',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: visible
                      ? const Color(0xFF2563EB)
                      : AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaskedText extends StatelessWidget {
  const _MaskedText({
    required this.line,
    required this.active,
    this.showLetters = false,
  });

  final String line;
  final bool active;
  final bool showLetters;

  @override
  Widget build(BuildContext context) {
    final List<String> toks = dictationTokens(line);
    if (showLetters) {
      final Color c = active
          ? const Color(0xFF2563EB)
          : AppDesignTokens.textSecondary;
      return Wrap(
        spacing: 10,
        runSpacing: 6,
        children: <Widget>[
          for (final String w in toks)
            Text(
              w.length == 1 ? w : '${w[0]}${'·' * (w.length - 1)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: c,
              ),
            ),
        ],
      );
    }
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: <Widget>[
        for (int i = 0; i < toks.length; i++)
          Container(
            width: 16,
            height: 7,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF93C5FD) : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.score, this.delta = 0, this.streak = 0});

  final DictationScore score;
  final int delta;
  final int streak;

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
        if (delta > 0) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            '+$delta 进步',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A7F37),
            ),
          ),
        ],
        if (streak >= 2) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            '连对 $streak',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFFEA580C),
            ),
          ),
        ],
      ],
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.label,
    required this.words,
    required this.isAnswer,
    this.onSpeakWord,
  });

  final String label;
  final List<MarkedWord> words;
  final bool isAnswer;
  final void Function(String word)? onSpeakWord;

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
            children: <Widget>[for (final MarkedWord w in words) _chip(w)],
          ),
        ),
      ],
    );
  }

  Widget _chip(MarkedWord w) {
    final Widget chip = _wordChip(w);
    if (w.mark == WordMark.ok || onSpeakWord == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: () => onSpeakWord!(w.text), child: chip),
    );
  }

  Widget _wordChip(MarkedWord w) {
    const TextStyle base = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
    switch (w.mark) {
      case WordMark.ok:
        return Text(w.text, style: base.copyWith(color: isAnswer ? null : _ok));
      case WordMark.wrong:
        return Text(w.text, style: base.copyWith(color: _wrong));
      case WordMark.near:
        return Text(
          w.text,
          style: base.copyWith(
            color: _miss,
            decoration: TextDecoration.underline,
            decorationColor: _miss,
          ),
        );
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
    required this.streak,
    required this.today,
  });

  final int sessionAttempts;
  final int sessionPercent;
  final int streak;
  final DictationDayStats? today;

  @override
  Widget build(BuildContext context) {
    final DictationDayStats? t = today;
    return Text(
      '本次 $sessionAttempts 句 · 平均 $sessionPercent%'
      '${streak >= 2 ? ' ｜ 连对 $streak' : ''}'
      '${t == null ? '' : ' ｜ 今日 ${t.attempts} 句 · ${t.percent}%'}',
      style: const TextStyle(
        fontSize: 12,
        color: AppDesignTokens.textSecondary,
      ),
    );
  }
}
