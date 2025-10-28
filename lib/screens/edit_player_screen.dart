// lib/screens/edit_player_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import 'package:flutter/services.dart';

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
  late TextEditingController _numberController;
  String? _selectedStaffRole;
  bool _isGoalkeeper = false;
  bool _isStaff = false;
  bool _isSaving = false;

  final List<String> _staffRoleOptions = [
    'Técnico',
    'Auxiliar Técnico',
    'Massagista',
    'Analista',
    // Adicione outros cargos fixos aqui se desejar
  ];

  @override
  void initState() {
    super.initState();
    
    if (widget.playerDoc != null) {
      // Modo Edição: Preenche os campos
      final data = widget.playerDoc!.data() as Map<String, dynamic>? ?? {};
      _nameController = TextEditingController(text: data['name'] ?? '');
      _numberController = TextEditingController(text: data['jersey_number']?.toString() ?? '');
      _isGoalkeeper = data['is_goalkeeper'] ?? false;
      _isStaff = data['is_staff'] ?? false;
     final String? savedRole = data['staff_role'];
    if (_isStaff && savedRole != null && _staffRoleOptions.contains(savedRole)) {
      _selectedStaffRole = savedRole;
    }
      
    } else {
      // Modo Criação: Campos vazios
      _nameController = TextEditingController();
      _numberController = TextEditingController();
      _isGoalkeeper = false;
      _isStaff = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) {
       return; // Validação falhou

       
    }

    if (_isStaff && _selectedStaffRole == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, selecione a Função / Cargo.')));
       return;
    }

    setState(() { _isSaving = true; });

    String result;
    try {
      final name = _nameController.text;

      // Converte o texto para int?. Se for vazio, salva null.
      final int? jerseyNumber = _numberController.text.isNotEmpty
          ? int.tryParse(_numberController.text)
          : null;
      // --- FIM ---

      // Se for staff, força 'isGoalkeeper' para false
      final bool isGoalkeeperFinal = _isStaff ? false : _isGoalkeeper;
      // Se for staff, força 'jerseyNumber' para null (opcional)
      final int? jerseyNumberFinal = _isStaff ? null : jerseyNumber;
      final String? staffRole = _isStaff ? _selectedStaffRole : null;

      if (widget.playerDoc == null) {
        // --- MODO CRIAÇÃO ---
        result = await _firestoreService.createPlayer(
          name: name,
          isGoalkeeper: isGoalkeeperFinal,
          teamId: widget.teamId,
          teamName: widget.teamName,
          teamShieldUrl: widget.teamShieldUrl,
          jerseyNumber: jerseyNumberFinal,
          isStaff: _isStaff,
          staffRole: staffRole,
        );
      } else {
        // --- MODO ATUALIZAÇÃO ---
        result = await _firestoreService.updatePlayer(
          playerDoc: widget.playerDoc!,
          name: name,
          isGoalkeeper: isGoalkeeperFinal,
          jerseyNumber: jerseyNumberFinal,
          isStaff: _isStaff,
          staffRole: staffRole,
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
            
            // --- 4. NOVO SWITCH "COMISSÃO TÉCNICA" ---
            SwitchListTile(
               title: const Text('Membro da Comissão Técnica?'),
               subtitle: const Text('(Treinador, Massagista, etc.)'),
               value: _isStaff,
               onChanged: _isSaving ? null : (bool value) {
                 setState(() {
                   _isStaff = value;
                   // Se virou staff, desmarca 'goleiro'
                   if (_isStaff) {
                     _isGoalkeeper = false;
                     _numberController.text = '';
                   }else {
                     // Se deixou de ser staff, limpa o cargo
                     _selectedStaffRole = null;
                   }
                 });
               },
               secondary: Icon(_isStaff ? Icons.assignment_ind : Icons.person),
               activeColor: Theme.of(context).primaryColor,
             ),
             // --- 6. CAMPO CONDICIONAL PARA O CARGO ---
            if (_isStaff)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: DropdownButtonFormField<String>(
                  value: _selectedStaffRole, // Valor atualmente selecionado
                  hint: const Text('Selecione a Função / Cargo'),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Função / Cargo',
                    border: OutlineInputBorder(),
                  ),
                  items: _staffRoleOptions.map((String role) { // Mapeia a lista de opções
                    return DropdownMenuItem<String>(
                      value: role,
                      child: Text(role),
                    );
                  }).toList(),
                  onChanged: _isSaving ? null : (value) { // Salva a seleção no estado
                    setState(() {
                      _selectedStaffRole = value;
                    });
                  },
                  validator: (value) {
                    // Obrigatório se 'is_staff' for true
                    if (_isStaff && value == null) {
                      return 'A função é obrigatória para comissão técnica';
                    }
                    return null;
                  },
                ),
              ),
            // --- FIM DO CAMPO ---
            // --- FIM DO SWITCH ---
            
            const Divider(),
            const SizedBox(height: 16),

            // --- CAMPO NÚMERO (DESABILITADO SE FOR STAFF) ---
            TextFormField(
              controller: _numberController,
              decoration: const InputDecoration(
                labelText: 'Número da Camisa',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              // Desabilita se estiver salvando OU se for staff
              enabled: !_isSaving && !_isStaff, 
            ),
            // --- FIM ---

            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder()),
              validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            
            // --- SWITCH GOLEIRO (DESABILITADO SE FOR STAFF) ---
             SwitchListTile(
               title: const Text('É Goleiro?'),
               value: _isGoalkeeper,
               // Desabilita se estiver salvando OU se for staff
               onChanged: (_isSaving || _isStaff) ? null : (bool value) {
                 setState(() {
                   _isGoalkeeper = value;
                 });
               },
               secondary: Icon(_isGoalkeeper ? Icons.shield_outlined : Icons.person_outline),
               activeColor: Theme.of(context).primaryColor,
             ),
             // --- FIM ---
          ],
        ),
      ),
    );
  }
}