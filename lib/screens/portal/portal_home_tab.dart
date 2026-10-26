import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/portal_auth_service.dart';
import '../../services/portal_service.dart';
import '../../models/portal_models.dart';
import '../../models/player_model.dart';
import '../../theme/app_theme.dart';
import '../../services/championship_service.dart';
import 'portal_substitution_tab.dart';

class PortalHomeTab extends StatelessWidget {
  final Function(int index) onNavigate;

  const PortalHomeTab({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<PortalAuthService>(context);
    final champService = Provider.of<ChampionshipService>(context, listen: false);
    final user = authService.currentPortalUser;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isAdmin = user.role == 'admin' || user.role == 'president' || user.role == 'staff';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPlayerHeader(context, user, champService.currentSeasonId),
          const SizedBox(height: 24),
          const Text(
            'Painel de Controle',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
          ),
          const SizedBox(height: 12),
          _buildUnifiedDashboardCard(context, user),

          if (isAdmin) ...[
            const SizedBox(height: 24),
            const Text(
              'Acesso Rápido (Comissão Técnica / Diretoria)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.shade100, shape: BoxShape.circle),
                  child: const Icon(Icons.timer, color: Colors.green),
                ),
                title: const Text('Controle de Substituições', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Regra dos 5 minutos contínuos obrigatórios.'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          flexibleSpace: Container(
                            decoration: const BoxDecoration(
                              image: AppTheme.headerImage,
                            ),
                          ),
                          title: const Text(
                            'Controle de Substituições (5 Min)',
                            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          iconTheme: const IconThemeData(color: Colors.white),
                        ),
                        body: PortalSubstitutionTab(
                          teamId: user.teamId,
                          isPresident: user.role == 'president' || user.role == 'staff',
                          isAdmin: user.role == 'admin',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.shade100, shape: BoxShape.circle),
                  child: const Icon(Icons.transfer_within_a_station, color: Colors.blue),
                ),
                title: const Text('Mercado de Atletas', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Veja jogadores livres para contratação.'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.of(context).pushNamed('/free-agents-market'),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildPlayerHeader(BuildContext context, PortalUser user, String seasonId) {
    if (user.playerId == null || user.playerId!.isEmpty) {
      return _buildFallbackHeader(user);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('player_stats').doc(user.playerId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final playerDoc = snapshot.data!;
        if (!playerDoc.exists) return _buildFallbackHeader(user);
        
        final player = Player.fromFirestore(playerDoc);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: AppTheme.primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white,
                    backgroundImage: player.photoUrl.isNotEmpty ? ResizeImage(NetworkImage(player.photoUrl), width: 150, height: 150) : null,
                    child: player.photoUrl.isEmpty ? const Icon(Icons.person, size: 36, color: Colors.grey) : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.name,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (player.teamShieldUrl.isNotEmpty) ...[
                              Image.network(player.teamShieldUrl, width: 20, height: 20, errorBuilder: (context, error, stackTrace) => const Icon(Icons.shield, size: 20, color: Colors.white)),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                player.teamName.isNotEmpty ? player.teamName : 'Sem Clube',
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          player.position ?? 'Posição Indefinida',
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    tooltip: 'Editar Biometria',
                    onPressed: () => _showEditBiometricsModal(context, seasonId, player),
                  )
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn('Peso', player.weightKg != null ? '${player.weightKg} kg' : '--'),
                  _buildStatColumn('Altura', player.heightCm != null ? '${player.heightCm} cm' : '--'),
                  _buildStatColumn('Pé', player.preferredFoot ?? '--'),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
      ],
    );
  }

  Widget _buildFallbackHeader(PortalUser user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 30, child: Icon(Icons.person, size: 30)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(user.username, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }

  void _showEditBiometricsModal(BuildContext context, String seasonId, Player player) {
    final heightCtrl = TextEditingController(text: player.heightCm?.toString() ?? '');
    final weightCtrl = TextEditingController(text: player.weightKg?.toString() ?? '');
    String? preferredFoot = player.preferredFoot;
    final List<String> footOptions = ['Destro', 'Canhoto', 'Ambidestro'];
    
    // Garantir que a opção existe na lista, se não, resetar
    if (preferredFoot != null && !footOptions.contains(preferredFoot)) {
      preferredFoot = null;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Editar Dados Físicos'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Peso (kg)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: heightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Altura (cm)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: preferredFoot,
                    decoration: const InputDecoration(labelText: 'Pé Preferido', border: OutlineInputBorder()),
                    items: footOptions.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (val) => setState(() => preferredFoot = val),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                FilledButton(
                  onPressed: () async {
                    final w = int.tryParse(weightCtrl.text);
                    final h = int.tryParse(heightCtrl.text);
                    await FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('player_stats').doc(player.id).update({
                      if (w != null) 'weight_kg': w,
                      if (h != null) 'height_cm': h,
                      if (preferredFoot != null) 'preferred_foot': preferredFoot,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Salvar'),
                )
              ],
            );
          }
        );
      }
    );
  }

  Widget _buildUnifiedDashboardCard(BuildContext context, PortalUser user) {
    final portalService = Provider.of<PortalService>(context, listen: false);
    final champService = Provider.of<ChampionshipService>(context, listen: true);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          // Seção Agenda
          Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<List<PortalEvent>>(
              stream: portalService.streamUpcomingEvents(teamId: user.teamId, userRole: user.role),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
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
                      id: m.id, title: 'Jogo: ${m.homeTeamName} x ${m.awayTeamName}',
                      date: m.datetime!, location: m.location,
                      description: 'Rodada ${m.round} - ${m.phase}', teamId: user.teamId,
                      targetRole: 'all', isMatch: true,
                    ));
                  }
                }
                
                events.sort((a, b) => a.date.compareTo(b.date));
                final nextEvent = events.isNotEmpty ? events.first : null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.calendar_month, color: AppTheme.secondaryColor, size: 20),
                            SizedBox(width: 8),
                            Text('Próximo Compromisso', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        InkWell(
                          onTap: () => onNavigate(1), // Aba Agenda (era 2)
                          child: const Text('Ver Agenda', style: TextStyle(color: AppTheme.primaryColor, fontSize: 13, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (nextEvent == null)
                      const Text('Nenhum evento agendado.', style: TextStyle(color: Colors.grey))
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                              child: Column(
                                children: [
                                  Text(DateFormat('MMM').format(nextEvent.date).toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                                  Text(DateFormat('dd').format(nextEvent.date), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(nextEvent.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time, size: 12, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(DateFormat('HH:mm').format(nextEvent.date), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.location_on, size: 12, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text(nextEvent.location, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    ],
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                      )
                  ],
                );
              }
            ),
          ),
          
          Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          
          // Seção Financeiro
          Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<List<PortalFinancialDue>>(
              stream: portalService.streamMyDues(user.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final dues = snapshot.data ?? [];
                final now = DateTime.now();
                final startOfToday = DateTime(now.year, now.month, now.day);
                
                final pendingDues = dues.where((d) => d.status != 'paid').toList();
                final overdueDues = pendingDues.where((d) => d.dueDate.isBefore(startOfToday) && d.status != 'under_review').toList();
                
                final bool isApto = overdueDues.isEmpty;

                return InkWell(
                  onTap: () => onNavigate(2), // Aba Financeiro (era 3)
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: isApto ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                            child: Icon(Icons.account_balance_wallet, color: isApto ? Colors.green : Colors.red, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Situação Financeira', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text(isApto ? 'Em dia' : '${pendingDues.length} pendências', style: TextStyle(color: isApto ? Colors.green : Colors.red, fontSize: 13)),
                            ],
                          )
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: isApto ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(12)),
                        child: Text(isApto ? 'APTO' : 'INAPTO', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                );
              }
            ),
          )
        ],
      ),
    );
  }
}
