import 'package:common_learn_english/features/dictation/domain/dictation_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String answer = 'It pairs with our companion app.';

  test('perfect input scores 100', () {
    final DictationScore score = scoreDictation(answer, answer);
    expect(score.percent, 100);
    expect(score.correct, 6);
    expect(score.userRow.every((MarkedWord w) => w.mark == WordMark.ok), isTrue);
  });

  test('substituted word is marked wrong on both rows', () {
    final DictationScore score = scoreDictation(
      answer,
      'It pairs with you companion app',
    );
    expect(score.percent, 83);
    expect(score.wrongWords, contains('our'));
    expect(
      score.userRow.any(
        (MarkedWord w) => w.mark == WordMark.wrong && w.text == 'you',
      ),
      isTrue,
    );
  });

  test('one-letter-off substitution is marked near, not wrong', () {
    final DictationScore score = scoreDictation(
      answer,
      'It pairs with our companion apps',
    );
    // 'apps' vs 'app' is a single-edit miss on a 3+ letter word → near.
    expect(
      score.userRow.any(
        (MarkedWord w) => w.mark == WordMark.near && w.text == 'apps',
      ),
      isTrue,
    );
    expect(
      score.answerRow.any(
        (MarkedWord w) => w.mark == WordMark.near && w.text == 'app',
      ),
      isTrue,
    );
    // Still an error: not counted correct, recorded for review.
    expect(score.correct, 5);
    expect(score.wrongWords, contains('app'));
  });

  test('far substitution stays wrong', () {
    final DictationScore score = scoreDictation(
      answer,
      'It pairs with you companion app',
    );
    expect(
      score.userRow.every((MarkedWord w) => w.mark != WordMark.near),
      isTrue,
    );
  });

  test('missing word does not shift later words', () {
    final DictationScore score = scoreDictation(
      answer,
      'It pairs with our app',
    );
    expect(score.missedWords, <String>['companion']);
    expect(score.correct, 5);
  });

  test('extra word is struck through, not counted as wrong', () {
    final DictationScore score = scoreDictation(
      answer,
      'It really pairs with our companion app',
    );
    expect(score.percent, 100);
    expect(
      score.userRow.any(
        (MarkedWord w) => w.mark == WordMark.extra && w.text == 'really',
      ),
      isTrue,
    );
  });

  test('spaceless input is segmented against the answer', () {
    final DictationScore score = scoreDictation(
      answer,
      'itpairswithourcompanionapp',
    );
    expect(score.percent, 100);
    expect(score.userRow.length, 6);
  });

  test('spaceless input with a typo still aligns', () {
    final DictationScore score = scoreDictation(
      answer,
      'itpairswithorcompanionapp',
    );
    expect(score.correct, 5);
    expect(score.wrongWords, contains('our'));
  });

  test('empty input marks every answer word as missed', () {
    final DictationScore score = scoreDictation(answer, '   ');
    expect(score.percent, 0);
    expect(score.missedWords.length, 6);
  });

  test('punctuation and case are ignored', () {
    final DictationScore score = scoreDictation(
      answer,
      'IT PAIRS, WITH OUR COMPANION APP!',
    );
    expect(score.percent, 100);
  });
}
