// lib/screens/edit_player_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // Para input formatters

class EditPlayerScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final DocumentSnapshot? playerDoc; // Nulo se for 'Criar'

  const EditPlayerScreen({
    super.key, 
    required this.teamId,
    required this.teamName,
    this.playerDoc,
  });

  @override
  State<EditPlayerScreen> createState() => _EditPlayerScreenState();
}

class _EditPlayerScreenState extends State<EditPlayerScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controladores
  late TextEditingController _nameController;
  late TextEditingController _numberController;
  
  // --- NOVOS ESTADOS PARA POSIÇÃO (REQ 2) ---
  bool _isGoalkeeper = false;
  // Define as posições (Goleiro é tratado pelo bool)
  final List<String> _positionOptions = ['Fixo', 'Ala', 'Pivô'];
  String? _selectedPosition;
  // --- FIM ---

  bool _isActive = true;
  bool _isStaff = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.playerDoc?.data() as Map<String, dynamic>?;

    _nameController = TextEditingController(text: data?['name'] ?? '');
    _numberController = TextEditingController(text: data?['jersey_number']?.toString() ?? '');
    _isActive = data?['isActive'] ?? true;
    _isStaff = data?['is_staff'] ?? false;
    
    // --- LÓGICA DE POSIÇÃO (REQ 2) ---
    _isGoalkeeper = data?['is_goalkeeper'] ?? false;
    _selectedPosition = data?['position'];
    
    // Garante que a posição só seja válida se NÃO for goleiro
    if (_isGoalkeeper) {
      _selectedPosition = null;
    } else if (data?['position'] == null) {
       _selectedPosition = 'Ala'; // Define 'Ala' como padrão se for novo
    }
    // --- FIM ---
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _savePlayer() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validação extra: Se não for goleiro, DEVE ter uma posição
    if (!_isGoalkeeper && _selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecione a Posição (Fixo, Ala ou Pivô).')),
      );
      return;
    }
    
    setState(() { _isSaving = true; });

    final String name = _nameController.text.trim();
    final int? number = int.tryParse(_numberController.text);
    
    // Prepara os dados
    Map<String, dynamic> playerData = {
      'name': name,
      'jersey_number': number,
      'team_id': widget.teamId,
      'team_name': widget.teamName, // (Armazena o nome do time para facilitar)
      'isActive': _isActive,
      'is_staff': _isStaff,
      'is_goalkeeper': _isGoalkeeper,
      // --- SALVA A POSIÇÃO (REQ 2) ---
      'position': _isGoalkeeper ? null : _selectedPosition, // Salva null se for goleiro
      
      // Reseta/Inicializa campos de estatísticas
      'goals': widget.playerDoc != null ? (widget.playerDoc!['goals'] ?? 0) : 0,
      'assists': widget.playerDoc != null ? (widget.playerDoc!['assists'] ?? 0) : 0,
      'yellow_cards': widget.playerDoc != null ? (widget.playerDoc!['yellow_cards'] ?? 0) : 0,
      'red_cards': widget.playerDoc != null ? (widget.playerDoc!['red_cards'] ?? 0) : 0,
      'total_yellow_cards': widget.playerDoc != null ? (widget.playerDoc!['total_yellow_cards'] ?? 0) : 0,
      'total_red_cards': widget.playerDoc != null ? (widget.playerDoc!['total_red_cards'] ?? 0) : 0,
      'goals_conceded': widget.playerDoc != null ? (widget.playerDoc!['goals_conceded'] ?? 0) : 0,
      'man_of_the_match_awards': widget.playerDoc != null ? (widget.playerDoc!['man_of_the_match_awards'] ?? 0) : 0,
      'is_suspended': widget.playerDoc != null ? (widget.playerDoc!['is_suspended'] ?? false) : false,
    };

    try {
      if (widget.playerDoc == null) {
        // Modo Criação
        await _firestore.collection('players').add(playerData);
      } else {
        // Modo Edição
        await widget.playerDoc!.reference.update(playerData);
      }
      
      if (mounted) {
        Navigator.of(context).pop(); // Volta para a tela de detalhes do time
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Jogador ${widget.playerDoc == null ? 'salvo' : 'atualizado'} com sucesso!')),
        );
      }
    } catch (e) {
       if (mounted) {
         setState(() { _isSaving = false; });
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Erro ao salvar jogador: $e')),
         );
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playerDoc == null ? 'Novo Jogador' : 'Editar Jogador'),
        actions: [
          IconButton(
            icon: _isSaving ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _savePlayer,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text('Time: ${widget.teamName}', style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 24),
            
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Completo do Jogador', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _numberController,
              decoration: const InputDecoration(labelText: 'Número da Camisa', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),

            // --- LÓGICA DE POSIÇÃO (REQ 2) ---
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    // É Goleiro? (Switch)
                    SwitchListTile(
                      title: const Text('É Goleiro?'),
                      value: _isGoalkeeper,
                      onChanged: _isSaving ? null : (value) {
                        setState(() {
                          _isGoalkeeper = value;
                          // Se virar goleiro, anula a posição de linha
                          if (value) _selectedPosition = null; 
                          else _selectedPosition = 'Ala'; // Define um padrão ao desmarcar
                        });
                      },
                    ),
                    
                    // Posição de Linha (Dropdown)
                    // Fica desabilitado se for Goleiro
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: DropdownButtonFormField<String>(
                        value: _selectedPosition,
                        decoration: InputDecoration(
                          labelText: 'Posição de Linha',
                          border: const OutlineInputBorder(),
                          // Mostra "Desabilitado" se for goleiro
                          filled: _isGoalkeeper, 
                          fillColor: Colors.grey[200],
                        ),
                        // Desabilita o dropdown se for goleiro
                        onChanged: _isGoalkeeper || _isSaving ? null : (String? newValue) {
                          setState(() {
                            _selectedPosition = newValue;
                          });
                        },
                        items: _positionOptions.map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // --- FIM ---
            
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Faz parte da Comissão Técnica?'),
              value: _isStaff,
              onChanged: _isSaving ? null : (value) => setState(() => _isStaff = value),
            ),
            SwitchListTile(
              title: const Text('Jogador Ativo?'),
              subtitle: const Text('Desmarque para dispensar o jogador.'),
              value: _isActive,
              onChanged: _isSaving ? null : (value) => setState(() => _isActive = value),
            ),
          ],
        ),
      ),
    );
  }
}