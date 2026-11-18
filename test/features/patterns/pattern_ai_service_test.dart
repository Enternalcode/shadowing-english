import 'package:common_learn_english/features/patterns/data/pattern_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatternAiService parsing', () {
    test('parses a fenced analysis response', () {
      final Map<String, Object?> decoded = PatternAiService.decodeChatJson(
        '```json\n{"pattern":"accuse sb of doing sth", "slots":"sb=the man; '
        'doing sth=taking his spot", "explanationCn":"指控某人做了某事", '
        '"grammarCn":"一般过去时；accuse sb of doing sth 中 doing 是动名词"}\n```',
      );
      final PatternAnalysis a = PatternAiService.parseAnalysis(
        decoded,
        sourceSentence: 'x',
      );
      expect(a.pattern, 'accuse sb of doing sth');
      expect(a.slots, contains('the man'));
      expect(a.explanation, contains('指控'));
      expect(a.grammar, contains('一般过去时'));
    });

    test('grammar defaults to empty for older responses', () {
      final PatternAnalysis a = PatternAiService.parseAnalysis(
        const <String, Object?>{'pattern': 'do sth'},
        sourceSentence: 'x',
      );
      expect(a.grammar, isEmpty);
    });

    test('parseAnalysis throws when pattern missing', () {
      expect(
        () => PatternAiService.parseAnalysis(const <String, Object?>{
          'explanationCn': 'x',
        }, sourceSentence: 'x'),
        throwsFormatException,
      );
    });

    test('parseExamples filters blanks and non-strings', () {
      final List<String> out = PatternAiService.parseExamples(
        const <String, Object?>{
          'examples': <Object?>[
            'I told him to back off. ',
            ' ',
            3,
            'Easy now.',
          ],
        },
      );
      expect(out, <String>['I told him to back off.', 'Easy now.']);
    });
  });
}
