import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/portal_models.dart';
import '../../services/portal_service.dart';
import '../../services/portal_auth_service.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

class PortalFinancialTab extends StatelessWidget {
  const PortalFinancialTab({super.key});

  @override
  Widget build(BuildContext context) {
    final portalService = Provider.of<PortalService>(context, listen: false);
    final authService = Provider.of<PortalAuthService>(context, listen: false);
    final user = authService.currentPortalUser;

    if (user == null) return const Center(child: Text("Usuário não encontrado."));

    return StreamBuilder<List<PortalFinancialDue>>(
      stream: portalService.streamMyDues(user.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        }
        
        final dues = snapshot.data ?? [];
        
        // Sort ascending in memory to avoid needing another index
        dues.sort((a, b) => a.dueDate.compareTo(b.dueDate));

        final pendingDues = dues.where((d) => d.status != 'paid').toList();
        final paidDues = dues.where((d) => d.status == 'paid').toList();

        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        
        final overdueDues = pendingDues.where((d) => d.dueDate.isBefore(startOfToday) && d.status != 'under_review').toList();
        final bool isApto = overdueDues.isEmpty;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isApto ? Colors.green.shade100 : Colors.red.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isApto ? Colors.green : Colors.red, width: 2),
              ),
              child: Row(
                children: [
                  Icon(isApto ? Icons.check_circle : Icons.warning, color: isApto ? Colors.green : Colors.red, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isApto ? 'APTO PARA JOGAR' : 'INAPTO PARA JOGAR',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isApto ? Colors.green.shade800 : Colors.red.shade800),
                        ),
                        if (!isApto)
                          Text('Você possui pendências financeiras.', style: TextStyle(color: Colors.red.shade900)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (dues.isEmpty)
              const Center(
                child: Text("Nenhum lançamento financeiro.", style: TextStyle(fontSize: 16, color: Colors.grey)),
              ),

            if (pendingDues.isNotEmpty) ...[
              const Text("Pendências", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...pendingDues.map((due) => _DueCard(due: due, isPending: true)),
              const SizedBox(height: 24),
            ],
            
            if (paidDues.isNotEmpty) ...[
              const Text("Histórico de Pagamentos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...paidDues.map((due) => _DueCard(due: due, isPending: false)),
            ]
          ],
        );
      },
    );
  }
}

class _DueCard extends StatefulWidget {
  final PortalFinancialDue due;
  final bool isPending;

  const _DueCard({required this.due, required this.isPending});

  @override
  State<_DueCard> createState() => _DueCardState();
}

class _DueCardState extends State<_DueCard> {
  bool _isLoadingPix = false;
  String? _pixCode;

  Future<void> _generatePix(BuildContext context) async {
    setState(() => _isLoadingPix = true);
    try {
      final portalService = Provider.of<PortalService>(context, listen: false);
      final authService = Provider.of<PortalAuthService>(context, listen: false);
      
      final result = await portalService.generatePixForDue(
        widget.due.id, 
        authService.currentPortalUser!.username
      );
      
      setState(() {
        _pixCode = result['pix_code'];
        _isLoadingPix = false;
      });
      
      if (mounted) _showPixModal(context);
      
    } catch (e) {
      setState(() => _isLoadingPix = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final due = widget.due;
    final isPending = widget.isPending;

    final dateFormat = DateFormat('dd/MM/yyyy');
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    final bool isOverdue = isPending && due.dueDate.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isPending ? (isOverdue ? Colors.red : Colors.orange) : Colors.green,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    due.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Text(
                  currencyFormat.format(due.amount),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  due.status == 'under_review' 
                    ? Icons.hourglass_empty 
                    : (isPending ? Icons.warning_amber_rounded : Icons.check_circle),
                  color: due.status == 'under_review' 
                    ? Colors.blue 
                    : (isPending ? (isOverdue ? Colors.red : Colors.orange) : Colors.green),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  due.status == 'under_review'
                    ? 'Em Análise'
                    : (isPending 
                      ? (isOverdue ? "Vencido em ${dateFormat.format(due.dueDate)}" : "Vence em ${dateFormat.format(due.dueDate)}")
                      : "Pago em ${due.paymentDate != null ? dateFormat.format(due.paymentDate!) : '-'}"),
                  style: TextStyle(
                    color: due.status == 'under_review'
                      ? Colors.blue
                      : (isPending ? (isOverdue ? Colors.red : Colors.orange[800]) : Colors.green),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (isPending && due.status != 'under_review') ...[
              const Divider(height: 24),
              SizedBox(
                width: double.infinity,
                child: _isLoadingPix 
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.pix),
                      label: const Text('PAGAR COM PIX'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _pixCode != null ? _showPixModal(context) : _generatePix(context),
                    ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('JÁ PAGUEI (OUTRO MEIO)'),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Confirmar Pagamento'),
                        content: const Text('Tem certeza que deseja marcar este débito como pago? Ele será enviado para análise da administração.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        final portalService = Provider.of<PortalService>(context, listen: false);
                        await portalService.updateDue(due.id, {'status': 'under_review'});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enviado para análise!'), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                      }
                    }
                  },
                ),
              )
            ]
          ],
        ),
      ),
    );
  }

  void _showPixModal(BuildContext context) {
    final due = widget.due;
    final pixPayload = _pixCode ?? '';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pix, size: 40, color: Colors.teal),
            const SizedBox(height: 16),
            Text('Pagar ${due.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'O pagamento via Pix possui baixa automática. O sistema confirmará em até 2 minutos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[200],
              child: const Icon(Icons.qr_code_2, size: 150), 
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('COPIAR CÓDIGO PIX'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pixPayload));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Código Pix copiado!'), backgroundColor: Colors.teal),
                );
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
