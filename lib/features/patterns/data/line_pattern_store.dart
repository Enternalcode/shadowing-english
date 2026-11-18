import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../settings/presentation/settings_provider.dart';
import 'pattern_ai_service.dart';

/// A sentence-pattern analysis attached to one subtitle line of one episode.
/// Persisted so the dissection survives restarts and shows inline under the
/// line instead of living only inside a transient dialog.
class LinePatternNote {
  const LinePatternNote({
    required this.pattern,
    required this.slots,
    required this.explanation,
    this.grammar = '',
    this.examples = const <String>[],
  });

  final String pattern;
  final String slots;
  final String explanation;
  final String grammar;
  final List<String> examples;

  String encode() => jsonEncode(<String, Object?>{
    'pattern': pattern,
    'slots': slots,
    'explanation': explanation,
    'grammar': grammar,
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
        grammar: (json['grammar'] as String? ?? '').trim(),
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
    grammar: grammar,
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

/// Analysis-job state: which line keys are being dissected right now, and the
/// last error per key. Centralized here so several mounted views of the same
/// line (subtitle row, dictation panel) never trigger duplicate AI calls.
typedef PatternJobs = ({Set<String> pending, Map<String, String> errors});

class PatternAnalysisJobs extends Notifier<PatternJobs> {
  @override
  PatternJobs build() => (pending: <String>{}, errors: <String, String>{});

  /// Dissects [sentence] into a reusable pattern and stores the note under
  /// [key]. No-ops while the same key is in flight; a cached note short-
  /// circuits unless [force] (re-analyze). Errors surface per key.
  Future<void> request({
    required String key,
    required String sentence,
    bool force = false,
  }) async {
    if (state.pending.contains(key)) return;
    if (!force && (await readLinePatternNote(key)) != null) return;
    state = (
      pending: <String>{...state.pending, key},
      errors: <String, String>{...state.errors}..remove(key),
    );
    try {
      final PatternAnalysis result = await ref
          .read(patternAiServiceProvider)
          .analyze(
            sentence: sentence,
            settings: ref.read(learningSettingsProvider),
          );
      await saveLinePatternNote(
        key,
        LinePatternNote(
          pattern: result.pattern,
          slots: result.slots,
          explanation: result.explanation,
          grammar: result.grammar,
        ),
      );
    } catch (e) {
      state = (
        pending: state.pending,
        errors: <String, String>{...state.errors, key: '$e'},
      );
    } finally {
      state = (
        pending: <String>{...state.pending}..remove(key),
        errors: state.errors,
      );
    }
  }

  /// Generates more colloquial examples for the stored note; returns how many
  /// were actually appended (dedupe may drop some).
  Future<int> generateMore({
    required String key,
    required LinePatternNote note,
    required String sourceSentence,
    int count = 4,
  }) async {
    if (state.pending.contains(key)) return 0;
    state = (
      pending: <String>{...state.pending, key},
      errors: <String, String>{...state.errors}..remove(key),
    );
    try {
      final List<String> fresh = await ref
          .read(patternAiServiceProvider)
          .generateExamples(
            pattern: note.pattern,
            sourceSentence: sourceSentence,
            settings: ref.read(learningSettingsProvider),
            count: count,
          );
      final Set<String> seen = note.examples
          .map((String e) => e.toLowerCase())
          .toSet();
      final List<String> added = fresh
          .where((String e) => seen.add(e.toLowerCase()))
          .toList(growable: false);
      if (added.isNotEmpty) {
        await saveLinePatternNote(key, note, newExamples: added);
      }
      return added.length;
    } catch (e) {
      state = (
        pending: state.pending,
        errors: <String, String>{...state.errors, key: '$e'},
      );
      return 0;
    } finally {
      state = (
        pending: <String>{...state.pending}..remove(key),
        errors: state.errors,
      );
    }
  }
}

final NotifierProvider<PatternAnalysisJobs, PatternJobs>
patternAnalysisJobsProvider =
    NotifierProvider<PatternAnalysisJobs, PatternJobs>(PatternAnalysisJobs.new);
