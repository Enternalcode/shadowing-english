import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/story.dart';

/// Full-screen swipeable read-aloud view: one card per book page with the
/// photographed page on top and the parentese lines in large type below —
/// built for glancing at the phone while reading to the baby.
class StoryReaderScreen extends ConsumerStatefulWidget {
  const StoryReaderScreen({
    required this.story,
    this.initialPage = 0,
    super.key,
  });

  final StoryRecord story;
  final int initialPage;

  static Future<void> show(BuildContext context, StoryRecord story) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => Dialog.fullscreen(child: StoryReaderScreen(story: story)),
    );
  }

  @override
  ConsumerState<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends ConsumerState<StoryReaderScreen> {
  late final PageController _pager = PageController(
    initialPage: widget.initialPage,
  );
  late int _index = widget.initialPage;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _go(int delta) {
    _pager.animateToPage(
      _index + delta,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<StoryPage> pages = widget.story.pages;
    return Scaffold(
      backgroundColor: const Color(0xFFFBF8F2),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.story.title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: pages.length,
              onPageChanged: (int i) => setState(() => _index = i),
              itemBuilder: (_, int i) => _StoryPageCard(page: pages[i]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: _index > 0 ? () => _go(-1) : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 30),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_index + 1} / ${pages.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _index < pages.length - 1 ? () => _go(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 30),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryPageCard extends ConsumerWidget {
  const _StoryPageCard({required this.page});

  final StoryPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: <Widget>[
        if (page.imagePath.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.34,
              ),
              child: Image.file(
                File(page.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 120,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
        if (page.imagePath.isNotEmpty) const SizedBox(height: 10),
        if (page.printedText.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3D6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '📖 ${page.printedText}',
              style: const TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        const SizedBox(height: 10),
        for (final String line in page.narrationLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                InkWell(
                  onTap: () => unawaited(
                    ref.read(wordPronunciationServiceProvider).speak(line),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.volume_up_rounded,
                      size: 20,
                      color: AppDesignTokens.brandGreenDark,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (page.tipCn.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F4EA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '💡 ${page.tipCn}',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF2F6B3C),
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}
