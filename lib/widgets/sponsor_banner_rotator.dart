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
  final BoxFit fit;

  const SponsorBannerRotator({
    super.key,
    this.location = 'footer_home',
    this.isStatic = false,
    this.height,
    this.filterTag,
    this.onCycleComplete,
    this.fit = BoxFit.cover,
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
      final List<dynamic> locations = data['locations'] ?? [];
      final String? oldLocation = data['location'];
      
      final matchesLocation = locations.contains(widget.location) || oldLocation == widget.location;
      if (!matchesLocation) return false;
      
      if (widget.filterTag != null) {
        final docRound = data['round'];
        if (docRound != null && docRound.toString().isNotEmpty) {
          if (docRound.toString() != widget.filterTag) return false;
        }
      }
      return true;
    }).toList();

    // Check if the filtered list actually changed before resetting state
    bool hasChanged = _filteredSponsors.length != filtered.length;
    if (!hasChanged) {
      for (int i = 0; i < filtered.length; i++) {
        if (_filteredSponsors[i]['name'] != filtered[i]['name'] ||
            _filteredSponsors[i]['imageUrl'] != filtered[i]['imageUrl']) {
          hasChanged = true;
          break;
        }
      }
    }

    if (hasChanged) {
      setState(() {
        _filteredSponsors = filtered;
        _currentIndex = 0;
      });

      // Registra a impressão do primeiro banner assim que os novos dados carregam
      if (_filteredSponsors.isNotEmpty && !_firstImpressionLogged) {
        _firstImpressionLogged = true;
        _logImpression(_filteredSponsors[_currentIndex]);
      }
      _precacheCurrentAndNext();
    } else {
      // If the list is the same, but we haven't logged the impression yet, do it.
      if (_filteredSponsors.isNotEmpty && !_firstImpressionLogged) {
        _firstImpressionLogged = true;
        _logImpression(_filteredSponsors[_currentIndex]);
      }
      _precacheCurrentAndNext();
    }
  }

  void _precacheCurrentAndNext() {
    if (!mounted || _filteredSponsors.isEmpty) return;
    try {
      final currentUrl = (_filteredSponsors[_currentIndex]['imageUrl']?.toString() ?? '').trim();
      if (currentUrl.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(currentUrl, maxWidth: 800), context);
      }
      if (_filteredSponsors.length > 1) {
        final nextIndex = (_currentIndex + 1) % _filteredSponsors.length;
        final nextUrl = (_filteredSponsors[nextIndex]['imageUrl']?.toString() ?? '').trim();
        if (nextUrl.isNotEmpty) {
          precacheImage(CachedNetworkImageProvider(nextUrl, maxWidth: 800), context);
        }
      }
    } catch (_) {}
  }

  void _precacheNextImage() {
    if (!mounted || _filteredSponsors.isEmpty) return;
    try {
      final int nextIndex = (_currentIndex + 1) % _filteredSponsors.length;
      final String? nextUrl = _filteredSponsors[nextIndex]['imageUrl']?.toString().trim();
      if (nextUrl != null && nextUrl.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(nextUrl, maxWidth: 800), context);
      }
    } catch (_) {}
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

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.white,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              const Color(0xFFC25F22).withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sponsorVm = Provider.of<SponsorViewModel>(context, listen: true);

    // PADRÕES DE TAMANHO DE BANNERS PARA OS ANUNCIANTES:
    // location == 'app_open'        -> Proporção 9:16  (1080x1920 px) - Formato Vertical / Tela Cheia
    // location == 'splash_loading'  -> Proporção 1:1   (100x100 px / Quadrado) - Parceiros da Tela de Splash
    // location == 'news_feed'       -> Proporção 1:1   (1080x1080 px) - Formato Quadrado
    // location == 'header_fixtures' -> Proporção 21:9  (1920x820 px)  - Formato Horizontal (Banner Largo, agora mais alto)
    // location == 'footer_home'     -> Proporção 21:9  (1920x820 px)  - Formato Horizontal (Rodapé, agora mais alto)
    // location == 'home_mid'        -> Proporção 21:9  (1920x820 px)  - Formato Horizontal (Meio da Home)

    double? aspect;
    if (widget.location == 'app_open') {
      aspect = 9 / 16;
    } else if (widget.location == 'news_feed' || widget.location == 'splash_loading') {
      aspect = 1 / 1;
    } else if (widget.location.startsWith('header_') || widget.location == 'footer_home' || widget.location == 'home_mid') {
      aspect = 21 / 9;
    }

    Widget content;

    if (_filteredSponsors.isEmpty) {
      if (sponsorVm.isLoading) {
        content = _buildPlaceholder();
      } else {
        content = _buildHouseAd();
      }
    } else {
      final data = _filteredSponsors[_currentIndex];
      final imageUrl = (data['imageUrl']?.toString() ?? '').trim();
      final targetUrl = data['targetUrl'] ?? '';
      final sponsorName = data['name'] ?? 'sponsor_$_currentIndex';
      final String uniqueKey = "${_currentIndex}_${imageUrl.isNotEmpty ? imageUrl : sponsorName}";

      content = AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: InkWell(
          key: ValueKey<String>(uniqueKey),
          onTap: () => _launchURL(targetUrl, sponsorName), // 🚨 Repassa o nome do patrocinador
          child: imageUrl.isEmpty
              ? _buildHouseAd(title: sponsorName)
              : (widget.fit == BoxFit.contain
                  ? Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: Colors.white,
                      alignment: Alignment.center,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        memCacheWidth: 800,
                        placeholder: (c, u) => _buildPlaceholder(),
                        errorWidget: (c, u, e) => _buildHouseAd(title: "$sponsorName (Sem Imagem)"),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: widget.fit,
                      width: double.infinity,
                      height: double.infinity,
                      memCacheWidth: 800,
                      placeholder: (c, u) => _buildPlaceholder(),
                      errorWidget: (c, u, e) => _buildHouseAd(title: "$sponsorName (Sem Imagem)"),
                    )),
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
    if (widget.location == 'grid_teams') {
      return _buildGridHouseAd(title: title);
    }
    return InkWell(
      onTap: () => _launchURL(null, title ?? "Seja Parceiro (House Ad)"),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E1E1E), Color(0xFF323232)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFFC25F22).withOpacity(0.5), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFC25F22), Color(0xFFC25F22)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFFC25F22).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: const FaIcon(FontAwesomeIcons.bullhorn, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ?? "SUA MARCA AQUI",
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFC25F22), letterSpacing: 1.0),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  const Text("Anuncie no App Oficial e ganhe destaque", style: TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFC25F22),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: const Text("Saber Mais", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridHouseAd({String? title}) {
    return InkWell(
      onTap: () => _launchURL(null, title ?? "Seja Parceiro (House Ad)"),
      child: Container(
        decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2A1110), Color(0xFF2A1110)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(Icons.all_inclusive, size: 100, color: Colors.white.withOpacity(0.05)),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFCC00).withOpacity(0.2), // AppTheme.yellowColor
                        shape: BoxShape.circle),
                    child: const FaIcon(FontAwesomeIcons.handshake, color: Color(0xFFFFCC00), size: 24),
                  ),
                  const SizedBox(height: 8),
                  const Text("SEJA PARCEIRO",
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          color: Color(0xFFC25F22),
                          letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  const Text("Anuncie aqui", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}