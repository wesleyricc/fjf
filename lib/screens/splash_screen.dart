// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'dart:html' as html; // Para PWA
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'team_detail_screen.dart';
import 'voting/voting_menu_screen.dart'; // <--- IMPORTANTE: Importar a nova tela

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const routeName = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late YoutubePlayerController _ytController;
  bool _isLoadingVideoId = true;
  final String _defaultVideoId = 'ByBvdFS1jko';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final List<Map<String, dynamic>> _socialLinks = [
    {'icon': FontAwesomeIcons.facebook, 'url': 'https://www.facebook.com/forcajovemfumacense'},
    {'icon': FontAwesomeIcons.instagram, 'url': 'https://www.instagram.com/fjf.forcajovem'},
    {'icon': FontAwesomeIcons.youtube, 'url': 'https://www.youtube.com/@forcajovemfumacense'},
  ];

  html.Event? _installPromptEvent;
  bool _showInstallButton = false;
  bool _isDrawerOpen = false; 
  String? _regulationUrl;
  bool _isPlayerVisible = false;

  late AnimationController _blinkController;
  
  @override
  void initState() {
    super.initState();
    debugPrint("SplashScreen: initState");

    _ytController = YoutubePlayerController.fromVideoId(
      videoId: _defaultVideoId,
      autoPlay: true, 
      params: const YoutubePlayerParams(
        showControls: true,
        mute: true,
        showFullscreenButton: true,
        enableCaption: false,
      ),
    );

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _fetchFirebaseData(); 
    
    if (kIsWeb) {
      html.window.addEventListener('beforeinstallprompt', (html.Event e) {
        e.preventDefault();
        if (mounted) {
          setState(() {
            _installPromptEvent = e;
            _showInstallButton = true;
          });
        }
      });
    }
  }

  Future<void> _fetchFirebaseData() async {
    final videoIdFuture = _fetchVideoId();
    final regulationUrlFuture = _fetchRegulationUrl();
    await regulationUrlFuture;
    final String correctVideoId = await videoIdFuture; 
    if (mounted) {
      final currentId = _ytController.metadata.videoId;
      if (currentId != correctVideoId) {
        _ytController.loadVideoById(videoId: correctVideoId);
      }
      setState(() {
        _isLoadingVideoId = false; 
      });
    }
  }

  Future<String> _fetchVideoId() async {
    String correctVideoId = _defaultVideoId;
    try {
      final docSnap = await _firestore.collection('config').doc('app_settings').get();
      if (docSnap.exists) {
        final docData = docSnap.data();
        if (docData != null &&
            docData.containsKey('live_video_id') &&
            docData.containsKey('live_video_timestamp')) {
          final fetchedId = docData['live_video_id'] as String?;
          final fetchedTimestamp = docData['live_video_timestamp'] as Timestamp?;
          if (fetchedId != null && fetchedId.isNotEmpty && fetchedTimestamp != null) {
            final Duration difference = DateTime.now().difference(fetchedTimestamp.toDate());
            if (difference.inHours < 24) correctVideoId = fetchedId;
          }
        }
      }
    } catch (e) {
      debugPrint("[DIAGNÓSTICO] ERRO CATCH ao buscar ID: $e.");
    }
    return correctVideoId;
  }
 
  Future<void> _fetchRegulationUrl() async {
    try {
      final docSnap = await _firestore.collection('config').doc('app_settings').get();
      if (docSnap.exists && docSnap.data()!.containsKey('regulation_pdf_url')) {
        final fetchedUrl = docSnap.get('regulation_pdf_url') as String?;
        if (fetchedUrl != null && fetchedUrl.isNotEmpty && mounted) {
          setState(() { _regulationUrl = fetchedUrl; });
        }
      }
    } catch (e) {
      debugPrint("[DIAGNÓSTICO] ERRO CATCH ao buscar URL do Regulamento: $e");
    }
  }

  @override
  void dispose() {
    _ytController.close();
    _blinkController.dispose();
    super.dispose();
  }

  Future<void> _launchURL(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir o link: $urlString')));
    }
  }
  
  void _triggerInstallPrompt() {
    if (_installPromptEvent == null) return;
    (_installPromptEvent as dynamic).prompt();
    setState(() {
      _installPromptEvent = null;
      _showInstallButton = false;
    });
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo3_fjf.png', height: 100),
              const SizedBox(width: 12),
              const Text('FJF 2025', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (_regulationUrl != null && _regulationUrl!.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Regulamento'),
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
                  onPressed: () => _launchURL(_regulationUrl!),
                ),
              ..._socialLinks.map((link) {
                return IconButton(
                  icon: Icon(link['icon'] as IconData),
                  iconSize: 24.0,
                  color: Colors.grey[700],
                  tooltip: link['url'] as String?,
                  onPressed: () => _launchURL(link['url'] as String),
                );
              }).toList(),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildMediaFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: Text(
            'Últimas Notícias',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('media_feed')
              .where('isActive', isEqualTo: true)
              .orderBy('order', descending: true)
              .limit(20)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const SizedBox(height: 100, child: Center(child: Text('Nenhuma mídia recente disponível.')));
            }
            final mediaItems = snapshot.data!.docs;
            return SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                itemCount: mediaItems.length,
                itemBuilder: (context, index) {
                  final itemData = mediaItems[index].data() as Map<String, dynamic>? ?? {};
                  return _buildMediaItem(
                    itemData['title'] ?? 'Sem Título',
                    itemData['imageUrl'] ?? '',
                    itemData['targetUrl'] ?? '',
                    itemData['author'] ?? '',
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMediaItem(String title, String imageUrl, String targetUrl, String author) {
    return SizedBox(
      width: 180,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        margin: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        child: InkWell(
          onTap: () => _launchURL(targetUrl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 100,
                width: 180,
                child: (imageUrl.isEmpty)
                  ? Container(color: Colors.grey[200], child: const Center(child: Icon(Icons.newspaper, color: Colors.grey)))
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: Colors.grey[200]),
                      errorWidget: (context, url, error) => Container(color: Colors.grey[200], child: const Center(child: Icon(Icons.broken_image, color: Colors.grey))),
                    ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 3, 
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (author.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Por: $author',
                            style: TextStyle(
                              fontSize: 9, 
                              color: Colors.grey[600], 
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: Text(
            'Equipes Participantes',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('teams')
              .orderBy('name')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('Nenhuma equipe encontrada.'));
            }
            final teams = snapshot.data!.docs;
            return GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: teams.length,
              itemBuilder: (context, index) {
                final teamDoc = teams[index];
                final teamData = teamDoc.data() as Map<String, dynamic>;
                final String teamName = teamData['name'] ?? 'Equipe';
                final String teamShield = teamData['shield_url'] ?? '';

                return Card(
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc),
                        ),
                      );
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center, 
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: CachedNetworkImage(
                              imageUrl: teamShield,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => const Icon(Icons.shield, size: 40),
                              errorWidget: (context, url, error) => const Icon(Icons.shield, size: 40),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                          child: Text(
                            teamName,
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isIOS = false;
    bool isAndroid = false;
    bool isStandalone = false;
    if (kIsWeb) {
      final userAgent = html.window.navigator.userAgent.toLowerCase();
      isIOS = userAgent.contains('iphone') || userAgent.contains('ipad');
      isAndroid = userAgent.contains('android');
      isStandalone = html.window.matchMedia('(display-mode: standalone)').matches;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('FJF App'),
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: (isOpening) {
        if (isOpening) {
          _ytController.pauseVideo(); 
          setState(() { _isDrawerOpen = true; });
        } else {
          setState(() { _isDrawerOpen = false; });
        }
      },
      
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  
                  _buildHeader(), 
                  
                  // --- ALTERAÇÃO: BOTÃO COM VISIBILIDADE CONTROLADA ---
                  StreamBuilder<DocumentSnapshot>(
                    stream: _firestore.collection('config').doc('app_settings').snapshots(),
                    builder: (context, snapshot) {

                      // 1. Se tiver erro, esconde o botão (não trava o app)
                      if (snapshot.hasError) {
                        debugPrint("Erro no botão de votação: ${snapshot.error}");
                        return const SizedBox.shrink();
                      }

                      // 2. Se estiver carregando, mostra um espaço vazio ou loading pequeno
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }

                      if (!snapshot.hasData) return const SizedBox.shrink();

                      final data = snapshot.data!.data() as Map<String, dynamic>?;
                      // Pega o valor do banco. Se não existir a chave, assume 'true' (visível) ou 'false' conforme sua preferência.
                      // Aqui coloquei 'true' para garantir que apareça se você ainda não salvou a config pela primeira vez.
                      final bool isVotingEnabled = data?['voting_enabled'] ?? true;

                      // Se estiver desativado, retorna um widget vazio (some com o botão)
                      if (!isVotingEnabled) {
                        return const SizedBox.shrink();
                      }

                      // Se estiver ativo, retorna o botão
                      return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[700], // Dourado/Laranja
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (ctx) => const VotingMenuScreen()),
                        );
                      },
                      icon: const Icon(Icons.emoji_events, size: 28),
                      label: const Text(
                        "VOTE NOS DESTAQUES DA FJF!",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                     );
                    },
                  ),
                  // --- FIM BOTÃO ---

                  if (kIsWeb && !isStandalone)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          if (_showInstallButton && !isIOS)
                            Padding(
                              padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.download_for_offline),
                                label: const Text('Instalar Aplicativo no Dispositivo'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _triggerInstallPrompt,
                              ),
                            ),
                          // ... (Códigos de instalação iOS/Android mantidos iguais) ...
                        ],
                      ),
                    ),

                  _buildMediaFeed(), 
                  
                  const Divider(height: 24, thickness: 1, indent: 16, endIndent: 16),
                  
                  _buildTeamsGrid(),
                  
                  const SizedBox(height: 10),

                  Text(
                    'Desenvolvido por Wesley Ricardo.\nTodos os direitos reservados © FJF 2025.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isDrawerOpen)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Card( 
                color: Colors.black,
                margin: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 8.0),
                child: Center(
                  child: const Text(
                    'Player pausado.\nFeche o menu para continuar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
            )
          else if (_isLoadingVideoId)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 50.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Stack(
              alignment: Alignment.center,
              children: [
                Visibility(
                  maintainState: true,
                  visible: _isPlayerVisible,
                  child: Card( 
                    elevation: 4,
                    clipBehavior: Clip.antiAlias,
                    margin: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 8.0),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: const Icon(Icons.close_fullscreen_outlined),
                            iconSize: 20,
                            color: Colors.grey[700],
                            tooltip: 'Recolher Player',
                            onPressed: () {
                              setState(() {
                                _isPlayerVisible = false;
                              });
                              _ytController.mute(); 
                            },
                          ),
                        ),
                        YoutubePlayer(controller: _ytController),
                      ],
                    ),
                  ),
                ),

                Visibility(
                  visible: !_isPlayerVisible,
                  child: Padding( 
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
                    child: SizedBox( 
                      width: double.infinity, 
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 255, 0, 0),
                          foregroundColor: const Color.fromARGB(255, 255, 255, 255),
                          padding: const EdgeInsets.symmetric(vertical: 10.0), 
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), 
                        ),
                        onPressed: () {
                          setState(() {
                            _isPlayerVisible = true;
                          });
                          _ytController.unMute();
                          _ytController.playVideo();
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FadeTransition(
                              opacity: _blinkController,
                              child: const Icon(Icons.circle, size: 16), 
                            ),
                            const SizedBox(width: 10),
                            const Text('SDP Lives - Assistir Ao Vivo'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}