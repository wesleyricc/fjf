import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class SponsorBannerRotator extends StatefulWidget {
  final String location;
  final bool isStatic;
  final double? height; // NOVO: Permite altura dinâmica

  const SponsorBannerRotator({
    super.key, 
    this.location = 'footer_home', 
    this.isStatic = false,
    this.height, // Se null, usa o padrão 100 ou ajusta ao pai
  });

  @override
  State<SponsorBannerRotator> createState() => _SponsorBannerRotatorState();
}

class _SponsorBannerRotatorState extends State<SponsorBannerRotator> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<DocumentSnapshot> _sponsors = [];
  int _currentIndex = 0;
  Timer? _timer;
  StreamSubscription? _subscription;
  bool _isLoading = true;

  static const String _partnerContactUrl = "https://wa.me/5548999999999?text=Quero%20anunciar%20no%20App%20FJF";

  @override
  void initState() {
    super.initState();
    _initSponsorStream();
  }

  void _initSponsorStream() {
    _subscription = _firestore
        .collection('sponsors')
        .where('isActive', isEqualTo: true)
        .where('location', isEqualTo: widget.location)
        .orderBy('order')
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            setState(() {
              _sponsors = snapshot.docs;
              _isLoading = false;
              if (_sponsors.isNotEmpty) {
                _currentIndex = 0;
              }
            });
            if (_sponsors.length > 1 && !widget.isStatic) {
              _resetTimer();
            } else {
              _timer?.cancel();
            }
          }
        }, onError: (e) {
          debugPrint("Erro Sponsors: $e");
          if (mounted) setState(() => _isLoading = false);
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

    final currentData = _sponsors[_currentIndex].data() as Map<String, dynamic>;
    final int durationSec = (currentData['displayTimeSeconds'] as num? ?? 5).toInt();

    _timer = Timer(Duration(seconds: durationSec), () {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _sponsors.length;
        });
        _resetTimer();
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
    final target = (urlString == null || urlString.isEmpty) ? _partnerContactUrl : urlString;
    final Uri url = Uri.parse(target);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Erro ao abrir: $target");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Se altura for fornecida, usa. Se não, 100 (padrão rodapé).
    // Se for double.infinity, o pai deve limitar.
    final double effectiveHeight = widget.height ?? 100;

    if (_isLoading) {
      return SizedBox(
        height: effectiveHeight == double.infinity ? 100 : effectiveHeight, 
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2))
      );
    }

    // --- HOUSE AD (SEM PATROCINADOR) ---
    if (_sponsors.isEmpty) {
      return _buildHouseAd(height: effectiveHeight);
    }

    // --- COM PATROCINADOR ---
    final sponsorDoc = _sponsors[_currentIndex];
    final data = sponsorDoc.data() as Map<String, dynamic>;
    final imageUrl = data['imageUrl'] ?? '';
    final targetUrl = data['targetUrl'] ?? '';

    return Container(
      color: Colors.white,
      height: effectiveHeight,
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        child: InkWell(
          key: ValueKey<String>(sponsorDoc.id),
          onTap: () => _launchURL(targetUrl),
          child: imageUrl.isEmpty
              ? _buildHouseAd(title: data['name'], height: effectiveHeight)
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover, // Preenche todo o card
                  width: double.infinity,
                  height: effectiveHeight,
                  errorWidget: (c, u, e) => _buildHouseAd(height: effectiveHeight),
                ),
        ),
      ),
    );
  }

  Widget _buildHouseAd({String? title, required double height}) {
    return InkWell(
      onTap: () => _launchURL(null),
      child: Container(
        width: double.infinity,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.symmetric(horizontal: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Ícone compactado
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(FontAwesomeIcons.handshake, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 12),
            
            // CORREÇÃO: Expanded evita o overflow no texto
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ?? "SEJA PARCEIRO",
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14, // Fonte levemente reduzida para caber
                      color: Color(0xFFC25F22),
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "Anuncie aqui",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}