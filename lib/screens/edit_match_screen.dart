// lib/screens/edit_match_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import 'package:cached_network_image/cached_network_image.dart';


class EditMatchScreen extends StatefulWidget {
  // Recebe 'null' se for CRIAR, ou o Doc se for EDITAR
  final DocumentSnapshot? match;

  const EditMatchScreen({super.key, this.match});

  @override
  State<EditMatchScreen> createState() => _EditMatchScreenState();
}

class _EditMatchScreenState extends State<EditMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  // Estados
  bool _isLoading = true; // Carregando times
  bool _isSaving = false;
  List<DocumentSnapshot> _teams = []; // Lista de todos os times

  // Controladores do Formulário
  DocumentSnapshot? _selectedHomeTeam;
  DocumentSnapshot? _selectedAwayTeam;
  final _locationController = TextEditingController();
  final _roundController = TextEditingController();
  DateTime _selectedDateTime = DateTime.now();
  String _selectedPhase = 'first'; // Padrão

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() { _isLoading = true; });
    try {
      // 1. Buscar todos os times
      final teamsSnapshot = await _firestore.collection('teams').orderBy('name').get();
      _teams = teamsSnapshot.docs;

      // 2. Se for MODO EDIÇÃO, preencher os campos
      if (widget.match != null) {
        final data = widget.match!.data() as Map<String, dynamic>;
        

        try {
          _selectedHomeTeam = _teams.firstWhere((t) => t.id == data['team_home_id']);
        } catch (e) {
          _selectedHomeTeam = null; 
          debugPrint("Aviso: Time da casa ${data['team_home_id']} não encontrado na lista de times.");
        }
        try {
          _selectedAwayTeam = _teams.firstWhere((t) => t.id == data['team_away_id']);
        } catch (e) {
          _selectedAwayTeam = null;
          debugPrint("Aviso: Time visitante ${data['team_away_id']} não encontrado na lista de times.");
        }

        _locationController.text = data['location'] ?? '';
        _roundController.text = (data['round'] ?? '').toString();
        _selectedPhase = data['phase'] ?? 'first';
        _selectedDateTime = (data['datetime'] as Timestamp? ?? Timestamp.now()).toDate();
      } else {
         // Modo Criação (padrões)
         _selectedPhase = 'first';
         _selectedDateTime = DateTime.now();
      }
    } catch (e) {
      debugPrint("Erro ao carregar dados para EditMatchScreen: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e')));
    } finally {
      if(mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _pickDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('pt', 'BR'),
    );
    if (date == null) return; // Cancelou data

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (time == null) return; // Cancelou hora

    setState(() {
      _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) {
       return;
    }
    if (_selectedHomeTeam == null || _selectedAwayTeam == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione ambos os times.')));
       return;
    }
    if (_selectedHomeTeam!.id == _selectedAwayTeam!.id) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time da casa e visitante não podem ser iguais.')));
       return;
    }

    setState(() { _isSaving = true; });

    String result;
    try {
      final location = _locationController.text;
      final round = int.tryParse(_roundController.text) ?? 0;

      if (widget.match == null) {
        // --- MODO CRIAÇÃO ---
        // (Só permite criar 1ª Fase, ignora _selectedPhase do form)
        result = await _firestoreService.createMatch(
          homeTeam: _selectedHomeTeam!,
          awayTeam: _selectedAwayTeam!,
          location: location,
          round: round,
          dateTime: _selectedDateTime,
        );
      } else {
        // --- MODO ATUALIZAÇÃO ---
        result = await _firestoreService.updateMatchDetails(
          match: widget.match!,
          homeTeam: _selectedHomeTeam!,
          awayTeam: _selectedAwayTeam!,
          location: location,
          round: round,
          dateTime: _selectedDateTime,
          phase: _selectedPhase, // Permite salvar a fase (ex: 'semifinal')
        );
      }

       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
         if (result.startsWith('Sucesso')) {
            Navigator.of(context).popUntil((route) => route.isFirst);
         }
       }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
       if (mounted) setState(() { _isSaving = false; });
    }
  }


  @override
  void dispose() {
    _locationController.dispose();
    _roundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.match == null ? 'Criar Nova Partida (1ª Fase)' : 'Editar Detalhes da Partida'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveForm,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // --- Seletor Time Casa ---
                  DropdownButtonFormField<DocumentSnapshot>(
                    value: _selectedHomeTeam,
                    hint: const Text('Selecione o Time da Casa'),
                    isExpanded: true, // Garante que o Row tenha espaço
                    items: _teams.map((team) {
                      final data = team.data() as Map<String, dynamic>? ?? {}; // Acesso seguro
                      final shieldUrl = data['shield_url'] ?? '';
                      final teamName = data['name'] ?? 'Time s/ nome';
                      
                      return DropdownMenuItem<DocumentSnapshot>(
                        value: team,
                        child: Row( // <-- Mudar para Row
                          children: [
                            if (shieldUrl.isNotEmpty)
                              SizedBox(
                                width: 25, height: 25, // Tamanho do escudo
                                child: CachedNetworkImage(
                                  imageUrl: shieldUrl,
                                  placeholder: (c, u) => const Icon(Icons.shield, size: 20, color: Colors.grey),
                                  errorWidget: (c, u, e) => const Icon(Icons.shield, size: 25, color: Colors.grey),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            if (shieldUrl.isNotEmpty) const SizedBox(width: 8), // Espaçamento
                            Expanded( // Para nomes longos
                              child: Text(
                                teamName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _isSaving ? null : (value) => setState(() => _selectedHomeTeam = value),
                    validator: (value) => value == null ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  // --- Seletor Time Visitante ---
                  DropdownButtonFormField<DocumentSnapshot>(
                    value: _selectedAwayTeam,
                    hint: const Text('Selecione o Time Visitante'),
                    isExpanded: true,
                    items: _teams.map((team) {
                      final data = team.data() as Map<String, dynamic>? ?? {}; // Acesso seguro
                      final shieldUrl = data['shield_url'] ?? '';
                      final teamName = data['name'] ?? 'Time s/ nome';

                      return DropdownMenuItem<DocumentSnapshot>(
                        value: team,
                        child: Row( // <-- Mudar para Row
                          children: [
                            if (shieldUrl.isNotEmpty)
                              SizedBox(
                                width: 25, height: 25,
                                child: CachedNetworkImage(
                                  imageUrl: shieldUrl,
                                  placeholder: (c, u) => const Icon(Icons.shield, size: 20, color: Colors.grey),
                                  errorWidget: (c, u, e) => const Icon(Icons.shield, size: 25, color: Colors.grey),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            if (shieldUrl.isNotEmpty) const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                teamName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _isSaving ? null : (value) => setState(() => _selectedAwayTeam = value),
                    validator: (value) => value == null ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  // --- Local ---
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(labelText: 'Local', border: OutlineInputBorder()),
                    validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  // --- Rodada (Só se for 1ª Fase) ---
                  if (_selectedPhase == 'first')
                    TextFormField(
                      controller: _roundController,
                      decoration: const InputDecoration(labelText: 'Rodada (1ª Fase)', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                         if (value == null || value.isEmpty) return 'Obrigatório';
                         if (int.tryParse(value) == null || int.parse(value) <= 0) return 'Valor inválido';
                         return null;
                      },
                      enabled: !_isSaving,
                    ),
                  const SizedBox(height: 16),
                  // --- Seletor Data/Hora ---
                  ListTile(
                    title: const Text('Data e Hora'),
                    subtitle: Text(DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(_selectedDateTime)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: _isSaving ? null : _pickDateTime, // Desabilita se estiver salvando
                    shape: RoundedRectangleBorder( // Adiciona borda similar
                       borderRadius: BorderRadius.circular(4.0),
                       side: BorderSide(color: Colors.grey.shade400)
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}