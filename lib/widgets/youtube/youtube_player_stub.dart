import 'package:flutter/material.dart';

class UniversalYoutubePlayer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
