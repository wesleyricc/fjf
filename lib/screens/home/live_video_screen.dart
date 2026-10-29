import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../services/championship_service.dart';
import '../../widgets/main_bottom_nav_bar.dart';
import '../../widgets/sponsor_banner_rotator.dart';
import '../../widgets/live_stream_chat_widget.dart';
import '../../widgets/youtube/universal_youtube_player.dart';

class LiveVideoScreen extends StatefulWidget {
  const LiveVideoScreen({super.key});
  static const routeName = '/live';

  @override
  State<LiveVideoScreen> createState() => _LiveVideoScreenState();
}

class _LiveVideoScreenState extends State<LiveVideoScreen> {
  String _videoId = 'ByBvdFS1jko';
  
  @override
  void initState() {
    super.initState();
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
        if (diff.inHours < 24 && remoteId != _videoId) {
          setState(() {
            _videoId = remoteId;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Fundo padrão do App
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: AppTheme.headerImage,
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
          UniversalYoutubePlayer(
            key: ValueKey(_videoId),
            videoId: _videoId,
            autoPlay: true,
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
