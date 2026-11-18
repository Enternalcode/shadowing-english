import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/story.dart';

const String _storyLibraryStorageKey = 'story_library_v1';

final NotifierProvider<StoryBookNotifier, List<StoryRecord>> storyBookProvider =
    NotifierProvider<StoryBookNotifier, List<StoryRecord>>(
      StoryBookNotifier.new,
    );

/// Directory holding a story's copied page photos — lives under the app
/// support dir so stories survive reinstalls of picked-source images.
Future<Directory> storyAssetsDir(String storyId) async {
  final Directory support = await getApplicationSupportDirectory();
  return Directory(
    '${support.path}${Platform.pathSeparator}story_assets'
    '${Platform.pathSeparator}$storyId',
  );
}

class StoryBookNotifier extends Notifier<List<StoryRecord>> {
  @override
  List<StoryRecord> build() {
    if (!Hive.isBoxOpen('prefs')) return const <StoryRecord>[];
    final String? stored = Hive.box<String>(
      'prefs',
    ).get(_storyLibraryStorageKey);
    if (stored == null || stored.isEmpty) return const <StoryRecord>[];
    try {
      return (jsonDecode(stored) as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(StoryRecord.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <StoryRecord>[];
    }
  }

  Future<StoryRecord> addStory({
    required String title,
    required int childAgeMonths,
    required List<StoryPage> pages,
  }) async {
    final StoryRecord entry = StoryRecord(
      id: 'story-${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim(),
      childAgeMonths: childAgeMonths,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      pages: pages,
    );
    state = <StoryRecord>[entry, ...state];
    await _persist();
    return entry;
  }

  Future<void> updateStory(StoryRecord updated) async {
    state = state
        .map((StoryRecord e) => e.id == updated.id ? updated : e)
        .toList(growable: false);
    await _persist();
  }

  /// Removes the record and its copied page photos.
  Future<void> removeStory(String id) async {
    state = state.where((StoryRecord e) => e.id != id).toList(growable: false);
    await _persist();
    unawaited(_deleteAssets(id));
  }

  static Future<void> _deleteAssets(String id) async {
    try {
      final Directory d = await storyAssetsDir(id);
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      _storyLibraryStorageKey,
      jsonEncode(state.map((StoryRecord e) => e.toJson()).toList()),
    );
  }
}
