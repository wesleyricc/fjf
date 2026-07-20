import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_league_model.dart';
import '../../services/fantasy_league_service.dart';
import 'admin_edit_sponsored_league_screen.dart';

class AdminSponsoredLeaguesScreen extends StatelessWidget {
  const AdminSponsoredLeaguesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final leagueService = FantasyLeagueService();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ligas Patrocinadas"),
      ),
      body: StreamBuilder<List<FantasyLeague>>(
        stream: leagueService.streamSponsoredLeagues(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Erro: ${snapshot.error}"));
          }
          final leagues = snapshot.data ?? [];

          if (leagues.isEmpty) {
            return const Center(child: Text("Nenhuma liga patrocinada encontrada."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: leagues.length,
            itemBuilder: (context, index) {
              final league = leagues[index];
              return Card(
                child: ListTile(
                  leading: league.sponsorImageUrl != null && league.sponsorImageUrl!.isNotEmpty
                      ? Image.network(league.sponsorImageUrl!, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))
                      : const Icon(Icons.image_not_supported, size: 50),
                  title: Text(league.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(league.prizeDescription ?? "Sem premiação definida"),
                  trailing: const Icon(Icons.edit, color: Colors.blue),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminEditSponsoredLeagueScreen(league: league),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminEditSponsoredLeagueScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text("Nova Liga"),
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black,
      ),
    );
  }
}
