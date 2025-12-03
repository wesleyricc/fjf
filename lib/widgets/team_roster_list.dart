import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Services & Models
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/player_model.dart'; // <-- Model

// Screens
import '../screens/player_profile_screen.dart';
import '../screens/edit_player_screen.dart';
import '../utils/custom_cache_manager.dart'; // Para cache de imagens

class TeamRosterList extends StatelessWidget {
  final String teamId;
  final String teamName;

  const TeamRosterList({super.key, required this.teamId, required this.teamName});

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final authService = Provider.of<AuthService>(context);
    final firestoreService = FirestoreService();

    return StreamBuilder<List<Player>>( // <-- Stream Tipada
      stream: firestoreService.streamPlayers(seasonId, teamId: teamId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
        }
        
        final allMembers = snapshot.data ?? [];
        if (allMembers.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Nenhum membro ativo.')));
        }

        // Separação segura usando o Model
        final players = allMembers.where((p) => !p.isStaff).toList();
        final staff = allMembers.where((p) => p.isStaff).toList();

        // Ordenação (Número -> Nome)
        players.sort((a, b) {
          final na = a.jerseyNumber ?? 999;
          final nb = b.jerseyNumber ?? 999;
          return na.compareTo(nb);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TABELA DE JOGADORES ---
            _buildSectionTitle(context, 'Elenco'),
            if (players.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Sem jogadores.'))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DataTable(
                  columnSpacing: 16.0,
                  horizontalMargin: 8.0,
                  headingRowHeight: 40,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 48,
                  columns: [
                    const DataColumn(label: Text('Nº', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Atleta', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Pos.', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Icon(Icons.sports_soccer, size: 18)),
                    const DataColumn(label: Icon(Icons.style, size: 18, color: Colors.orange)),
                    const DataColumn(label: Icon(Icons.style, size: 18, color: Colors.red)),
                    if (authService.isAuthenticated) const DataColumn(label: Icon(Icons.settings, size: 18)),
                  ],
                  rows: players.map((player) {
                    return DataRow(cells: [
                      DataCell(Text('${player.jerseyNumber ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(
                        InkWell(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: player.id))),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.grey[200],
                                backgroundImage: player.photoUrl.isNotEmpty 
                                    ? CachedNetworkImageProvider(player.photoUrl, cacheManager: PlayerCacheManager.instance) 
                                    : null,
                                child: player.photoUrl.isEmpty ? const Icon(Icons.person, size: 16, color: Colors.grey) : null,
                              ),
                              const SizedBox(width: 8),
                              Text(player.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                      DataCell(Text(player.isGoalkeeper ? 'GK' : (player.position?.substring(0, 3) ?? '-'))),
                      DataCell(Text('${player.goals > 0 ? player.goals : "-"}')),
                      DataCell(Text('${player.totalYellowCards > 0 ? player.totalYellowCards : "-"}')),
                      DataCell(Text('${player.totalRedCards > 0 ? player.totalRedCards : "-"}')),
                      if (authService.isAuthenticated)
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditPlayerScreen(teamId: teamId, teamName: teamName, playerDoc: null))), // Obs: Idealmente adaptar EditPlayer para receber Player model
                          ),
                        ),
                    ]);
                  }).toList(),
                ),
              ),

            // --- LISTA DE STAFF ---
            if (staff.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle(context, 'Comissão Técnica'),
              ...staff.map((member) => Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: Icon(_getStaffIcon(member.staffRole), color: Colors.blueGrey),
                  title: Text(member.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(member.staffRole ?? 'Membro'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: member.id))),
                ),
              )),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  IconData _getStaffIcon(String? role) {
    if (role == null) return Icons.assignment_ind_outlined;
    String roleLower = role.toLowerCase();
    if (roleLower.contains('treinador') || roleLower.contains('técnico')) return Icons.content_paste;
    if (roleLower.contains('auxiliar')) return Icons.support_agent;
    if (roleLower.contains('atendente')) return Icons.how_to_reg;
    if (roleLower.contains('analista')) return Icons.analytics;
    if (roleLower.contains('massagista') || roleLower.contains('fisio')) return Icons.healing;
    return Icons.assignment_ind_outlined;
  }
}