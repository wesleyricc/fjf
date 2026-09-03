import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/portal_models.dart';
import '../../services/portal_service.dart';
import '../../services/portal_auth_service.dart';
import 'package:intl/intl.dart';
import 'portal_admin_modals.dart';
import 'portal_event_attendance_screen.dart';
import '../../theme/app_theme.dart';
import '../../services/championship_service.dart';

class PortalAgendaTab extends StatelessWidget {
  const PortalAgendaTab({super.key});

  @override
  Widget build(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);
    final authService = Provider.of<PortalAuthService>(context, listen: false);
    final champService = Provider.of<ChampionshipService>(context, listen: true);
    final user = authService.currentPortalUser;

    if (user == null) return const Center(child: Text("Usuário não encontrado."));

    return StreamBuilder<List<PortalEvent>>(
      stream: portalService.streamUpcomingEvents(teamId: user.teamId, userRole: user.role),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }

        List<PortalEvent> events = List.from(snapshot.data ?? []);
        
        if (user.teamId != null) {
          final now = DateTime.now();
          final matches = champService.matches.where((m) => 
            (m.homeTeamId == user.teamId || m.awayTeamId == user.teamId) && 
            m.datetime != null && m.datetime!.isAfter(now)
          );
          
          for (var m in matches) {
            events.add(PortalEvent(
              id: m.id,
              title: 'Jogo: ${m.homeTeamName} x ${m.awayTeamName}',
              date: m.datetime!,
              location: m.location,
              description: 'Rodada ${m.round} - ${m.phase}',
              teamId: user.teamId,
              targetRole: 'all',
              isMatch: true,
            ));
          }
        }
        
        events.sort((a, b) => a.date.compareTo(b.date));
        
        final listWidget = events.isEmpty 
          ? const Center(
              child: Text("Sua agenda está livre! Não há próximos eventos.",
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return _EventCard(event: event, user: user, portalService: portalService);
              },
            );

        return Scaffold(
          body: listWidget,
          floatingActionButton: (user.role == 'admin' || user.role == 'president')
            ? FloatingActionButton(
                backgroundColor: AppTheme.primaryColor,
                child: const Icon(Icons.add, color: Colors.white),
                onPressed: () => PortalAdminModals.showCreateEventModal(context, user),
              )
            : null,
        );
      },
    );
  }
}

class _EventCard extends StatelessWidget {
  final PortalEvent event;
  final PortalUser user;
  final PortalService portalService;

  const _EventCard({
    required this.event,
    required this.user,
    required this.portalService,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                // Minimalist Date Block
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(DateFormat('MMM').format(event.date).toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                      Text(DateFormat('dd').format(event.date), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                
                // Event Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(DateFormat('HH:mm').format(event.date), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(width: 12),
                          const Icon(Icons.location_on, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(child: Text(event.location, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Admin Actions Popup
                if (!event.isMatch && (user.role == 'admin' || user.role == 'president'))
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    onSelected: (val) async {
                      if (val == 'edit') {
                        PortalAdminModals.showEditEventModal(context, event);
                      } else if (val == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Excluir Evento'),
                            content: const Text('Certeza que deseja excluir?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirm == true) await portalService.deleteEvent(event.id);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'edit', child: Text('Editar Evento')),
                      const PopupMenuItem(value: 'delete', child: Text('Excluir', style: TextStyle(color: Colors.red))),
                    ],
                  ),
              ],
            ),
            
            // Attendance Controls
            if (!event.isMatch) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              StreamBuilder<List<PortalAttendance>>(
                stream: portalService.streamAttendanceForEvent(event.id),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  
                  final myAttendance = snapshot.data!.where((a) => a.userId == user.id).firstOrNull;
                  final status = myAttendance?.status ?? 'pending';

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            status == 'confirmed' ? Icons.check_circle : (status == 'absent' ? Icons.cancel : Icons.help_outline),
                            size: 16,
                            color: status == 'confirmed' ? Colors.green : (status == 'absent' ? Colors.red : Colors.grey),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status == 'confirmed' ? 'Você confirmou presença' : (status == 'absent' ? 'Você marcou ausência' : 'Confirme sua presença:'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: status != 'pending' ? FontWeight.bold : FontWeight.normal,
                              color: status == 'confirmed' ? Colors.green : (status == 'absent' ? Colors.red : Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      
                      if (status == 'pending')
                        Row(
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                minimumSize: const Size(0, 30),
                                foregroundColor: Colors.red,
                              ),
                              onPressed: () => portalService.updateAttendance(event.id, user.id, 'absent'),
                              child: const Text('NÃO IREI', style: TextStyle(fontSize: 12)),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                minimumSize: const Size(0, 30),
                                backgroundColor: Colors.green,
                              ),
                              onPressed: () => portalService.updateAttendance(event.id, user.id, 'confirmed'),
                              child: const Text('IREI', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        )
                      else
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                          onPressed: () => portalService.updateAttendance(event.id, user.id, 'pending'),
                        ),
                    ],
                  );
                },
              ),
              
              if (user.role == 'admin' || user.role == 'staff') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PortalEventAttendanceScreen(event: event)),
                      );
                    },
                    icon: const Icon(Icons.checklist, size: 16),
                    label: const Text('Lista de Chamada', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      side: const BorderSide(color: Colors.indigo),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ]
            ],
          ],
        ),
      ),
    );
  }
}
