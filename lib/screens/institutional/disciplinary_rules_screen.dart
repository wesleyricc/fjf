import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // Para input formatters
import 'package:provider/provider.dart'; 
import '../../services/admin_service.dart';
import '../../services/championship_service.dart';

class DisciplinaryRulesScreen extends StatefulWidget {
  const DisciplinaryRulesScreen({super.key});

  @override
  State<DisciplinaryRulesScreen> createState() => _DisciplinaryRulesScreenState();
}

class _DisciplinaryRulesScreenState extends State<DisciplinaryRulesScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores
  late TextEditingController _pendingController;
  late TextEditingController _suspensionController;
  late bool _suspendOnRed;
  late bool _resetYellowsOnSuspension;
  late bool _resetYellowsOnRed;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Inicializa com os valores já carregados no AdminService (pelo ChampionshipService)
    _pendingController = TextEditingController(text: AdminService.pendingYellowCards.toString());
    _suspensionController = TextEditingController(text: AdminService.suspensionYellowCards.toString());
    _suspendOnRed = AdminService.suspensionOnRed;
    _resetYellowsOnSuspension = AdminService.resetYellowsOnSuspension;
    _resetYellowsOnRed = AdminService.resetYellowsOnRed;
  }

  @override
  void dispose() {
    _pendingController.dispose();
    _suspensionController.dispose();
    super.dispose();
  }

  // Helper para salvar no local certo (PADRONIZADO)
  DocumentReference _getSettingsDocRef(String seasonId, String docId) {
    // Agora aponta sempre para a subcoleção da temporada atual
    return FirebaseFirestore.instance
        .collection('championships')
        .doc(seasonId)
        .collection('settings')
        .doc(docId);
  }

  Future<void> _saveRules() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    
    // 1. Pega Temporada Atual
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    try {
      final int pending = int.parse(_pendingController.text);
      final int suspension = int.parse(_suspensionController.text);

      // 2. Salva no documento correto da temporada
      await _getSettingsDocRef(seasonId, 'disciplinary_rules').set({
        'pending_yellow_cards': pending,
        'suspension_yellow_cards': suspension,
        'suspension_on_red': _suspendOnRed,
        'reset_yellows_on_suspension': _resetYellowsOnSuspension,
        'reset_yellows_on_red': _resetYellowsOnRed,
      }, SetOptions(merge: true));

      // 3. Atualiza memória local (AdminService)
      // Isso garante que o app use as novas regras imediatamente sem reload
      AdminService.pendingYellowCards = pending;
      AdminService.suspensionYellowCards = suspension;
      AdminService.suspensionOnRed = _suspendOnRed;
      AdminService.resetYellowsOnSuspension = _resetYellowsOnSuspension;
      AdminService.resetYellowsOnRed = _resetYellowsOnRed;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Regras disciplinares salvas!')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Regras Disciplinares'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Defina os limites de cartões para as regras automáticas desta temporada.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _pendingController,
                decoration: const InputDecoration(
                  labelText: 'Cartões para "Pendurado"',
                  helperText: 'Ex: 2 amarelos (apenas visual)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _suspensionController,
                decoration: const InputDecoration(
                  labelText: 'Cartões para Suspensão Automática',
                  helperText: 'Ex: 3 amarelos (gera suspensão)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 20),

              SwitchListTile(
                title: const Text('Suspender ao receber Cartão Vermelho?'),
                subtitle: const Text('Gera suspensão automática de 1 jogo.'),
                value: _suspendOnRed,
                onChanged: _isSaving ? null : (bool value) => setState(() => _suspendOnRed = value),
                secondary: Icon(_suspendOnRed ? Icons.block : Icons.check_circle_outline, color: _suspendOnRed ? Colors.red : Colors.grey),
              ),
              
              const Divider(),
              
              SwitchListTile(
                title: const Text('Zerar amarelos ao suspender por CA?'),
                subtitle: const Text('Após tomar o 3º amarelo e suspender, a contagem volta a zero?'),
                value: _resetYellowsOnSuspension,
                onChanged: _isSaving ? null : (bool value) => setState(() => _resetYellowsOnSuspension = value),
                secondary: Icon(_resetYellowsOnSuspension ? Icons.restart_alt : Icons.history),
              ),

              SwitchListTile(
                title: const Text('Zerar amarelos ao suspender por CV?'),
                subtitle: const Text('Se tomar vermelho direto, zera os amarelos acumulados?'),
                value: _resetYellowsOnRed,
                onChanged: _isSaving ? null : (bool value) => setState(() => _resetYellowsOnRed = value),
                secondary: Icon(_resetYellowsOnRed ? Icons.layers_clear : Icons.layers),
              ),

              const SizedBox(height: 32),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Salvando...' : 'Salvar Regras'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                  onPressed: _isSaving ? null : _saveRules,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}