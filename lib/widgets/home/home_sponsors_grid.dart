import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../viewmodels/sponsor_viewmodel.dart';
import '../../theme/app_theme.dart';

class HomeSponsorsGrid extends StatelessWidget {
  const HomeSponsorsGrid({super.key});

  List<Map<String, dynamic>> _getHomeSponsors(SponsorViewModel sponsorVm) {
    return sponsorVm.sponsors.where((data) {
      final List<dynamic> locations = data['locations'] ?? [];
      final String? oldLocation = data['location'];
      return locations.contains('home_partners_grid') || oldLocation == 'home_partners_grid';
    }).toList();
  }

  int _getCategoryPriority(String category) {
    switch (category) {
      case 'MASTER': return 1;
      case 'PLATINUM':
      case 'PREMIUM': return 2;
      case 'OURO': return 3;
      case 'PRATA': return 4;
      case 'BRONZE': default: return 5;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'MASTER': return const Color(0xFF00E5FF); // Diamante
      case 'PLATINUM':
      case 'PREMIUM': return const Color(0xFF50C878); // Esmeralda
      case 'OURO': return const Color(0xFFFFD700); // Ouro
      case 'PRATA': return const Color(0xFFC0C0C0); // Prata
      case 'BRONZE': default: return const Color(0xFFCD7F32); // Bronze
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SponsorViewModel>(
      builder: (context, sponsorVm, _) {
        final sponsors = _getHomeSponsors(sponsorVm);
        
        // Ordenação por tipo de patrocinador
        sponsors.sort((a, b) {
          int priorityA = _getCategoryPriority(a['category'] ?? '');
          int priorityB = _getCategoryPriority(b['category'] ?? '');
          return priorityA.compareTo(priorityB);
        });

        if (sponsors.isEmpty) {
          return SliverToBoxAdapter(
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.0,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: 4,
              itemBuilder: (context, index) => _buildDefaultCard(),
            ),
          );
        }

        return SliverToBoxAdapter(
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.0,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: sponsors.length,
            itemBuilder: (context, index) {
              return _buildSponsorCard(sponsors[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildSponsorCard(Map<String, dynamic> data) {
    final String imageUrl = (data['imageUrl']?.toString() ?? '').trim();
    final String? targetUrl = data['targetUrl'];
    final String categoryName = data['category'] ?? 'BRONZE';

    if (imageUrl.isEmpty) {
      return _buildDefaultCard();
    }
    
    Color borderColor = _getCategoryColor(categoryName);
    double borderWidth = categoryName == 'MASTER' ? 2.5 : ((categoryName == 'PREMIUM' || categoryName == 'PLATINUM') ? 2.0 : 1.5);

    return InkWell(
      onTap: () async {
        if (targetUrl != null && targetUrl.isNotEmpty) {
          final uri = Uri.parse(targetUrl);
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            debugPrint("Erro ao abrir: $targetUrl");
          }
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox.expand(
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: 400,
              placeholder: (context, url) => Container(
                color: Colors.white,
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultCard() {
    const String partnerContactUrl = "https://wa.me/5548996381626?text=Ol%C3%A1,%20gostaria%20de%20ser%20parceiro%20do%20aplicativo%20da%20FJF.";
    return InkWell(
      onTap: () => launchUrl(Uri.parse(partnerContactUrl), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
            image: AppTheme.headerImage,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.yellowColor, width: 1.5)),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(Icons.all_inclusive, size: 40, color: Colors.white.withOpacity(0.05)),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: AppTheme.yellowColor.withOpacity(0.2),
                        shape: BoxShape.circle),
                    child: const FaIcon(FontAwesomeIcons.handshake, color: AppTheme.yellowColor, size: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text("PARCEIRO",
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 7,
                          color: AppTheme.yellowColor,
                          letterSpacing: 0.2)),
                  const SizedBox(height: 1),
                  const Text("Anuncie", textAlign: TextAlign.center, style: TextStyle(fontSize: 6, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
