import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/portal_models.dart';
import '../../services/portal_service.dart';
import 'package:intl/intl.dart';
import 'portal_admin_modals.dart';
import '../../theme/app_theme.dart';

class PortalAdminTab extends StatelessWidget {
  const PortalAdminTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: AppTheme.primaryColor,
            indicatorColor: AppTheme.primaryColor,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Dashboard'),
              Tab(text: 'Membros'),
              Tab(text: 'Financeiro (Geral)'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildDashboard(context),
                const _MembersTab(),
                const _FinancialTab(),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);

    return StreamBuilder<List<PortalUser>>(
      stream: portalService.streamAllUsers(),
      builder: (context, userSnapshot) {
        return StreamBuilder<List<PortalFinancialDue>>(
          stream: portalService.streamAllDues(),
          builder: (context, dueSnapshot) {
            if (userSnapshot.hasError || dueSnapshot.hasError) {
              return const Center(
                  child: Text('Erro ao carregar dados',
                      style: TextStyle(color: Colors.red)));
            }
            if (!userSnapshot.hasData || !dueSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final users = userSnapshot.data!;
            final dues = dueSnapshot.data!;

            final totalMembers = users.length;

            final now = DateTime.now();
            final startOfToday = DateTime(now.year, now.month, now.day);

            // A vencer (no prazo)
            final pending = dues
                .where((d) =>
                    d.status != 'paid' && !d.dueDate.isBefore(startOfToday))
                .toList();
            // Vencidos (atrasados)
            final overdue = dues
                .where((d) =>
                    d.status != 'paid' && d.dueDate.isBefore(startOfToday))
                .toList();
            // Pagos
            final paid = dues.where((d) => d.status == 'paid').toList();

            double totalPending =
                pending.fold(0, (sum, item) => sum + item.amount);
            double totalOverdue =
                overdue.fold(0, (sum, item) => sum + item.amount);
            double totalPaid = paid.fold(0, (sum, item) => sum + item.amount);

            // Inadimplência é o % de atrasados em relação ao total que já deveria ter sido pago (pago + atrasado)
            double delinquencyRate = (totalOverdue + totalPaid) > 0
                ? (totalOverdue / (totalOverdue + totalPaid)) * 100
                : 0;

            final currency =
                NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Visão Geral',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: _DashboardCard(
                              title: 'Membros',
                              value: totalMembers.toString(),
                              icon: Icons.people,
                              color: Colors.blue)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _DashboardCard(
                              title: 'Recebido',
                              value: currency.format(totalPaid),
                              icon: Icons.check_circle,
                              color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: _DashboardCard(
                              title: 'A Receber (No Prazo)',
                              value: currency.format(totalPending),
                              icon: Icons.schedule,
                              color: Colors.blueAccent)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _DashboardCard(
                              title: 'Atrasado',
                              value: currency.format(totalOverdue),
                              icon: Icons.warning_amber,
                              color: Colors.red)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: _DashboardCard(
                              title: 'Taxa de Inadimplência',
                              value: '${delinquencyRate.toStringAsFixed(1)}%',
                              icon: Icons.pie_chart,
                              color: Colors.orange)),
                      const SizedBox(width: 16),
                      Expanded(
                          child:
                              Container()), // empty slot to keep width balanced
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text('Mensalidades Recentes (Pagas)',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildRecentPaidDues(paid, currency),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRecentPaidDues(
      List<PortalFinancialDue> paidDues, NumberFormat currency) {
    if (paidDues.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Nenhuma mensalidade paga recente.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final sorted = List<PortalFinancialDue>.from(paidDues)
      ..sort((a, b) {
        final aDate = a.paymentDate ?? a.dueDate;
        final bDate = b.paymentDate ?? b.dueDate;
        return bDate.compareTo(aDate);
      });

    final recent = sorted.take(5).toList();

    return Column(
      children: recent.map((due) {
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text(
                '${due.title} - ${due.userName ?? due.userId.substring(0, 5)}'),
            subtitle: Text(
                'Data: ${DateFormat('dd/MM/yyyy').format(due.paymentDate ?? due.dueDate)}'),
            trailing: Text(currency.format(due.amount),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.green)),
          ),
        );
      }).toList(),
    );
  }

  // _buildMembers e _buildFinancial extraídos para StatefulWidgets
}

class _MembersTab extends StatefulWidget {
  const _MembersTab();

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);

    return StreamBuilder<List<PortalUser>>(
      stream: portalService.streamAllUsers(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
              child: Text('Erro: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red)));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final users = snapshot.data!;
        final filteredUsers = users.where((u) {
          if (_searchQuery.isEmpty) return true;
          final terms = _searchQuery.toLowerCase().trim().split(RegExp(r'\s+'));
          final nameStr = u.name.toLowerCase();
          final usernameStr = u.username.toLowerCase();
          final teamStr = (u.teamId ?? '').toLowerCase();
          
          for (var term in terms) {
            if (!(nameStr.contains(term) || usernameStr.contains(term) || teamStr.contains(term))) {
              return false;
            }
          }
          return true;
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Filtrar por nome, username ou equipe',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      PortalAdminModals.showCreateUserModal(context),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Novo Membro / Acesso'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filteredUsers.length,
                itemBuilder: (ctx, i) {
                  final u = filteredUsers[i];
                  return ListTile(
                    leading: CircleAvatar(
                        child: Text(u.name.substring(0, 1).toUpperCase())),
                    title: Text(u.name),
                    subtitle:
                        Text('@${u.username} • Time: ${u.teamId ?? "Geral"}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(label: Text(u.role.toUpperCase())),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () =>
                              PortalAdminModals.showEditUserModal(context, u),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Excluir Membro'),
                                content: const Text(
                                    'Tem certeza que deseja excluir o acesso deste membro?'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancelar')),
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Excluir',
                                          style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await portalService.deleteUser(u.id);
                            }
                          },
                        ),
                      ],
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
}

class _FinancialTab extends StatefulWidget {
  const _FinancialTab();

  @override
  State<_FinancialTab> createState() => _FinancialTabState();
}

class _FinancialTabState extends State<_FinancialTab> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);

    return StreamBuilder<List<PortalFinancialDue>>(
      stream: portalService.streamAllDues(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
              child: Text('Erro: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red)));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final allDues = snapshot.data!;

        final filteredDues = allDues.where((d) {
          if (_searchQuery.isEmpty) return true;
          final terms = _searchQuery.toLowerCase().trim().split(RegExp(r'\s+'));
          final titleStr = d.title.toLowerCase();
          final userStr = (d.userName ?? d.userId).toLowerCase();
          final teamStr = (d.teamId ?? '').toLowerCase();
          
          for (var term in terms) {
            if (!(titleStr.contains(term) || userStr.contains(term) || teamStr.contains(term))) {
              return false;
            }
          }
          return true;
        }).toList();

        final pending = filteredDues.where((d) => d.status != 'paid').toList();
        final paid = filteredDues.where((d) => d.status == 'paid').toList();

        double totalPending = pending.fold(0, (sum, item) => sum + item.amount);
        double totalPaid = paid.fold(0, (sum, item) => sum + item.amount);

        final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Filtrar por atleta, equipe ou título',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[200],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatBox('A Receber', currency.format(totalPending),
                      Colors.orange),
                  _StatBox(
                      'Recebido', currency.format(totalPaid), Colors.green),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      PortalAdminModals.showCreateDueModal(context),
                  icon: const Icon(Icons.add_card),
                  label: const Text('Lançar Débito / Cobrança'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filteredDues.length,
                itemBuilder: (ctx, i) {
                  final due = filteredDues[i];
                  final isPaid = due.status == 'paid';
                  final isUnderReview = due.status == 'under_review';
                  return ListTile(
                    leading: Icon(
                      isPaid ? Icons.check_circle : (isUnderReview ? Icons.hourglass_empty : Icons.warning_amber),
                      color: isPaid ? Colors.green : (isUnderReview ? Colors.blue : Colors.orange),
                    ),
                    title: Text(
                        '${due.title} (Atleta: ${due.userName ?? due.userId.substring(0, 5) + "..."})'),
                    subtitle: Text('Time: ${due.teamId ?? "Geral"}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(currency.format(due.amount),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () =>
                              PortalAdminModals.showEditDueModal(context, due),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Excluir Débito'),
                                content: const Text(
                                    'Tem certeza que deseja excluir este débito?'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancelar')),
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Excluir',
                                          style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await portalService.deleteDue(due.id);
                            }
                          },
                        ),
                      ],
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
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBox(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.w900)),
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12))),
              ],
            ),
            const SizedBox(height: 16),
            Text(value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}
