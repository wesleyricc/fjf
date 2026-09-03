import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/portal_models.dart';
import '../../models/team_model.dart';
import '../../services/portal_service.dart';
import '../../services/championship_service.dart';
import '../../services/team_service.dart';

class PortalEventAttendanceScreen extends StatelessWidget {
  final PortalEvent event;

  const PortalEventAttendanceScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);
    final champService = Provider.of<ChampionshipService>(context, listen: false);
    final teamService = Provider.of<TeamService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chamada / Presença', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 1,
      ),
      body: StreamBuilder<List<PortalUser>>(
        stream: portalService.streamAllUsers(),
        builder: (context, userSnap) {
          if (!userSnap.hasData) return const Center(child: CircularProgressIndicator());
          
          final allUsers = userSnap.data!;
          // Filtra atletas pelo time do evento, ou todos se for geral
          final eventUsers = event.teamId == null 
            ? allUsers 
            : allUsers.where((u) => u.teamId == event.teamId).toList();

          return StreamBuilder<List<PortalAttendance>>(
            stream: portalService.streamAttendanceForEvent(event.id),
            builder: (context, attSnap) {
              if (!attSnap.hasData) return const Center(child: CircularProgressIndicator());
              
              final allAttendance = attSnap.data!;

              return StreamBuilder<List<Team>>(
                stream: teamService.streamTeams(champService.currentSeasonId),
                builder: (context, teamSnap) {
                  if (!teamSnap.hasData) return const Center(child: CircularProgressIndicator());

                  final teams = teamSnap.data!;
                  
                  // Agrupar usuários
                  final Map<String, List<PortalUser>> groupedUsers = {};
                  final List<PortalUser> noTeamUsers = [];

                  for (var u in eventUsers) {
                    if (u.teamId != null && u.teamId!.isNotEmpty) {
                      groupedUsers.putIfAbsent(u.teamId!, () => []).add(u);
                    } else {
                      noTeamUsers.add(u);
                    }
                  }

                  // Converter map em widgets
                  final List<Widget> children = [];

                  // Se houver times
                  for (var entry in groupedUsers.entries) {
                    final teamId = entry.key;
                    final teamUsers = entry.value;
                    final team = teams.where((t) => t.id == teamId).firstOrNull;
                    final teamName = team?.name ?? 'Equipe Desconhecida';

                    int confirmedCount = 0;
                    for (var u in teamUsers) {
                      final att = allAttendance.where((a) => a.userId == u.id).firstOrNull;
                      if (att?.status == 'confirmed') {
                        confirmedCount++;
                      }
                    }

                    children.add(
                      ExpansionTile(
                        title: Text(teamName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$confirmedCount confirmados de ${teamUsers.length} membros'),
                        children: _buildUserList(teamUsers, allAttendance, portalService, event.id),
                      )
                    );
                  }

                  // Staff / Sem time
                  if (noTeamUsers.isNotEmpty) {
                    int confirmedCount = 0;
                    for (var u in noTeamUsers) {
                      final att = allAttendance.where((a) => a.userId == u.id).firstOrNull;
                      if (att?.status == 'confirmed') {
                        confirmedCount++;
                      }
                    }

                    children.add(
                      ExpansionTile(
                        title: const Text('Staff / Sem Equipe', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$confirmedCount confirmados de ${noTeamUsers.length} membros'),
                        children: _buildUserList(noTeamUsers, allAttendance, portalService, event.id),
                      )
                    );
                  }
                  
                  if (children.isEmpty) {
                    return const Center(child: Text("Nenhum usuário convocado."));
                  }

                  return ListView(
                    children: children,
                  );
                }
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildUserList(List<PortalUser> users, List<PortalAttendance> allAttendance, PortalService portalService, String eventId) {
    return users.map((user) {
      final attendance = allAttendance.where((a) => a.userId == user.id).firstOrNull;
      final status = attendance?.status ?? 'pending';

      Color statusColor = Colors.grey;
      if (status == 'confirmed') statusColor = Colors.green;
      if (status == 'absent') statusColor = Colors.red;

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
        title: Text(user.name),
        subtitle: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => portalService.updateAttendance(eventId, user.id, 'confirmed'),
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: () => portalService.updateAttendance(eventId, user.id, 'absent'),
            ),
          ],
        ),
      );
    }).toList();
  }
}
