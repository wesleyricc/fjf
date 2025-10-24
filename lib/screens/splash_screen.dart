// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Para ícones sociais

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const routeName = '/splash'; // Nome da rota (opcional)

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // --- Estados do Player e UI ---
  late YoutubePlayerController _ytController; // Inicializado no initState
  bool _isLoadingVideoId = true; // Controla o loading inicial do ID
  final String _defaultVideoId = 'hi8CH7KOUSk'; // SEU ID PADRÃO COMO FALLBACK
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Estados para controles customizados
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _showControls = true; // Controles começam visíveis

  // Lista de redes sociais
  final List<Map<String, dynamic>> _socialLinks = [
    {'icon': FontAwesomeIcons.facebook, 'url': 'https://www.facebook.com/forcajovemfumacense'},
    {'icon': FontAwesomeIcons.instagram, 'url': 'https://www.instagram.com/fjf.forcajovem'},
    {'icon': FontAwesomeIcons.youtube, 'url': 'https://www.youtube.com/@forcajovemfumacense'},
  ];

  @override
  void initState() {
    super.initState();
    debugPrint("SplashScreen: initState");

    // Inicializa o controller imediatamente com o ID padrão
    _ytController = YoutubePlayerController(
      initialVideoId: _defaultVideoId, // Usa o ID padrão
      flags: const YoutubePlayerFlags(
        autoPlay: false, // Vídeo começa pausado
        mute: false,     // Vídeo começa com som
        isLive: true,    // !!! Ajuste para true se for live, false se for vídeo normal !!!
        hideControls: true, // Esconde os controles padrão do YouTube
        enableCaption: false,
      ),
    )..addListener(_playerListener); // Adiciona listener para estado de play/pause

    // Inicia a busca pelo ID correto do Firestore
    _fetchAndLoadCorrectVideoId();
  }

  // Listener para atualizar o estado _isPlaying baseado no controller
  void _playerListener() {
    if (mounted) {
       final bool isCurrentlyPlaying = _ytController.value.isPlaying;
       // Atualiza _isPlaying apenas se o valor realmente mudou
       if (isCurrentlyPlaying != _isPlaying) {
         setState(() {
           _isPlaying = isCurrentlyPlaying;
         });
       }
    }
  }

  // Busca o ID do vídeo no Firestore e carrega no player
  Future<void> _fetchAndLoadCorrectVideoId() async {
    // Garante que o estado de loading comece (ou recomece) true
    if (!_isLoadingVideoId && mounted) {
      setState(() { _isLoadingVideoId = true; });
    } else if (!mounted && !_isLoadingVideoId) {
      _isLoadingVideoId = true;
    }

    String correctVideoId = _defaultVideoId; // Começa com o ID padrão
    dynamic fetchedIdFromFirestore; // Variável para guardar o que veio do banco

    try {
      debugPrint("[DIAGNÓSTICO] Iniciando busca no Firestore...");
      final docRef = _firestore.collection('config').doc('app_settings');
      final docSnap = await docRef.get();

      if (docSnap.exists) {
        debugPrint("[DIAGNÓSTICO] Documento 'app_settings' encontrado.");
        final docData = docSnap.data();
        if (docData != null && docData.containsKey('live_video_id')) {
          fetchedIdFromFirestore = docData['live_video_id'];
          debugPrint("[DIAGNÓSTICO] Campo 'live_video_id' encontrado. Valor: '$fetchedIdFromFirestore' (Tipo: ${fetchedIdFromFirestore?.runtimeType})");
          if (fetchedIdFromFirestore is String && fetchedIdFromFirestore.isNotEmpty) {
             correctVideoId = fetchedIdFromFirestore;
             debugPrint("[DIAGNÓSTICO] ID do Firestore é válido. Usando: $correctVideoId");
          } else {
             debugPrint("[DIAGNÓSTICO] ID do Firestore é nulo, vazio ou não é String. Usando padrão: $_defaultVideoId");
             correctVideoId = _defaultVideoId;
          }
        } else {
           debugPrint("[DIAGNÓSTICO] Campo 'live_video_id' NÃO encontrado. Usando padrão: $_defaultVideoId");
           correctVideoId = _defaultVideoId;
        }
      } else {
         debugPrint("[DIAGNÓSTICO] Documento 'app_settings' NÃO encontrado. Usando padrão: $_defaultVideoId");
         correctVideoId = _defaultVideoId;
      }
    } catch (e) {
      debugPrint("[DIAGNÓSTICO] ERRO CATCH ao buscar ID: $e. Usando padrão: $_defaultVideoId");
      correctVideoId = _defaultVideoId;
    } finally {
      debugPrint("[DIAGNÓSTICO] Bloco finally. ID final a ser usado: $correctVideoId");
      debugPrint("[DIAGNÓSTICO] ID inicial do controller: ${_ytController.initialVideoId}");

      if (mounted) {
        if (_ytController.initialVideoId != correctVideoId) {
          debugPrint("[DIAGNÓSTICO] IDs são diferentes. Chamando _ytController.load('$correctVideoId')...");
          _ytController.load(correctVideoId); // Carrega o ID correto
        } else {
          debugPrint("[DIAGNÓSTICO] IDs são iguais. Nenhuma ação de load necessária.");
        }
        setState(() {
          _isLoadingVideoId = false; // Finaliza o loading da busca do ID
        });
        debugPrint("[DIAGNÓSTICO] setState chamado, _isLoadingVideoId = false.");
      } else {
        debugPrint("[DIAGNÓSTICO] Widget desmontado no finally.");
      }
    }
  }

  @override
  void dispose() {
    debugPrint("SplashScreen: dispose");
    _ytController.removeListener(_playerListener); // Remove o listener
    _ytController.dispose(); // Libera recursos do controller
    super.dispose();
  }

  // Função para abrir URLs externas
  Future<void> _launchURL(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Não foi possível abrir $urlString');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o link: $urlString')),
        );
      }
    }
  }

  // Funções de controle do Player
  void _togglePlayPause() {
    // 1. Atualiza o estado local IMEDIATAMENTE para mudar o ícone
    setState(() {
      _isPlaying = !_isPlaying; // Inverte o estado atual
    });

    // 2. Aplica a ação no controller
    if (_isPlaying) { // Se o NOVO estado é 'playing'
      _ytController.play();
    } else { // Se o NOVO estado é 'paused'
      _ytController.pause();
    }
    // O listener (_playerListener) ainda servirá para sincronizar
    // se o estado mudar por outros motivos (ex: fim do vídeo, buffering).
  }

  void _toggleMute() {
    setState(() { // Atualiza o ícone imediatamente
      _isMuted = !_isMuted;
    });
    // Aplica a ação no controller
    if (_isMuted) {
      _ytController.mute();
    } else {
      _ytController.unMute();
    }
  }

  // Controla a visibilidade dos botões sobrepostos
  void _toggleControlsVisibility() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FJF App - Página Inicial'),
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0), // Padding inferior para banner
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Estica filhos na horizontal
          children: [
            // --- 1. Logo Principal ---
            Image.asset(
              'assets/logo3_fjf.png', // Verifique o nome/caminho da sua logo
              height: 120,
            ),
            const SizedBox(height: 10),

            // --- 2. Player do YouTube ---
            Card(
              elevation: 4,
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: Text(
                      'SPD Lives - Transmissão', // Seu título
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Mostra Loading ou o Player com Controles
                  _isLoadingVideoId
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 50.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Stack( // Usa Stack para sobrepor controles
                          alignment: Alignment.center,
                          children: [
                            // Player (base)
                            YoutubePlayer(
                              controller: _ytController,
                              showVideoProgressIndicator: false, // Desliga barra de progresso padrão
                              onReady: () => debugPrint('Player is ready.'),
                              onEnded: (metaData) { // Pausa o ícone no fim
                                 if (mounted) setState(() => _isPlaying = false);
                              },
                            ),

                            // Camada de Controles (sobreposta)
                            GestureDetector(
                              onTap: _toggleControlsVisibility, // Mostra/Esconde ao tocar
                              behavior: HitTestBehavior.translucent, // Pega toque na área toda
                              child: AnimatedOpacity(
                                 opacity: _showControls ? 1.0 : 0.0, // Anima visibilidade
                                 duration: const Duration(milliseconds: 300),
                                 child: Container( // Fundo escuro opcional
                                 color: Colors.transparent,
                                   child: Center(
                                     child: Row(
                                       mainAxisAlignment: MainAxisAlignment.center,
                                       children: [
                                         // Botão Play/Pause
                                         IconButton(
                                           icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                                           color: Colors.white, iconSize: 64.0,
                                           onPressed: _togglePlayPause,
                                           style: IconButton.styleFrom(shadowColor: Colors.black54, elevation: 5),
                                         ),
                                         const SizedBox(width: 20),
                                         // Botão Mudo/Desmudo (Volume)
                                         IconButton(
                                           icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
                                           color: Colors.white, iconSize: 36.0,
                                           onPressed: _toggleMute,
                                           style: IconButton.styleFrom(shadowColor: Colors.black54, elevation: 5),
                                         ),
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
            ), // Fim Card Player
            const SizedBox(height: 20),

            // --- 3. Links de Redes Sociais ---
            Text(
              'Siga-nos nas Redes Sociais',
               style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
               textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _socialLinks.map((link) {
                  return IconButton(
                    icon: Icon(link['icon'] as IconData),
                    iconSize: 40.0,
                    color: Theme.of(context).primaryColor,
                    tooltip: link['url'] as String?,
                    onPressed: () => _launchURL(link['url'] as String),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 30),

            // --- 4. Banner de Patrocinadores ---
            Text(
              'Patrocinadores',
               style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
               textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const SponsorBannerRotator(), // Widget do banner

          ],
        ),
      ),
    );
  }
}