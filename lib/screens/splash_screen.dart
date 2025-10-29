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

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const routeName = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // --- Estados do Player e UI ---
  late YoutubePlayerController _ytController;
  bool _isLoadingVideoId = true;
  final String _defaultVideoId = 'ByBvdFS1jko';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Lista de redes sociais
  final List<Map<String, dynamic>> _socialLinks = [
    {
      'icon': FontAwesomeIcons.facebook,
      'url': 'https://www.facebook.com/forcajovemfumacense',
    },
    {
      'icon': FontAwesomeIcons.instagram,
      'url': 'https://www.instagram.com/fjf.forcajovem',
    },
    {
      'icon': FontAwesomeIcons.youtube,
      'url': 'https://www.youtube.com/@forcajovemfumacense',
    },
  ];

  // --- NOVO ESTADO PARA O EVENTO DE INSTALAÇÃO ---
  html.Event? _installPromptEvent;
  bool _showInstallButton = false;
  bool _isDrawerOpen = false;

  // --- FIM ---
  @override
  void initState() {
    super.initState();
    debugPrint("SplashScreen: initState");

    _fetchAndLoadCorrectVideoId();

    // --- CAPTURAR O EVENTO DE INSTALAÇÃO (SÓ NA WEB) ---
    if (kIsWeb) {
      debugPrint("Verificando instalação PWA...");

      // --- CORREÇÃO: Use addEventListener com o NOME da string ---
      html.window.addEventListener('beforeinstallprompt', (html.Event e) {
        debugPrint("Evento 'beforeinstallprompt' capturado!");
        e.preventDefault(); // Impede o pop-up automático
        if (mounted) {

        // Atualiza o estado da tela principal
        setState(() {
          _installPromptEvent = e; // Salva o evento
          _showInstallButton = true; // Mostra nosso botão
        });
         }
      });
      // --- FIM DA CORREÇÃO ---
    }
    // --- FIM DA CAPTURA ---
  }

  // Busca o ID do vídeo no Firestore e carrega no player
  Future<void> _fetchAndLoadCorrectVideoId() async {
    // Garante que o estado de loading comece (ou recomece) true
    if (!_isLoadingVideoId && mounted) {
      setState(() { _isLoadingVideoId = true; });
    } else if (!mounted && !_isLoadingVideoId) {
      _isLoadingVideoId = true;
    }

    String correctVideoId = _defaultVideoId;
    try {
      debugPrint("[DIAGNÓSTICO] Iniciando busca no Firestore...");
      final docSnap = await _firestore.collection('config').doc('app_settings').get();

      if (docSnap.exists) {
        final docData = docSnap.data();
        if (docData != null && docData.containsKey('live_video_id')) {
          final fetchedId = docData['live_video_id'];
          if (fetchedId is String && fetchedId.isNotEmpty) {
            correctVideoId = fetchedId;
            debugPrint("[DIAGNÓSTICO] ID do Firestore é válido. Usando: $correctVideoId");
          } else {
            debugPrint("[DIAGNÓSTICO] ID do Firestore inválido. Usando padrão: $_defaultVideoId");
          }
        } else {
          debugPrint("[DIAGNÓSTICO] Campo 'live_video_id' NÃO encontrado. Usando padrão.");
        }
      } else {
        debugPrint("[DIAGNÓSTICO] Documento 'app_settings' NÃO encontrado. Usando padrão.");
      }
    } catch (e) {
      debugPrint("[DIAGNÓSTICO] ERRO CATCH ao buscar ID: $e. Usando padrão.");
    } finally {
      debugPrint("[DIAGNÓTICO] Bloco finally. ID final a ser usado: $correctVideoId");

      // --- CRIAÇÃO DO CONTROLLER ---
      // Cria o controller AQUI, com o ID correto (do Firestore ou o padrão)
      _ytController = YoutubePlayerController.fromVideoId(
        videoId: correctVideoId, // Usa o ID final
        autoPlay: true,
        params: const YoutubePlayerParams(
          showControls: true,
          mute: true,
          showFullscreenButton: true,
          enableCaption: false,
        ),
      );
      // --- FIM DA CRIAÇÃO ---

      // Verifica se o widget ainda está montado ANTES de chamar setState
      if (mounted) {
        setState(() {
          _isLoadingVideoId = false; // Finaliza o loading
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
    if (mounted || !_isLoadingVideoId) {
    _ytController.close();
    }
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

  // --- NOVA FUNÇÃO PARA ACIONAR O PROMPT ---
  void _triggerInstallPrompt() {
    if (_installPromptEvent == null) {
      debugPrint("Evento de instalação não está pronto.");
      return;
    }
    (_installPromptEvent as dynamic).prompt();
    setState(() {
      _installPromptEvent = null;
      _showInstallButton = false;
    });
  }
  // --- FIM ---

  @override
  Widget build(BuildContext context) {
    // --- VERIFICA SE É IOS (PARA INSTRUÇÕES) ---
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
      appBar: AppBar(title: const Text('FJF App - Página Inicial')),

      drawer: const AppDrawer(),
      // Chamado quando o drawer começa a abrir
      onDrawerChanged: (isOpening) {
        if (isOpening) {
          // Pausa o vídeo e remove o player da árvore
          _ytController.pauseVideo();
          setState(() {
            _isDrawerOpen = true;
          });
        } else {
          // Recoloca o player na árvore
          setState(() {
            _isDrawerOpen = false;
          });
        }
      },

      // --- FIM DOS CALLBACKS ---
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo
          Image.asset('assets/logo3_fjf.png', height: 120),
          const SizedBox(height: 5),

          Card(
            elevation: 4,
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 8.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                  child: Text(
                    'SPD Lives - Ao Vivo',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                _isLoadingVideoId
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 50.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : (_isDrawerOpen
                          // Se o Drawer estiver aberto, mostra um placeholder
                          ? AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Container(
                                color: Colors.black,
                                alignment: Alignment.center,
                                child: const Text(
                                  'Player pausado.\nFeche o menu para continuar.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                            )
                          // Se o Drawer estiver fechado, mostra o player
                          : YoutubePlayer(controller: _ytController)),
              ],
            ),
          ),
          // --- FIM DO PLAYER FIXO ---

          // --- 3. CONTEÚDO ROLÁVEL (EM EXPANDED) ---
          Expanded(
            child: SingleChildScrollView(
              // Padding movido para dentro do conteúdo rolável
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (kIsWeb && !isStandalone) ...[
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
                      margin: const EdgeInsets.only(top: 10.0, bottom: 10.0),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.5),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Para instalar o app no seu iPhone/iPad:',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '1. Toque no ícone de "Compartilhar" (quadrado com seta para cima) na barra do navegador Safari.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '2. Role para baixo e selecione "Adicionar à Tela de Início".',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),

                  // --- FIM INSTRUÇÕES iOS ---
                  if (!_showInstallButton && isAndroid)
                    Container(
                      padding: const EdgeInsets.all(12.0),
                      margin: const EdgeInsets.only(top: 24.0, bottom: 16.0),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.5),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Para instalar o app no seu Android:',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '1. Toque no ícone de menu (três pontos ⋮) no canto superior do navegador.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '2. Selecione a opção "Instalar aplicativo" ou "Adicionar à tela inicial".',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 5),
                  // --- 3. Links de Redes Sociais ---
                  Text(
                    'Siga-nos nas Redes Sociais',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 5),
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

                  const SizedBox(height: 5), // Espaço generoso antes do rodapé
                      Text(
                        'Desenvolvido por Wesley Ricardo.\nTodos os direitos reservados © FJF 2025.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600], // Cor sutil
                          fontSize: 12,
                          height: 1.5, // Espaçamento entre linhas
                        ),
                      ),

                ],
              ),
            ),
          ),
          // --- FIM DO CONTEÚDO ROLÁVEL ---
        ],
      ),

      // --- FIM DA CORREÇÃO DO BODY ---
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}
