import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../viewmodels/sponsor_viewmodel.dart';
import '../services/analytics_service.dart'; // 🚨 IMPORT ANALYTICS

class SponsorBannerRotator extends StatefulWidget {
  final String location;
  final bool isStatic;
  final double? height;
  final String? filterTag;
  final VoidCallback? onCycleComplete;

  const SponsorBannerRotator({
    super.key,
    this.location = 'footer_home',
    this.isStatic = false,
    this.height,
    this.filterTag,
    this.onCycleComplete,
  });

  @override
  State<SponsorBannerRotator> createState() => _SponsorBannerRotatorState();
}

class _SponsorBannerRotatorState extends State<SponsorBannerRotator> {
  List<Map<String, dynamic>> _filteredSponsors = [];
  int _currentIndex = 0;
  Timer? _timer;
  static const String _partnerContactUrl = "https://wa.me/5548996381626?text=Quero%20anunciar%20no%20App%20FJF";
  
  bool _firstImpressionLogged = false;

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
    if (widget.location != oldWidget.location || widget.filterTag != oldWidget.filterTag) {
      _filterSponsorsFromCache();
    }
  }

  void _filterSponsorsFromCache() {
    final sponsorVm = Provider.of<SponsorViewModel>(context, listen: true);
    final allSponsors = sponsorVm.sponsors;

    final filtered = allSponsors.where((data) {
      if (data['location'] != widget.location) return false;
      if (widget.filterTag != null) {
        final docRound = data['round'];
        if (docRound != null && docRound.toString().isNotEmpty) {
          if (docRound.toString() != widget.filterTag) return false;
        }
      }
      return true;
    }).toList();

    setState(() {
      _filteredSponsors = filtered;
      _currentIndex = 0;
    });

    // Registra a impressão do primeiro banner assim que os dados carregam
    if (_filteredSponsors.isNotEmpty && !_firstImpressionLogged) {
      _firstImpressionLogged = true;
      _logImpression(_filteredSponsors[_currentIndex]);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      if (_filteredSponsors.length > 1 && !widget.isStatic) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _filteredSponsors.length;
        });
        
        // 🚨 RASTREIA A IMPRESSÃO A CADA GIRO DO BANNER
        _logImpression(_filteredSponsors[_currentIndex]);
        _precacheNextImage();

        if (_currentIndex == 0) {
          widget.onCycleComplete?.call();
        }
      } else {
        widget.onCycleComplete?.call();
      }
    });
  }

  void _logImpression(Map<String, dynamic> sponsorData) {
    final name = sponsorData['name'] ?? 'sponsor_unknown';
    AnalyticsService.logAdImpression(name, widget.location);
  }

  void _precacheNextImage() {
    if (_filteredSponsors.isEmpty) return;
    try {
      final int nextIndex = (_currentIndex + 1) % _filteredSponsors.length;
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

  Future<void> _launchURL(String? urlString, String sponsorName) async {
    final target = (urlString == null || urlString.isEmpty) ? _partnerContactUrl : urlString;
    
    // 🚨 RASTREIA O CLIQUE NO ANÚNCIO!
    AnalyticsService.logAdClick(sponsorName, widget.location, target);

    final Uri url = Uri.parse(target);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Erro ao abrir: $target");
    }
  }

  @override
  Widget build(BuildContext context) {
    // PADRÕES DE TAMANHO DE BANNERS PARA OS ANUNCIANTES:
    // location == 'app_open'        -> Proporção 9:16  (1080x1920 px) - Formato Vertical / Tela Cheia
    // location == 'news_feed'       -> Proporção 1:1   (1080x1080 px) - Formato Quadrado
    // location == 'header_fixtures' -> Proporção 32:9  (1920x540 px)  - Formato Horizontal (Banner Largo)
    // location == 'footer_home'     -> Proporção 32:9  (1920x540 px)  - Formato Horizontal (Rodapé)

    double? aspect;
    if (widget.location == 'app_open') {
      aspect = 9 / 16;
    } else if (widget.location == 'news_feed') {
      aspect = 1 / 1;
    } else if (widget.location == 'header_fixtures' || widget.location == 'footer_home') {
      aspect = 32 / 9;
    }

    Widget content;

    if (_filteredSponsors.isEmpty) {
      content = _buildHouseAd();
    } else {
      final data = _filteredSponsors[_currentIndex];
      final imageUrl = data['imageUrl'] ?? '';
      final targetUrl = data['targetUrl'] ?? '';
      final sponsorName = data['name'] ?? 'sponsor_$_currentIndex';
      final String uniqueKey = imageUrl.isNotEmpty ? imageUrl : sponsorName;

      content = AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        child: InkWell(
          key: ValueKey<String>(uniqueKey),
          onTap: () => _launchURL(targetUrl, sponsorName), // 🚨 Repassa o nome do patrocinador
          child: imageUrl.isEmpty
              ? _buildHouseAd(title: sponsorName)
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorWidget: (c, u, e) => _buildHouseAd(),
                ),
        ),
      );
    }

    if (widget.height != null) {
      return Container(
        color: Colors.white,
        height: widget.height,
        width: double.infinity,
        child: content,
      );
    } else if (aspect != null) {
      return AspectRatio(
        aspectRatio: aspect,
        child: Container(
          color: Colors.white,
          width: double.infinity,
          child: content,
        ),
      );
    } else {
      return Container(
        color: Colors.white,
        height: 100,
        width: double.infinity,
        child: content,
      );
    }
  }

  Widget _buildHouseAd({String? title}) {
    return InkWell(
      onTap: () => _launchURL(null, title ?? "Seja Parceiro (House Ad)"),
      child: Container(
        width: double.infinity,
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
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFFC25F22), letterSpacing: 0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const Text("Anuncie aqui", style: TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
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