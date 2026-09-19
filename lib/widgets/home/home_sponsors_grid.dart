import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../viewmodels/sponsor_viewmodel.dart';

class HomeSponsorsGrid extends StatefulWidget {
  const HomeSponsorsGrid({super.key});

  @override
  State<HomeSponsorsGrid> createState() => _HomeSponsorsGridState();
}

class _HomeSponsorsGridState extends State<HomeSponsorsGrid> {
  Timer? _timer;
  int _currentPage = 0;
  final int _itemsPerPage = 25;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (mounted) {
        final sponsorVm = Provider.of<SponsorViewModel>(context, listen: false);
        final sponsors = _getHomeSponsors(sponsorVm);
        
        if (sponsors.length > _itemsPerPage) {
          setState(() {
            int totalPages = (sponsors.length / _itemsPerPage).ceil();
            _currentPage = (_currentPage + 1) % totalPages;
          });
        }
      }
    });
  }
  
  List<Map<String, dynamic>> _getHomeSponsors(SponsorViewModel sponsorVm) {
    return sponsorVm.sponsors.where((data) {
      final List<dynamic> locations = data['locations'] ?? [];
      final String? oldLocation = data['location'];
      return locations.contains('home_partners_grid') || oldLocation == 'home_partners_grid';
    }).toList();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SponsorViewModel>(
      builder: (context, sponsorVm, _) {
        final sponsors = _getHomeSponsors(sponsorVm);

        int startIndex = 0;
        int endIndex = 0;
        List<Map<String, dynamic>> currentSponsors = [];

        if (sponsors.isNotEmpty) {
          startIndex = _currentPage * _itemsPerPage;
          endIndex = startIndex + _itemsPerPage;
          if (endIndex > sponsors.length) endIndex = sponsors.length;
          
          if (startIndex >= sponsors.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _currentPage = 0);
              }
            });
            startIndex = 0;
            endIndex = sponsors.length < _itemsPerPage ? sponsors.length : _itemsPerPage;
          }
          currentSponsors = List.from(sponsors.sublist(startIndex, endIndex));
        }

        while (currentSponsors.length < _itemsPerPage) {
          currentSponsors.add({});
        }

        final master = currentSponsors.where((s) => s['category'] == 'MASTER').toList();
        final premium = currentSponsors.where((s) => s['category'] == 'PREMIUM').toList();
        final ouro = currentSponsors.where((s) => s['category'] == 'OURO').toList();
        final prata = currentSponsors.where((s) => s['category'] == 'PRATA').toList();
        final bronzeAndOthers = currentSponsors.where((s) {
          final cat = s['category'];
          return cat != 'MASTER' && cat != 'PREMIUM' && cat != 'OURO' && cat != 'PRATA';
        }).toList();

        return SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: Column(
              key: ValueKey<int>(_currentPage),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (master.isNotEmpty) _buildCategoryGrid(master, 3, 'MASTER'),
                if (premium.isNotEmpty) _buildCategoryGrid(premium, 3, 'PREMIUM'),
                if (ouro.isNotEmpty) _buildCategoryGrid(ouro, 4, 'OURO'),
                if (prata.isNotEmpty) _buildCategoryGrid(prata, 5, 'PRATA'),
                if (bronzeAndOthers.isNotEmpty) _buildCategoryGrid(bronzeAndOthers, 5, 'BRONZE'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryGrid(List<Map<String, dynamic>> categorySponsors, int crossAxisCount, String categoryName) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Text(
              'Parceiros $categoryName',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _getCategoryColor(categoryName),
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 1.0,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: categorySponsors.length,
            itemBuilder: (context, index) {
              final data = categorySponsors[index];
              return _buildSponsorCard(data, categoryName);
            },
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'MASTER':
        return Colors.black87;
      case 'PREMIUM':
        return Colors.blue.shade800;
      case 'OURO':
        return const Color(0xFFFFD700);
      case 'PRATA':
        return const Color(0xFFC0C0C0);
      case 'BRONZE':
      default:
        return const Color(0xFFCD7F32);
    }
  }

  Widget _buildSponsorCard(Map<String, dynamic> data, String categoryName) {
    final String imageUrl = data['imageUrl'] ?? '';
    final String? targetUrl = data['targetUrl'];

    if (imageUrl.isEmpty) {
      return _buildDefaultCard();
    }
    
    Color borderColor = _getCategoryColor(categoryName);
    double borderWidth = categoryName == 'MASTER' ? 3.0 : (categoryName == 'PREMIUM' ? 2.5 : 1.5);

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
          borderRadius: BorderRadius.circular(11),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            memCacheWidth: 300,
            errorWidget: (_, __, ___) => Container(
              color: Colors.grey.shade200,
              child: const Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultCard() {
    final String partnerContactUrl = "https://wa.me/5548996381626?text=Ol%C3%A1,%20gostaria%20de%20ser%20parceiro%20do%20aplicativo%20da%20FJF.";
    return InkWell(
      onTap: () => launchUrl(Uri.parse(partnerContactUrl), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF002776), Color(0xFF001133)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC5A814), width: 1.5)),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(Icons.all_inclusive, size: 50, color: Colors.white.withOpacity(0.05)),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: const Color(0xFFC5A814).withOpacity(0.2),
                        shape: BoxShape.circle),
                    child: const Icon(FontAwesomeIcons.handshake, color: Color(0xFFC5A814), size: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text("PARCEIRO",
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 7,
                          color: Color(0xFFC5A814),
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
