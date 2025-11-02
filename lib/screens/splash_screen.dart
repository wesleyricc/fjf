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
import 'team_detail_screen.dart'; // Import da TeamDetailScreen

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const routeName = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

// --- 1. ADICIONA O MIXIN DE ANIMAÇÃO ---
class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late YoutubePlayerController _ytController;
  bool _isLoadingVideoId = true;
  final String _defaultVideoId = 'ByBvdFS1jko';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Lista de redes sociais
  final List<Map<String, dynamic>> _socialLinks = [
    {'icon': FontAwesomeIcons.facebook, 'url': 'https://www.facebook.com/forcajovemfumacense'},
    {'icon': FontAwesomeIcons.instagram, 'url': 'https://www.instagram.com/fjf.forcajovem'},
    {'icon': FontAwesomeIcons.youtube, 'url': 'https://www.youtube.com/@forcajovemfumacense'},
  ];

  // Estado PWA e Drawer
  html.Event? _installPromptEvent;
  bool _showInstallButton = false;
  bool _isDrawerOpen = false; 
  String? _regulationUrl;

  // Estado do Player
  bool _isPlayerExpanded = false;

  // --- 2. CONTROLLER DA ANIMAÇÃO "PISCANDO" ---
  late AnimationController _blinkController;
  // --- FIM ---

  @override
  void initState() {
    super.initState();
    debugPrint("SplashScreen: initState");

    // Inicializa o controller do YouTube
    _ytController = YoutubePlayerController.fromVideoId(
      videoId: _defaultVideoId,
      autoPlay: true, 
      params: const YoutubePlayerParams(
        showControls: true,
        mute: true, // Começa mutado
        showFullscreenButton: true,
        enableCaption: false,
      ),
    );

    // --- 3. INICIALIZA O CONTROLLER DA ANIMAÇÃO ---
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // Inicia as buscas
    _fetchFirebaseData(); 
    
    // Captura o evento de instalação (SÓ NA WEB)
    if (kIsWeb) {
      debugPrint("Verificando instalação PWA...");
      html.window.addEventListener('beforeinstallprompt', (html.Event e) {
        debugPrint("Evento 'beforeinstallprompt' capturado!");
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

  // --- FUNÇÕES DE BUSCA (Sem mudanças) ---
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
  // --- FIM DAS FUNÇÕES DE BUSCA ---

  @override
  void dispose() {
    debugPrint("SplashScreen: dispose");
    _ytController.close();
    _blinkController.dispose();
    super.dispose();
  }

  // Função para abrir URLs (sem mudanças)
  Future<void> _launchURL(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir o link: $urlString')));
    }
  }
  
  // Função para acionar o Prompt PWA (sem mudanças)
  void _triggerInstallPrompt() {
    if (_installPromptEvent == null) return;
    (_installPromptEvent as dynamic).prompt();
    setState(() {
      _installPromptEvent = null;
      _showInstallButton = false;
    });
  }

  // --- WIDGET: CABEÇALHO (sem mudanças) ---
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
  
  // --- WIDGET: SEÇÃO DE MÍDIAS (sem mudanças) ---
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
              .limit(10)
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
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  // --- WIDGET: Item da Lista de Mídia (sem mudanças) ---
  Widget _buildMediaItem(String title, String imageUrl, String targetUrl) {
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
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET: SEÇÃO DAS EQUIPES (sem mudanças) ---
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
  // --- FIM DA SEÇÃO DAS EQUIPES ---


  @override
  Widget build(BuildContext context) {
    // Verificação de plataforma (como antes)
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
      
      // --- ESTRUTURA DO BODY (Player Fixo, Conteúdo Rolável) ---
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          
          // --- 1. CONTEÚDO ROLÁVEL (DENTRO DE 'EXPANDED') ---
          Expanded(
            child: SingleChildScrollView(
              // Usa ClampingScrollPhysics para desabilitar o "bounce" do iOS
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  
                  _buildHeader(), 
                  
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
                    if (!_showInstallButton && isIOS)
                      Container(
                         padding: const EdgeInsets.all(12.0),
                         margin: const EdgeInsets.only(top: 24.0, bottom: 16.0),
                         decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(8),
                         ),
                         child: Column(
                           children: [
                             Text('Para instalar o app no seu iPhone/iPad:', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                             const SizedBox(height: 8),
                             Text('1. Toque no ícone de "Compartilhar" (quadrado com seta para cima) na barra do navegador Safari.', style: Theme.of(context).textTheme.bodySmall),
                             const SizedBox(height: 4),
                             Text('2. Role para baixo e selecione "Adicionar à Tela de Início".', style: Theme.of(context).textTheme.bodySmall),
                           ],
                         ),
                      ),
                    if (kIsWeb && !_showInstallButton && isAndroid)
                       Container(
                         padding: const EdgeInsets.all(12.0),
                         margin: const EdgeInsets.only(top: 24.0, bottom: 16.0),
                         decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(8),
                         ),
                         child: Column(
                           children: [
                             Text('Para instalar o app no seu Android:', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                             const SizedBox(height: 8),
                             Text('1. Toque no ícone de menu (três pontos ⋮) no canto superior do navegador.', style: Theme.of(context).textTheme.bodySmall),
                             const SizedBox(height: 4),
                             Text('2. Selecione a opção "Instalar aplicativo" ou "Adicionar à tela inicial".', style: Theme.of(context).textTheme.bodySmall),
                           ],
                         ),
                      ),
                  ],
                ),
              ),

                  _buildMediaFeed(), 
                  
                  const Divider(height: 24, thickness: 1, indent: 16, endIndent: 16),
                  
                  _buildTeamsGrid(),
                  
                  const SizedBox(height: 10),

                  // Copyright (movido para o final da rolagem)
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
          // --- FIM DO CONTEÚDO ROLÁVEL ---

          // --- 2. O PLAYER DO YOUTUBE (FIXO NO FIM DA COLUMN) (ATUALIZADO) ---
          
          
          // Se o drawer estiver aberto, mostra o placeholder
           _isDrawerOpen
            ? AspectRatio(
                aspectRatio: 16 / 9,
                child: Card( 
                  color: Colors.black,
                  margin: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 8.0),
                  child: Center(
                    child: const Text(
                      'Player pausado.\nFeche o menu para continuar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              )

             : Card(
                elevation: 4,
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 8.0), // Margens
                child: ExpansionTile(
                  // --- TÍTULO CLICÁVEL (COM ÍCONE PISCANDO) ---
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Ícone Piscando
                      FadeTransition(
                        opacity: _blinkController,
                        child: Icon(Icons.circle, color: Colors.red[700], size: 14),
                      ),
                      const SizedBox(width: 8),
                      // Título
                      Text(
                        'SPD Lives - Acompanhe Ao Vivo!',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  // --- FIM DO TÍTULO ---

                  // Remove a seta padrão da direita
                  trailing: const SizedBox.shrink(), 
                  // Ícone de "play" que muda (no lugar do leading)
                  leading: Icon(
                    _isPlayerExpanded ? Icons.pause_circle_outline : Icons.play_circle_fill,
                    color: Colors.red[700],
                    size: 32.0,
                  ),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  // Controla a expansão
                  initiallyExpanded: _isPlayerExpanded,
                  onExpansionChanged: (isExpanding) {
                    setState(() {
                      _isPlayerExpanded = isExpanding;
                    });
                    if (isExpanding) {
                      _ytController.unMute();
                      _ytController.playVideo();
                    } else {
                      _ytController.mute();
                      _ytController.pauseVideo();
                    }
                  },
                  // O player fica aqui, envolto em Visibility
                  children: [
                    Visibility(
                      maintainState: true, // <-- Impede o player de quebrar
                      visible: _isPlayerExpanded, 
                      child: _isLoadingVideoId
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 50.0),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : YoutubePlayer(controller: _ytController),
                    ),
                  ],
                ),
              ),
          // --- FIM DO PLAYER ---
        ],
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}