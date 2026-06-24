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
    final double effectiveHeight = widget.height ?? 100;

    if (_filteredSponsors.isEmpty) {
      return _buildHouseAd(height: effectiveHeight);
    }

    final data = _filteredSponsors[_currentIndex];
    final imageUrl = data['imageUrl'] ?? '';
    final targetUrl = data['targetUrl'] ?? '';
    final sponsorName = data['name'] ?? 'sponsor_$_currentIndex';
    final String uniqueKey = imageUrl.isNotEmpty ? imageUrl : sponsorName;

    return Container(
      color: Colors.white,
      height: effectiveHeight,
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        child: InkWell(
          key: ValueKey<String>(uniqueKey),
          onTap: () => _launchURL(targetUrl, sponsorName), // 🚨 Repassa o nome do patrocinador
          child: imageUrl.isEmpty
              ? _buildHouseAd(title: sponsorName, height: effectiveHeight)
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
      onTap: () => _launchURL(null, title ?? "Seja Parceiro (House Ad)"),
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