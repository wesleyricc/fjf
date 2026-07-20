import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/portal_auth_service.dart';
import '../../services/portal_service.dart';
import '../../models/portal_models.dart';
import '../../theme/app_theme.dart';

class PortalHomeTab extends StatelessWidget {
  final Function(int index) onNavigate;

  const PortalHomeTab({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<PortalAuthService>(context);
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
          Text(
            'Olá, ${user.name.split(' ').first} 👋',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aqui está o resumo da sua situação no clube.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          
          _buildFinancialSummaryCard(context, user),
          const SizedBox(height: 16),
          
          _buildAgendaSummaryCard(context, user),
          const SizedBox(height: 16),
          
          _buildProfileSummaryCard(context, user),

          if (isAdmin) ...[
            const SizedBox(height: 24),
            const Text(
              'Acesso Rápido (Diretoria)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _buildProfileSummaryCard(BuildContext context, PortalUser user) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primaryColor,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(user.username, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => onNavigate(1), // Aba Perfil
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: const BorderSide(color: AppTheme.primaryColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Ver Perfil Completo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgendaSummaryCard(BuildContext context, PortalUser user) {
    final portalService = Provider.of<PortalService>(context, listen: false);

    return StreamBuilder<List<PortalEvent>>(
      stream: portalService.streamUpcomingEvents(teamId: user.teamId, userRole: user.role),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
        }

        final events = snapshot.data ?? [];
        final nextEvent = events.isNotEmpty ? events.first : null;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.calendar_month, color: AppTheme.secondaryColor),
                        SizedBox(width: 8),
                        Text('Próximo Evento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    if (nextEvent != null)
                      TextButton(
                        onPressed: () => onNavigate(2), // Aba Agenda
                        child: const Text('Ver Agenda'),
                      )
                  ],
                ),
                const SizedBox(height: 8),
                if (nextEvent == null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Sua agenda está livre! Não há próximos eventos marcados.', style: TextStyle(color: Colors.grey)),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nextEvent.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(DateFormat('dd/MM/yyyy HH:mm').format(nextEvent.date), style: const TextStyle(color: Colors.black87, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(child: Text(nextEvent.location, style: const TextStyle(color: Colors.black87, fontSize: 13), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (nextEvent == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: TextButton(onPressed: () => onNavigate(2), child: const Text('Abrir Agenda Completa')),
                    ),
                  )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFinancialSummaryCard(BuildContext context, PortalUser user) {
    final portalService = Provider.of<PortalService>(context, listen: false);

    return StreamBuilder<List<PortalFinancialDue>>(
      stream: portalService.streamMyDues(user.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
        }

        final dues = snapshot.data ?? [];
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        
        final pendingDues = dues.where((d) => d.status != 'paid').toList();
        final overdueDues = pendingDues.where((d) => d.dueDate.isBefore(startOfToday) && d.status != 'under_review').toList();
        
        final bool isApto = overdueDues.isEmpty;
        final int openCount = pendingDues.length;

        return InkWell(
          onTap: () => onNavigate(3), // Aba Financeiro
          borderRadius: BorderRadius.circular(12),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isApto ? Colors.green : Colors.red, width: 1.5)
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: isApto 
                    ? [Colors.green.shade50, Colors.white] 
                    : [Colors.red.shade50, Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.account_balance_wallet, color: Colors.black87),
                          SizedBox(width: 8),
                          Text('Situação Financeira', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      Icon(isApto ? Icons.check_circle : Icons.warning, color: isApto ? Colors.green : Colors.red),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isApto ? 'APTO PARA JOGAR' : 'INAPTO PARA JOGAR',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isApto ? Colors.green.shade800 : Colors.red.shade800),
                  ),
                  const SizedBox(height: 4),
                  if (!isApto)
                    Text('Você possui $openCount pendência(s) em aberto.', style: TextStyle(color: Colors.red.shade900))
                  else
                    Text(openCount > 0 ? 'Você tem $openCount cobrança(s) a vencer.' : 'Tudo em dia! Nenhuma cobrança em aberto.', style: TextStyle(color: Colors.green.shade900)),
                  
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Ver Detalhes', style: TextStyle(fontWeight: FontWeight.bold, color: isApto ? Colors.green.shade700 : Colors.red.shade700)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 14, color: isApto ? Colors.green.shade700 : Colors.red.shade700)
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
