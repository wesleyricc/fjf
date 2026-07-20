import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/fantasy_service.dart';
import '../../utils/custom_cache_manager.dart';
import '../../widgets/sponsor_banner_rotator.dart';

class FantasyScoutsScreen extends StatelessWidget {
  const FantasyScoutsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Central de Scouts"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Mais Escalados", icon: Icon(Icons.groups)),
              Tab(text: "Seleção da Rodada", icon: Icon(Icons.star)),
            ],
          ),
        ),
        bottomNavigationBar: const SponsorBannerRotator(location: 'fantasy'),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FantasyService().streamGlobalScouts(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text("As estatísticas globais ainda não foram geradas para esta rodada.", 
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
                ),
              );
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final mostSelected = List<Map<String, dynamic>>.from(data['most_selected'] ?? []);
            final dreamTeam = List<Map<String, dynamic>>.from(data['dream_team'] ?? []);

            return TabBarView(
              children: [
                _buildMostSelectedList(mostSelected),
                _buildDreamTeamList(dreamTeam),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMostSelectedList(List<Map<String, dynamic>> players) {
    if (players.isEmpty) {
      return const Center(child: Text("Nenhum dado disponível.", style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final p = players[index];
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[200],
              backgroundImage: p['photo_url'] != null && p['photo_url'].toString().isNotEmpty
                  ? CachedNetworkImageProvider(p['photo_url'], cacheManager: PlayerCacheManager.instance)
                  : null,
              child: p['photo_url'] == null || p['photo_url'].toString().isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            title: Text(p['name'] ?? 'Desconhecido', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${p['position'] ?? ''}"),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("${p['selections'] ?? 0}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                const Text("times", style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDreamTeamList(List<Map<String, dynamic>> players) {
    if (players.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text("A Seleção da Rodada será gerada ao final da rodada, com base nas pontuações reais.", 
          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final p = players[index];
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[200],
              backgroundImage: p['photo_url'] != null && p['photo_url'].toString().isNotEmpty
                  ? CachedNetworkImageProvider(p['photo_url'], cacheManager: PlayerCacheManager.instance)
                  : null,
              child: p['photo_url'] == null || p['photo_url'].toString().isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            title: Text(p['name'] ?? 'Desconhecido', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${p['position'] ?? ''}"),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("${(p['score'] ?? 0).toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                const Text("pts", style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }
}
