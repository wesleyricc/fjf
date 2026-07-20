import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/portal_models.dart';
import '../../services/portal_service.dart';
import '../../services/portal_auth_service.dart';
import 'package:intl/intl.dart';
import 'portal_admin_modals.dart';
import 'portal_event_attendance_screen.dart';
import '../../theme/app_theme.dart';

class PortalAgendaTab extends StatelessWidget {
  const PortalAgendaTab({super.key});

  @override
  Widget build(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);
    final authService = Provider.of<PortalAuthService>(context, listen: false);
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

        final events = snapshot.data ?? [];
        
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
    final dateFormat = DateFormat('dd/MM/yyyy • HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event, color: Colors.black87),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (user.role == 'admin' || user.role == 'president') ...[
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => PortalAdminModals.showEditEventModal(context, event),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Excluir Evento'),
                          content: const Text('Tem certeza que deseja excluir este evento?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await portalService.deleteEvent(event.id);
                      }
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(event.description, style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(dateFormat.format(event.date), style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(event.location, style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const Divider(height: 24),
            
            // Controle de presença
            StreamBuilder<List<PortalAttendance>>(
              stream: portalService.streamAttendanceForEvent(event.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox(height: 40);
                
                final allAttendance = snapshot.data!;
                final myAttendance = allAttendance.where((a) => a.userId == user.id).firstOrNull;
                
                final String status = myAttendance?.status ?? 'pending';

                return Row(
                  children: [
                    const Text('Sua presença:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (status == 'pending') ...[
                      OutlinedButton(
                        onPressed: () => portalService.updateAttendance(event.id, user.id, 'absent'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('NÃO IREI'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => portalService.updateAttendance(event.id, user.id, 'confirmed'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: const Text('CONFIRMAR'),
                      ),
                    ] else if (status == 'confirmed') ...[
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 4),
                      const Text('Confirmado', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => portalService.updateAttendance(event.id, user.id, 'pending'),
                      )
                    ] else if (status == 'absent') ...[
                      const Icon(Icons.cancel, color: Colors.red),
                      const SizedBox(width: 4),
                      const Text('Ausente', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => portalService.updateAttendance(event.id, user.id, 'pending'),
                      )
                    ] else ...[
                      const Icon(Icons.info, color: Colors.orange),
                      const SizedBox(width: 4),
                      const Text('Justificado', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    ]
                  ],
                );
              },
            ),

            if (user.role == 'admin' || user.role == 'staff') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PortalEventAttendanceScreen(event: event)),
                    );
                  },
                  icon: const Icon(Icons.checklist),
                  label: const Text('LISTA DE CHAMADA'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
