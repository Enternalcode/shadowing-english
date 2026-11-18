import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../domain/sentence_pattern.dart';

const String _patternBookStorageKey = 'sentence_patterns_v1';

final NotifierProvider<PatternBookNotifier, List<SentencePattern>>
patternBookProvider =
    NotifierProvider<PatternBookNotifier, List<SentencePattern>>(
      PatternBookNotifier.new,
    );

class PatternBookNotifier extends Notifier<List<SentencePattern>> {
  @override
  List<SentencePattern> build() {
    if (!Hive.isBoxOpen('prefs')) return const <SentencePattern>[];
    final String? stored = Hive.box<String>(
      'prefs',
    ).get(_patternBookStorageKey);
    if (stored == null || stored.isEmpty) return const <SentencePattern>[];
    try {
      return (jsonDecode(stored) as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(SentencePattern.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <SentencePattern>[];
    }
  }

  /// Saves a pattern; dedupes on (pattern + sourceSentence) by returning the
  /// existing entry instead of creating a second card.
  SentencePattern addPattern({
    required String pattern,
    required String explanation,
    required String sourceSentence,
    String? episodeId,
    String? courseTitle,
    String slots = '',
    String grammar = '',
    List<String> examples = const <String>[],
  }) {
    final String normalized = pattern.trim().toLowerCase();
    for (final SentencePattern item in state) {
      if (item.pattern.trim().toLowerCase() == normalized &&
          item.sourceSentence.trim() == sourceSentence.trim()) {
        return item;
      }
    }
    final SentencePattern entry = SentencePattern(
      id: 'pattern-${DateTime.now().microsecondsSinceEpoch}',
      pattern: pattern.trim(),
      explanation: explanation.trim(),
      sourceSentence: sourceSentence.trim(),
      episodeId: episodeId,
      courseTitle: courseTitle,
      slots: slots.trim(),
      grammar: grammar.trim(),
      examples: _dedupe(examples),
      createdAt: DateTime.now().toIso8601String(),
    );
    state = <SentencePattern>[entry, ...state];
    unawaited(_persist());
    return entry;
  }

  void removePattern(String id) {
    state = state
        .where((SentencePattern item) => item.id != id)
        .toList(growable: false);
    unawaited(_persist());
  }

  /// Appends freshly generated examples, skipping duplicates already on the
  /// card. Returns how many new ones were actually added.
  int addExamples(String id, List<String> incoming) {
    int added = 0;
    state = state
        .map((SentencePattern item) {
          if (item.id != id) return item;
          final Set<String> existing = item.examples
              .map((String e) => e.trim().toLowerCase())
              .toSet();
          final List<String> next = <String>[...item.examples];
          for (final String e in incoming) {
            final String t = e.trim();
            if (t.isEmpty || existing.contains(t.toLowerCase())) continue;
            existing.add(t.toLowerCase());
            next.add(t);
            added++;
          }
          return item.copyWith(examples: next);
        })
        .toList(growable: false);
    if (added > 0) unawaited(_persist());
    return added;
  }

  void removeExample(String id, int index) {
    state = state
        .map((SentencePattern item) {
          if (item.id != id || index < 0 || index >= item.examples.length) {
            return item;
          }
          final List<String> next = <String>[...item.examples]..removeAt(index);
          return item.copyWith(examples: next);
        })
        .toList(growable: false);
    unawaited(_persist());
  }

  static List<String> _dedupe(List<String> examples) {
    final Set<String> seen = <String>{};
    return examples
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty && seen.add(e.toLowerCase()))
        .toList(growable: false);
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      _patternBookStorageKey,
      jsonEncode(state.map((SentencePattern e) => e.toJson()).toList()),
    );
  }
}
