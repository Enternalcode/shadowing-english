import 'dart:async';
import 'dart:io';
import 'dart:ui' show PathMetric;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

import '../../import_course/domain/import_match.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/lesson_from_text_generator.dart';
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
  bool _dragging = false;
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

  /// Reads an image straight off the system clipboard (Win+Shift+S
  /// screenshots etc.) and stores it under the temp dir for packaging.
  Future<void> _pasteClipboardImage() async {
    try {
      final Uint8List? bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty) {
        final Directory tmp = await getTemporaryDirectory();
        final String path =
            '${tmp.path}${Platform.pathSeparator}text_import_clip'
            '_${DateTime.now().millisecondsSinceEpoch}.png';
        await File(path).writeAsBytes(bytes);
        setState(() {
          _imagePath = path;
          _error = null;
        });
        return;
      }
      // Copied an image FILE in Explorer rather than image pixels.
      const Set<String> imageExts = <String>{
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.bmp',
      };
      final List<String> files = await Pasteboard.files();
      final String? fileImage = files
          .where(
            (String f) =>
                imageExts.any((String e) => f.toLowerCase().endsWith(e)),
          )
          .firstOrNull;
      if (fileImage != null && File(fileImage).existsSync()) {
        setState(() {
          _imagePath = fileImage;
          _error = null;
        });
        return;
      }
      setState(() => _error = '剪贴板里没有图片（先 Win+Shift+S 截图再点）');
    } catch (e) {
      setState(() => _error = '读取剪贴板图片失败：$e');
    }
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

    try {
      final Directory support = await getApplicationSupportDirectory();
      final String slug = slugifyLessonName(
        _titleCtrl.text.trim().isEmpty ? 'text_lesson' : _titleCtrl.text,
      );
      final Directory outDir = Directory(
        '${support.path}${Platform.pathSeparator}imported_sources'
        '${Platform.pathSeparator}text_lessons'
        '${Platform.pathSeparator}${slug}_${DateTime.now().millisecondsSinceEpoch % 100000}',
      );
      final LessonGenerationResult generated =
          await generateLessonFromSentences(
            sentences: sentences,
            apiKey: key,
            voice: _voice,
            outDir: outDir,
            baseName: slug,
            imagePath: _imagePath,
            onStep: (String step) => setState(() => _progress = step),
          );
      final PackagedTextLesson pkg = generated.pkg;
      final List<String> failed = generated.failed;

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
            '已生成 ${generated.clipCount}/${generated.totalCount} 句 '
            '（${pkg.totalSeconds.toStringAsFixed(0)}s）'
            '${failed.isEmpty ? '' : '，${failed.length} 句失败'}';
        _progress = '';
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(
            LogicalKeyboardKey.keyV,
            control: true,
            shift: true,
          ): _pasteClipboardImage,
        },
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
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
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
        _buildImageZone(),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: _generating
                  ? null
                  : () => setState(() => _splitDone = false),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('重贴文本'),
            ),
            const Spacer(),
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

  static bool _isImageFile(String path) {
    const List<String> exts = <String>[
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.bmp',
    ];
    final String lower = path.toLowerCase();
    return exts.any(lower.endsWith);
  }

  /// Full-width dashed drop target for the lesson cover: accepts dragged
  /// image files, tap-to-browse, and clipboard paste in one place.
  Widget _buildImageZone() {
    final bool hasImage = _imagePath != null;
    final Color border = _dragging
        ? AppDesignTokens.brandGreen
        : const Color(0xFFC4CDD9);
    return DropTarget(
      onDragDone: (DropDoneDetails details) {
        setState(() => _dragging = false);
        final XFile? file = details.files.firstOrNull;
        if (file == null) {
          return;
        }
        if (_isImageFile(file.path)) {
          setState(() {
            _imagePath = file.path;
            _error = null;
          });
        } else {
          setState(() => _error = '拖入的不是图片文件');
        }
      },
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 88,
        decoration: BoxDecoration(
          color: _dragging
              ? AppDesignTokens.brandGreen.withValues(alpha: 0.08)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: border, radius: 12),
          child: hasImage ? _filledImageZone() : _emptyImageZone(),
        ),
      ),
    );
  }

  Widget _emptyImageZone() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _pickImage,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            _dragging
                ? Icons.download_rounded
                : Icons.add_photo_alternate_rounded,
            size: 26,
            color: _dragging
                ? AppDesignTokens.brandGreen
                : AppDesignTokens.textSecondary,
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _dragging ? '松手放图' : '拖拽截图/图片到这里',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '帖子配图会成为课程画面（可选）',
                style: TextStyle(
                  fontSize: 11,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          OutlinedButton(
            onPressed: _pickImage,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('选图'),
          ),
          const SizedBox(width: 6),
          FilledButton.tonalIcon(
            onPressed: _pasteClipboardImage,
            icon: const Icon(Icons.content_paste_rounded, size: 15),
            label: const Text('贴图'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  Widget _filledImageZone() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_imagePath!),
              width: 104,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '配图就绪',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _imagePath!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: _pickImage, child: const Text('换图')),
          IconButton(
            iconSize: 18,
            tooltip: '移除配图',
            onPressed: () => setState(() => _imagePath = null),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
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

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    const double dash = 6;
    const double gap = 4;
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
