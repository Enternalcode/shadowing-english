import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _atlasAsset = 'assets/dictionary/word_atlas.json';
const String _atlasMediaBase = 'https://0xlei.tech/words/atlas';

final Provider<WordAtlasDictionary> wordAtlasDictionaryProvider =
    Provider<WordAtlasDictionary>((Ref ref) => WordAtlasDictionary());

class WordAtlasSense {
  const WordAtlasSense({required this.pos, required this.zh, required this.en});

  final String pos;
  final String zh;
  final String en;
}

class WordAtlasExample {
  const WordAtlasExample({required this.en, required this.zh});

  final String en;
  final String zh;
}

class WordAtlasEntry {
  const WordAtlasEntry({
    required this.id,
    required this.word,
    required this.ipaUk,
    required this.ipaUs,
    required this.senses,
    required this.examples,
    required this.collocations,
    required this.tip,
    required this.cefr,
    required this.topic,
  });

  final String id;
  final String word;
  final String ipaUk;
  final String ipaUs;
  final List<WordAtlasSense> senses;
  final List<WordAtlasExample> examples;
  final List<String> collocations;
  final String tip;
  final String cefr;
  final String topic;

  String get imageUrl => '$_atlasMediaBase/img/$id.webp';
  String get ukAudioUrl => '$_atlasMediaBase/audio/uk/$id.mp3';
  String get usAudioUrl => '$_atlasMediaBase/audio/us/$id.mp3';
  String get exampleAudioUrl => '$_atlasMediaBase/audio/ex/$id.mp3';
}

/// Word Atlas (词光, CC BY 4.0): 7,298 curated entries with illustrations
/// and recorded pronunciations. Bundled JSON covers the text offline;
/// media streams on demand from the project's CDN.
class WordAtlasDictionary {
  Future<Map<String, WordAtlasEntry>>? _entriesFuture;

  Future<WordAtlasEntry?> lookup(String rawWord) async {
    final String word = rawWord.trim().toLowerCase().replaceAll('’', "'");
    if (word.isEmpty) return null;
    final Map<String, WordAtlasEntry> entries = await (_entriesFuture ??=
        _load());
    for (final String candidate in _candidates(word)) {
      final WordAtlasEntry? entry = entries[candidate];
      if (entry != null) return entry;
    }
    return null;
  }

  /// Exact hit first, then light de-inflection so `dedicated` can reach
  /// `dedicate` and `studies` can reach `study`.
  Iterable<String> _candidates(String word) sync* {
    yield word;
    if (word.endsWith("'s")) {
      yield word.substring(0, word.length - 2);
    }
    if (word.endsWith('ies') && word.length > 3) {
      yield '${word.substring(0, word.length - 3)}y';
    }
    if (word.endsWith('es') && word.length > 3) {
      yield word.substring(0, word.length - 2);
    }
    if (word.endsWith('s') && word.length > 2 && !word.endsWith('ss')) {
      yield word.substring(0, word.length - 1);
    }
    if (word.endsWith('ied') && word.length > 3) {
      yield '${word.substring(0, word.length - 3)}y';
    }
    if (word.endsWith('ed') && word.length > 3) {
      yield word.substring(0, word.length - 2);
      yield '${word.substring(0, word.length - 2)}e';
    }
    if (word.endsWith('ing') && word.length > 4) {
      yield word.substring(0, word.length - 3);
      yield '${word.substring(0, word.length - 3)}e';
    }
    if (word.endsWith('er') && word.length > 4) {
      yield word.substring(0, word.length - 2);
    }
    if (word.endsWith('est') && word.length > 5) {
      yield word.substring(0, word.length - 3);
    }
  }

  Future<Map<String, WordAtlasEntry>> _load() async {
    final List<dynamic> decoded =
        jsonDecode(await rootBundle.loadString(_atlasAsset)) as List<dynamic>;
    final Map<String, WordAtlasEntry> entries = <String, WordAtlasEntry>{};
    for (final dynamic raw in decoded) {
      final Map<String, dynamic> item = raw as Map<String, dynamic>;
      final String word = (item['w'] as String? ?? '').trim();
      if (word.isEmpty) continue;
      final List<WordAtlasSense> senses = <WordAtlasSense>[
        for (final dynamic s
            in (item['senses'] as List<dynamic>? ?? const <dynamic>[]))
          if (s is Map<String, dynamic>)
            WordAtlasSense(
              pos: (s['pos'] as String? ?? '').trim(),
              zh: (s['zh'] as String? ?? '').trim(),
              en: (s['en'] as String? ?? '').trim(),
            ),
      ];
      final List<WordAtlasExample> examples = <WordAtlasExample>[
        for (final dynamic e
            in (item['ex'] as List<dynamic>? ?? const <dynamic>[]))
          if (e is Map<String, dynamic>)
            WordAtlasExample(
              en: (e['en'] as String? ?? '').trim(),
              zh: (e['zh'] as String? ?? '').trim(),
            ),
      ];
      entries[word.toLowerCase().replaceAll('’', "'")] = WordAtlasEntry(
        id: (item['id'] as String? ?? word).trim(),
        word: word,
        ipaUk: (item['uk'] as String? ?? '').trim(),
        ipaUs: (item['us'] as String? ?? '').trim(),
        senses: senses,
        examples: examples,
        collocations: (item['col'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false),
        tip: (item['tip'] as String? ?? '').trim(),
        cefr: (item['cefr'] as String? ?? '').trim(),
        topic: (item['topic'] as String? ?? '').trim(),
      );
    }
    return entries;
  }
}
