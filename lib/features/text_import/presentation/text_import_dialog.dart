import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../import_course/domain/import_match.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/stepfun_realtime_tts.dart';
import '../data/text_lesson_packager.dart';
import '../domain/sentence_splitter.dart';

/// Paste raw social-media/article text → rule-split into sentences →
/// synthesize each with StepFun realtime TTS → ffmpeg renders an mp4
/// (picked image as the frame, else waveform) → registered as a course.
class TextImportDialog extends ConsumerStatefulWidget {
  const TextImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const TextImportDialog(),
    );
  }

  @override
  ConsumerState<TextImportDialog> createState() => _TextImportDialogState();
}

class _TextImportDialogState extends ConsumerState<TextImportDialog> {
  static const List<({String id, String label})> _voices =
      <({String id, String label})>[
        (id: 'qingchunshaonv', label: '清纯少女'),
        (id: 'linjiajiejie', label: '邻家姐姐'),
        (id: 'elegantgentle-female', label: '优雅女声'),
        (id: 'wenrounvsheng', label: '温柔女声'),
      ];

  final TextEditingController _textCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();
  List<TextEditingController> _sentenceCtrls = <TextEditingController>[];
  String _voice = 'qingchunshaonv';
  String? _imagePath;
  String? _targetCourseId;
  bool _splitDone = false;
  bool _generating = false;
  String _progress = '';
  String? _error;
  String? _doneMessage;

  @override
  void initState() {
    super.initState();
    _prefillKey();
  }

  Future<void> _prefillKey() async {
    if (Hive.isBoxOpen('prefs')) {
      final String saved =
          Hive.box<String>('prefs').get('stepfun_rt_key') ?? '';
      if (saved.isNotEmpty) {
        _keyCtrl.text = saved;
        return;
      }
    }
    // Convenience for this machine: reuse the toolkit key if present.
    const String toolkitKey = r'E:\英语口语\mwc-toolkit\stepfun_key.txt';
    try {
      final File f = File(toolkitKey);
      if (f.existsSync()) {
        _keyCtrl.text = (await f.readAsString()).trim();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _titleCtrl.dispose();
    _keyCtrl.dispose();
    for (final TextEditingController c in _sentenceCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _split() {
    final List<String> sentences = splitSentences(_textCtrl.text);
    for (final TextEditingController c in _sentenceCtrls) {
      c.dispose();
    }
    _sentenceCtrls = sentences
        .map((String s) => TextEditingController(text: s))
        .toList();
    if (_titleCtrl.text.trim().isEmpty && sentences.isNotEmpty) {
      String t = sentences.first;
      if (t.length > 30) t = '${t.substring(0, 30)}…';
      _titleCtrl.text = t;
    }
    setState(() => _splitDone = true);
  }

  Future<void> _pickImage() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: '图片',
          extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
    if (file != null) setState(() => _imagePath = file.path);
  }

  List<String> get _sentences => _sentenceCtrls
      .map((TextEditingController c) => c.text.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);

  Future<void> _generate() async {
    final List<String> sentences = _sentences;
    final String key = _keyCtrl.text.trim();
    if (sentences.isEmpty) {
      setState(() => _error = '先拆分或手填至少一句');
      return;
    }
    if (key.isEmpty) {
      setState(() => _error = '需要 StepFun API Key（realtime 语音合成）');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
      _progress = '连接 StepFun realtime…';
    });

    final StepfunRealtimeTts tts = StepfunRealtimeTts(
      apiKey: key,
      voice: _voice,
    );
    final List<({String text, Uint8List wav})> clips =
        <({String text, Uint8List wav})>[];
    final List<String> failed = <String>[];
    try {
      for (int i = 0; i < sentences.length; i++) {
        final String s = sentences[i];
        setState(() => _progress = '合成 ${i + 1}/${sentences.length}：$s');
        Uint8List? wav;
        String lastErr = '';
        for (int attempt = 0; attempt < 3 && wav == null; attempt++) {
          try {
            wav = await tts.synthesize(s);
          } catch (e) {
            lastErr = '$e'.replaceAll('\n', ' ');
            await Future<void>.delayed(const Duration(milliseconds: 800));
          }
        }
        if (wav == null) {
          failed.add('${i + 1}. $s — $lastErr');
        } else {
          clips.add((text: s, wav: wav));
        }
      }
      if (clips.isEmpty) {
        throw StateError(
          '全部句子合成失败${failed.isNotEmpty ? '：${failed.first}' : ''}',
        );
      }

      setState(() => _progress = 'ffmpeg 打包视频…');
      final Directory support = await getApplicationSupportDirectory();
      final String slug = _slug(
        _titleCtrl.text.trim().isEmpty ? 'text_lesson' : _titleCtrl.text,
      );
      final Directory outDir = Directory(
        '${support.path}${Platform.pathSeparator}imported_sources'
        '${Platform.pathSeparator}text_lessons'
        '${Platform.pathSeparator}${slug}_${DateTime.now().millisecondsSinceEpoch % 100000}',
      );
      final PackagedTextLesson pkg = await packageTextLesson(
        outDir: outDir,
        baseName: slug,
        clips: clips,
        imagePath: _imagePath,
      );

      final ImportMatchRow row = ImportMatchRow(
        episodeName: _titleCtrl.text.trim().isEmpty
            ? '文本录入'
            : _titleCtrl.text.trim(),
        videoFile: '$slug.mp4',
        videoPath: pkg.videoPath,
        subtitleTracks: <String, ImportSubtitleTrack>{
          'en': ImportSubtitleTrack(
            languageCode: 'en',
            languageLabel: '英文',
            path: pkg.subtitlePath,
          ),
        },
      );
      final bool ok = await ref
          .read(libraryCatalogProvider.notifier)
          .importCourseFromMatches(
            rows: <ImportMatchRow>[row],
            videoFolder: outDir.path,
            subtitleFolder: outDir.path,
            sourceLabel: '文本录入',
            targetCourseId: _targetCourseId,
            courseTitle: _titleCtrl.text.trim().isEmpty
                ? null
                : _titleCtrl.text.trim(),
          );
      if (!ok) throw StateError('课程注册失败');

      if (Hive.isBoxOpen('prefs')) {
        unawaited(Hive.box<String>('prefs').put('stepfun_rt_key', key));
      }
      setState(() {
        _doneMessage =
            '已生成 ${clips.length}/${sentences.length} 句（${pkg.totalSeconds.toStringAsFixed(0)}s）'
            '${failed.isEmpty ? '' : '，${failed.length} 句失败'}';
        _progress = '';
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      await tts.dispose();
      if (mounted) setState(() => _generating = false);
    }
  }

  static String _slug(String s) {
    final String t = s
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return t.isEmpty ? 'text_lesson' : t;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.edit_note_rounded, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    '文本录入 → 生成听力课',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _generating
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _doneMessage != null
                    ? _buildDone()
                    : _splitDone
                    ? _buildSentenceEditor()
                    : _buildPasteArea(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasteArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _textCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: '粘贴帖子/文章原文…每段一句或多句都行，拆分可以编辑',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: '课程标题',
                  hintText: '留空取首句',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _split,
              icon: const Icon(Icons.content_cut_rounded, size: 16),
              label: const Text('拆分句子'),
            ),
          ],
        ),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }

  Widget _buildSentenceEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView.separated(
            itemCount: _sentenceCtrls.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (BuildContext context, int i) {
              if (i == _sentenceCtrls.length) {
                return TextButton.icon(
                  onPressed: () => setState(
                    () => _sentenceCtrls.add(TextEditingController()),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('添加一句'),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${i + 1}.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _sentenceCtrls[i],
                      maxLines: null,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 18,
                    tooltip: '删除',
                    onPressed: () =>
                        setState(() => _sentenceCtrls.removeAt(i).dispose()),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: _voice,
                decoration: const InputDecoration(
                  labelText: '音色',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _voices
                    .map(
                      (({String id, String label}) v) =>
                          DropdownMenuItem<String>(
                            value: v.id,
                            child: Text(v.label),
                          ),
                    )
                    .toList(),
                onChanged: (String? v) => setState(() => _voice = v ?? _voice),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _keyCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'StepFun API Key',
                  hintText: 'realtime 权限的 key',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_rounded, size: 16),
              label: Text(_imagePath == null ? '配图（可选）' : '换图'),
            ),
            if (_imagePath != null) ...<Widget>[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(_imagePath!),
                  width: 56,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
              IconButton(
                iconSize: 16,
                tooltip: '移除配图',
                onPressed: () => setState(() => _imagePath = null),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
            const Spacer(),
            TextButton.icon(
              onPressed: _generating
                  ? null
                  : () => setState(() => _splitDone = false),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('重贴文本'),
            ),
            FilledButton.icon(
              onPressed: _generating ? null : _generate,
              icon: const Icon(Icons.graphic_eq_rounded, size: 16),
              label: Text('生成（${_sentences.length} 句）'),
            ),
          ],
        ),
        if (_progress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _progress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }

  Widget _buildDone() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.check_circle_rounded,
            size: 48,
            color: AppDesignTokens.brandGreen,
          ),
          const SizedBox(height: 12),
          Text(_doneMessage!, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
            '回到课程库 → 进入该课程 → 自动开始听写',
            style: TextStyle(
              fontSize: 12,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Color(0xFFD4380D)),
      ),
    );
  }
}
