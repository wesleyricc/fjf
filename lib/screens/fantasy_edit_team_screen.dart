import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_service.dart';
import '../services/fantasy_auth_service.dart';

class FantasyEditTeamScreen extends StatefulWidget {
  const FantasyEditTeamScreen({super.key});

  @override
  State<FantasyEditTeamScreen> createState() => _FantasyEditTeamScreenState();
}

class _FantasyEditTeamScreenState extends State<FantasyEditTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // CORREÇÃO 1: Inicializa imediatamente (sem 'late') para evitar o crash
  final TextEditingController _teamNameController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  
  String _selectedShield = '1'; 
  bool _isLoading = true; // CORREÇÃO 2: Começa carregando

  // Lista de escudos disponíveis (Cores/Ícones)
  final List<Map<String, dynamic>> _availableShields = [
    {'id': '1', 'color': Colors.blue, 'icon': Icons.shield},
    {'id': '2', 'color': Colors.red, 'icon': Icons.shield},
    {'id': '3', 'color': Colors.green, 'icon': Icons.shield},
    {'id': '4', 'color': Colors.orange, 'icon': Icons.shield},
    {'id': '5', 'color': Colors.purple, 'icon': Icons.shield},
    {'id': '6', 'color': Colors.black, 'icon': Icons.shield},
    {'id': '7', 'color': Colors.teal, 'icon': Icons.security},
    {'id': '8', 'color': Colors.amber, 'icon': Icons.security},
    {'id': '9', 'color': Colors.indigo, 'icon': Icons.verified_user},
    {'id': '10', 'color': Colors.deepOrange, 'icon': Icons.verified_user},
  ];

  @override
  void initState() {
    super.initState();
    // Chama o carregamento logo no início
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentData();
    });
  }

  @override
  void dispose() {
    // Boa prática: descartar controllers
    _teamNameController.dispose();
    _ownerNameController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentData() async {
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final fantasyService = Provider.of<FantasyService>(context, listen: false);

    if (authService.user != null) {
      // Pega o primeiro valor da stream (estado atual)
      final team = await fantasyService.streamMyTeam(authService.user!.uid).first;
      
      if (team != null && mounted) {
        setState(() {
          // CORREÇÃO 3: Apenas atualiza o texto, não recria o controller
          _teamNameController.text = team.teamName;
          _ownerNameController.text = team.ownerName;
          _selectedShield = team.shieldType;
          _isLoading = false; // Para de carregar
        });
        return;
      }
    }
    
    // Se não achar nada, para o loading mesmo assim
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final fantasyService = Provider.of<FantasyService>(context, listen: false);

    final result = await fantasyService.updateTeamProfile(
      userId: authService.user!.uid,
      teamName: _teamNameController.text.trim(),
      ownerName: _ownerNameController.text.trim(),
      shieldType: _selectedShield,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      
      if (result == "Sucesso") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Perfil atualizado com sucesso!"), backgroundColor: Colors.green)
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Editar Equipe"),
        //backgroundColor: Colors.green[800],
        //foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLoading ? null : _saveProfile,
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // PREVIEW DO ESCUDO
                Center(
                  child: Column(
                    children: [
                      _buildShieldPreview(_selectedShield, 80),
                      const SizedBox(height: 10),
                      const Text("Toque abaixo para escolher", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),

                // GALERIA DE ESCUDOS
                SizedBox(
                  height: 70,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableShields.length,
                    itemBuilder: (ctx, i) {
                      final shield = _availableShields[i];
                      final isSelected = shield['id'] == _selectedShield;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedShield = shield['id']),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: isSelected ? Border.all(color: Colors.green, width: 3) : null,
                          ),
                          child: CircleAvatar(
                            backgroundColor: shield['color'],
                            child: Icon(shield['icon'], color: Colors.white),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 30),

                // CAMPOS DE TEXTO
                TextFormField(
                  controller: _teamNameController,
                  decoration: const InputDecoration(
                    labelText: "Nome do Time",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag),
                  ),
                  validator: (v) => v!.isEmpty ? "Informe o nome do time" : null,
                ),
                
                const SizedBox(height: 20),
                
                TextFormField(
                  controller: _ownerNameController,
                  decoration: const InputDecoration(
                    labelText: "Nome do Técnico (Você)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => v!.isEmpty ? "Informe seu nome" : null,
                ),

                const SizedBox(height: 30),
                
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    //style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                    onPressed: _saveProfile,
                    child: const Text("SALVAR ALTERAÇÕES", style: TextStyle(color: Colors.white)),
                  ),
                )
              ],
            ),
          ),
    );
  }

  // Widget Auxiliar para desenhar o escudo baseado no ID
  Widget _buildShieldPreview(String id, double size) {
    final shieldData = _availableShields.firstWhere(
      (e) => e['id'] == id, 
      orElse: () => _availableShields[0]
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: shieldData['color'],
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))]
      ),
      child: Icon(shieldData['icon'], color: Colors.white, size: size * 0.5),
    );
  }
}