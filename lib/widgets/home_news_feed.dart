import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/championship_service.dart';
import 'sponsor_banner_rotator.dart'; 

class HomeNewsFeed extends StatelessWidget {
  const HomeNewsFeed({super.key});

  Future<void> _launchURL(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Erro ao abrir link: $urlString");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
          child: Row(
            children: [
              Icon(Icons.newspaper, size: 20, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              const Text('Últimas Notícias', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        
        SizedBox(
          height: 210, 
          child: Consumer<ChampionshipService>(
            builder: (context, service, _) {
              final newsList = service.news;

              if (newsList.isEmpty) {
                if (service.isLoading) return const Center(child: CircularProgressIndicator());
                return const Center(child: Text("Nenhuma notícia publicada.", style: TextStyle(color: Colors.grey)));
              }

              List<Widget> carouselItems = [];
              for (int i = 0; i < newsList.length; i++) {
                carouselItems.add(_buildNewsCard(context, newsList[i]));
                if ((i + 1) % 3 == 0) carouselItems.add(_buildAdCard());
              }

              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                children: carouselItems,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNewsCard(BuildContext context, Map<String, dynamic> data) {
    final String title = data['title'] ?? 'Sem Título';
    final String imageUrl = data['imageUrl'] ?? '';
    final String targetUrl = data['targetUrl'] ?? '';
    final String author = data['author'] ?? '';

    return Container(
      width: 240, 
      margin: const EdgeInsets.only(right: 12.0, bottom: 8.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _launchURL(targetUrl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 130,
                width: double.infinity,
                child: imageUrl.isEmpty
                    ? Container(color: Colors.grey[200], child: const Icon(Icons.image, color: Colors.grey))
                    : CachedNetworkImage(
                        imageUrl: imageUrl, fit: BoxFit.cover,
                        placeholder: (c, u) => Container(color: Colors.grey[200]),
                        errorWidget: (c, u, e) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (author.isNotEmpty)
                        Row(children: [
                            const Icon(Icons.person_outline, size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(child: Text(author, style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis)),
                        ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdCard() {
    return Container(
      width: 240, 
      margin: const EdgeInsets.only(right: 12.0, bottom: 8.0),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const SponsorBannerRotator(location: 'news_feed', isStatic: false, height: double.infinity),
            Positioned(
              top: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                child: const Text("Publicidade", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}