import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class MatchMediaTab extends StatefulWidget {
  final List<Map<String, dynamic>> mediaLinks;

  const MatchMediaTab({super.key, required this.mediaLinks});

  @override
  State<MatchMediaTab> createState() => _MatchMediaTabState();
}

class _MatchMediaTabState extends State<MatchMediaTab> {
  VideoPlayerController? _activeVideoPlayerController;
  ChewieController? _activeChewieController;
  String _activeMediaTitle = '';
  String _currentVideoUrl = '';

  @override
  void initState() {
    super.initState();
    if (widget.mediaLinks.isNotEmpty) {
      _changeMediaVideo(
        widget.mediaLinks.first['videoUrl'],
        widget.mediaLinks.first['title'],
        autoPlay: false,
      );
    }
  }

  @override
  void dispose() {
    _activeVideoPlayerController?.dispose();
    _activeChewieController?.dispose();
    super.dispose();
  }

  Future<void> _changeMediaVideo(String videoUrl, String title, {bool autoPlay = true}) async {
    if (_currentVideoUrl == videoUrl) return;

    _activeChewieController?.dispose();
    _activeVideoPlayerController?.dispose(); 
    _activeChewieController = null; 

    if (!mounted) return;

    setState(() {
      _currentVideoUrl = videoUrl;
      _activeMediaTitle = title;
    });

    try {
      final newVideoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await newVideoController.initialize();

      if (!mounted) {
        newVideoController.dispose();
        return;
      }

      _activeVideoPlayerController = newVideoController;

      _activeChewieController = ChewieController(
        videoPlayerController: _activeVideoPlayerController!,
        autoPlay: autoPlay,
        looping: false,
        aspectRatio: _activeVideoPlayerController!.value.aspectRatio > 0 
            ? _activeVideoPlayerController!.value.aspectRatio 
            : 16 / 9,
        allowFullScreen: true,
        placeholder: Container(color: Colors.black, child: const Center(child: CircularProgressIndicator())),
        errorBuilder: (context, errorMessage) {
          return Center(child: Padding(padding: const EdgeInsets.all(8.0), child: Text('Erro: $errorMessage', style: const TextStyle(color: Colors.white))));
        },
      );

      setState(() {}); 
    } catch (e) {
      debugPrint("Erro ao carregar vídeo: $e");
      if (mounted) {
        setState(() => _activeMediaTitle = "Erro ao carregar vídeo");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaLinks.isEmpty) {
      return const Center(child: Text('Nenhuma mídia disponível.'));
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Área do Player
                Card(
                  elevation: 3,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_activeMediaTitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 8.0),
                          child: Text(
                            _activeMediaTitle,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          color: Colors.black,
                          child: _activeChewieController != null && _activeVideoPlayerController!.value.isInitialized
                              ? Chewie(controller: _activeChewieController!)
                              : const Center(child: CircularProgressIndicator(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text('Lista de Reprodução', style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
          ),
        ),
        
        // Lista de Vídeos Otimizada
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final media = widget.mediaLinks[index];
              final String title = media['title'] ?? 'Vídeo';
              final String videoUrl = media['videoUrl'];
              final bool isPlaying = (_currentVideoUrl == videoUrl);

              return ListTile(
                dense: true,
                selected: isPlaying,
                selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
                leading: Icon(
                  isPlaying ? Icons.play_circle_fill : Icons.play_circle_outline,
                  color: isPlaying ? Theme.of(context).primaryColor : Colors.grey,
                ),
                title: Text(title, style: TextStyle(fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal)),
                onTap: () => _changeMediaVideo(videoUrl, title),
              );
            },
            childCount: widget.mediaLinks.length,
          ),
        ),
        
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }
}