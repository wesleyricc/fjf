// lib/screens/edit_player_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';

class EditPlayerScreen extends StatefulWidget {
  // Recebe dados do time para associar
  final String teamId;
  final String teamName;
  final String teamShieldUrl;
  // Recebe 'null' se for CRIAR, ou o Doc se for EDITAR
  final DocumentSnapshot? playerDoc;

  const EditPlayerScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.teamShieldUrl,
    this.playerDoc,
  });

  @override
  State<EditPlayerScreen> createState() => _EditPlayerScreenState();
}

class _EditPlayerScreenState extends State<EditPlayerScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();

  // Controladores do Formulário
  late TextEditingController _nameController;
  bool _isGoalkeeper = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.playerDoc != null) {
      // Modo Edição: Preenche os campos
      final data = widget.playerDoc!.data() as Map<String, dynamic>? ?? {};
      _nameController = TextEditingController(text: data['name'] ?? '');
      _isGoalkeeper = data['is_goalkeeper'] ?? false;
    } else {
      // Modo Criação: Campos vazios
      _nameController = TextEditingController();
      _isGoalkeeper = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) {
       return; // Validação falhou
    }

    setState(() { _isSaving = true; });

    String result;
    try {
      final name = _nameController.text;

      if (widget.playerDoc == null) {
        // --- MODO CRIAÇÃO ---
        result = await _firestoreService.createPlayer(
          name: name,
          isGoalkeeper: _isGoalkeeper,
          teamId: widget.teamId,
          teamName: widget.teamName,
          teamShieldUrl: widget.teamShieldUrl,
        );
      } else {
        // --- MODO ATUALIZAÇÃO ---
        result = await _firestoreService.updatePlayer(
          playerDoc: widget.playerDoc!,
          name: name,
          isGoalkeeper: _isGoalkeeper,
        );
      }

       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
         if (result.startsWith('Sucesso')) {
            Navigator.of(context).pop(); // Volta para a tela de detalhes do time
         }
       }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
       if (mounted) setState(() { _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isEditing = widget.playerDoc != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Jogador' : 'Adicionar Jogador'),
        actions: [
          IconButton(
            icon: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveForm,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text(
              'Equipe: ${widget.teamName}', // Mostra a qual time está sendo adicionado
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            // --- Nome ---
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Completo do Jogador', border: OutlineInputBorder()),
              validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            // --- É Goleiro? ---
             SwitchListTile(
               title: const Text('É Goleiro?'),
               value: _isGoalkeeper,
               onChanged: _isSaving ? null : (bool value) {
                 setState(() {
                   _isGoalkeeper = value;
                 });
               },
               secondary: Icon(_isGoalkeeper ? Icons.shield_outlined : Icons.person_outline),
               activeColor: Theme.of(context).primaryColor,
             ),
          ],
        ),
      ),
    );
  }
}