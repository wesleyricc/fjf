import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/portal_models.dart';
import '../../models/team_model.dart';
import '../../services/portal_service.dart';
import '../../services/team_service.dart';
import '../../services/championship_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/team_logo_widget.dart';
import 'portal_admin_team_management_screen.dart';

class PortalAdminTeamsTab extends StatefulWidget {
  const PortalAdminTeamsTab({super.key});

  @override
  State<PortalAdminTeamsTab> createState() => _PortalAdminTeamsTabState();
}

class _PortalAdminTeamsTabState extends State<PortalAdminTeamsTab> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);
    final teamService = Provider.of<TeamService>(context, listen: false);
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    if (seasonId.isEmpty) {
      return const Center(child: Text('Nenhum campeonato selecionado.'));
    }

    return StreamBuilder<List<PortalUser>>(
      stream: portalService.streamAllUsers(),
      builder: (context, userSnapshot) {
        return StreamBuilder<List<PortalFinancialDue>>(
          stream: portalService.streamAllDues(),
          builder: (context, dueSnapshot) {
            return StreamBuilder<List<Team>>(
              stream: teamService.streamTeams(seasonId),
              builder: (context, teamSnapshot) {
                if (userSnapshot.hasError || dueSnapshot.hasError || teamSnapshot.hasError) {
                  return const Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.red)));
                }

                if (!userSnapshot.hasData || !dueSnapshot.hasData || !teamSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = userSnapshot.data!;
                final dues = dueSnapshot.data!;
                final allTeams = teamSnapshot.data!;

                final filteredTeams = allTeams.where((t) {
                  if (_searchQuery.isEmpty) return true;
                  return t.name.toLowerCase().contains(_searchQuery.toLowerCase());
                }).toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar equipe...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: Colors.grey[200],
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                    Expanded(
                      child: filteredTeams.isEmpty
                          ? const Center(child: Text('Nenhuma equipe encontrada.'))
                          : ListView.builder(
                              itemCount: filteredTeams.length,
                              itemBuilder: (context, index) {
                                final team = filteredTeams[index];
                                final teamUsers = users.where((u) => u.teamId == team.id).toList();
                                final teamDues = dues.where((d) {
                                  if (d.teamId == team.id) return true;
                                  return teamUsers.any((u) => u.id == d.userId);
                                }).toList();

                                final pendingAndOverdue = teamDues.where((d) => d.status != 'paid').toList();
                                final totalDebt = pendingAndOverdue.fold(0.0, (sum, d) => sum + d.amount);

                                final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  elevation: 2,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(12),
                                    leading: TeamLogoWidget(logoUrl: team.shieldUrl, radius: 25),
                                    title: Text(team.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Row(
                                        children: [
                                          Icon(Icons.people, size: 16, color: Colors.grey[600]),
                                          const SizedBox(width: 4),
                                          Text('${teamUsers.length} membros'),
                                          const SizedBox(width: 16),
                                          Icon(Icons.warning_amber, size: 16, color: totalDebt > 0 ? Colors.red : Colors.green),
                                          const SizedBox(width: 4),
                                          Text(
                                            currency.format(totalDebt),
                                            style: TextStyle(
                                              color: totalDebt > 0 ? Colors.red : Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PortalAdminTeamManagementScreen(
                                            team: team,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          }
        );
      }
    );
  }
}
