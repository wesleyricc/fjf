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
  int _currentIndex = 0;
  Timer? _timer;
  List<DocumentSnapshot> _sponsors = []; // Guarda os patrocinadores buscados

  @override
  void dispose() {
    _timer?.cancel(); // Cancela o timer ao sair da tela
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel(); // Cancela o timer anterior, se houver

    if (_sponsors.isEmpty) return; // Não faz nada se não há patrocinadores

    // Garante que o índice atual é válido
    _currentIndex = _currentIndex % _sponsors.length;

    final currentSponsor =
        _sponsors[_currentIndex].data() as Map<String, dynamic>;
    final displayTime =
        (currentSponsor['displayTimeSeconds'] ?? 5) as int; // Padrão de 5s

    // Cria um novo timer com a duração específica deste banner
    _timer = Timer(Duration(seconds: displayTime), () {
      if (!mounted) return; // Verifica se o widget ainda está na tela
      setState(() {
        _currentIndex =
            (_currentIndex + 1) % _sponsors.length; // Avança para o próximo
      });
      _startTimer(); // Chama recursivamente para agendar o próximo timer
    });
  }

  // --- NOVA FUNÇÃO PARA ABRIR URL ---
  Future<void> _launchURL(String? urlString) async {
    if (urlString == null || urlString.isEmpty) {
      debugPrint('URL do banner está vazia.');
      return; // Não faz nada se a URL for nula ou vazia
    }

    final Uri url = Uri.parse(urlString); // Converte a string para Uri

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // Se não conseguir abrir no navegador externo, mostra erro
      debugPrint('Não foi possível abrir $urlString');
      if (mounted) {
        // Verifica se o widget ainda está na tela
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o link: $urlString')),
        );
      }
    }
  }
  // --- FIM DA NOVA FUNÇÃO ---

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // Busca patrocinadores ativos, ordenados
      stream: _firestore
          .collection('sponsors')
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Mostra um placeholder enquanto carrega
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const SizedBox(
            height: 120,
            child: Center(child: Text('Erro ao carregar patrocinadores')),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          // Não mostra nada se não houver patrocinadores ativos
          return const SizedBox.shrink(); // Widget vazio
        }

        // Atualiza a lista de patrocinadores e reinicia o timer se necessário
        // Compara as listas para ver se houve mudança real nos dados
        final newSponsors = snapshot.data!.docs;
        bool listChanged = _didSponsorListChange(newSponsors);
        _sponsors = newSponsors;

        // Se a lista mudou ou o timer não está ativo, inicia/reinicia
        if (listChanged || _timer == null || !_timer!.isActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _startTimer();
          });
        }

        if (_sponsors.isEmpty) return const SizedBox.shrink(); // Segurança extra

        // Garante que o índice é válido após a atualização da lista
        _currentIndex = _currentIndex % _sponsors.length;
        final currentSponsorData = _sponsors[_currentIndex].data() as Map<String, dynamic>;
        final imageUrl = currentSponsorData['imageUrl'];
        final targetUrl = currentSponsorData['targetUrl'];

        // --- 1. LÓGICA DE PRÉ-CACHE ---
        // Pega o índice do *próximo* banner
        final int nextIndex = (_currentIndex + 1) % _sponsors.length;
        // Pega a URL do próximo banner
        final String nextImageUrl = (_sponsors[nextIndex].data() as Map<String, dynamic>?)?['imageUrl'] ?? '';
        
        if (nextImageUrl.isNotEmpty) {
           // Baixa a próxima imagem em segundo plano
           // (O 'context' é necessário para precacheImage)
           precacheImage(CachedNetworkImageProvider(nextImageUrl), context);
        }
        // --- FIM DO PRÉ-CACHE ---
        
        return AnimatedSwitcher(
          duration: const Duration(
            milliseconds: 500,
          ), // Duração da animação de fade
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },

          // --- 3. LAYOUT BUILDER EXPLÍCITO ---
          // Força o AnimatedSwitcher a empilhar os widgets (cross-fade)
          // em vez de potencialmente mostrá-los em sequência
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
      },
    );
  }

  // Função auxiliar para verificar se a lista de patrocinadores mudou
  bool _didSponsorListChange(List<DocumentSnapshot> newSponsors) {
    if (newSponsors.length != _sponsors.length) return true;
    for (int i = 0; i < newSponsors.length; i++) {
      if (newSponsors[i].id != _sponsors[i].id) return true;
      // Poderia adicionar mais verificações (ex: imageUrl mudou), se necessário
    }
    return false;
  }
}
