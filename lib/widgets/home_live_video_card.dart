import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeLiveVideoCard extends StatefulWidget {
  final bool hidePlayer; // <-- Controle externo para evitar sobreposição

  const HomeLiveVideoCard({super.key, this.hidePlayer = false});

  @override
  State<HomeLiveVideoCard> createState() => _HomeLiveVideoCardState();
}

class _HomeLiveVideoCardState extends State<HomeLiveVideoCard> with SingleTickerProviderStateMixin {
  late YoutubePlayerController _ytController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isPlayerExpanded = false;
  final String _defaultVideoId = 'ByBvdFS1jko'; 
  late AnimationController _blinkController;

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

    _fetchCurrentLiveId();
  }

  @override
  void dispose() {
    _ytController.close();
    _blinkController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLiveId() async {
    try {
      final docSnap = await _firestore.collection('config').doc('app_settings').get();
      if (docSnap.exists) {
        final data = docSnap.data();
        final String? remoteId = data?['live_video_id'];
        final Timestamp? timestamp = data?['live_video_timestamp'];

        if (remoteId != null && remoteId.isNotEmpty && timestamp != null) {
          final diff = DateTime.now().difference(timestamp.toDate());
          if (diff.inHours < 24) {
            _ytController.loadVideoById(videoId: remoteId);
          }
        }
      }
    } catch (_) {}
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
    // Se o Drawer estiver aberto, ou o player estiver fechado, mostra o botão
    if (widget.hidePlayer || !_isPlayerExpanded) {
      // Se o drawer abrir enquanto o vídeo toca, pausamos visualmente
      if (widget.hidePlayer && _isPlayerExpanded) {
         // Opcional: _ytController.pauseVideo(); 
         // Mas apenas esconder a view já resolve o erro visual
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              shadowColor: Colors.redAccent.withOpacity(0.4),
            ),
            onPressed: widget.hidePlayer ? null : _togglePlayer, // Desabilita clique se menu aberto
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

    // Player Expandido (Só renderiza se hidePlayer for false)
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