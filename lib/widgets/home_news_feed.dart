import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';

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
    // 1. Obtém contexto da temporada
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    // ALTERAÇÃO: Define a query sempre para a subcoleção da temporada atual
    // Removemos a verificação de LEGACY_ID
    final Query mediaQuery = firestore
        .collection('championships')
        .doc(seasonId)
        .collection('news');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
          child: Row(
            children: [
              Icon(Icons.newspaper, size: 20, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Text(
                'Últimas Notícias',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        
        SizedBox(
          height: 210, // Altura fixa para o carrossel
          child: StreamBuilder<QuerySnapshot>(
            stream: mediaQuery
                .where('isActive', isEqualTo: true)
                .orderBy('order', descending: true)
                .limit(10)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.feed_outlined, size: 40, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text('Nenhuma notícia publicada.', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                );
              }

              final docs = snapshot.data!.docs;

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  return _buildNewsCard(context, data);
                },
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
      width: 240, // Largura do card
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
              // Imagem
              SizedBox(
                height: 130,
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
              
              // Texto
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (author.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(child: Text(author, style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
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
}