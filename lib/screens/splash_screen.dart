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
  String? _regulationUrl;

  // --- FIM ---
  @override
  void initState() {
    super.initState();
    debugPrint("SplashScreen: initState");

    // Inicializa o controller
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

    // Inicia as buscas
    _fetchFirebaseData(); // Nova função "wrapper"
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

  // --- 2. NOVA FUNÇÃO WRAPPER PARA BUSCAR TUDO ---
  // Chama ambas as buscas do Firestore
  Future<void> _fetchFirebaseData() async {
    // Inicia ambas as buscas em paralelo
    final videoIdFuture = _fetchVideoId();
    final regulationUrlFuture = _fetchRegulationUrl();
    
    await regulationUrlFuture;

    final String correctVideoId = await videoIdFuture;

    // Quando ambas terminarem, inicializa o player com o ID correto
    // e finaliza o loading da tela
    if (mounted) {
      final correctVideoId = await videoIdFuture; // Pega o resultado
      
      // Carrega o vídeo correto no controller (que já existe)
      final currentId = _ytController.metadata.videoId;
      if (currentId != correctVideoId) {
        debugPrint("SplashScreen: Carregando ID ($correctVideoId) no player...");
        _ytController.loadVideoById(videoId: correctVideoId);
      } else {
        debugPrint("SplashScreen: IDs são iguais. Nenhuma ação de load necessária.");
      }

      // Atualiza o estado (URL do regulamento já foi setada)
      setState(() {
        _isLoadingVideoId = false; // Termina o loading do player
      });
      debugPrint("[DIAGNÓSTICO] setState chamado, _isLoadingVideoId = false.");
    }
  }
  // --- FIM DA FUNÇÃO WRAPPER ---


  // --- 3. FUNÇÃO DE BUSCA DO VÍDEO (AGORA RETORNA STRING) ---


  // Busca o ID do vídeo no Firestore e carrega no player
 Future<String> _fetchVideoId() async {
    String correctVideoId = _defaultVideoId; // Começa com o ID padrão
    try {
      debugPrint("[DIAGNÓSTICO] Iniciando busca (Vídeo)...");
      final docSnap = await _firestore.collection('config').doc('app_settings').get();

      if (docSnap.exists) {
        final docData = docSnap.data();
        // --- VERIFICAÇÃO DE 24 HORAS ---
        if (docData != null &&
            docData.containsKey('live_video_id') &&
            docData.containsKey('live_video_timestamp')) {
          
          final fetchedId = docData['live_video_id'] as String?;
          final fetchedTimestamp = docData['live_video_timestamp'] as Timestamp?; // Pega o timestamp

          if (fetchedId != null && fetchedId.isNotEmpty && fetchedTimestamp != null) {
            final DateTime timestampDate = fetchedTimestamp.toDate();
            final DateTime now = DateTime.now();
            final Duration difference = now.difference(timestampDate);

            if (difference.inHours < 24) {
              correctVideoId = fetchedId; // VÁLIDO
            } else {
              debugPrint("[DIAGNÓSTICO] ID do Firestore EXPIRADO. Usando padrão.");
              correctVideoId = _defaultVideoId;
            }
          } else {
             debugPrint("[DIAGNÓSTICO] Campos de vídeo incompletos. Usando padrão.");
             correctVideoId = _defaultVideoId;
          }
        } else {
          debugPrint("[DIAGNÓSTICO] Campo 'live_video_id' ou 'timestamp' NÃO encontrado. Usando padrão.");
          correctVideoId = _defaultVideoId;
        }
      } else {
        debugPrint("[DIAGNÓSTICO] Documento 'app_settings' NÃO encontrado. Usando padrão.");
        correctVideoId = _defaultVideoId;
      }
    } catch (e) {
      debugPrint("[DIAGNÓSTICO] ERRO CATCH ao buscar ID: $e. Usando padrão.");
      correctVideoId = _defaultVideoId;
    }
    return correctVideoId; // Retorna o ID final
  }

   // --- 4. NOVA FUNÇÃO PARA BUSCAR URL DO REGULAMENTO ---
  Future<void> _fetchRegulationUrl() async {
    try {
      debugPrint("[DIAGNÓSTICO] Iniciando busca (Regulamento)...");
      final docSnap = await _firestore.collection('config').doc('app_settings').get();
      if (docSnap.exists && docSnap.data()!.containsKey('regulation_pdf_url')) {
        final fetchedUrl = docSnap.get('regulation_pdf_url') as String?;
        if (fetchedUrl != null && fetchedUrl.isNotEmpty) {
          debugPrint("[DIAGNÓSTICO] URL do Regulamento encontrada.");
          if (mounted) {
            setState(() {
              _regulationUrl = fetchedUrl; // Salva a URL no estado
            });
          }
        } else {
           debugPrint("[DIAGNÓSTICO] URL do Regulamento está vazia no Firestore.");
        }
      } else {
         debugPrint("[DIAGNÓSTICO] Campo 'regulation_pdf_url' NÃO encontrado.");
      }
    } catch (e) {
       debugPrint("[DIAGNÓSTICO] ERRO CATCH ao buscar URL do Regulamento: $e");
    }
    // Não precisa de finally ou setState, pois _regulationUrl ser nulo
    // apenas esconderá o botão.
  }
  // --- FIM DA FUNÇÃO ---


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

                  // --- 5. BOTÃO REGULAMENTO (NOVO) ---
                  if (_regulationUrl != null && _regulationUrl!.isNotEmpty) // Só mostra se a URL foi carregada
                    Padding(
                      padding: const EdgeInsets.only(top: 24.0, left: 32.0, right: 32.0), // Padding para centralizar/afunilar
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Regulamento Oficial'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          backgroundColor: Colors.grey[100], // Cor neutra
                          foregroundColor: Theme.of(context).primaryColor, // Cor do texto
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Theme.of(context).primaryColor, width: 1.5) // Borda
                          )
                        ),
                        onPressed: () {
                          _launchURL(_regulationUrl!); // Abre o PDF
                        },
                      ),
                    ),
                  // --- FIM DO BOTÃO ---

                  const SizedBox(height: 10), // Espaço

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

                  const SizedBox(height: 5),
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
