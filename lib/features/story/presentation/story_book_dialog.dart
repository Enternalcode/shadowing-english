import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/story_lesson.dart';
import '../data/story_store.dart';
import '../domain/story.dart';
import 'story_create_dialog.dart';
import 'story_reader_screen.dart';

/// Saved picture books: open the read-aloud pager, rebuild a practice
/// lesson, or create a new book.
class StoryBookDialog extends ConsumerStatefulWidget {
  const StoryBookDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const StoryBookDialog(),
    );
  }

  @override
  ConsumerState<StoryBookDialog> createState() => _StoryBookDialogState();
}

class _StoryBookDialogState extends ConsumerState<StoryBookDialog> {
  String? _notice;
  String? _busyId;

  Future<void> _generateLesson(StoryRecord story) async {
    setState(() {
      _busyId = story.id;
      _notice = '生成练习课…';
    });
    try {
      final String msg = await generateStoryLesson(
        ref: ref,
        story: story,
        onStep: (String step) {
          if (mounted) setState(() => _notice = step);
        },
      );
      if (mounted) setState(() => _notice = msg);
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _remove(StoryRecord story) async {
    await ref.read(storyBookProvider.notifier).removeStory(story.id);
    if (mounted) setState(() => _notice = '已删除「${story.title}」');
  }

  @override
  Widget build(BuildContext context) {
    final List<StoryRecord> stories = ref.watch(storyBookProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.auto_stories_rounded, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '绘本库',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => StoryCreateDialog.show(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建绘本'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: stories.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有绘本——点「新建绘本」，拍几页书就能生成带读脚本',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppDesignTokens.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: stories.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, int i) => _StoryTile(
                          story: stories[i],
                          busy: _busyId == stories[i].id,
                          onOpen: () => unawaited(
                            StoryReaderScreen.show(context, stories[i]),
                          ),
                          onGenerate: () =>
                              unawaited(_generateLesson(stories[i])),
                          onDelete: () => unawaited(_remove(stories[i])),
                        ),
                      ),
              ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _notice!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    required this.story,
    required this.busy,
    required this.onOpen,
    required this.onGenerate,
    required this.onDelete,
  });

  final StoryRecord story;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onGenerate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String cover = story.pages
        .map((StoryPage p) => p.imagePath)
        .firstWhere((String p) => p.isNotEmpty, orElse: () => '');
    final int lines = story.practiceSentences.length;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onOpen,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: cover.isNotEmpty
              ? Image.file(
                  File(cover),
                  width: 40,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              : _placeholder(),
        ),
        title: Text(
          story.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${story.pages.length} 页 · $lines 句 · 宝宝 ${story.childAgeMonths} 月龄',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...<Widget>[
              IconButton(
                tooltip: '生成练习课',
                visualDensity: VisualDensity.compact,
                onPressed: onGenerate,
                icon: const Icon(Icons.record_voice_over_outlined, size: 18),
              ),
              IconButton(
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: 40,
    height: 52,
    color: const Color(0xFFE8F4EA),
    child: const Icon(Icons.auto_stories_outlined, size: 20),
  );
}
