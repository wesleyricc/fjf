import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart'; // <-- NOVO IMPORT
import '../services/championship_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/player_selection_modal.dart'; 
import '../utils/custom_cache_manager.dart';

class PlayerComparisonScreen extends StatefulWidget {
  const PlayerComparisonScreen({super.key});

  @override
  State<PlayerComparisonScreen> createState() => _PlayerComparisonScreenState();
}

class _PlayerComparisonScreenState extends State<PlayerComparisonScreen> {
  DocumentSnapshot? _player1;
  DocumentSnapshot? _player2;

  Future<void> _openSelectionModal(int slot) async {
    final DocumentSnapshot? selected = await showDialog<DocumentSnapshot>(
      context: context,
      builder: (ctx) => const PlayerSelectionModal(),
    );

    if (selected != null) {
      setState(() {
        if (slot == 1) _player1 = selected;
        else _player2 = selected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonName = Provider.of<ChampionshipService>(context).currentSeasonName;

    return Scaffold(
      appBar: AppBar(
        // 🚨 NOVO: Gradiente da Copa aplicado
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.brazilGradient,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Comparador de Atletas'),
            Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
          ],
        ),
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber[50],
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: const Text(
              'Estatísticas - Temporada Selecionada', 
              textAlign: TextAlign.center, 
              style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold, fontSize: 12)
            ),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildPlayerHeader(1, _player1)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 30.0),
                  child: Text("VS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.grey)),
                ),
                Expanded(child: _buildPlayerHeader(2, _player2)),
              ],
            ),
          ),

          Expanded(
            child: (_player1 == null || _player2 == null)
                ? _buildEmptyState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Column(
                      children: [
                         _buildComparisonRow('Gols', 'goals', higherIsBetter: true),
                         _buildComparisonRow('Assistências', 'assists', higherIsBetter: true),
                         _buildComparisonRow('Participações', 'goals', secondaryField: 'assists', labelOverride: 'Participações em Gols', higherIsBetter: true),
                         _buildComparisonRow('Cartões Amarelos', 'total_yellow_cards', higherIsBetter: false),
                         _buildComparisonRow('Cartões Vermelhos', 'total_red_cards', higherIsBetter: false),
                         _buildComparisonRow('Craque do Jogo', 'man_of_the_match_awards', higherIsBetter: true),
                         
                         if ((_isGoalkeeper(_player1)) || (_isGoalkeeper(_player2)))
                           _buildComparisonRow('Gols Sofridos', 'goals_conceded', higherIsBetter: false),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  bool _isGoalkeeper(DocumentSnapshot? p) {
    if (p == null) return false;
    return (p.data() as Map<String, dynamic>)['is_goalkeeper'] == true;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.compare_arrows, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Selecione dois atletas para iniciar.', style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildPlayerHeader(int slot, DocumentSnapshot? player) {
    if (player == null) {
      return Column(
        children: [
          GestureDetector(
            onTap: () => _openSelectionModal(slot),
            child: CircleAvatar(
              radius: 45, 
              backgroundColor: Colors.white, 
              child: Icon(Icons.add, size: 40, color: Theme.of(context).primaryColor),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _openSelectionModal(slot),
            style: ElevatedButton.styleFrom(
              visualDensity: VisualDensity.compact, 
              backgroundColor: Theme.of(context).primaryColor, 
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Selecionar'),
          ),
        ],
      );
    }

    final data = player.data() as Map<String, dynamic>;
    final int? number = data['jersey_number'];
    final String name = data['name'] ?? '';
    final String photoUrl = data['photo_url'] ?? '';
    final String teamName = data['team_name'] ?? '';

    return Column(
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            GestureDetector(
               onTap: () => _openSelectionModal(slot),
               child: CircleAvatar(
                radius: 45,
                backgroundColor: Colors.white,
                backgroundImage: photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl, cacheManager: PlayerCacheManager.instance) : null,
                child: photoUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
              ),
            ),
            Positioned(
              right: 0, top: 0,
              child: GestureDetector(
                onTap: () => setState(() { if (slot == 1) _player1 = null; else _player2 = null; }),
                child: const CircleAvatar(radius: 14, backgroundColor: Colors.red, child: Icon(Icons.close, size: 16, color: Colors.white)),
              ),
            )
          ],
        ),
        const SizedBox(height: 12),
        Text(
          number != null ? '#$number $name' : name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
          maxLines: 2, overflow: TextOverflow.ellipsis
        ),
        const SizedBox(height: 4),
        Text(teamName, style: TextStyle(fontSize: 12, color: Colors.grey[700]), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildComparisonRow(String label, String fieldKey, {String? secondaryField, String? labelOverride, required bool higherIsBetter}) {
    final data1 = _player1!.data() as Map<String, dynamic>;
    final data2 = _player2!.data() as Map<String, dynamic>;

    num val1 = (data1[fieldKey] ?? 0) + (secondaryField != null ? (data1[secondaryField] ?? 0) : 0);
    num val2 = (data2[fieldKey] ?? 0) + (secondaryField != null ? (data2[secondaryField] ?? 0) : 0);

    Color color1 = Colors.black87;
    Color color2 = Colors.black87;
    FontWeight weight1 = FontWeight.normal;
    FontWeight weight2 = FontWeight.normal;

    if (val1 != val2) {
      if (higherIsBetter) {
        if (val1 > val2) { color1 = Colors.green[700]!; weight1 = FontWeight.bold; }
        else { color2 = Colors.green[700]!; weight2 = FontWeight.bold; }
      } else {
        if (val1 < val2) { color1 = Colors.green[700]!; weight1 = FontWeight.bold; }
        else { color2 = Colors.green[700]!; weight2 = FontWeight.bold; }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          Expanded(child: Text(val1.toString(), style: TextStyle(fontSize: 20, color: color1, fontWeight: weight1), textAlign: TextAlign.center)),
          Expanded(
            flex: 2, 
            child: Text(
              labelOverride ?? label, 
              style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500), 
              textAlign: TextAlign.center
            )
          ),
          Expanded(child: Text(val2.toString(), style: TextStyle(fontSize: 20, color: color2, fontWeight: weight2), textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}