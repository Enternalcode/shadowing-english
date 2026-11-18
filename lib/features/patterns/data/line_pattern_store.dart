import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

/// A sentence-pattern analysis attached to one subtitle line of one episode.
/// Persisted so the dissection survives restarts and shows inline under the
/// line instead of living only inside a transient dialog.
class LinePatternNote {
  const LinePatternNote({
    required this.pattern,
    required this.slots,
    required this.explanation,
    this.examples = const <String>[],
  });

  final String pattern;
  final String slots;
  final String explanation;
  final List<String> examples;

  String encode() => jsonEncode(<String, Object?>{
    'pattern': pattern,
    'slots': slots,
    'explanation': explanation,
    'examples': examples,
  });

  static LinePatternNote? decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      final String pattern = (json['pattern'] as String? ?? '').trim();
      if (pattern.isEmpty) return null;
      return LinePatternNote(
        pattern: pattern,
        slots: (json['slots'] as String? ?? '').trim(),
        explanation: (json['explanation'] as String? ?? '').trim(),
        examples: (json['examples'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false),
      );
    } catch (_) {
      return null;
    }
  }

  LinePatternNote withExamples(List<String> merged) => LinePatternNote(
    pattern: pattern,
    slots: slots,
    explanation: explanation,
    examples: merged,
  );
}

const String _boxName = 'line_patterns';

/// Storage key: episode-scoped so different courses never collide.
String linePatternKey(String episodeId, int lineIndex) =>
    '$episodeId::$lineIndex';

Future<Box<String>> _box() async {
  if (!Hive.isBoxOpen(_boxName)) {
    await Hive.openBox<String>(_boxName);
  }
  return Hive.box<String>(_boxName);
}

/// Saves (or merges) a note under [key]. New examples are appended deduped.
Future<void> saveLinePatternNote(
  String key,
  LinePatternNote note, {
  List<String> newExamples = const <String>[],
}) async {
  final Box<String> box = await _box();
  final LinePatternNote? existing = LinePatternNote.decode(box.get(key));
  final Set<String> seen = <String>{
    ...?existing?.examples.map((String e) => e.toLowerCase()),
    ...note.examples.map((String e) => e.toLowerCase()),
  };
  final List<String> merged = <String>[
    ...?existing?.examples,
    ...note.examples,
  ];
  for (final String e in newExamples) {
    if (seen.add(e.toLowerCase())) merged.add(e);
  }
  await box.put(key, note.withExamples(merged).encode());
}

Future<LinePatternNote?> readLinePatternNote(String key) async {
  final Box<String> box = await _box();
  return LinePatternNote.decode(box.get(key));
}

/// Reactive per-line lookup — rebuilds when the note is written or deleted.
// ignore: always_specify_types
final linePatternProvider = StreamProvider.family<LinePatternNote?, String>((
  Ref ref,
  String key,
) async* {
  final Box<String> box = await _box();
  yield LinePatternNote.decode(box.get(key));
  await for (final BoxEvent _ in box.watch(key: key)) {
    yield LinePatternNote.decode(box.get(key));
  }
});
