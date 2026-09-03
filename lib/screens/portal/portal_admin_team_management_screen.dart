import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/portal_models.dart';
import '../../models/team_model.dart';
import '../../services/portal_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/team_logo_widget.dart';
import 'portal_admin_modals.dart';

class PortalAdminTeamManagementScreen extends StatelessWidget {
  final Team team;

  const PortalAdminTeamManagementScreen({
    super.key,
    required this.team,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              TeamLogoWidget(logoUrl: team.shieldUrl, radius: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Gestão: ${team.name}', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Visão Geral'),
              Tab(text: 'Membros'),
              Tab(text: 'Débitos'),
            ],
          ),
        ),
        body: _TeamManagementBody(team: team),
      ),
    );
  }
}

class _TeamManagementBody extends StatelessWidget {
  final Team team;
  const _TeamManagementBody({required this.team});

  @override
  Widget build(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);

    return StreamBuilder<List<PortalUser>>(
      stream: portalService.streamAllUsers(),
      builder: (context, userSnapshot) {
        return StreamBuilder<List<PortalFinancialDue>>(
          stream: portalService.streamAllDues(),
          builder: (context, dueSnapshot) {
            if (userSnapshot.hasError || dueSnapshot.hasError) {
              return const Center(child: Text('Erro ao carregar dados da equipe.', style: TextStyle(color: Colors.red)));
            }
            if (!userSnapshot.hasData || !dueSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allUsers = userSnapshot.data!;
            final teamUsers = allUsers.where((u) => u.teamId == team.id).toList();

            final allDues = dueSnapshot.data!;
            final teamDues = allDues.where((d) {
              if (d.teamId == team.id) return true;
              return teamUsers.any((u) => u.id == d.userId);
            }).toList();

            return TabBarView(
              children: [
                _buildOverviewTab(context, teamUsers, teamDues),
                _buildMembersTab(context, teamUsers),
                _buildFinancialTab(context, teamUsers, teamDues),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOverviewTab(BuildContext context, List<PortalUser> users, List<PortalFinancialDue> dues) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final pending = dues.where((d) => d.status != 'paid' && !d.dueDate.isBefore(startOfToday)).toList();
    final overdue = dues.where((d) => d.status != 'paid' && d.dueDate.isBefore(startOfToday)).toList();
    final paid = dues.where((d) => d.status == 'paid').toList();

    double totalPending = pending.fold(0, (sum, item) => sum + item.amount);
    double totalOverdue = overdue.fold(0, (sum, item) => sum + item.amount);
    double totalPaid = paid.fold(0, (sum, item) => sum + item.amount);

    double delinquencyRate = (totalOverdue + totalPaid) > 0 ? (totalOverdue / (totalOverdue + totalPaid)) * 100 : 0;

    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resumo Financeiro e Administrativo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _DashboardCard(title: 'Membros', value: users.length.toString(), icon: Icons.people, color: Colors.blue)),
              const SizedBox(width: 16),
              Expanded(child: _DashboardCard(title: 'Pago', value: currency.format(totalPaid), icon: Icons.check_circle, color: Colors.green)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _DashboardCard(title: 'A Receber', value: currency.format(totalPending), icon: Icons.schedule, color: Colors.orange)),
              const SizedBox(width: 16),
              Expanded(child: _DashboardCard(title: 'Atrasado', value: currency.format(totalOverdue), icon: Icons.warning_amber, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _DashboardCard(title: 'Taxa Inadimplência', value: '${delinquencyRate.toStringAsFixed(1)}%', icon: Icons.pie_chart, color: Colors.purple)),
              const SizedBox(width: 16),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTab(BuildContext context, List<PortalUser> users) {
    if (users.isEmpty) {
      return const Center(child: Text('Nenhum membro vinculado a esta equipe.'));
    }

    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (ctx, i) {
        final u = users[i];
        return ListTile(
          leading: CircleAvatar(child: Text(u.name.substring(0, 1).toUpperCase())),
          title: Text(u.name),
          subtitle: Text('@${u.username} • Papel: ${u.role}'),
          trailing: IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue),
            onPressed: () => PortalAdminModals.showEditUserModal(context, u),
          ),
        );
      },
    );
  }

  Widget _buildFinancialTab(BuildContext context, List<PortalUser> users, List<PortalFinancialDue> dues) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    // Sort: overdue first, then pending by date, then paid by date desc
    final sortedDues = List<PortalFinancialDue>.from(dues)..sort((a, b) {
      if (a.status == 'paid' && b.status != 'paid') return 1;
      if (b.status == 'paid' && a.status != 'paid') return -1;
      
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      
      bool aOverdue = a.status != 'paid' && a.dueDate.isBefore(startOfToday);
      bool bOverdue = b.status != 'paid' && b.dueDate.isBefore(startOfToday);
      
      if (aOverdue && !bOverdue) return -1;
      if (bOverdue && !aOverdue) return 1;
      
      if (a.status == 'paid' && b.status == 'paid') {
        return (b.paymentDate ?? b.dueDate).compareTo(a.paymentDate ?? a.dueDate);
      }
      return a.dueDate.compareTo(b.dueDate);
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Novo Débito (Para a Equipe)'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () {
                    PortalAdminModals.showCreateDueModal(context, lockedTeamId: team.id);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: sortedDues.isEmpty
              ? const Center(child: Text('Nenhum débito encontrado.'))
              : ListView.builder(
                  itemCount: sortedDues.length,
                  itemBuilder: (ctx, i) {
                    final d = sortedDues[i];
                    Color statusColor = Colors.grey;
                    IconData statusIcon = Icons.help;
                    String statusText = 'Pendente';

                    final now = DateTime.now();
                    final startOfToday = DateTime(now.year, now.month, now.day);

                    if (d.status == 'paid') {
                      statusColor = Colors.green;
                      statusIcon = Icons.check_circle;
                      statusText = 'Pago';
                    } else if (d.dueDate.isBefore(startOfToday)) {
                      statusColor = Colors.red;
                      statusIcon = Icons.warning;
                      statusText = 'Atrasado';
                    } else {
                      statusColor = Colors.blue;
                      statusIcon = Icons.schedule;
                      statusText = 'No Prazo';
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: Icon(statusIcon, color: statusColor, size: 30),
                        title: Text('${d.title} (${currency.format(d.amount)})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'Membro: ${d.userName ?? "Time"}\n'
                          'Vencimento: ${DateFormat('dd/MM/yyyy').format(d.dueDate)}\n'
                          'Status: $statusText',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (d.status != 'paid')
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                tooltip: 'Marcar como Pago',
                                onPressed: () {
                                  Provider.of<PortalService>(context, listen: false).updateDue(d.id, {
                                    'status': 'paid',
                                    'payment_date': DateTime.now(),
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Débito pago com sucesso!')));
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Excluir Débito',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Excluir Débito'),
                                    content: const Text('Tem certeza que deseja apagar este débito?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Excluir', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await Provider.of<PortalService>(context, listen: false).deleteDue(d.id);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Débito removido.')));
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
          ),
        ],
      ),
    );
  }
}
