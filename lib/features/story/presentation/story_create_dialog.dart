import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/story_ai_service.dart';
import '../data/story_lesson.dart';
import '../data/story_store.dart';
import '../domain/story.dart';
import 'story_reader_screen.dart';

/// Picture-book creation flow: pick photographed pages (order = pick
/// order), let the vision model draft a parentese script, edit inline,
/// then save to the story library and/or build a practice lesson.
class StoryCreateDialog extends ConsumerStatefulWidget {
  const StoryCreateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const StoryCreateDialog(),
    );
  }

  @override
  ConsumerState<StoryCreateDialog> createState() => _StoryCreateDialogState();
}

class _StoryCreateDialogState extends ConsumerState<StoryCreateDialog> {
  final TextEditingController _titleCtrl = TextEditingController(
    text: "Where's Spot?",
  );
  final TextEditingController _ageCtrl = TextEditingController(text: '14');
  final List<XFile> _picked = <XFile>[];
  List<StoryPageDraft>? _drafts;
  String? _notice;
  bool _busy = false;
  String? _savedId;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  int get _ageMonths => int.tryParse(_ageCtrl.text.trim()) ?? 14;

  Future<void> _pickImages() async {
    final List<XFile> files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: '书页照片',
          extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
    if (files.isNotEmpty) {
      setState(() {
        _picked.addAll(files);
        _drafts = null;
        _savedId = null;
      });
    }
  }

  /// Shrinks a photo to ~1024px wide PNG so a multi-page upload stays
  /// within a sane request size. Falls back to raw bytes if undecodable.
  Future<Uint8List> _downscale(String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 1024,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ByteData? png = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
      if (png != null) return png.buffer.asUint8List();
    } catch (_) {}
    return bytes;
  }

  Future<void> _generate() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _notice = '先填书名');
      return;
    }
    setState(() {
      _busy = true;
      _notice = '正在读图生成带读脚本…';
    });
    try {
      final List<Uint8List> images = <Uint8List>[
        for (final XFile f in _picked) await _downscale(f.path),
      ];
      List<StoryPageDraft> drafts = await ref
          .read(storyAiServiceProvider)
          .generateScript(
            settings: ref.read(learningSettingsProvider),
            bookTitle: _titleCtrl.text.trim(),
            childAgeMonths: _ageMonths,
            pageImages: images,
          );
      // Pair drafts with photos by index; extra photos get empty drafts,
      // extra drafts get no photo.
      while (drafts.length < _picked.length) {
        drafts = <StoryPageDraft>[...drafts, StoryPageDraft()];
      }
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _notice = '脚本已生成，检查/修改后可存入绘本库';
      });
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Copies picked photos into the story's asset dir and builds pages.
  Future<StoryRecord> _save() async {
    final String tempId = 'story-${DateTime.now().microsecondsSinceEpoch}';
    final Directory dir = await storyAssetsDir(tempId);
    await dir.create(recursive: true);
    final List<StoryPage> pages = <StoryPage>[
      for (int i = 0; i < (_drafts?.length ?? 0); i++)
        StoryPage(
          imagePath: await _copyImage(i, dir),
          printedText: _drafts![i].printedText.trim(),
          narrationLines: _drafts![i].narrationLines
              .map((String e) => e.trim())
              .where((String e) => e.isNotEmpty)
              .toList(),
          tipCn: _drafts![i].tipCn.trim(),
        ),
    ];
    final StoryRecord record = StoryRecord(
      id: tempId,
      title: _titleCtrl.text.trim(),
      childAgeMonths: _ageMonths,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      pages: pages,
    );
    await ref
        .read(storyBookProvider.notifier)
        .addStory(
          title: record.title,
          childAgeMonths: record.childAgeMonths,
          pages: pages,
        );
    // addStory assigns its own id — align the asset dir with it.
    final StoryRecord saved = ref.read(storyBookProvider).first;
    if (saved.id != tempId) {
      final Directory realDir = await storyAssetsDir(saved.id);
      await dir.rename(realDir.path);
      final StoryRecord fixed = StoryRecord(
        id: saved.id,
        title: saved.title,
        childAgeMonths: saved.childAgeMonths,
        createdAtMs: saved.createdAtMs,
        pages: <StoryPage>[
          for (final StoryPage p in saved.pages)
            p.copyWith(imagePath: p.imagePath.replaceAll(tempId, saved.id)),
        ],
      );
      await ref.read(storyBookProvider.notifier).updateStory(fixed);
      return fixed;
    }
    return saved;
  }

  Future<String> _copyImage(int index, Directory dir) async {
    if (index >= _picked.length) return '';
    final String ext = _picked[index].path.contains('.')
        ? _picked[index].path.substring(_picked[index].path.lastIndexOf('.'))
        : '.jpg';
    final String dest =
        '${dir.path}${Platform.pathSeparator}page_${(index + 1).toString().padLeft(2, '0')}$ext';
    await File(_picked[index].path).copy(dest);
    return dest;
  }

  Future<void> _saveOnly() async {
    if (_drafts == null) return;
    setState(() => _busy = true);
    try {
      final StoryRecord saved = await _save();
      if (!mounted) return;
      setState(() {
        _savedId = saved.id;
        _notice = '已存入绘本库';
      });
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// All spoken lines → StepFun TTS → practice lesson (mp4 with the first
  /// page as the video frame on desktop; audio-only wav on Android).
  Future<void> _saveAndGenerateLesson() async {
    if (_drafts == null) return;
    setState(() {
      _busy = true;
      _notice = '保存绘本…';
    });
    try {
      final StoryRecord saved = await _save();
      _savedId = saved.id;
      final String msg = await generateStoryLesson(
        ref: ref,
        story: saved,
        onStep: (String step) {
          if (mounted) setState(() => _notice = step);
        },
      );
      if (!mounted) return;
      setState(() => _notice = msg);
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 660),
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
                      '新建绘本带读',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _titleCtrl,
                            decoration: const InputDecoration(
                              labelText: '书名',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _ageCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '宝宝月龄',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _pickImages,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(_picked.isEmpty ? '选择书页照片' : '追加照片'),
                        ),
                        const SizedBox(width: 8),
                        if (_picked.isNotEmpty)
                          Text(
                            '已选 ${_picked.length} 页（按顺序对应）',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    if (_picked.isNotEmpty)
                      SizedBox(
                        height: 96,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _picked.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, int i) => Stack(
                            children: <Widget>[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_picked[i].path),
                                  height: 80,
                                  width: 64,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _picked.removeAt(i);
                                    _drafts = null;
                                    _savedId = null;
                                  }),
                                  child: const CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.black54,
                                    child: Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _generate,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(_drafts == null ? '生成带读脚本' : '重新生成脚本'),
                    ),
                    if (_drafts != null) ...<Widget>[
                      const SizedBox(height: 12),
                      for (int i = 0; i < _drafts!.length; i++)
                        _DraftPageCard(
                          index: i,
                          draft: _drafts![i],
                          imagePath: i < _picked.length
                              ? _picked[i].path
                              : null,
                          onChanged: () => setState(() {}),
                        ),
                    ],
                  ],
                ),
              ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: <Widget>[
                      if (_busy)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(
                          Icons.info_outline,
                          size: 14,
                          color: AppDesignTokens.textSecondary,
                        ),
                      const SizedBox(width: 6),
                      Expanded(
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
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (_savedId != null)
                    TextButton.icon(
                      onPressed: () {
                        final StoryRecord? saved = ref
                            .read(storyBookProvider)
                            .where((StoryRecord e) => e.id == _savedId)
                            .firstOrNull;
                        if (saved != null) {
                          unawaited(StoryReaderScreen.show(context, saved));
                        }
                      },
                      icon: const Icon(Icons.menu_book_outlined, size: 16),
                      label: const Text('打开带读'),
                    ),
                  TextButton(
                    onPressed: _busy || _drafts == null ? null : _saveOnly,
                    child: const Text('存入绘本库'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy || _drafts == null
                        ? null
                        : _saveAndGenerateLesson,
                    icon: const Icon(Icons.record_voice_over_rounded, size: 18),
                    label: const Text('存库并生成练习课'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftPageCard extends StatelessWidget {
  const _DraftPageCard({
    required this.index,
    required this.draft,
    required this.imagePath,
    required this.onChanged,
  });

  final int index;
  final StoryPageDraft draft;
  final String? imagePath;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (imagePath != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(imagePath!),
                        width: 44,
                        height: 58,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Text(
                  '第 ${index + 1} 页',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            TextFormField(
              key: ValueKey<String>('printed-$index'),
              initialValue: draft.printedText,
              decoration: const InputDecoration(
                labelText: '页面原文',
                isDense: true,
              ),
              onChanged: (String v) => draft.printedText = v,
            ),
            const SizedBox(height: 6),
            for (int j = 0; j < draft.narrationLines.length; j++)
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      key: ValueKey<String>('narr-$index-$j'),
                      initialValue: draft.narrationLines[j],
                      decoration: InputDecoration(
                        labelText: '带读句 ${j + 1}',
                        isDense: true,
                      ),
                      onChanged: (String v) => draft.narrationLines[j] = v,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    onPressed: () {
                      draft.narrationLines.removeAt(j);
                      onChanged();
                    },
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  draft.narrationLines.add('');
                  onChanged();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('加一句', style: TextStyle(fontSize: 12)),
              ),
            ),
            TextFormField(
              key: ValueKey<String>('tip-$index'),
              initialValue: draft.tipCn,
              decoration: const InputDecoration(
                labelText: '中文互动提示',
                isDense: true,
              ),
              onChanged: (String v) => draft.tipCn = v,
            ),
          ],
        ),
      ),
    );
  }
}
