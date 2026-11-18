import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../patterns/data/pattern_ai_service.dart';
import '../../settings/presentation/settings_provider.dart';

final Provider<StoryAiService> storyAiServiceProvider =
    Provider<StoryAiService>((Ref ref) => const StoryAiService());

/// AI-generated read-aloud script for one page (before it is paired with
/// the photographed image and saved).
class StoryPageDraft {
  StoryPageDraft({
    this.printedText = '',
    List<String>? narrationLines,
    this.tipCn = '',
  }) : narrationLines = narrationLines ?? <String>[];

  String printedText;
  final List<String> narrationLines;
  String tipCn;
}

/// Calls the configured OpenAI-compatible chat endpoint with page photos
/// (standard `image_url` base64 parts — works for StepFun, DeepSeek,
/// OpenRouter etc. as long as the chosen model is vision-capable) and
/// returns a per-page parentese read-aloud script.
class StoryAiService {
  const StoryAiService({this.dio});

  final Dio? dio;

  static const Set<String> _chatProviders = <String>{
    'OpenAI',
    'OpenRouter',
    'SiliconFlow',
    'DeepSeek',
    'StepFun',
  };

  /// [pageImages] are raw image bytes in page order (already downscaled).
  /// With zero images the model writes a best-known script from the title.
  Future<List<StoryPageDraft>> generateScript({
    required LearningSettingsState settings,
    required String bookTitle,
    required int childAgeMonths,
    List<Uint8List> pageImages = const <Uint8List>[],
  }) async {
    if (settings.translationApiKey.isEmpty ||
        !_chatProviders.contains(settings.translationProvider)) {
      throw StateError('先在设置里配置一个 AI 翻译接口（如 StepFun）');
    }
    final Dio client =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: settings.translationBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 120),
            headers: <String, String>{
              'Authorization': 'Bearer ${settings.translationApiKey}',
              'Content-Type': 'application/json',
            },
          ),
        );

    final String system =
        'You are a read-aloud coach helping a Chinese parent narrate an '
        'English picture book to their $childAgeMonths-month-old toddler. '
        'For EACH page image (in order) return strict JSON: '
        '{"pages":[{"printed":"...","narration":["..."],"tipCn":"..."}]}. '
        'Rules: "printed" = the English text printed on that page exactly '
        'as written ("" if the page has no words). "narration" = 3-5 SHORT '
        'spoken lines the parent can SAY while showing the page — warm '
        'parentese for a 1-2 year old: simple words, sound effects '
        '(Knock knock! Woof woof! Roar!), questions (Where is he? Can you '
        'see him?), reactions (Oh no! Uh-oh! Yay!). Each line under 10 '
        'words; do NOT just repeat the printed text, expand on it. '
        '"tipCn" = one short Chinese sentence telling the parent what to '
        'DO physically (lift the flap, point at the dog, make the sound, '
        'let the baby turn the page). Return JSON only, no markdown.';

    final String userText = pageImages.isEmpty
        ? 'Book: "$bookTitle". No page images attached — write a typical '
              'read-aloud script for this book (up to 8 pages) from what '
              'you know of it; invent plausible page content if unsure.'
        : 'Book: "$bookTitle". The child is $childAgeMonths months old. '
              'The attached ${pageImages.length} image(s) are the book '
              'pages in order — one JSON page entry per image, same order.';

    final Response<dynamic> response = await client.post<dynamic>(
      '/chat/completions',
      data: <String, dynamic>{
        'model': settings.effectiveVisionModel,
        'temperature': 0.6,
        if (settings.reasoningEffortParam != null)
          'reasoning_effort': settings.reasoningEffortParam,
        'messages': <Map<String, Object>>[
          <String, Object>{'role': 'system', 'content': system},
          <String, Object>{
            'role': 'user',
            'content': <Map<String, Object>>[
              <String, Object>{'type': 'text', 'text': userText},
              for (final Uint8List img in pageImages)
                <String, Object>{
                  'type': 'image_url',
                  'image_url': <String, Object>{'url': _dataUri(img)},
                },
            ],
          },
        ],
      },
    );
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    final Map<String, dynamic> choice =
        (data['choices'] as List<dynamic>).first as Map<String, dynamic>;
    final String content =
        ((choice['message'] as Map<String, dynamic>)['content'] as String? ??
                '')
            .trim();
    return parsePages(PatternAiService.decodeChatJson(content));
  }

  /// png magic → image/png, everything else → jpeg mime for the data URI.
  static String _dataUri(Uint8List bytes) {
    final bool isPng =
        bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    return 'data:image/${isPng ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}';
  }

  static List<StoryPageDraft> parsePages(Map<String, Object?> decoded) {
    final List<Object?> raw =
        decoded['pages'] as List<Object?>? ?? const <Object?>[];
    final List<StoryPageDraft> pages = <StoryPageDraft>[
      for (final Object? e in raw)
        if (e is Map<String, Object?>)
          StoryPageDraft(
            printedText: (e['printed'] as String? ?? '').trim(),
            narrationLines:
                (e['narration'] as List<Object?>? ?? const <Object?>[])
                    .whereType<String>()
                    .map((String s) => s.trim())
                    .where((String s) => s.isNotEmpty)
                    .toList(),
            tipCn: (e['tipCn'] as String? ?? '').trim(),
          ),
    ];
    if (pages.isEmpty ||
        pages.every(
          (StoryPageDraft p) =>
              p.printedText.isEmpty && p.narrationLines.isEmpty,
        )) {
      throw const FormatException('AI 没有返回可用的带读内容');
    }
    return pages;
  }
}
