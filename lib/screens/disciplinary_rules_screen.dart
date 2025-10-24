// lib/screens/disciplinary_rules_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // Para input formatters
import '../services/admin_service.dart';

class DisciplinaryRulesScreen extends StatefulWidget {
  const DisciplinaryRulesScreen({super.key});

  @override
  State<DisciplinaryRulesScreen> createState() => _DisciplinaryRulesScreenState();
}

class _DisciplinaryRulesScreenState extends State<DisciplinaryRulesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>(); // Chave para o formulário

  // Controladores para os campos
  late TextEditingController _pendingController;
  late TextEditingController _suspensionController;
  late bool _suspendOnRed;
  late bool _resetYellowsOnSuspension;
  late bool _resetYellowsOnRed;
  late bool _resetYellowsOnRedWhilePending;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _pendingController = TextEditingController();
    _suspensionController = TextEditingController();
    _suspendOnRed = AdminService.suspensionOnRed; // Usa valor do cache inicial
    _resetYellowsOnSuspension = AdminService.resetYellowsOnSuspension;
    _resetYellowsOnRed = AdminService.resetYellowsOnRed;
    _resetYellowsOnRedWhilePending = AdminService.resetYellowsOnRedWhilePending;
    _loadCurrentRules();
  }

  // Carrega as regras atuais do Firestore para preencher o form
  Future<void> _loadCurrentRules() async {
    setState(() { _isLoading = true; });
    try {
       // Usa as regras já carregadas no AdminService para preencher inicialmente
       _pendingController.text = AdminService.pendingYellowCards.toString();
       _suspensionController.text = AdminService.suspensionYellowCards.toString();
       _suspendOnRed = AdminService.suspensionOnRed;
        _resetYellowsOnSuspension = AdminService.resetYellowsOnSuspension;
        _resetYellowsOnRed = AdminService.resetYellowsOnRed;
        _resetYellowsOnRedWhilePending = AdminService.resetYellowsOnRedWhilePending;
       // Opcional: Busca novamente do Firestore para garantir o valor mais recente
       // final docSnap = await _firestore.collection('config').doc('disciplinary_rules').get();
       // if (docSnap.exists && docSnap.data() != null) {
       //    _pendingController.text = (docSnap.data()!['pending_yellow_cards'] ?? AdminService.pendingYellowCards).toString();
       //    _suspensionController.text = (docSnap.data()!['suspension_yellow_cards'] ?? AdminService.suspensionYellowCards).toString();
       //    _suspendOnRed = docSnap.data()!['suspension_on_red'] ?? AdminService.suspensionOnRed;
       // }
    } catch (e) {
       debugPrint("Erro ao carregar regras atuais: $e");
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar regras: $e')));
    } finally {
       if (mounted) setState(() { _isLoading = false; });
    }
  }

  // Salva as novas regras no Firestore
  Future<void> _saveRules() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() { _isSaving = true; });
      try {
        final int pending = int.parse(_pendingController.text);
        final int suspension = int.parse(_suspensionController.text);

        await _firestore.collection('config').doc('disciplinary_rules').set({ // Usa .set para criar/sobrescrever
          'pending_yellow_cards': pending,
          'suspension_yellow_cards': suspension,
          'suspension_on_red': _suspendOnRed,
          'reset_yellows_on_suspension': _resetYellowsOnSuspension,
          'reset_yellows_on_red': _resetYellowsOnRed,
          'reset_yellows_on_red_while_pending': _resetYellowsOnRedWhilePending,
        });

        // Recarrega as regras no AdminService para o app usar imediatamente
        await AdminService.loadDisciplinaryRules();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Regras salvas com sucesso!')));
          Navigator.of(context).pop(); // Volta para o menu admin
        }

      } catch (e) {
         debugPrint("Erro ao salvar regras: $e");
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar regras: $e')));
      } finally {
         if (mounted) setState(() { _isSaving = false; });
      }
    }
  }


  @override
  void dispose() {
    _pendingController.dispose();
    _suspensionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Regras Disciplinares'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  TextFormField(
                    controller: _pendingController,
                    decoration: const InputDecoration(
                      labelText: 'Nº Cartões Amarelos para "Pendurado"',
                      hintText: 'Ex: 2',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Campo obrigatório';
                      if (int.tryParse(value) == null || int.parse(value) <= 0) return 'Valor inválido (> 0)';
                      return null;
                    },
                    enabled: !_isSaving,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _suspensionController,
                    decoration: const InputDecoration(
                      labelText: 'Nº Cartões Amarelos para "Suspensão"',
                      hintText: 'Ex: 3',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                     validator: (value) {
                      if (value == null || value.isEmpty) return 'Campo obrigatório';
                      final suspValue = int.tryParse(value);
                      final pendValue = int.tryParse(_pendingController.text);
                      if (suspValue == null || suspValue <= 0) return 'Valor inválido (> 0)';
                      if (pendValue != null && suspValue <= pendValue) return 'Deve ser maior que o nº para pendurar';
                      return null;
                    },
                    enabled: !_isSaving,
                  ),
                   const SizedBox(height: 16),
                   SwitchListTile(
                     title: const Text('Cartão Vermelho causa Suspensão?'),
                     value: _suspendOnRed,
                     onChanged: _isSaving ? null : (bool value) {
                       setState(() {
                         _suspendOnRed = value;
                       });
                     },
                     secondary: Icon(_suspendOnRed ? Icons.check_circle : Icons.cancel_outlined),
                     activeColor: Theme.of(context).primaryColor,
                   ),
                    const Divider(),

                    SwitchListTile(
                     title: const Text('Zerar amarelos ao suspender por CA?'),
                     value: _resetYellowsOnSuspension,
                     onChanged: _isSaving ? null : (bool value) => setState(() => _resetYellowsOnSuspension = value),
                     secondary: Icon(_resetYellowsOnSuspension ? Icons.clear_all : Icons.layers_clear),
                    ),
                    SwitchListTile(
                      title: const Text('Zerar amarelos ao receber CV direto?'),
                      value: _resetYellowsOnRed,
                      onChanged: _isSaving ? null : (bool value) => setState(() => _resetYellowsOnRed = value),
                      secondary: Icon(_resetYellowsOnRed ? Icons.clear_all : Icons.layers_clear),
                    ),
                    SwitchListTile(
                      title: const Text('NÃO zerar amarelos se levar CV estando Pendurado?'),
                      subtitle: const Text('(Ignora a regra anterior neste caso específico)'),
                      value: !_resetYellowsOnRedWhilePending, // Invertido: Switch ON = NÃO ZERAR
                      onChanged: _isSaving ? null : (bool value) => setState(() => _resetYellowsOnRedWhilePending = !value), // Inverte ao salvar
                      secondary: Icon(!_resetYellowsOnRedWhilePending ? Icons.block : Icons.task_alt),
                    ),

                   const SizedBox(height: 32),
                   ElevatedButton.icon(
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
                ],
              ),
            ),
    );
  }
}