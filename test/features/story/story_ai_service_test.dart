import 'package:common_learn_english/features/story/data/story_ai_service.dart';
import 'package:common_learn_english/features/story/domain/story.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StoryAiService.parsePages', () {
    test('parses a normal pages payload', () {
      final List<StoryPageDraft> pages = StoryAiService.parsePages(
        <String, Object?>{
          'pages': <Object?>[
            <String, Object?>{
              'printed': 'Is he behind the door?',
              'narration': <Object?>[
                'Knock knock!',
                "Let's look behind the door!",
                "Oh! It's a bear!",
              ],
              'tipCn': '让宝宝自己掀开门板页',
            },
            <String, Object?>{
              'printed': '',
              'narration': <Object?>['Peek-a-boo!'],
              'tipCn': '假装往床底下看',
            },
          ],
        },
      );
      expect(pages, hasLength(2));
      expect(pages[0].printedText, 'Is he behind the door?');
      expect(pages[0].narrationLines, hasLength(3));
      expect(pages[0].tipCn, '让宝宝自己掀开门板页');
      expect(pages[1].printedText, isEmpty);
    });

    test('trims and drops empty narration lines', () {
      final List<StoryPageDraft> pages = StoryAiService.parsePages(
        <String, Object?>{
          'pages': <Object?>[
            <String, Object?>{
              'printed': 'Hi',
              'narration': <Object?>['  ok  ', '', '   '],
            },
          ],
        },
      );
      expect(pages.single.narrationLines, <String>['ok']);
    });

    test('throws when the payload has no usable content', () {
      expect(
        () => StoryAiService.parsePages(<String, Object?>{
          'pages': <Object?>[
            <String, Object?>{'printed': '', 'narration': <Object?>[]},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () =>
            StoryAiService.parsePages(<String, Object?>{'pages': <Object?>[]}),
        throwsFormatException,
      );
    });
  });

  group('StoryRecord', () {
    test('json roundtrip preserves pages', () {
      const StoryRecord record = StoryRecord(
        id: 'story-1',
        title: "Where's Spot?",
        childAgeMonths: 14,
        createdAtMs: 123,
        pages: <StoryPage>[
          StoryPage(
            imagePath: '/tmp/p1.jpg',
            printedText: 'Is he behind the door?',
            narrationLines: <String>['Knock knock!', 'Open the door!'],
            tipCn: '掀门板页',
          ),
        ],
      );
      final StoryRecord decoded = StoryRecord.decode(record.encode())!;
      expect(decoded.id, 'story-1');
      expect(decoded.childAgeMonths, 14);
      expect(decoded.pages.single.tipCn, '掀门板页');
      expect(decoded.pages.single.narrationLines, hasLength(2));
    });

    test('practiceSentences puts printed text first per page', () {
      const StoryRecord record = StoryRecord(
        id: 's',
        title: 't',
        childAgeMonths: 14,
        createdAtMs: 0,
        pages: <StoryPage>[
          StoryPage(
            imagePath: '',
            printedText: 'Printed line',
            narrationLines: <String>['Say this', ''],
            tipCn: '',
          ),
          StoryPage(
            imagePath: '',
            printedText: '',
            narrationLines: <String>['Only narration'],
            tipCn: '',
          ),
        ],
      );
      expect(record.practiceSentences, <String>[
        'Printed line',
        'Say this',
        'Only narration',
      ]);
    });
  });
}
