import 'package:flutter/material.dart';

import '../theme/orion_theme.dart';
import '../state/orion_controller.dart';
import 'orion_overlay.dart';

/// A provider-supplied image; unavailable images remain explicit placeholders.
class ScriptThumbnail extends StatefulWidget {
  final String? imageUrl;
  final String title;
  final bool reducedMotion;
  final bool allowViewer;
  final BoxFit fit;
  final OrionController? controller;

  const ScriptThumbnail({
    super.key,
    required this.imageUrl,
    required this.title,
    this.reducedMotion = false,
    this.allowViewer = true,
    this.fit = BoxFit.cover,
    this.controller,
  });

  @override
  State<ScriptThumbnail> createState() => _ScriptThumbnailState();
}

class _ScriptThumbnailState extends State<ScriptThumbnail> {
  int _attempt = 0;
  bool _retrying = false;

  String? get _url {
    final candidate = widget.imageUrl;
    final uri = candidate == null ? null : Uri.tryParse(candidate);
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? candidate
        : null;
  }

  Future<void> _retry() async {
    final url = _url;
    if (url == null || _retrying) return;
    setState(() => _retrying = true);
    await NetworkImage(url).evict();
    if (mounted) {
      setState(() {
        _attempt++;
        _retrying = false;
      });
    }
  }

  void _viewImage() {
    final url = _url;
    if (url == null || !widget.allowViewer) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        final controller = widget.controller;
        if (controller == null) return _imageDialog(context, url);
        return OrionOverlayTheme(
          controller: controller,
          builder: (context) => _imageDialog(context, url),
        );
      },
    );
  }

  Widget _imageDialog(BuildContext context, String url) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    clipBehavior: Clip.antiAlias,
    child: OrionOverlaySurface(
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 980,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OrionType.sectionTitle,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close image',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: ScriptThumbnail(
                  imageUrl: url,
                  title: widget.title,
                  reducedMotion: widget.reducedMotion,
                  allowViewer: false,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _placeholder(
    BuildContext context, {
    bool loading = false,
    bool failed = false,
    double? progress,
  }) {
    final colors = OrionColors.of(context);
    return ColoredBox(
      color: colors.elevated,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading && !widget.reducedMotion)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  color: colors.readableAccent,
                ),
              )
            else
              Icon(
                loading
                    ? Icons.hourglass_empty_rounded
                    : failed
                    ? Icons.broken_image_outlined
                    : Icons.image_outlined,
                size: 26,
                color: colors.muted,
              ),
            const SizedBox(height: 12),
            Text(
              loading
                  ? 'Loading image…'
                  : failed
                  ? 'Image unavailable'
                  : 'No image',
              style: OrionType.body.copyWith(color: colors.muted),
            ),
            if (failed) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _retrying ? null : _retry,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Retry image'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  textStyle: OrionType.label,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final url = _url;
    final image = AspectRatio(
      aspectRatio: 16 / 9,
      child: url == null
          ? _placeholder(context)
          : Image.network(
              url,
              key: ValueKey('$url/$_attempt'),
              fit: widget.fit,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: widget.allowViewer ? 800 : null,
              semanticLabel: '${widget.title} image',
              frameBuilder: (context, child, frame, synchronous) =>
                  frame == null ? _placeholder(context, loading: true) : child,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                final total = progress.expectedTotalBytes;
                return _placeholder(
                  context,
                  loading: true,
                  progress: total != null && total > 0
                      ? progress.cumulativeBytesLoaded / total
                      : null,
                );
              },
              errorBuilder: (context, error, stackTrace) =>
                  _placeholder(context, failed: true),
            ),
    );
    if (!widget.allowViewer || url == null) return image;
    return Tooltip(
      message: 'View image',
      child: Material(
        color: colors.elevated,
        child: InkWell(
          onTap: _viewImage,
          child: Stack(
            children: [
              image,
              Positioned(
                right: 10,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.panel.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.open_in_full_rounded,
                      size: 18,
                      color: colors.ink,
                    ),
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
