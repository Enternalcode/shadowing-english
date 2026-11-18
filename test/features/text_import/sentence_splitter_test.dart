import 'package:common_learn_english/features/text_import/domain/sentence_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitSentences', () {
    test('splits simple sentences on periods', () {
      expect(splitSentences('Hello world. How are you? Great!'), <String>[
        'Hello world.',
        'How are you?',
        'Great!',
      ]);
    });

    test('keeps closing quotes with the sentence', () {
      expect(splitSentences('He said "no way." Then he left.'), <String>[
        'He said "no way."',
        'Then he left.',
      ]);
    });

    test('does not split inside abbreviations and initials', () {
      expect(
        splitSentences('Dr. Smith arrived at 3.5 percent. P.S. I agree.'),
        <String>['Dr. Smith arrived at 3.5 percent.', 'P.S. I agree.'],
      );
    });

    test('does not split inside e.g. and decimals', () {
      final List<String> out = splitSentences(
        'It costs 4.99, e.g. a coffee. Buy one.',
      );
      expect(out, <String>['It costs 4.99, e.g. a coffee.', 'Buy one.']);
    });

    test('blank lines are sentence boundaries even without punctuation', () {
      expect(splitSentences('First line no period\n\nSecond line.'), <String>[
        'First line no period',
        'Second line.',
      ]);
    });

    test('merges junk fragments into previous sentence', () {
      expect(splitSentences('It happened. "'), <String>['It happened. "']);
      expect(splitSentences('He did it. " Really.'), <String>[
        'He did it.',
        '" Really.',
      ]);
    });

    test('social-media style post keeps register intact', () {
      const String post =
          'The defendant actually struck him from behind! Wild. '
          'Apparently he had a concussion, per the report. '
          'e.g. things like this happen all the time in LA. '
          'Sources: cnn.com has more.';
      final List<String> out = splitSentences(post);
      expect(out, <String>[
        'The defendant actually struck him from behind!',
        'Wild.',
        'Apparently he had a concussion, per the report.',
        'e.g. things like this happen all the time in LA.',
        'Sources: cnn.com has more.',
      ]);
    });

    test('trims and drops empties', () {
      expect(splitSentences('   '), isEmpty);
      expect(splitSentences('One.  \n\n  Two.'), <String>['One.', 'Two.']);
    });
  });
}
