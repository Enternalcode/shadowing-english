import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Returns the path of a `cover.*` image sitting next to [videoPath]
/// (written by the text-import packager), or null when there is none.
String? findCoverImageForVideo(String? videoPath) {
  if (videoPath == null || videoPath.isEmpty) {
    return null;
  }
  final int sep = videoPath.lastIndexOf(Platform.pathSeparator);
  final int slash = videoPath.lastIndexOf('/');
  final int cut = sep > slash ? sep : slash;
  if (cut <= 0) {
    return null;
  }
  final String dir = videoPath.substring(0, cut);
  for (final String ext in const <String>[
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
  ]) {
    final String candidate = '$dir${Platform.pathSeparator}cover$ext';
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

/// Renders a local image file as an interactive, zoomable surface for
/// image-backed lessons (screenshot corpora etc.). Mouse wheel zooms around
/// the cursor, dragging pans, and double-tap resets. Replaces the media_kit
/// Video widget while the mp4's audio track keeps playing underneath.
class ZoomableImageSurface extends StatefulWidget {
  const ZoomableImageSurface({required this.imagePath, super.key});

  final String imagePath;

  @override
  State<ZoomableImageSurface> createState() => _ZoomableImageSurfaceState();
}

class _ZoomableImageSurfaceState extends State<ZoomableImageSurface> {
  static const double _maxScale = 8;

  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoomAt(Offset focal, double factor) {
    final Matrix4 current = _controller.value.clone();
    final double scale = current.getMaxScaleOnAxis();
    final double applied = (scale * factor / scale).clamp(
      1.0 / scale,
      _maxScale / scale,
    );
    if (applied == 1.0) {
      return;
    }
    _controller.value = current.multiplied(
      _translation(focal.dx, focal.dy)
          .multiplied(Matrix4.diagonal3Values(applied, applied, 1))
          .multiplied(_translation(-focal.dx, -focal.dy)),
    );
  }

  static Matrix4 _translation(double x, double y) => Matrix4.identity()
    ..setEntry(3, 0, x)
    ..setEntry(3, 1, y);

  void _handleSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _zoomAt(event.localPosition, event.scrollDelta.dy < 0 ? 1.12 : 0.9);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _handleSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _controller.value = Matrix4.identity(),
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: _maxScale,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: Image.file(
            File(widget.imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Color(0x66FFFFFF),
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
