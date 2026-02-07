import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/championship_service.dart';

class HomeLiveVideoCard extends StatefulWidget {
  final bool hidePlayer;

  const HomeLiveVideoCard({super.key, this.hidePlayer = false});

  @override
  State<HomeLiveVideoCard> createState() => _HomeLiveVideoCardState();
}

class _HomeLiveVideoCardState extends State<HomeLiveVideoCard> with SingleTickerProviderStateMixin {
  late YoutubePlayerController _ytController;
  
  bool _isPlayerExpanded = false;
  final String _defaultVideoId = 'ByBvdFS1jko'; 
  late AnimationController _blinkController;
  bool _hasActiveLive = false;

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

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Carrega do Cache em vez de chamar Firebase
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLiveFromCache());
  }

  void _checkLiveFromCache() {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final data = service.appSettings; // Dados cacheados

    if (data != null) {
      final String? remoteId = data['live_video_id'];
      final Timestamp? timestamp = data['live_video_timestamp'];

      if (remoteId != null && remoteId.isNotEmpty && timestamp != null) {
        final diff = DateTime.now().difference(timestamp.toDate());
        // Regra: Mostra a live se foi iniciada nas últimas 24h
        if (diff.inHours < 24) {
          _ytController.loadVideoById(videoId: remoteId);
          setState(() {
            _hasActiveLive = true;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _ytController.close();
    _blinkController.dispose();
    super.dispose();
  }

  void _togglePlayer() {
    setState(() {
      _isPlayerExpanded = !_isPlayerExpanded;
      if (_isPlayerExpanded) {
        _ytController.playVideo();
      } else {
        _ytController.pauseVideo();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Se não tiver live ativa detectada no cache, nem mostra o widget
    // (Ou você pode remover essa verificação se quiser mostrar o botão padrão sempre)
    // if (!_hasActiveLive) return const SizedBox.shrink(); 

    if (widget.hidePlayer || !_isPlayerExpanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14.0),
              elevation: 4,
              shadowColor: Colors.redAccent.withOpacity(0.4),
            ),
            onPressed: widget.hidePlayer ? null : _togglePlayer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: _blinkController,
                  child: const Icon(Icons.circle, size: 14, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('ASSISTIR AO VIVO / VÍDEO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 8,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.live_tv, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      const Text("Transmissão FJF TV", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  InkWell(
                    onTap: _togglePlayer,
                    child: const Icon(Icons.close, color: Colors.white, size: 22),
                  )
                ],
              ),
            ),
            YoutubePlayer(
              controller: _ytController,
              aspectRatio: 16 / 9,
            ),
          ],
        ),
      ),
    );
  }
}