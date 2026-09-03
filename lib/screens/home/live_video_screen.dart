import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../services/championship_service.dart';
import '../../widgets/main_bottom_nav_bar.dart';
import '../../widgets/sponsor_banner_rotator.dart';
import '../../widgets/live_stream_chat_widget.dart';

class LiveVideoScreen extends StatefulWidget {
  const LiveVideoScreen({super.key});
  static const routeName = '/live';

  @override
  State<LiveVideoScreen> createState() => _LiveVideoScreenState();
}

class _LiveVideoScreenState extends State<LiveVideoScreen> {
  late YoutubePlayerController _ytController;
  final String _defaultVideoId = 'ByBvdFS1jko';
  
  @override
  void initState() {
    super.initState();
    _ytController = YoutubePlayerController.fromVideoId(
      videoId: _defaultVideoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        mute: false,
        showFullscreenButton: true,
        enableCaption: false,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLiveFromCache());
  }

  void _checkLiveFromCache() {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final data = service.appSettings;
    if (data != null) {
      final String? remoteId = data['live_video_id'];
      final Timestamp? timestamp = data['live_video_timestamp'];
      if (remoteId != null && remoteId.isNotEmpty && timestamp != null) {
        final diff = DateTime.now().difference(timestamp.toDate());
        if (diff.inHours < 24) {
          _ytController.loadVideoById(videoId: remoteId);
        }
      }
    }
  }

  @override
  void dispose() {
    _ytController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Fundo padrão do App
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.brazilGradient,
          ),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv, color: Colors.white),
            SizedBox(width: 8),
            Text('FJF TV Ao Vivo', style: TextStyle(color: Colors.white)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SponsorBannerRotator(location: 'header_live'),
          YoutubePlayer(
            controller: _ytController,
            aspectRatio: 16 / 9,
          ),
          const Expanded(
            child: LiveStreamChatWidget(),
          ),
        ],
      ),
      bottomNavigationBar: const MainBottomNavBar(currentRoute: LiveVideoScreen.routeName),
    );
  }
}
