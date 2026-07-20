import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import '../../viewmodels/mini_bolao_home_viewmodel.dart';

class MiniBolaoPixDialog extends StatefulWidget {
  final String pixCode; final String paymentId; final String title; final double fee; final String userId;
  const MiniBolaoPixDialog({required this.pixCode, required this.paymentId, required this.title, required this.fee, required this.userId});
  @override State<MiniBolaoPixDialog> createState() => MiniBolaoPixDialogState();
}

class MiniBolaoPixDialogState extends State<MiniBolaoPixDialog> {
  final MiniBolaoHomeViewModel _viewModel = MiniBolaoHomeViewModel();
  bool _isChecking = false; late StreamSubscription _orderSub;

  @override void initState() { super.initState(); _listenToPayment(); }
  @override void dispose() { _orderSub.cancel(); super.dispose(); }

  void _listenToPayment() {
    _orderSub = _viewModel.streamPaymentOrder(widget.paymentId).listen((snap) {
      if (snap.exists && (snap.data() as Map)['status'] == 'approved') _handleSuccess();
    });
  }

  void _handleSuccess() {
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pagamento aprovado! Você entrou no Mini Bolão."), backgroundColor: Colors.green));
  }

  Future<void> _checkManualStatus() async {
    setState(() => _isChecking = true);
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('checkPixStatus').call({'txid': widget.paymentId, 'userId': widget.userId, 'type': 'mini_bolao'});
      if ((res.data as Map)['is_paid'] == true) _handleSuccess();
      else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Aguardando pagamento..."), backgroundColor: Colors.orange));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e")));
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [Icon(Icons.qr_code_2, color: Colors.orange), SizedBox(width: 8), Text("PIX Copia e Cola")]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Entrada: ${widget.title}", style: const TextStyle(fontWeight: FontWeight.bold)),
          Text("Valor: R\$ ${widget.fee.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)), child: SelectableText(widget.pixCode, style: const TextStyle(fontSize: 10, color: Colors.black54), textAlign: TextAlign.center)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900, foregroundColor: Colors.white), icon: const Icon(Icons.copy), label: const Text("COPIAR CÓDIGO PIX"), onPressed: () { Clipboard.setData(ClipboardData(text: widget.pixCode)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código copiado! Cole no seu banco."), backgroundColor: Colors.green)); })),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade900), icon: _isChecking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh), label: Text(_isChecking ? "Verificando..." : "JÁ PAGUEI (VERIFICAR)"), onPressed: _isChecking ? null : _checkManualStatus)),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fechar", style: TextStyle(color: Colors.grey)))],
    );
  }
}

