import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class UniversalYoutubePlayer extends StatefulWidget {
  final String videoId;
  final bool autoPlay;
  final double aspectRatio;

  const UniversalYoutubePlayer({
    super.key,
    required this.videoId,
    this.autoPlay = false,
    this.aspectRatio = 16 / 9,
  });

  @override
  State<UniversalYoutubePlayer> createState() => _UniversalYoutubePlayerState();
}

class _UniversalYoutubePlayerState extends State<UniversalYoutubePlayer> {
  late String _viewId;
  web.HTMLIFrameElement? _iframeElement;

  @override
  void initState() {
    super.initState();
    _initIframe();
  }

  @override
  void didUpdateWidget(covariant UniversalYoutubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId || oldWidget.autoPlay != widget.autoPlay) {
      _iframeElement?.src = _buildSrc();
    }
  }

  String _buildSrc() {
    final auto = widget.autoPlay ? '1' : '0';
    return 'https://www.youtube-nocookie.com/embed/${widget.videoId}?autoplay=$auto&rel=0&playsinline=1';
  }

  void _initIframe() {
    _viewId = 'yt-embed-${widget.videoId}-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) {
        final iframe = web.HTMLIFrameElement()
          ..src = _buildSrc()
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = 'none'
          ..style.pointerEvents = 'auto'
          ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
          ..referrerPolicy = 'strict-origin-when-cross-origin'
          ..allowFullscreen = true;
        _iframeElement = iframe;
        return iframe;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: HtmlElementView(
        key: ValueKey(_viewId),
        viewType: _viewId,
      ),
    );
  }
}
