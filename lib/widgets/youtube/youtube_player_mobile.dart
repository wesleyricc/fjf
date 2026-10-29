import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

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
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: widget.autoPlay,
      params: const YoutubePlayerParams(
        showControls: true,
        mute: false,
        showFullscreenButton: true,
        loop: false,
        enableCaption: false,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant UniversalYoutubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      if (widget.autoPlay) {
        _controller.loadVideoById(videoId: widget.videoId);
      } else {
        _controller.cueVideoById(videoId: widget.videoId);
      }
    }
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: YoutubePlayer(
        controller: _controller,
        aspectRatio: widget.aspectRatio,
      ),
    );
  }
}
