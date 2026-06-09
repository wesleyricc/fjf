import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart'; 
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/championship_service.dart';
import '../services/player_service.dart';
import '../models/player_model.dart';
import '../viewmodels/edit_player_viewmodel.dart';

class EditPlayerScreen extends StatelessWidget {
  final String teamId;
  final String teamName;
  final Player? player;

  const EditPlayerScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    this.player,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EditPlayerViewModel(
        Provider.of<PlayerService>(context, listen: false), 
        player,
      ),
      child: _EditPlayerScreenContent(
        teamId: teamId,
        teamName: teamName,
        player: player,
      ),
    );
  }
}

class _EditPlayerScreenContent extends StatefulWidget {
  final String teamId;
  final String teamName;
  final Player? player;

  const _EditPlayerScreenContent({required this.teamId, required this.teamName, this.player});

  @override
  State<_EditPlayerScreenContent> createState() => _EditPlayerScreenContentState();
}

class _EditPlayerScreenContentState extends State<_EditPlayerScreenContent> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _jerseyNumberController;
  late TextEditingController _dateOfBirthController;
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  late TextEditingController _instagramController;
  late TextEditingController _phoneController;

  final List<String> _positionOptions = ['Fixo', 'Ala', 'Pivô'];
  final List<String> _footOptions = ['Destro', 'Canhoto', 'Ambidestro'];
  final List<String> _staffRoleOptions = ['Técnico', 'Auxiliar Técnico', 'Atendente', 'Analista', 'Massagista', 'Preparador Físico'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.player?.name ?? '');
    _jerseyNumberController = TextEditingController(text: widget.player?.jerseyNumber?.toString() ?? '');
    
    _dateOfBirthController = TextEditingController();
    if (widget.player?.dateOfBirth != null) {
      _dateOfBirthController.text = DateFormat('dd/MM/yyyy').format(widget.player!.dateOfBirth!);
    }

    _heightController = TextEditingController(text: widget.player?.heightCm?.toString() ?? '');
    _weightController = TextEditingController(text: widget.player?.weightKg?.toString() ?? '');
    _instagramController = TextEditingController();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _jerseyNumberController.dispose();
    _dateOfBirthController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _instagramController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleSave(EditPlayerViewModel vm) async {
    if (!_formKey.currentState!.validate()) return;

    Timestamp? dobTimestamp;
    if (_dateOfBirthController.text.isNotEmpty) {
      try {
        final date = DateFormat('dd/MM/yyyy').parse(_dateOfBirthController.text);
        dobTimestamp = Timestamp.fromDate(date);
      } catch (_) {}
    }

    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    final result = await vm.savePlayer(
      seasonId: seasonId,
      teamId: widget.teamId,
      teamName: widget.teamName,
      name: _nameController.text,
      jerseyNumber: int.tryParse(_jerseyNumberController.text),
      dobTimestamp: dobTimestamp,
      heightCm: int.tryParse(_heightController.text),
      weightKg: int.tryParse(_weightController.text),
      instagram: _instagramController.text,
      phone: _phoneController.text,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      if (result.startsWith("Sucesso")) {
        await Provider.of<ChampionshipService>(context, listen: false).fetchRoster(widget.teamId, force: true);
        Navigator.pop(context);
      }
    }
  }

  Future<void> _selectDate() async {
    DateTime initial = DateTime(2000);
    if (_dateOfBirthController.text.isNotEmpty) {
      try { initial = DateFormat('dd/MM/yyyy').parse(_dateOfBirthController.text); } catch (_) {}
    }
    final DateTime? picked = await showDatePicker(
      context: context, initialDate: initial, firstDate: DateTime(1950), lastDate: DateTime.now(), locale: const Locale('pt', 'BR')
    );
    if (picked != null) setState(() => _dateOfBirthController.text = DateFormat('dd/MM/yyyy').format(picked));
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = Provider.of<AuthService>(context).isAuthenticated;
    if (!isAuthenticated) return const Scaffold(body: Center(child: Text("Acesso Negado")));

    return Consumer<EditPlayerViewModel>(
      builder: (context, vm, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.player == null ? 'Novo Jogador' : 'Editar ${_nameController.text}'),
            actions: [
              IconButton(
                icon: vm.isUploading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Icon(Icons.save),
                onPressed: vm.isUploading ? null : () => _handleSave(vm),
              )
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: vm.pickImage,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: vm.imageFile != null
                          ? FileImage(vm.imageFile!) as ImageProvider
                          : vm.webImageBytes != null
                              ? MemoryImage(vm.webImageBytes!)
                              : (vm.photoUrl != null && vm.photoUrl!.isNotEmpty)
                                  ? CachedNetworkImageProvider(vm.photoUrl!) as ImageProvider
                                  : null,
                      child: (vm.imageFile == null && vm.webImageBytes == null && (vm.photoUrl == null || vm.photoUrl!.isEmpty))
                          ? Icon(Icons.camera_alt, size: 40, color: Colors.grey.shade400)
                          : null,
                    ),
                  ),
                ),
                if (vm.photoUrl != null || vm.imageFile != null || vm.webImageBytes != null)
                  Center(
                    child: TextButton(
                      onPressed: vm.clearImage,
                      child: const Text('Remover Foto', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _jerseyNumberController,
                        decoration: const InputDecoration(labelText: 'Nº Camisa', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _dateOfBirthController,
                        readOnly: true,
                        onTap: _selectDate,
                        decoration: const InputDecoration(labelText: 'Nascimento', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Membro da Comissão Técnica?'),
                        subtitle: const Text('Técnico, Auxiliar, etc.'),
                        value: vm.isStaff,
                        onChanged: vm.setStaff,
                      ),
                      if (!vm.isStaff)
                        SwitchListTile(
                          title: const Text('É Goleiro?'),
                          value: vm.isGoalkeeper,
                          onChanged: vm.setGoalkeeper,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (vm.isStaff)
                  DropdownButtonFormField<String>(
                    value: vm.selectedStaffRole,
                    decoration: const InputDecoration(labelText: 'Função', border: OutlineInputBorder()),
                    items: _staffRoleOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: vm.setStaffRole,
                  ),

                if (!vm.isStaff && !vm.isGoalkeeper)
                  DropdownButtonFormField<String>(
                    value: vm.selectedPosition,
                    decoration: const InputDecoration(labelText: 'Posição', border: OutlineInputBorder()),
                    items: _positionOptions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: vm.setPosition,
                  ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: TextFormField(controller: _heightController, decoration: const InputDecoration(labelText: 'Altura (cm)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                    const SizedBox(width: 16),
                    Expanded(child: TextFormField(controller: _weightController, decoration: const InputDecoration(labelText: 'Peso (kg)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: vm.selectedFoot,
                  decoration: const InputDecoration(labelText: 'Pé Preferido', border: OutlineInputBorder()),
                  items: _footOptions.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: vm.setFoot,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}