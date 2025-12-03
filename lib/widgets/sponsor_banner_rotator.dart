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
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _firestore
        .collection('sponsors')
        .where('isActive', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            setState(() {
              _sponsors = snapshot.docs;
              if (_sponsors.isNotEmpty) {
                // Garante índice válido ao recarregar
                _currentIndex = _currentIndex % _sponsors.length;
              }
            });
            _resetTimer();
          }
        });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    if (_sponsors.isEmpty) return;

    // Obtém o tempo de exibição do banner atual (padrão 5s)
    final currentData = _sponsors[_currentIndex].data() as Map<String, dynamic>;
    final int durationSec = (currentData['displayTimeSeconds'] as num? ?? 5).toInt();

    _timer = Timer(Duration(seconds: durationSec), () {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _sponsors.length;
        });
        _resetTimer(); // Chama recursivamente para o próximo
        
        // Pré-cache da próxima imagem para evitar piscadas
        _precacheNextImage();
      }
    });
  }

  void _precacheNextImage() {
    if (_sponsors.isEmpty) return;
    try {
      final int nextIndex = (_currentIndex + 1) % _sponsors.length;
      final nextData = _sponsors[nextIndex].data() as Map<String, dynamic>;
      final String? url = nextData['imageUrl'];
      if (url != null && url.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(url), context);
      }
    } catch (_) {}
  }

  Future<void> _launchURL(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Erro ao abrir banner: $urlString");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sponsors.isEmpty) return const SizedBox.shrink();

    final sponsorDoc = _sponsors[_currentIndex];
    final data = sponsorDoc.data() as Map<String, dynamic>;
    final imageUrl = data['imageUrl'] ?? '';
    final targetUrl = data['targetUrl'] ?? '';

    return Container(
      color: Colors.white, // Fundo base
      height: 100, // Altura fixa
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: InkWell(
          key: ValueKey<String>(sponsorDoc.id), // Key crucial para animação
          onTap: () => _launchURL(targetUrl),
          child: imageUrl.isEmpty
              ? Container(
                  color: Colors.grey[100],
                  alignment: Alignment.center,
                  child: Text(data['name'] ?? 'Patrocinador', style: const TextStyle(color: Colors.grey)),
                )
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain, // Contain para garantir que a logo apareça inteira
                  width: double.infinity,
                  height: 100,
                  // Removemos o placeholder pesado para evitar "flash" branco na troca
                  errorWidget: (c, u, e) => const Icon(Icons.broken_image, color: Colors.grey),
                ),
        ),
      ),
    );
  }
}