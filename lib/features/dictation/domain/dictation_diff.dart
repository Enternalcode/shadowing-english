/// Word-level dictation scoring, ported from english-trainer's blind-listen
/// implementation: edit-distance alignment producing per-word statuses
/// (correct / substituted / missing / extra), plus answer-aware segmentation
/// so the user may type without spaces.
library;

enum DictationOpType { equal, substitute, delete, insert }

class DictationOp {
  const DictationOp(this.type, {this.ti = -1, this.uj = -1});

  final DictationOpType type;
  final int ti;
  final int uj;
}

enum WordMark { ok, wrong, miss, extra, near }

class MarkedWord {
  const MarkedWord(this.text, this.mark);

  final String text;
  final WordMark mark;
}

class DictationScore {
  const DictationScore({
    required this.correct,
    required this.total,
    required this.answerRow,
    required this.userRow,
    required this.wrongWords,
    required this.missedWords,
  });

  final int correct;
  final int total;
  final List<MarkedWord> answerRow;
  final List<MarkedWord> userRow;
  final List<String> wrongWords;
  final List<String> missedWords;

  int get percent => total == 0 ? 0 : (correct * 100 / total).round();
}

final RegExp _wordPattern = RegExp("[A-Za-z']+");

List<String> dictationTokens(String input) => _wordPattern
    .allMatches(input)
    .map((RegExpMatch m) => m.group(0)!)
    .toList(growable: false);

/// Levenshtein alignment over word arrays, backtracked into an op sequence
/// so a missing word doesn't shift every later word into "wrong".
List<DictationOp> wordDiff(List<String> target, List<String> user) {
  final int n = target.length;
  final int m = user.length;
  final List<List<int>> dp = List<List<int>>.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
  );
  for (int i = 0; i <= n; i++) {
    dp[i][0] = i;
  }
  for (int j = 0; j <= m; j++) {
    dp[0][j] = j;
  }
  for (int i = 1; i <= n; i++) {
    for (int j = 1; j <= m; j++) {
      dp[i][j] = target[i - 1] == user[j - 1]
          ? dp[i - 1][j - 1]
          : 1 +
                <int>[dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1]].reduce(
                  (int a, int b) => a < b ? a : b,
                );
    }
  }
  final List<DictationOp> ops = <DictationOp>[];
  int i = n;
  int j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && target[i - 1] == user[j - 1]) {
      ops.add(DictationOp(DictationOpType.equal, ti: i - 1, uj: j - 1));
      i--;
      j--;
    } else if (i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + 1) {
      ops.add(DictationOp(DictationOpType.substitute, ti: i - 1, uj: j - 1));
      i--;
      j--;
    } else if (i > 0 && dp[i][j] == dp[i - 1][j] + 1) {
      ops.add(DictationOp(DictationOpType.delete, ti: i - 1));
      i--;
    } else {
      ops.add(DictationOp(DictationOpType.insert, uj: j - 1));
      j--;
    }
  }
  return ops.reversed.toList(growable: false);
}

int _levenshtein(String a, String b) {
  final int n = a.length;
  final int m = b.length;
  if (n == 0) return m;
  if (m == 0) return n;
  List<int> prev = List<int>.generate(m + 1, (int j) => j);
  for (int i = 1; i <= n; i++) {
    final List<int> cur = List<int>.filled(m + 1, 0);
    cur[0] = i;
    for (int j = 1; j <= m; j++) {
      cur[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
          ? prev[j - 1]
          : 1 +
                <int>[prev[j - 1], prev[j], cur[j - 1]].reduce(
                  (int x, int y) => x < y ? x : y,
                );
    }
    prev = cur;
  }
  return prev[m];
}

/// A substitution counts as "near" when it's one edit away on a word of 3+
/// letters — close enough to deserve a softer colour than a plain miss.
bool _isNearMiss(String user, String answer) =>
    answer.length >= 3 && _levenshtein(user, answer) <= 1;

/// Segments spaceless input against the known answer words, biased toward the
/// answer — a local replacement for english-trainer's `/api/segment`.
/// Returns one (possibly empty) segment per answer word, in order.
List<String> segmentToAnswer(String input, List<String> answerLower) {
  final String cleaned = input.toLowerCase().replaceAll(
    RegExp("[^a-z']"),
    '',
  );
  final int k = answerLower.length;
  final int n = cleaned.length;
  if (k == 0) return const <String>[];
  const int inf = 1 << 30;
  final List<List<int>> dp = List<List<int>>.generate(
    n + 1,
    (_) => List<int>.filled(k + 1, inf),
  );
  final List<List<int>> parent = List<List<int>>.generate(
    n + 1,
    (_) => List<int>.filled(k + 1, -1),
  );
  dp[0][0] = 0;
  for (int j = 1; j <= k; j++) {
    final String word = answerLower[j - 1];
    for (int i = 0; i <= n; i++) {
      if (dp[i][j - 1] == inf) continue;
      for (int e = i; e <= n; e++) {
        final int cand = dp[i][j - 1] + _levenshtein(cleaned.substring(i, e), word);
        if (cand < dp[e][j]) {
          dp[e][j] = cand;
          parent[e][j] = i;
        }
      }
    }
  }
  final List<String> segments = List<String>.filled(k, '');
  int i = n;
  int j = k;
  while (j > 0 && i >= 0) {
    final int p = parent[i][j];
    if (p < 0) break;
    segments[j - 1] = cleaned.substring(p, i);
    i = p;
    j--;
  }
  return segments;
}

/// Full pipeline: tokenize the answer, pick the right segmentation strategy
/// for the input (spaced input → word diff with insert support; spaceless →
/// answer-aware char alignment), then mark every word.
DictationScore scoreDictation(String answer, String input) {
  final List<String> ansTok = dictationTokens(answer);
  final List<String> ansLow = ansTok
      .map((String w) => w.toLowerCase())
      .toList(growable: false);
  final List<MarkedWord> answerRow = <MarkedWord>[];
  final List<MarkedWord> userRow = <MarkedWord>[];
  final List<String> wrongWords = <String>[];
  final List<String> missedWords = <String>[];
  int correct = 0;

  final String trimmed = input.trim();
  if (trimmed.isEmpty || ansTok.isEmpty) {
    for (final String w in ansTok) {
      answerRow.add(MarkedWord(w, WordMark.miss));
      missedWords.add(w.toLowerCase());
    }
    return DictationScore(
      correct: 0,
      total: ansTok.length,
      answerRow: answerRow,
      userRow: userRow,
      wrongWords: wrongWords,
      missedWords: missedWords,
    );
  }

  final bool hasSpaces = RegExp(r'\s').hasMatch(trimmed);
  if (!hasSpaces && dictationTokens(trimmed).isNotEmpty) {
    final List<String> segs = segmentToAnswer(trimmed, ansLow);
    for (int idx = 0; idx < ansTok.length; idx++) {
      final String seg = idx < segs.length ? segs[idx] : '';
      if (seg.isEmpty) {
        answerRow.add(MarkedWord(ansTok[idx], WordMark.miss));
        missedWords.add(ansLow[idx]);
      } else if (seg == ansLow[idx]) {
        correct++;
        answerRow.add(MarkedWord(ansTok[idx], WordMark.ok));
        userRow.add(MarkedWord(seg, WordMark.ok));
      } else {
        final bool near = _isNearMiss(seg, ansLow[idx]);
        answerRow.add(
          MarkedWord(ansTok[idx], near ? WordMark.near : WordMark.wrong),
        );
        userRow.add(MarkedWord(seg, near ? WordMark.near : WordMark.wrong));
        wrongWords.add(ansLow[idx]);
      }
    }
  } else {
    final List<String> uTok = dictationTokens(trimmed);
    final List<String> uLow = uTok
        .map((String w) => w.toLowerCase())
        .toList(growable: false);
    for (final DictationOp op in wordDiff(ansLow, uLow)) {
      switch (op.type) {
        case DictationOpType.equal:
          correct++;
          answerRow.add(MarkedWord(ansTok[op.ti], WordMark.ok));
          userRow.add(MarkedWord(uTok[op.uj], WordMark.ok));
        case DictationOpType.substitute:
          final bool near = _isNearMiss(uLow[op.uj], ansLow[op.ti]);
          answerRow.add(
            MarkedWord(ansTok[op.ti], near ? WordMark.near : WordMark.wrong),
          );
          userRow.add(
            MarkedWord(uTok[op.uj], near ? WordMark.near : WordMark.wrong),
          );
          wrongWords.add(ansLow[op.ti]);
        case DictationOpType.delete:
          answerRow.add(MarkedWord(ansTok[op.ti], WordMark.miss));
          missedWords.add(ansLow[op.ti]);
        case DictationOpType.insert:
          userRow.add(MarkedWord(uTok[op.uj], WordMark.extra));
      }
    }
  }

  return DictationScore(
    correct: correct,
    total: ansTok.length,
    answerRow: answerRow,
    userRow: userRow,
    wrongWords: wrongWords,
    missedWords: missedWords,
  );
}
