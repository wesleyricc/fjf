import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/team_service.dart';
import '../services/match_service.dart';
import '../services/championship_service.dart';
import '../models/match_model.dart'; 
import '../models/team_model.dart';  

class EditMatchScreen extends StatefulWidget {
  final MatchModel? match; 

  const EditMatchScreen({super.key, this.match});

  @override
  State<EditMatchScreen> createState() => _EditMatchScreenState();
}

class _EditMatchScreenState extends State<EditMatchScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isSaving = false;
  
  String? _selectedHomeTeamId;
  String? _selectedAwayTeamId;
  
  final _locationController = TextEditingController();
  final _roundController = TextEditingController();
  DateTime _selectedDateTime = DateTime.now();
  String _selectedPhase = 'first';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _roundController.dispose();
    super.dispose();
  }

  void _loadInitialData() {
    if (widget.match != null) {
      final m = widget.match!;
      _selectedHomeTeamId = m.homeTeamId;
      _selectedAwayTeamId = m.awayTeamId;
      _locationController.text = m.location;
      _roundController.text = m.round.toString();
      _selectedPhase = m.phase;
      _selectedDateTime = m.datetime ?? DateTime.now();
    } else {
       _selectedPhase = 'first';
       _selectedDateTime = DateTime.now();
       _locationController.text = 'Ginásio Principal'; 
    }
  }

  Future<void> _pickDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      locale: const Locale('pt', 'BR'),
    );
    if (date == null) return;

    if (!mounted) return;

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
    
    if (_selectedHomeTeamId == null || _selectedAwayTeamId == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione ambos os times.')));
       return;
    }
    if (_selectedHomeTeamId == _selectedAwayTeamId) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Times devem ser diferentes.')));
       return;
    }

    setState(() => _isSaving = true);
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final teamService = Provider.of<TeamService>(context, listen: false);
    final matchService = Provider.of<MatchService>(context, listen: false);

    try {
      final location = _locationController.text;
      final round = int.tryParse(_roundController.text) ?? 0;
      
      final homeSnap = await teamService.getTeamSnapshot(_selectedHomeTeamId!, seasonId);
      final awaySnap = await teamService.getTeamSnapshot(_selectedAwayTeamId!, seasonId);

      if (homeSnap == null || awaySnap == null) throw Exception("Times não encontrados no banco.");

      String result;
      if (widget.match == null) {
        result = await matchService.createMatch(
          seasonId: seasonId,
          homeTeam: homeSnap,
          awayTeam: awaySnap,
          location: location,
          round: round,
          dateTime: _selectedDateTime,
        );
      } else {
        final matchRef = FirebaseFirestore.instance
            .collection('championships')
            .doc(seasonId)
            .collection('matches')
            .doc(widget.match!.id);
        
        final matchSnap = await matchRef.get();

        if (matchSnap.exists) {
          result = await matchService.updateMatchDetails(
            match: matchSnap,
            homeTeam: homeSnap,
            awayTeam: awaySnap,
            location: location,
            round: round,
            dateTime: _selectedDateTime,
            phase: _selectedPhase,
          );
        } else {
          result = "Erro: Partida original não encontrada.";
        }
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
       if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildTeamDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    required List<Team> teamsList, 
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      isExpanded: true, // <--- CORREÇÃO AQUI: Impede o erro de layout infinito
      items: teamsList.map((team) {
        return DropdownMenuItem<String>(
          value: team.id,
          child: Row(
            children: [
              if (team.shieldUrl.isNotEmpty)
                CachedNetworkImage(imageUrl: team.shieldUrl, width: 24, height: 24, fit: BoxFit.contain)
              else 
                const Icon(Icons.shield, size: 24, color: Colors.grey),
              const SizedBox(width: 10),
              // Expanded precisa de um pai com largura definida (garantida pelo isExpanded: true acima)
              Expanded(child: Text(team.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
      }).toList(),
      onChanged: _isSaving ? null : onChanged,
      validator: (v) => v == null ? 'Obrigatório' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final teams = Provider.of<ChampionshipService>(context).teams;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.match == null ? 'Criar Partida' : 'Editar Detalhes'),
        actions: [
          IconButton(
            icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveForm,
          ),
        ],
      ),
      body: teams.isEmpty 
          ? const Center(child: Text("Nenhum time disponível. Carregue as equipes primeiro."))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  const Text('Equipes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  _buildTeamDropdown(
                    label: 'Time da Casa',
                    value: _selectedHomeTeamId,
                    onChanged: (val) => setState(() => _selectedHomeTeamId = val),
                    teamsList: teams,
                  ),
                  const SizedBox(height: 16),
                  _buildTeamDropdown(
                    label: 'Time Visitante',
                    value: _selectedAwayTeamId,
                    onChanged: (val) => setState(() => _selectedAwayTeamId = val),
                    teamsList: teams,
                  ),
                  
                  const Divider(height: 40),
                  
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(labelText: 'Local', prefixIcon: Icon(Icons.place)),
                    validator: (value) => (value == null || value.isEmpty) ? 'Informe o local' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  if (_selectedPhase == 'first')
                    TextFormField(
                      controller: _roundController,
                      decoration: const InputDecoration(labelText: 'Rodada', prefixIcon: Icon(Icons.tag)),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) => (value == null || value.isEmpty) ? 'Informe a rodada' : null,
                    ),
                  
                  const SizedBox(height: 16),
                  ListTile(
                    tileColor: Colors.grey[100],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                    title: Text(DateFormat('dd/MM/yyyy - HH:mm', 'pt_BR').format(_selectedDateTime)),
                    subtitle: const Text('Toque para alterar data e hora'),
                    leading: const Icon(Icons.calendar_month, color: Colors.blue),
                    onTap: _isSaving ? null : _pickDateTime,
                  ),
                ],
              ),
            ),
    );
  }
}