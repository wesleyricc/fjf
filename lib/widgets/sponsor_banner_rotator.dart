// lib/widgets/sponsor_banner_rotator.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SponsorBannerRotator extends StatefulWidget {
  const SponsorBannerRotator({super.key});

  @override
  State<SponsorBannerRotator> createState() => _SponsorBannerRotatorState();
}

class _SponsorBannerRotatorState extends State<SponsorBannerRotator> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<DocumentSnapshot> _sponsors = [];
  int _currentIndex = 0;
  Timer? _timer;
  StreamSubscription? _sponsorSubscription;
  bool _isLoading = true; 

  @override
  void initState() {
    super.initState();
    _listenForSponsorChanges(); // Inicia o listener
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sponsorSubscription?.cancel(); // Cancela a inscrição do Firestore
    super.dispose();
  }

  // 1. Ouve as mudanças no Firestore
  void _listenForSponsorChanges() {
    // Configura a query
    final query = _firestore
        .collection('sponsors')
        .where('isActive', isEqualTo: true)
        .orderBy('order');

    // Cancela qualquer listener anterior
    _sponsorSubscription?.cancel();
    
    // Inicia o novo listener
    _sponsorSubscription = query.snapshots().listen(
      (snapshot) {
        // --- Dados recebidos ---
        debugPrint("[Rotator] Dados de patrocinadores recebidos: ${snapshot.docs.length} banners.");
        
        if (!mounted) return; // Se a tela foi fechada, não faz nada
        
        bool listChanged = _didSponsorListChange(snapshot.docs); // Compara com a lista antiga
        
        setState(() {
          _sponsors = snapshot.docs;
          _isLoading = false; // Terminou o carregamento
          
          // Se a lista mudou ou está vazia, reseta o índice
          if (listChanged || _sponsors.isEmpty) {
            _currentIndex = 0;
          }
          // Garante que o índice atual é válido
          if (_sponsors.isNotEmpty) {
             _currentIndex = _currentIndex % _sponsors.length;
          }
        });

        // Inicia ou reinicia o timer com os novos dados
        if (_sponsors.isNotEmpty) {
          _startTimer();
        } else {
          _timer?.cancel(); // Para o timer se não há banners
        }
      },
      onError: (error) {
        // --- Erro ao buscar dados ---
        debugPrint("[Rotator] Erro ao ouvir patrocinadores: $error");
        if (mounted) {
          setState(() {
            _isLoading = false;
            _sponsors = [];
            _timer?.cancel();
          });
        }
      }
    );
  }

  void _startTimer() {
    _timer?.cancel(); // Cancela timer anterior
    if (_sponsors.isEmpty || !mounted) return; // Não faz nada se lista vazia

    // Pega a duração do banner ATUAL
    try {
      final currentSponsorData = _sponsors[_currentIndex].data() as Map<String, dynamic>;
      final displayTime = (currentSponsorData['displayTimeSeconds'] ?? 5) as int;

      // Agenda o próximo "setState"
      _timer = Timer(Duration(seconds: displayTime), () {
        if (!mounted) return;
        
        // --- AQUI É O PULO ---
        // Apenas avança o índice e chama setState
        setState(() {
          _currentIndex = (_currentIndex + 1) % _sponsors.length;
        });
        // --- FIM DO PULO ---
        
        _startTimer(); // Chama recursivamente para o próximo ciclo
      });
    } catch (e) {
      debugPrint("[Rotator] Erro ao iniciar timer (provavelmente dados inválidos): $e");
    }
  }

  // 3. Função de pré-cache (Opcional, mas ajuda. Chamada no build)
  // Removida na versão anterior, mas vamos tentar de novo COM a lógica de estado correta.
  void _precacheNextImage() {
    if (_sponsors.isEmpty || !mounted) return;

    try {
      final int nextIndex = (_currentIndex + 1) % _sponsors.length;
      final String nextImageUrl = (_sponsors[nextIndex].data() as Map<String, dynamic>?)?['imageUrl'] ?? '';
      
      if (nextImageUrl.isNotEmpty) {
         // pre-cache não deve ser chamado excessivamente, mas aqui é ok
         precacheImage(CachedNetworkImageProvider(nextImageUrl), context);
      }
    } catch (e) {
       debugPrint("[Rotator] Erro no pré-cache: $e");
    }
  }

  Future<void> _launchURL(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
       debugPrint('Não foi possível abrir $urlString');
    }
  }

  // Função auxiliar para checar se a lista mudou
  bool _didSponsorListChange(List<DocumentSnapshot> newSponsors) {
    if (newSponsors.length != _sponsors.length) return true;
    for (int i = 0; i < newSponsors.length; i++) {
      if (newSponsors[i].id != _sponsors[i].id) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Estado 1: Carregando pela primeira vez
    if (_isLoading) {
      return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
    }
    
    // Estado 2: Carregou, mas não há patrocinadores
    if (_sponsors.isEmpty) {
      return const SizedBox.shrink(); // Não mostra nada
    }

    // Estado 3: Temos patrocinadores, vamos exibir
    
    // Tenta carregar a próxima imagem em segundo plano
    _precacheNextImage();

    // Pega os dados do banner atual
    final currentSponsorData = _sponsors[_currentIndex].data() as Map<String, dynamic>;
    final imageUrl = currentSponsorData['imageUrl'] as String? ?? ''; // Garante String
    final targetUrl = currentSponsorData['targetUrl'] as String? ?? ''; // Garante String
        
        return AnimatedSwitcher(
          duration: const Duration(
            milliseconds: 500,
          ), // Duração da animação de fade
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },

          // LayoutBuilder para garantir sobreposição (cross-fade)
          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // O widget antigo (fading out) fica por baixo
                ...previousChildren,
                // O widget novo (fading in) fica por cima
                if (currentChild != null) currentChild,
              ],
            );
          },
          // --- FIM DO LAYOUT BUILDER ---
          child: SizedBox(
            // Chave é ESSENCIAL para o AnimatedSwitcher detectar a mudança
            key: ValueKey<String>(_sponsors[_currentIndex].id),
            height: 120, // Altura fixa para o banner
            width: double.infinity, // Ocupa toda a largura
            child: InkWell(
              onTap: () => _launchURL(targetUrl),
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover, // ou contain

                      placeholder: (context, url) => SizedBox(
                        height: 120,
                        width: double.infinity,
                        child: Container(color: Colors.grey[200]), // Cor sólida
                      ),
                      // O fade da própria imagem (após carregar do placeholder)
                      // Definir como 0 pode ajudar se o pré-cache funcionar bem
                      fadeInDuration: const Duration(milliseconds: 500), 
                      fadeOutDuration: const Duration(milliseconds: 500),
                      errorWidget: (context, url, error) => SizedBox(
                        height: 120, 
                        width: double.infinity,
                        child: Container(
                          color: Colors.grey[300],
                          alignment: Alignment.center,
                          child: const Text(
                            'Erro Banner',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 120, // <-- USE A MESMA ALTURA DO SIZEDBOX EXTERNO
                      width: double.infinity,
                      child: Container(
                        // Placeholder se a URL for nula
                        color: Colors.grey[300],
                        alignment: Alignment.center,
                        child: const Text(
                          'Banner Indisponível',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
            ),
          ),
    );
  }
}
