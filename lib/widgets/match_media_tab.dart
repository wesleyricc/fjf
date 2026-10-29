import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/youtube_utils.dart';
import 'youtube/universal_youtube_player.dart';

class MatchMediaTab extends StatefulWidget {
  final List<Map<String, dynamic>> mediaLinks;

  const MatchMediaTab({super.key, required this.mediaLinks});

  @override
  State<MatchMediaTab> createState() => _MatchMediaTabState();
}

class _MatchMediaTabState extends State<MatchMediaTab> {
  final ScrollController _scrollController = ScrollController();

  // YouTube State
  bool _isYoutube = false;
  String? _activeVideoId;
  bool _autoPlay = false;

  // Fallback para vídeos legados do Storage (.mp4)
  VideoPlayerController? _activeVideoPlayerController;
  ChewieController? _activeChewieController;

  String _activeMediaTitle = '';
  String _currentVideoUrl = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.mediaLinks.isNotEmpty) {
      final first = widget.mediaLinks.first;
      _changeMediaVideo(
        first['videoUrl'] ?? '',
        first['title'] ?? 'Vídeo',
        autoPlay: false,
      );
    }
  }

  @override
  void didUpdateWidget(covariant MatchMediaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se a lista mudou e não tínhamos nada tocando, inicializa
    if (_currentVideoUrl.isEmpty && widget.mediaLinks.isNotEmpty) {
      final first = widget.mediaLinks.first;
      _changeMediaVideo(
        first['videoUrl'] ?? '',
        first['title'] ?? 'Vídeo',
        autoPlay: false,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _disposePlayers();
    super.dispose();
  }

  void _disposePlayers() {
    _activeChewieController?.dispose();
    _activeChewieController = null;
    _activeVideoPlayerController?.dispose();
    _activeVideoPlayerController = null;
  }

  void _scrollToPlayer() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _changeMediaVideo(String videoUrl, String title, {bool autoPlay = true}) async {
    if (videoUrl.isEmpty) return;

    final videoId = YoutubeUtils.extractVideoId(videoUrl);

    // Se já é o vídeo atual, ativa autoplay se foi clicado
    if (_currentVideoUrl == videoUrl) {
      if (!_autoPlay && autoPlay) {
        setState(() {
          _autoPlay = true;
        });
      }
      return;
    }

    setState(() {
      _currentVideoUrl = videoUrl;
      _activeMediaTitle = title;
      _autoPlay = autoPlay;
      _isLoading = true;
    });

    if (videoId != null) {
      // --- MODO YOUTUBE ---
      _activeChewieController?.dispose();
      _activeChewieController = null;
      _activeVideoPlayerController?.dispose();
      _activeVideoPlayerController = null;

      _activeVideoId = videoId;
      _isYoutube = true;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      // --- MODO LEGADO (Storage / MP4 direto) ---
      _isYoutube = false;
      _activeVideoId = null;

      _activeChewieController?.dispose();
      _activeVideoPlayerController?.dispose();
      _activeChewieController = null;

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
          placeholder: Container(
            color: Colors.black,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
          errorBuilder: (context, errorMessage) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Erro ao carregar vídeo: $errorMessage',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        );

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint("Erro ao carregar vídeo legado: $e");
        if (mounted) {
          setState(() {
            _isLoading = false;
            _activeMediaTitle = "Erro ao carregar vídeo";
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaLinks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.video_library_outlined,
                  size: 54,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nenhuma mídia disponível',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Melhores momentos, gols e transmissões no YouTube desta partida serão exibidos aqui.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Área do Player
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cabeçalho com Título e Badge
                      if (_activeMediaTitle.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isYoutube ? Icons.smart_display : Icons.videocam,
                                color: _isYoutube ? Colors.red : Theme.of(context).primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _activeMediaTitle,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_isYoutube && _activeVideoId != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'YouTube',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide(color: Colors.red.withOpacity(0.4)),
                                    foregroundColor: Colors.red,
                                  ),
                                  icon: const Icon(Icons.open_in_new, size: 14),
                                  label: const Text(
                                    'Abrir no YouTube',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: () {
                                    final url = 'https://www.youtube.com/watch?v=$_activeVideoId';
                                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),

                      // Player Responsivo 16:9
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                          ),
                          child: _buildPlayerContent(),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    children: [
                      const Icon(Icons.playlist_play, size: 22),
                      const SizedBox(width: 6),
                      Text(
                        'Vídeos da Partida (${widget.mediaLinks.length})',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // Lista de Vídeos com Thumbnails e Destaque
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final media = widget.mediaLinks[index];
                final String title = media['title'] ?? 'Vídeo ${index + 1}';
                final String videoUrl = media['videoUrl'] ?? '';
                final bool isPlaying = (_currentVideoUrl == videoUrl);
                final String? ytThumb = YoutubeUtils.getThumbnailUrl(videoUrl);
                final bool isYt = YoutubeUtils.isValidYoutubeUrl(videoUrl);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8.0),
                  elevation: isPlaying ? 2 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isPlaying
                          ? Theme.of(context).primaryColor
                          : Colors.grey.withOpacity(0.2),
                      width: isPlaying ? 1.5 : 1,
                    ),
                  ),
                  color: isPlaying
                      ? Theme.of(context).primaryColor.withOpacity(0.06)
                      : Theme.of(context).cardColor,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      _changeMediaVideo(videoUrl, title, autoPlay: true);
                      _scrollToPlayer();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          // Thumbnail Preview com Badge Play
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 96,
                              height: 54, // 16:9 proporção para 96 de largura
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (ytThumb != null)
                                    CachedNetworkImage(
                                      imageUrl: ytThumb,
                                      fit: BoxFit.cover,
                                      placeholder: (c, u) => Container(
                                        color: Colors.black12,
                                        child: const Center(
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                      errorWidget: (c, u, e) => Container(
                                        color: Colors.grey[800],
                                        child: const Icon(Icons.broken_image, color: Colors.white54, size: 20),
                                      ),
                                    )
                                  else
                                    Container(
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.movie_outlined, color: Colors.white, size: 28),
                                    ),
                                  // Overlay escuro com botão play
                                  Container(
                                    color: Colors.black.withOpacity(0.25),
                                    child: Center(
                                      child: Icon(
                                        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                        color: isPlaying ? Theme.of(context).primaryColor : Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Título e Informações
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontWeight: isPlaying ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 14,
                                    color: isPlaying
                                        ? Theme.of(context).primaryColor
                                        : null,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      isYt ? Icons.smart_display : Icons.video_file,
                                      size: 13,
                                      color: isYt ? Colors.red : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isYt ? 'YouTube' : 'Vídeo Local',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isYt ? Colors.red[700] : Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (isPlaying) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).primaryColor,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Em reprodução',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 4),
                          Icon(
                            isPlaying ? Icons.volume_up : Icons.chevron_right,
                            color: isPlaying ? Theme.of(context).primaryColor : Colors.grey,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: widget.mediaLinks.length,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildPlayerContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_isYoutube && _activeVideoId != null) {
      return UniversalYoutubePlayer(
        key: ValueKey('yt-$_activeVideoId'),
        videoId: _activeVideoId!,
        autoPlay: _autoPlay,
        aspectRatio: 16 / 9,
      );
    }

    if (!_isYoutube &&
        _activeChewieController != null &&
        _activeVideoPlayerController != null &&
        _activeVideoPlayerController!.value.isInitialized) {
      return Chewie(controller: _activeChewieController!);
    }

    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}