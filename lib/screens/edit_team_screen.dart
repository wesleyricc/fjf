// lib/screens/edit_team_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class EditTeamScreen extends StatefulWidget {
  // Recebe 'null' se for CRIAR, ou o Doc se for EDITAR
  final DocumentSnapshot? team;

  const EditTeamScreen({super.key, this.team});

  @override
  State<EditTeamScreen> createState() => _EditTeamScreenState();
}

class _EditTeamScreenState extends State<EditTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();

  // Controladores do Formulário
  late TextEditingController _nameController;
  late TextEditingController _shortNameController;
  late TextEditingController _shieldUrlController;

  bool _isSaving = false;
  String _currentShieldUrl = ''; // Para preview da imagem

  @override
  void initState() {
    super.initState();
    
    // Preenche controladores se estiver no modo de edição
    _nameController = TextEditingController(text: widget.team?['name'] ?? '');
    _shortNameController = TextEditingController(text: widget.team?['short_name'] ?? '');
    _shieldUrlController = TextEditingController(text: widget.team?['shield_url'] ?? '');
    _currentShieldUrl = widget.team?['shield_url'] ?? '';

    // Adiciona listener para atualizar o preview do escudo
    _shieldUrlController.addListener(() {
      if (mounted) {
        setState(() {
          _currentShieldUrl = _shieldUrlController.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortNameController.dispose();
    _shieldUrlController.dispose();
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
      final shortName = _shortNameController.text.toUpperCase(); // Força maiúscula
      final shieldUrl = _shieldUrlController.text;

      if (widget.team == null) {
        // --- MODO CRIAÇÃO ---
        result = await _firestoreService.createTeam(
          name: name,
          shortName: shortName,
          shieldUrl: shieldUrl,
        );
      } else {
        // --- MODO ATUALIZAÇÃO ---
        result = await _firestoreService.updateTeam(
          teamDoc: widget.team!,
          name: name,
          shortName: shortName,
          shieldUrl: shieldUrl,
        );
      }

       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
         if (result.startsWith('Sucesso')) {
            Navigator.of(context).pop(); // Volta para a lista de times
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
    bool isEditing = widget.team != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Equipe' : 'Criar Nova Equipe'),
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
            // --- Preview do Escudo ---
            if (_currentShieldUrl.isNotEmpty)
              Center(
                child: CachedNetworkImage(
                  imageUrl: _currentShieldUrl,
                  height: 80, width: 80, fit: BoxFit.contain,
                  placeholder: (c, u) => const SizedBox(height: 80, width: 80, child: Center(child: CircularProgressIndicator())),
                  errorWidget: (c, u, e) => const SizedBox(height: 80, width: 80, child: Icon(Icons.error_outline, color: Colors.red, size: 40)),
                ),
              ),
            const SizedBox(height: 16),

            // --- Nome ---
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Completo da Equipe', border: OutlineInputBorder()),
              validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            // --- Sigla ---
            TextFormField(
              controller: _shortNameController,
              decoration: const InputDecoration(labelText: 'Sigla (Ex: FLA)', border: OutlineInputBorder()),
              maxLength: 3, // Limite de 3 caracteres
              textCapitalization: TextCapitalization.characters, // Sugere maiúsculas
              validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            // --- URL do Escudo ---
            TextFormField(
              controller: _shieldUrlController,
              decoration: const InputDecoration(labelText: 'URL do Escudo (https://...)', border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Obrigatório';
                if (!value.startsWith('http://') && !value.startsWith('https://')) return 'URL inválida';
                return null;
              },
              enabled: !_isSaving,
            ),
          ],
        ),
      ),
    );
  }
}