import 'dart:async';
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
  Timer? _newsTimer;
  bool _showAdInHero = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      Provider.of<NewsViewModel>(context, listen: false).loadNews(seasonId);
    });

    _startNewsTimer();
  }

  void _startNewsTimer() {
    _newsTimer?.cancel();
    _newsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _showAdInHero = true;
        });
      }
    });
  }

  void _onAdCycleComplete() {
    if (mounted) {
      setState(() {
        _showAdInHero = false;
      });
      _startNewsTimer();
    }
  }

  @override
  void dispose() {
    _newsTimer?.cancel();
    super.dispose();
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
          
          Consumer<NewsViewModel>(
            builder: (context, newsVm, _) {
              final newsList = newsVm.news;
              
              if (newsList.isEmpty) {
                if (newsVm.isLoading) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(12.0),
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(child: Text("Nenhuma notícia publicada.", style: TextStyle(color: Colors.grey))),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                      child: SizedBox(height: 160, child: _buildHeroAdCard()),
                    ),
                  ],
                );
              }

              final heroNews = newsList[0];
              final remainingNews = newsList.length > 1 ? newsList.sublist(1) : <Map<String, dynamic>>[];

              return Container(
                height: 240, // Altura perfeita para acomodar 2 cards de 114px na lateral + espaçamento
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    // BLOCO MAIOR (DESTAQUE REVEZANDO COM PUBLICIDADE)
                    Expanded(
                      flex: 6, // Aumentado o flex da notícia principal
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                        child: _showAdInHero
                            ? _buildHeroAdCard(key: const ValueKey('ad'), onCycleComplete: _onAdCycleComplete)
                            : _buildHeroNewsCard(context, heroNews, key: const ValueKey('news')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ROLAGEM VERTICAL (MAIS NOTÍCIAS)
                    Expanded(
                      flex: 4, // Reduzido o espaço da barra de rolagem lateral
                      child: _buildVerticalSideScroll(context, remainingNews),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeroNewsCard(BuildContext context, Map<String, dynamic> data, {Key? key}) {
    final String title = data['title'] ?? 'Sem Título';
    final String imageUrl = data['imageUrl'] ?? '';
    final String targetUrl = data['targetUrl'] ?? '';

    return GestureDetector(
      key: key,
      onTap: () => _launchURL(targetUrl),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
          color: Colors.grey[200],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl, 
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(color: Colors.grey[200]),
                errorWidget: (c, u, e) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
              )
            else
              const Center(child: Icon(Icons.image, color: Colors.grey, size: 40)),
            
            // Gradiente para tornar o texto legível sobre a imagem
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black87, Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0.0, 0.7]
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                     decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(4)),
                     child: const Text("DESTAQUE", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title, 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, height: 1.2), 
                    maxLines: 4, 
                    overflow: TextOverflow.ellipsis
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalSideScroll(BuildContext context, List<Map<String, dynamic>> remainingNews) {
    if (remainingNews.isEmpty) {
       return const Center(child: Text("Sem mais notícias.", style: TextStyle(fontSize: 10, color: Colors.grey)));
    }

    List<Widget> listItems = [];
    
    for (int i = 0; i < remainingNews.length; i++) {
        listItems.add(_buildSideNewsCard(context, remainingNews[i]));
        if (i < remainingNews.length - 1) {
            listItems.add(const SizedBox(height: 12));
        }
    }

    return ListView(
      scrollDirection: Axis.vertical,
      padding: EdgeInsets.zero, 
      children: listItems,
    );
  }

  Widget _buildSideNewsCard(BuildContext context, Map<String, dynamic> data) {
    final String title = data['title'] ?? 'Sem Título';
    final String imageUrl = data['imageUrl'] ?? '';
    final String targetUrl = data['targetUrl'] ?? '';

    return GestureDetector(
      onTap: () => _launchURL(targetUrl),
      child: Container(
        height: 114, // Altura que permite exibir 2 itens exatos junto com a imagem hero
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: imageUrl.isEmpty
                  ? Container(color: Colors.grey[200], child: const Icon(Icons.image, color: Colors.grey))
                  : CachedNetworkImage(
                      imageUrl: imageUrl, 
                      fit: BoxFit.cover,
                      placeholder: (c, u) => Container(color: Colors.grey[200]),
                      errorWidget: (c, u, e) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
                    ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Text(
                  title, 
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10, height: 1.1), 
                  maxLines: 3, 
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroAdCard({Key? key, VoidCallback? onCycleComplete}) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: Colors.amber.shade300, width: 2), 
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            SponsorBannerRotator(
              location: 'news_feed', 
              isStatic: false,
              onCycleComplete: onCycleComplete,
            ),
            Positioned(
              top: 6, right: 6,
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