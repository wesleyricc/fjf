import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/portal_models.dart';
import '../../services/portal_service.dart';

class PortalEventAttendanceScreen extends StatelessWidget {
  final PortalEvent event;

  const PortalEventAttendanceScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);

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
              
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: eventUsers.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (ctx, i) {
                  final user = eventUsers[i];
                  final attendance = allAttendance.where((a) => a.userId == user.id).firstOrNull;
                  final status = attendance?.status ?? 'pending';

                  Color statusColor = Colors.grey;
                  if (status == 'confirmed') statusColor = Colors.green;
                  if (status == 'absent') statusColor = Colors.red;

                  return ListTile(
                    title: Text(user.name),
                    subtitle: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () => portalService.updateAttendance(event.id, user.id, 'confirmed'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () => portalService.updateAttendance(event.id, user.id, 'absent'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
