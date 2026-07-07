import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/championship_service.dart';
import '../viewmodels/news_viewmodel.dart';
import 'sponsor_banner_rotator.dart';

class HomeNewsFeed extends StatefulWidget {
  const HomeNewsFeed({super.key});

  @override
  State<HomeNewsFeed> createState() => _HomeNewsFeedState();
}

class _HomeNewsFeedState extends State<HomeNewsFeed> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      Provider.of<NewsViewModel>(context, listen: false).loadNews(seasonId);
    });
  }

  Future<void> _launchURL(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Erro ao abrir link: $urlString");
    }
  }

  Widget _buildThemedHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFC5A814), Color(0xFF00873E)], 
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: const Row(
        children: [
          Icon(Icons.newspaper, size: 20, color: Colors.white),
          SizedBox(width: 8),
          Text('Últimas Notícias', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
        border: Border.all(color: Colors.grey.shade200)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildThemedHeader(),
          SizedBox(
            height: 245, // Altura ajustada para acomodar a proporção 16:9 + textos
            child: Consumer<NewsViewModel>(
              builder: (context, newsVm, _) {
                final newsList = newsVm.news;
                if (newsList.isEmpty) {
                  if (newsVm.isLoading) return const Center(child: CircularProgressIndicator());
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))
                    ),
                    child: const Center(child: Text("Nenhuma notícia publicada.", style: TextStyle(color: Colors.grey))),
                  );
                }

                List<Widget> carouselItems = [];
                for (int i = 0; i < newsList.length; i++) {
                  carouselItems.add(_buildNewsCard(context, newsList[i]));
                  if ((i + 1) % 3 == 0) carouselItems.add(_buildAdCard());
                }

                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12.0), // Padding interno para a lista
                  children: carouselItems,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(BuildContext context, Map<String, dynamic> data) {
    final String title = data['title'] ?? 'Sem Título';
    final String imageUrl = data['imageUrl'] ?? '';
    final String targetUrl = data['targetUrl'] ?? '';
    final String author = data['author'] ?? '';

    return Container(
      width: 240, 
      margin: const EdgeInsets.only(right: 12.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _launchURL(targetUrl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9, // Força a proporção exata de 1920x1080 px
                child: SizedBox(
                  width: double.infinity,
                  child: imageUrl.isEmpty
                      ? Container(color: Colors.grey[200], child: const Icon(Icons.image, color: Colors.grey))
                      : CachedNetworkImage(
                          imageUrl: imageUrl, 
                          fit: BoxFit.cover,
                          placeholder: (c, u) => Container(color: Colors.grey[200]),
                          errorWidget: (c, u, e) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
                        ),
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
      margin: const EdgeInsets.only(right: 12.0),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
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