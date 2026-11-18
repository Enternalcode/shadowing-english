import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/settings_provider.dart';

final Provider<PatternAiService> patternAiServiceProvider =
    Provider<PatternAiService>((Ref ref) => const PatternAiService());

/// Result of dissecting one sentence into a reusable spoken pattern.
class PatternAnalysis {
  const PatternAnalysis({
    required this.pattern,
    required this.slots,
    required this.explanation,
  });

  final String pattern;
  final String slots;
  final String explanation;
}

/// Calls the configured OpenAI-compatible chat endpoint (the translation
/// provider in settings — StepFun works) to extract sentence patterns and
/// generate colloquial drill sentences.
class PatternAiService {
  const PatternAiService({this.dio});

  final Dio? dio;

  static const Set<String> _chatProviders = <String>{
    'OpenAI',
    'OpenRouter',
    'SiliconFlow',
    'DeepSeek',
    'StepFun',
  };

  bool _usable(LearningSettingsState settings) {
    return settings.translationApiKey.isNotEmpty &&
        _chatProviders.contains(settings.translationProvider);
  }

  Future<PatternAnalysis> analyze({
    required String sentence,
    required LearningSettingsState settings,
  }) async {
    if (!_usable(settings)) {
      throw StateError('先在设置里配置一个 AI 翻译接口（如 StepFun）');
    }
    final Map<String, Object?> decoded = await _chatJson(
      settings: settings,
      system:
          'You are a sentence-pattern coach for a Chinese learner of spoken '
          'English. Given one sentence, extract the ONE most reusable '
          'colloquial sentence pattern. Replace the variable parts with slot '
          'markers like sb, sth, doing sth, adj, a place. Return strict JSON: '
          '{"pattern":"accuse sb of doing sth","slots":"sb=the man; doing '
          'sth=taking his parking spot","explanationCn":"用法说明"}. '
          'explanationCn is one or two short Chinese sentences about when '
          'to use the pattern and how to fill the slots.',
      user: 'Sentence: "$sentence"',
    );
    return parseAnalysis(decoded, sourceSentence: sentence);
  }

  /// Generates [count] more everyday spoken sentences drilled on the same
  /// pattern. The caller dedupes against what it already has.
  Future<List<String>> generateExamples({
    required String pattern,
    required String sourceSentence,
    required LearningSettingsState settings,
    int count = 4,
  }) async {
    if (!_usable(settings)) {
      throw StateError('先在设置里配置一个 AI 翻译接口（如 StepFun）');
    }
    final Map<String, Object?> decoded = await _chatJson(
      settings: settings,
      system:
          'You are a spoken-English drill writer. Using the given sentence '
          'pattern, write $count NEW short everyday spoken sentences — the '
          'kind people actually say to friends, coworkers, shop staff. Vary '
          'topics, keep each under 15 words, natural contractions welcome. '
          'Return strict JSON: {"examples":["...","..."]}',
      user:
          'Pattern: "$pattern"\nOriginal sentence: "$sourceSentence"\n'
          'Write $count different sentences using the same pattern.',
    );
    return parseExamples(decoded);
  }

  Future<Map<String, Object?>> _chatJson({
    required LearningSettingsState settings,
    required String system,
    required String user,
  }) async {
    final Dio client =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: settings.translationBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 60),
            headers: <String, String>{
              'Authorization': 'Bearer ${settings.translationApiKey}',
              'Content-Type': 'application/json',
            },
          ),
        );
    final Response<dynamic> response = await client.post<dynamic>(
      '/chat/completions',
      data: <String, dynamic>{
        'model': settings.translationModel,
        'temperature': 0.4,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': system},
          <String, String>{'role': 'user', 'content': user},
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
    return decodeChatJson(content);
  }

  /// Strips markdown fences and decodes the model's JSON object.
  static Map<String, Object?> decodeChatJson(String content) {
    final String cleaned = content.replaceAll(
      RegExp(r'^```(?:json)?\s*|\s*```$', caseSensitive: false),
      '',
    );
    return jsonDecode(cleaned) as Map<String, Object?>;
  }

  static PatternAnalysis parseAnalysis(
    Map<String, Object?> decoded, {
    required String sourceSentence,
  }) {
    final String pattern = (decoded['pattern'] as String? ?? '').trim();
    if (pattern.isEmpty) {
      throw const FormatException('AI 没有返回句式');
    }
    return PatternAnalysis(
      pattern: pattern,
      slots: (decoded['slots'] as String? ?? '').trim(),
      explanation: (decoded['explanationCn'] as String? ?? '').trim(),
    );
  }

  static List<String> parseExamples(Map<String, Object?> decoded) {
    final List<Object?> raw =
        decoded['examples'] as List<Object?>? ?? const <Object?>[];
    return raw
        .whereType<String>()
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList(growable: false);
  }
}
