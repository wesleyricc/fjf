import 'dart:async';
import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // Removido, não usamos mais Snapshot aqui
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/championship_service.dart';

class SponsorBannerRotator extends StatefulWidget {
  final String location;
  final bool isStatic;
  final double? height; 
  
  // Parâmetro único de filtro (ex: "1", "5", "semifinal", "final")
  final String? filterTag; 

  const SponsorBannerRotator({
    super.key, 
    this.location = 'footer_home', 
    this.isStatic = false,
    this.height, 
    this.filterTag, 
  });

  @override
  State<SponsorBannerRotator> createState() => _SponsorBannerRotatorState();
}

class _SponsorBannerRotatorState extends State<SponsorBannerRotator> {
  // CORREÇÃO: Agora é uma lista de Maps, pois o Service entrega dados puros
  List<Map<String, dynamic>> _filteredSponsors = [];
  int _currentIndex = 0;
  Timer? _timer;

  static const String _partnerContactUrl = "https://wa.me/5548996381626?text=Quero%20anunciar%20no%20App%20FJF";

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _filterSponsorsFromCache();
  }

  @override
  void didUpdateWidget(covariant SponsorBannerRotator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location != oldWidget.location || 
        widget.filterTag != oldWidget.filterTag) {
      _filterSponsorsFromCache();
    }
  }

  // --- LÓGICA UNIFICADA ---
  void _filterSponsorsFromCache() {
    final service = Provider.of<ChampionshipService>(context, listen: true);
    final allSponsors = service.sponsors; // Retorna List<Map<String, dynamic>>

    final filtered = allSponsors.where((data) {
      // CORREÇÃO: Acesso direto ao Map, sem .data()
      
      // 1. Filtra Localização (Obrigatório)
      if (data['location'] != widget.location) return false;

      // 2. Filtra pela Tag Unificada (Campo 'round' no Firestore)
      if (widget.filterTag != null) {
        final docRound = data['round']; 

        if (docRound != null && docRound.toString().isNotEmpty) {
          if (docRound.toString() != widget.filterTag) {
            return false;
          }
        }
      } 

      return true;
    }).toList();

    setState(() {
      _filteredSponsors = filtered;
      _currentIndex = 0; 
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      if (_filteredSponsors.length > 1 && !widget.isStatic) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _filteredSponsors.length;
        });
        _precacheNextImage();
      }
    });
  }

  void _precacheNextImage() {
    if (_filteredSponsors.isEmpty) return;
    try {
      final int nextIndex = (_currentIndex + 1) % _filteredSponsors.length;
      // CORREÇÃO: Acesso direto ao Map
      final nextData = _filteredSponsors[nextIndex];
      final String? url = nextData['imageUrl'];
      if (url != null && url.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(url), context);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    final double effectiveHeight = widget.height ?? 100;

    if (_filteredSponsors.isEmpty) {
      return _buildHouseAd(height: effectiveHeight);
    }

    // CORREÇÃO: Acesso direto ao Map
    final data = _filteredSponsors[_currentIndex];
    final imageUrl = data['imageUrl'] ?? '';
    final targetUrl = data['targetUrl'] ?? '';
    
    // Usamos a URL como chave única, já que o ID do documento pode não estar no Map otimizado
    final String uniqueKey = imageUrl.isNotEmpty ? imageUrl : (data['name'] ?? 'sponsor_$_currentIndex');

    return Container(
      color: Colors.white,
      height: effectiveHeight,
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        child: InkWell(
          key: ValueKey<String>(uniqueKey),
          onTap: () => _launchURL(targetUrl),
          child: imageUrl.isEmpty
              ? _buildHouseAd(title: data['name'], height: effectiveHeight)
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(FontAwesomeIcons.handshake, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ?? "SEJA PARCEIRO",
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
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