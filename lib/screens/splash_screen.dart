// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  // Nome da rota para navegação (opcional, mas bom ter)
  static const routeName = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  
  late YoutubePlayerController _ytController;

  // --- !!! IMPORTANTE: COLOQUE O ID DO SEU VÍDEO/LIVE AQUI !!! ---
  bool _isLoadingVideoId = true;
  String _videoId = 'hi8CH7KOUSk';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Instância do Firestore

  // Lista de redes sociais (ícone, url)
  final List<Map<String, dynamic>> _socialLinks = [
    {'icon': FontAwesomeIcons.facebook, 'url': 'https://www.facebook.com/forcajovemfumacense'},
    {'icon': FontAwesomeIcons.instagram, 'url': 'https://www.instagram.com/fjf.forcajovem'},
    {'icon': FontAwesomeIcons.youtube, 'url': 'https://www.youtube.com/@forcajovemfumacense'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchVideoIdAndInitializePlayer();
  }

  // Função para buscar o ID e inicializar o player
  Future<void> _fetchVideoIdAndInitializePlayer() async {
    String fetchedVideoId = _videoId; // Começa com o padrão
    try {
      final docSnap = await _firestore.collection('config').doc('app_settings').get();
      if (docSnap.exists && docSnap.data()!.containsKey('live_video_id')) {
        fetchedVideoId = docSnap.get('live_video_id');
      } else {
         debugPrint("Documento 'config/app_settings' ou campo 'live_video_id' não encontrado. Usando ID padrão.");
      }
    } catch (e) {
      debugPrint("Erro ao buscar video ID do Firestore: $e. Usando ID padrão.");
    } finally {
      // Garante que o ID final (buscado ou padrão) seja válido
      if (fetchedVideoId.isEmpty) {
        fetchedVideoId = 'hi8CH7KOUSk'; // Garante um ID válido se o do Firestore estiver vazio
      }
       
      // Inicializa ou atualiza o controller
       if (mounted) {
         setState(() {
           _videoId = fetchedVideoId;
           // Só cria o controller se ele não existir ainda
           //if (_ytController == null) {
              _ytController = YoutubePlayerController(
                initialVideoId: _videoId,
                flags: const YoutubePlayerFlags(
                  autoPlay: true,
                  mute: true,
                  isLive: true, // Ajuste conforme necessário
                ),
              );
           //} else {
             // Se já existia (ex: vindo de um hot reload), apenas carrega o novo ID
             //_ytController!.load(_videoId);
           //}
           _isLoadingVideoId = false; // Terminou o carregamento
         });
       }
    }
  }


  @override
  void dispose() {
    _ytController?.dispose(); // Libera recursos do player
    super.dispose();
  }

  Future<void> _launchURL(String urlString) async {
    // (Mesma função _launchURL que usamos no banner)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FJF App - Início'), // Título mais curto
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        // Padding geral para afastar conteúdo das bordas da tela
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center, // Centraliza filhos horizontalmente
          children: [
            
            // --- 1. Logo Principal ---
            Image.asset(
              'assets/logo3_fjf.png',
              height: 120, // Pode ajustar o tamanho
            ),
            const SizedBox(height: 10), // Espaçamento maior após a logo

            // --- 2. Player do YouTube (Dentro de um Card) ---
            Card(
              elevation: 4, // Adiciona uma sombra sutil
              clipBehavior: Clip.antiAlias, // Garante que o player respeite as bordas arredondadas do Card
              margin: const EdgeInsets.symmetric(vertical: 8.0), // Margem vertical
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: Text(
                      'SPD Lives - Transmissão',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  _isLoadingVideoId
                  ? const Padding( // Placeholder enquanto carrega
                      padding: EdgeInsets.symmetric(vertical: 50.0),
                      child: Center(child: CircularProgressIndicator()),
                    ) 
                  : (_ytController != null // Garante que o controller foi inicializado
                        ? YoutubePlayer(
                          controller: _ytController!, // Usa '!' pois garantimos que não é nulo aqui
                          showVideoProgressIndicator: true,
                          progressIndicatorColor: Theme.of(context).primaryColor,
                          liveUIColor: Colors.red,
                          onReady: () => debugPrint('Player is ready.'),
                        )
                      : const Padding( // Mensagem de erro se o controller falhar
                        padding: EdgeInsets.symmetric(vertical: 50.0),
                        child: Center(child: Text('Erro ao carregar o player.')),
                      )
                   ),
                ],
              ),
            ),
            const SizedBox(height: 20), // Espaçamento maior antes das redes sociais

            // --- 3. Links de Redes Sociais ---
             Text(
              'Siga-nos nas Redes Sociais',
               style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            // Container opcional para agrupar ou estilizar os ícones
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              // Exemplo de decoração (opcional):
              // decoration: BoxDecoration(
              //   color: Colors.grey.shade200,
              //   borderRadius: BorderRadius.circular(10),
              // ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly, // Espaça igualmente os ícones
                children: _socialLinks.map((link) {
                  return IconButton(
                    icon: Icon(link['icon'] as IconData),
                    iconSize: 40.0, // Ícones um pouco maiores
                    color: Theme.of(context).primaryColor,
                    tooltip: link['url'] as String?, // Mostra URL ao pressionar e segurar
                    onPressed: () => _launchURL(link['url'] as String),
                  );
                }).toList(),
              ),
            ),
            //const SizedBox(height: 12), // Espaçamento maior antes dos patrocinadores

            // --- 4. Banner de Patrocinadores ---
             Text(
              'Patrocinadores',
               style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const SponsorBannerRotator(), // Nosso widget reutilizável
          ],
        ),
      ),
    );
  }
}