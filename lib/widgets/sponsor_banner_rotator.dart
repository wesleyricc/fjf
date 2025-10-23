// lib/widgets/sponsor_banner_rotator.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

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
    
    final currentSponsor = _sponsors[_currentIndex].data() as Map<String, dynamic>;
    final displayTime = (currentSponsor['displayTimeSeconds'] ?? 5) as int; // Padrão de 5s

    // Cria um novo timer com a duração específica deste banner
    _timer = Timer(Duration(seconds: displayTime), () {
      if (!mounted) return; // Verifica se o widget ainda está na tela
      setState(() {
        _currentIndex = (_currentIndex + 1) % _sponsors.length; // Avança para o próximo
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
        if (mounted) { // Verifica se o widget ainda está na tela
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
          return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return const SizedBox(height: 60, child: Center(child: Text('Erro ao carregar patrocinadores')));
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

        // Garante que o índice é válido após a atualização da lista
         _currentIndex = _currentIndex % _sponsors.length;
        final currentSponsorData = _sponsors[_currentIndex].data() as Map<String, dynamic>;
        final imageUrl = currentSponsorData['imageUrl'];
        final targetUrl = currentSponsorData['targetUrl']; // <-- Pega a URL do Firestore

        // AnimatedSwitcher para a transição suave entre banners
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500), // Duração da animação de fade
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: SizedBox(
            // Chave é ESSENCIAL para o AnimatedSwitcher detectar a mudança
            key: ValueKey<String>(_sponsors[_currentIndex].id), 
            height: 120, // Altura fixa para o banner
            width: double.infinity, // Ocupa toda a largura
            child: InkWell( // <-- 1. ENVOLVE COM InkWell
              onTap: () { // <-- 2. AÇÃO AO CLICAR
                _launchURL(targetUrl); // Chama a função para abrir a URL
              },
              child: imageUrl != null
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover, // Ou BoxFit.cover, dependendo do design
                      // Placeholder enquanto a imagem carrega
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      // Placeholder em caso de erro ao carregar a imagem
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[300],
                          alignment: Alignment.center,
                          child: const Text('Erro Banner', style: TextStyle(color: Colors.grey)),
                        );
                      },
                    )
                  : Container( // Placeholder se a URL for nula
                      color: Colors.grey[300],
                      alignment: Alignment.center,
                      child: const Text('Banner Inválido', style: TextStyle(color: Colors.grey)),
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