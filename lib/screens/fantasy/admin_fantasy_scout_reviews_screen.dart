import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/fantasy_scout_appeal_model.dart';
import '../../services/championship_service.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/fantasy_scout_appeal_service.dart';
import 'admin_fantasy_scout_audit_screen.dart';

class AdminFantasyScoutReviewsScreen extends StatefulWidget {
  const AdminFantasyScoutReviewsScreen({super.key});

  @override
  State<AdminFantasyScoutReviewsScreen> createState() =>
      _AdminFantasyScoutReviewsScreenState();
}

class _AdminFantasyScoutReviewsScreenState
    extends State<AdminFantasyScoutReviewsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FantasyScoutAppealService _appealService = FantasyScoutAppealService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final champService = Provider.of<ChampionshipService>(context);
    final seasonId = champService.currentSeasonId;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Avaliação de Contestações de Scout"),
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check),
            tooltip: "Central de Auditoria de Scouts",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminFantasyScoutAuditScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.amber,
          tabs: [
            Tab(
              child: StreamBuilder<int>(
                stream: _appealService.streamPendingCount(seasonId: seasonId),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Row(
                    children: [
                      const Text("Pendentes"),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "$count",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            const Tab(text: "Aprovadas"),
            const Tab(text: "Recusadas"),
            const Tab(text: "Todas"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAppealsList(seasonId, 'pending'),
          _buildAppealsList(seasonId, 'approved'),
          _buildAppealsList(seasonId, 'rejected'),
          _buildAppealsList(seasonId, null),
        ],
      ),
    );
  }

  Widget _buildAppealsList(String seasonId, String? statusFilter) {
    return StreamBuilder<List<FantasyScoutAppeal>>(
      stream: _appealService.streamAllAppeals(
          seasonId: seasonId, statusFilter: statusFilter),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text("Erro ao carregar: ${snapshot.error}"));
        }

        final appeals = snapshot.data ?? [];

        if (appeals.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    statusFilter == 'pending'
                        ? "Nenhuma contestação pendente de análise!"
                        : "Nenhuma solicitação encontrada.",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: appeals.length,
          itemBuilder: (context, index) {
            final appeal = appeals[index];
            return _buildAdminAppealCard(appeal);
          },
        );
      },
    );
  }

  Widget _buildAdminAppealCard(FantasyScoutAppeal appeal) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: appeal.statusColor.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status + Solicitante
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: appeal.statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: appeal.statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(appeal.statusIcon,
                          size: 14, color: appeal.statusColor),
                      const SizedBox(width: 5),
                      Text(
                        appeal.statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: appeal.statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  dateFormat.format(appeal.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Usuário / Time
            Row(
              children: [
                const Icon(Icons.account_circle, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "${appeal.userName} (${appeal.userTeamName})",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Jogo, Rodada e Tempo
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sports_soccer,
                          size: 15, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "${appeal.matchLabel} • Rodada ${appeal.round}",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 15, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        "${appeal.period} • Minuto: ${appeal.minute}",
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 15, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        "Atleta: ${appeal.playerName} (${appeal.playerTeamName})",
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.fact_check,
                          size: 15, color: Colors.deepPurple),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "${appeal.actionType}: ${appeal.scoutType}",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Descrição do Lance
            const Text(
              "Descrição pelo Cartoleiro:",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              appeal.description,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade900, height: 1.3),
            ),

            // Link do Vídeo
            if (appeal.videoUrl != null && appeal.videoUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(appeal.videoUrl!);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_circle_fill,
                          size: 16, color: Colors.red),
                      const SizedBox(width: 6),
                      const Text(
                        "Assistir ao Vídeo Informado",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Parecer Anterior (Se já respondido)
            if (appeal.adminFeedback != null &&
                appeal.adminFeedback!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: appeal.status == 'approved'
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: appeal.status == 'approved'
                          ? Colors.green.shade300
                          : Colors.red.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Parecer atual: ${appeal.adminFeedback}",
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (appeal.reviewedAt != null)
                      Text(
                        "Respondido em ${dateFormat.format(appeal.reviewedAt!)} por ${appeal.reviewedBy ?? 'Admin'}",
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade600),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            const Divider(),

            // Botões de Ação para o Admin
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminFantasyScoutAuditScreen()),
                    );
                  },
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text("Auditar Súmula",
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blueGrey,
                    side: BorderSide(color: Colors.blueGrey.shade300),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openReviewDialog(appeal, 'rejected'),
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                  label: const Text("Recusar",
                      style: TextStyle(fontSize: 12, color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _openReviewDialog(appeal, 'approved'),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text("Aprovar Lance",
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openReviewDialog(FantasyScoutAppeal appeal, String targetStatus) {
    final bool isApproval = targetStatus == 'approved';
    final feedbackController = TextEditingController(
      text: isApproval
          ? "Lance verificado na gravação/súmula. O scout de ${appeal.scoutType} foi devidamente validado e atualizado."
          : "Lance revisado pela comissão de arbitragem/scouts: a marcação da súmula foi mantida.",
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isApproval ? Icons.check_circle : Icons.cancel,
              color: isApproval ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(isApproval
                ? "Aprovar Contestação"
                : "Recusar Contestação"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Lance: ${appeal.playerName} (${appeal.matchLabel})\n"
              "Scout: ${appeal.scoutType} (${appeal.minute})",
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              "Justificativa / Parecer que será exibido ao usuário:",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: feedbackController,
              maxLines: 3,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isApproval ? Colors.green.shade700 : Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final auth =
                  Provider.of<FantasyAuthService>(context, listen: false);
              final adminName =
                  auth.user?.displayName ?? auth.user?.email ?? 'Comissão FJF';

              await _appealService.reviewAppeal(
                appealId: appeal.id,
                status: targetStatus,
                adminFeedback: feedbackController.text.trim(),
                reviewedBy: adminName,
              );

              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isApproval
                        ? "Contestação aprovada com sucesso!"
                        : "Contestação recusada."),
                    backgroundColor:
                        isApproval ? Colors.green : Colors.orange,
                  ),
                );
              }
            },
            child: const Text("Confirmar Parecer"),
          ),
        ],
      ),
    );
  }
}
