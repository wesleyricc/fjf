import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // <-- Importante
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../services/championship_service.dart'; // <-- Importante
import 'package:cached_network_image/cached_network_image.dart';

class EditMatchScreen extends StatefulWidget {
  final DocumentSnapshot? match;

  const EditMatchScreen({super.key, this.match});

  @override
  State<EditMatchScreen> createState() => _EditMatchScreenState();
}

class _EditMatchScreenState extends State<EditMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();

  bool _isLoading = true;
  bool _isSaving = false;
  List<DocumentSnapshot> _teams = [];

  DocumentSnapshot? _selectedHomeTeam;
  DocumentSnapshot? _selectedAwayTeam;
  final _locationController = TextEditingController();
  final _roundController = TextEditingController();
  DateTime _selectedDateTime = DateTime.now();
  String _selectedPhase = 'first';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() { _isLoading = true; });
    
    // 1. Obtém a temporada atual para saber onde buscar os times
    // Se estivermos no modo Legado, busca em /teams.
    // Se estivermos no modo Novo, busca em /championships/{id}/teams_participation
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    
    try {
      Query teamsQuery;
      if (seasonId == FirestoreService.LEGACY_ID) {
        teamsQuery = FirebaseFirestore.instance.collection('teams').orderBy('name');
      } else {
        teamsQuery = FirebaseFirestore.instance
            .collection('championships')
            .doc(seasonId)
            .collection('teams_participation')
            .orderBy('name');
      }

      final teamsSnapshot = await teamsQuery.get();
      _teams = teamsSnapshot.docs;

      if (widget.match != null) {
        final data = widget.match!.data() as Map<String, dynamic>;
        try {
          _selectedHomeTeam = _teams.firstWhere((t) => t.id == data['team_home_id']);
        } catch (e) { _selectedHomeTeam = null; }
        try {
          _selectedAwayTeam = _teams.firstWhere((t) => t.id == data['team_away_id']);
        } catch (e) { _selectedAwayTeam = null; }

        _locationController.text = data['location'] ?? '';
        _roundController.text = (data['round'] ?? '').toString();
        _selectedPhase = data['phase'] ?? 'first';
        _selectedDateTime = (data['datetime'] as Timestamp? ?? Timestamp.now()).toDate();
      } else {
         _selectedPhase = 'first';
         _selectedDateTime = DateTime.now();
      }
    } catch (e) {
      debugPrint("Erro ao carregar dados: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
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
    if (date == null) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (time == null) return;

    setState(() {
      _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedHomeTeam == null || _selectedAwayTeam == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione ambos os times.')));
       return;
    }
    if (_selectedHomeTeam!.id == _selectedAwayTeam!.id) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Times devem ser diferentes.')));
       return;
    }

    setState(() { _isSaving = true; });

    // 2. Obtém ID da temporada para salvar na coleção correta
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    String result;
    try {
      final location = _locationController.text;
      final round = int.tryParse(_roundController.text) ?? 0;

      if (widget.match == null) {
        // --- MODO CRIAÇÃO ---
        result = await _firestoreService.createMatch(
          seasonId: seasonId, // <-- NOVO
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
          phase: _selectedPhase,
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
    final currentSeasonName = Provider.of<ChampionshipService>(context, listen: false).currentSeasonName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.match == null ? 'Criar Partida' : 'Editar Detalhes'),
            Text('Em: $currentSeasonName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
          ],
        ),
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
                  DropdownButtonFormField<DocumentSnapshot>(
                    value: _selectedHomeTeam,
                    hint: const Text('Selecione o Time da Casa'),
                    isExpanded: true,
                    items: _teams.map((team) {
                      final data = team.data() as Map<String, dynamic>? ?? {};
                      final shieldUrl = data['shield_url'] ?? '';
                      final teamName = data['name'] ?? 'Time s/ nome';
                      return DropdownMenuItem<DocumentSnapshot>(
                        value: team,
                        child: Row(
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
                            Expanded(child: Text(teamName, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _isSaving ? null : (value) => setState(() => _selectedHomeTeam = value),
                    validator: (value) => value == null ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<DocumentSnapshot>(
                    value: _selectedAwayTeam,
                    hint: const Text('Selecione o Time Visitante'),
                    isExpanded: true,
                    items: _teams.map((team) {
                      final data = team.data() as Map<String, dynamic>? ?? {};
                      final shieldUrl = data['shield_url'] ?? '';
                      final teamName = data['name'] ?? 'Time s/ nome';
                      return DropdownMenuItem<DocumentSnapshot>(
                        value: team,
                        child: Row(
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
                            Expanded(child: Text(teamName, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _isSaving ? null : (value) => setState(() => _selectedAwayTeam = value),
                    validator: (value) => value == null ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(labelText: 'Local', border: OutlineInputBorder()),
                    validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
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
                  ListTile(
                    title: const Text('Data e Hora'),
                    subtitle: Text(DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(_selectedDateTime)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: _isSaving ? null : _pickDateTime,
                    shape: RoundedRectangleBorder(
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