import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

final Provider<DictationStatsStore> dictationStatsStoreProvider =
    Provider<DictationStatsStore>((Ref ref) => DictationStatsStore());

class DictationDayStats {
  const DictationDayStats({
    required this.attempts,
    required this.correct,
    required this.total,
  });

  final int attempts;
  final int correct;
  final int total;

  int get percent => total == 0 ? 0 : (correct * 100 / total).round();
}

/// Persists per-day dictation accuracy and per-word error counts in Hive,
/// so the practice dialog can show "today / trend" feedback.
class DictationStatsStore {
  static const String _boxName = 'dictation_stats_v1';
  Box<String>? _box;

  Future<Box<String>> _openBox() async =>
      _box ??= await Hive.openBox<String>(_boxName);

  Future<void> record({
    required int correct,
    required int total,
    required List<String> wrongWords,
    required List<String> missedWords,
  }) async {
    final Box<String> box = await _openBox();
    final String dayKey = 'day:${_dayKey(DateTime.now())}';
    final Map<String, int> day = _decodeMap(box.get(dayKey));
    day['attempts'] = (day['attempts'] ?? 0) + 1;
    day['correct'] = (day['correct'] ?? 0) + correct;
    day['total'] = (day['total'] ?? 0) + total;
    await box.put(dayKey, jsonEncode(day));
    for (final String w in wrongWords) {
      await _bumpWord(box, w, 'wrong');
    }
    for (final String w in missedWords) {
      await _bumpWord(box, w, 'miss');
    }
  }

  Future<DictationDayStats> today() async {
    final Box<String> box = await _openBox();
    final Map<String, int> day = _decodeMap(
      box.get('day:${_dayKey(DateTime.now())}'),
    );
    return DictationDayStats(
      attempts: day['attempts'] ?? 0,
      correct: day['correct'] ?? 0,
      total: day['total'] ?? 0,
    );
  }

  Future<List<DictationDayStats>> recentDays(int days) async {
    final Box<String> box = await _openBox();
    final List<DictationDayStats> result = <DictationDayStats>[];
    for (int i = days - 1; i >= 0; i--) {
      final DateTime d = DateTime.now().subtract(Duration(days: i));
      final Map<String, int> map = _decodeMap(box.get('day:${_dayKey(d)}'));
      result.add(
        DictationDayStats(
          attempts: map['attempts'] ?? 0,
          correct: map['correct'] ?? 0,
          total: map['total'] ?? 0,
        ),
      );
    }
    return result;
  }

  /// Words the user keeps hearing wrong, most frequent first.
  Future<List<MapEntry<String, int>>> topErrorWords({int limit = 10}) async {
    final Box<String> box = await _openBox();
    final List<MapEntry<String, int>> entries = <MapEntry<String, int>>[];
    for (final String key in box.keys.whereType<String>()) {
      if (!key.startsWith('err:')) continue;
      final Map<String, int> counts = _decodeMap(box.get(key));
      entries.add(
        MapEntry<String, int>(
          key.substring(4),
          (counts['wrong'] ?? 0) + (counts['miss'] ?? 0),
        ),
      );
    }
    entries.sort(
      (MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value),
    );
    return entries.take(limit).toList(growable: false);
  }

  Future<void> _bumpWord(Box<String> box, String word, String kind) async {
    final String key = 'err:$word';
    final Map<String, int> counts = _decodeMap(box.get(key));
    counts[kind] = (counts[kind] ?? 0) + 1;
    await box.put(key, jsonEncode(counts));
  }

  Map<String, int> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map(
          (String k, dynamic v) => MapEntry<String, int>(k, (v as num).toInt()),
        );
      }
    } catch (_) {}
    return <String, int>{};
  }

  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
