import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/bolao_service.dart';
import '../../models/bolao_models.dart';
import 'dart:typed_data'; // ADICIONE ESTE
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class BolaoPredictionsScreen extends StatefulWidget {
  const BolaoPredictionsScreen({super.key});

  @override
  State<BolaoPredictionsScreen> createState() => _BolaoPredictionsScreenState();
}

class _BolaoPredictionsScreenState extends State<BolaoPredictionsScreen>
    with SingleTickerProviderStateMixin {
  final BolaoService _bolaoService = BolaoService();
  late TabController _tabController;

  final Map<String, TextEditingController> _homeControllers = {};
  final Map<String, TextEditingController> _awayControllers = {};
  final TextEditingController _nameController = TextEditingController();

  bool _isSavingName = false;
  Timer? _debounce;

  // VARIÁVEIS DE ESTADO DOS FILTROS
  String _selectedStatusFilter = "Todos";
  String _selectedPhaseFilter = "Todas as Fases";

  final List<String> _phaseOptions = [
    "Todas as Fases",
    "Grupo A",
    "Grupo B",
    "Grupo C",
    "Grupo D",
    "Grupo E",
    "Grupo F",
    "Grupo G",
    "Grupo H",
    "Grupo I",
    "Grupo J",
    "Grupo K",
    "Grupo L",
    "16 Avos de Final",
    "Oitavas de Final",
    "Quartas de Final",
    "Semifinal",
    "Disputa 3º Lugar",
    "Final"
  ];

  // DICIONÁRIO DE SELEÇÕES E BANDEIRAS PARA OS BÔNUS EXTRAS
  final Map<String, String> _teamsFlagsMap = {
    'México': '🇲🇽',
    'África do Sul': '🇿🇦',
    'Coreia do Sul': '🇰🇷',
    'República Tcheca': '🇨🇿',
    'Canadá': '🇨🇦',
    'Bósnia e Herzegovina': '🇧🇦',
    'Estados Unidos': '🇺🇸',
    'Paraguai': '🇵🇾',
    'Espanha': '🇪🇸',
    'Camboja': '🇰🇭',
    'França': '🇫🇷',
    'Irã': '🇮🇷',
    'Brasil': '🇧🇷',
    'Marrocos': '🇲🇦',
    'Escócia': '🏴󠁧󠁢󠁳󠁣󠁴󠁿',
    'Haiti': '🇭🇹',
    'Argentina': '🇦🇷',
    'Senegal': '🇸🇳',
    'Gana': '🇬🇭',
    'Croácia': '🇭🇷',
    'Bélgica': '🇧🇪',
    'Egito': '🇪🇬',
    'Tunísia': '🇹🇳',
    'Japão': '🇯🇵',
    'Suíça': '🇨🇭',
    'Catar': '🇶🇦',
    'Nigéria': '🇳🇬',
    'Uruguai': '🇺🇾',
    'Colômbia': '🇨🇴',
    'Portugal': '🇵🇹',
    'Cabo Verde': '🇨🇻',
    'Gales': '🏴󠁧󠁢󠁷󠁬󠁳󠁿',
    'Panamá': '🇵🇦',
    'Inglaterra': '🇬🇧',
    'Nova Zelândia': '🇳🇿',
    'Itália': '🇮🇹',
    'Argélia': '🇩🇿',
    'Jamaica': '🇯🇲',
    'Equador': '🇪🇨',
    'Holanda': '🇳🇱',
    'Alemanha': '🇩🇪',
    'Curaçau': '🇨🇼',
    'Costa do Marfim': '🇨🇮',
    'Austrália': '🇦🇺',
    'Arábia Saudita': '🇸🇦',
    'Honduras': '🇭🇳',
    'Peru': '🇵🇪',
    'Venezuela': '🇻🇪',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _debounce?.cancel();
    for (var c in _homeControllers.values) {
      c.dispose();
    }
    for (var c in _awayControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

// ===========================================================================
  // 🚨 MODAL DE REGRAS E PREMIAÇÃO
  // ===========================================================================
  void _showRulesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.rule, color: Color(0xFF1B5E20), size: 28),
                      SizedBox(width: 8),
                      Text("Regras do Bolão", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 20),
              
              const Text("💰 PREMIAÇÃO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
              const SizedBox(height: 4),
              const Text("O grande vencedor (1º Lugar do Ranking) leva 30% de TODO o valor arrecadado com as inscrições!", style: TextStyle(fontSize: 14)),
              
              const Divider(height: 30),
              
              const Text("⚽ PALPITES DOS JOGOS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
              const SizedBox(height: 4),
              const Text("• Na Mosca (Placar Exato): +5 Pontos\n• Vencedor + Saldo de Gols: +3 Pontos\n• Acerto Simples (Vencedor): +1 Ponto", style: TextStyle(fontSize: 14, height: 1.5)),
              const Text("💡 Dica de Empate: Se apostar 0x0 e o jogo terminar 1x1, você ganha 3 pontos! (Acertou o empate e o saldo de gols, que é zero).", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54)),
                                
              const Divider(height: 30),
              
              const Text("🏆 BÔNUS EXTRAS (Prazo: 11/06/26)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
              const SizedBox(height: 4),
              const Text("• O Grande Campeão: +20 Pontos\n• Vice-Campeão: +10 Pontos\n• Melhor Ataque: +10 Pontos\n• Pior Defesa: +10 Pontos\n• A Grande Decepção: +10 Pontos", style: TextStyle(fontSize: 14, height: 1.5)),
              
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("ENTENDI, VAMOS JOGAR!", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      }
    );
  }

  // --- AUTO-SAVE DOS PALPITES ---
  void _onScoreChanged(
      String matchId, String userId, BolaoPrediction? currentPred) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 1500), () async {
      final homeStr = _homeControllers[matchId]?.text ?? '';
      final awayStr = _awayControllers[matchId]?.text ?? '';

      if (homeStr.isNotEmpty && awayStr.isNotEmpty) {
        final newHomeScore = int.parse(homeStr);
        final newAwayScore = int.parse(awayStr);

        if (currentPred != null &&
            currentPred.scoreHome == newHomeScore &&
            currentPred.scoreAway == newAwayScore) {
          return; // Dirty check: não salva se for igual
        }

        try {
          await _bolaoService.savePrediction(
              userId, matchId, newHomeScore, newAwayScore);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text("Palpite Salvo! ($newHomeScore x $newAwayScore) ✔️"),
                  backgroundColor: Colors.green,
                  duration: const Duration(milliseconds: 1200)),
            );
          }
        } catch (e) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Erro ao salvar: $e"),
                backgroundColor: Colors.red));
        }
      }
    });
  }

  // --- GRAVAÇÃO DOS BÔNUS VIA CLOUD FUNCTION ---
  Future<void> _saveBonusPrediction(
      String userId, String field, String? value) async {
    if (value == null) return;
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('submitBolaoBonus');
      await callable.call({
        'field': field,
        'teamName': value,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Bônus salvo com sucesso! 🏆"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Erro: O prazo encerrou!"),
            backgroundColor: Colors.red));
    }
  }

  // --- SALVAR NOME DO RANKING ---
  Future<void> _updateProfileName(String userId) async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _isSavingName = true);
    try {
      await _bolaoService.saveUserName(userId, _nameController.text.trim());
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Nome atualizado no Ranking! 🇧🇷"),
            backgroundColor: Colors.green));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isSavingName = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<FantasyAuthService>(context);
    final user = authService.user;
    if (user == null)
      return const Scaffold(body: Center(child: Text("Sessão expirada.")));

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bolao_config')
          .doc('settings')
          .snapshots(),
      builder: (context, settingsSnapshot) {
        bool isGlobalLocked = true;
        if (settingsSnapshot.hasData && settingsSnapshot.data!.exists) {
          final settingsData =
              settingsSnapshot.data!.data() as Map<String, dynamic>?;
          if (settingsData != null &&
              settingsData.containsKey('is_predictions_open')) {
            isGlobalLocked = !(settingsData['is_predictions_open'] as bool);
          }
        }

       return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text("Bolão Copa do Mundo", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            backgroundColor: const Color(0xFF1B5E20),
            iconTheme: const IconThemeData(color: Colors.white),
            
            // 🚨 ADICIONE O ACTIONS AQUI:
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.amber),
                tooltip: "Regras e Premiação",
                onPressed: () => _showRulesModal(context),
              )
            ],

            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.amber,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: "Palpites"),
                Tab(text: "Bônus Extras"),
                Tab(text: "Ranking Geral"),
              ],
            ),
          ),
          body: Column(
            children: [
              if (isGlobalLocked && _tabController.index != 2)
                Container(
                  width: double.infinity,
                  color: Colors.red[800],
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  child: const Row(
                    children: [
                      Icon(Icons.lock, color: Colors.white, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                          child: Text("MERCADO GERAL FECHADO PELO ADMIN!",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
              if (_tabController.index == 0) _buildFilterBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMatchesTab(user.uid, isGlobalLocked),
                    _buildBonusTab(user.uid, isGlobalLocked),
                    _buildRankingTab(user.uid),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // WIDGETS DA TELA
  // ===========================================================================

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _buildFilterChip("Todos", _selectedStatusFilter == "Todos",
                (selected) {
              if (selected) setState(() => _selectedStatusFilter = "Todos");
            }),
            _buildFilterChip("Em Aberto", _selectedStatusFilter == "Em Aberto",
                (selected) {
              if (selected) setState(() => _selectedStatusFilter = "Em Aberto");
            }),
            _buildFilterChip(
                "Encerrados", _selectedStatusFilter == "Encerrados",
                (selected) {
              if (selected)
                setState(() => _selectedStatusFilter = "Encerrados");
            }),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                  height: 20,
                  child:
                      VerticalDivider(thickness: 1.5, color: Colors.black12)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: _selectedPhaseFilter != "Todas as Fases"
                      ? const Color(0xFF1B5E20).withOpacity(0.1)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _selectedPhaseFilter != "Todas as Fases"
                          ? const Color(0xFF1B5E20)
                          : Colors.black12)),
              child: DropdownButton<String>(
                value: _selectedPhaseFilter,
                underline: const SizedBox(),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _selectedPhaseFilter != "Todas as Fases"
                        ? const Color(0xFF1B5E20)
                        : Colors.black87),
                icon: Icon(Icons.arrow_drop_down,
                    color: _selectedPhaseFilter != "Todas as Fases"
                        ? const Color(0xFF1B5E20)
                        : Colors.black54),
                items: _phaseOptions
                    .map((phase) =>
                        DropdownMenuItem(value: phase, child: Text(phase)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedPhaseFilter = val);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
      String label, bool isSelected, ValueChanged<bool> onSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: const Color(0xFF1B5E20),
        backgroundColor: Colors.grey[100],
        onSelected: onSelected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(
            color: isSelected ? const Color(0xFF1B5E20) : Colors.black12),
        showCheckmark: false,
      ),
    );
  }

  // ===========================================================================
  // 🚨 MODAL DE EDIÇÃO MULTIPLATAFORMA (Suporta Web, Android e iOS)
  // ===========================================================================
  Future<void> _showEditProfileModal(BolaoUser bUser, String userId) async {
    final nameCtrl = TextEditingController(text: bUser.name == 'Utilizador' ? '' : bUser.name);
    final cpfCtrl = TextEditingController(text: bUser.cpf);
    final phoneCtrl = TextEditingController(text: bUser.phone);
    
    // Usamos Uint8List em vez de File para funcionar na Web!
    Uint8List? selectedImageBytes; 
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Perfil do Treinador", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // FOTO DE PERFIL
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                        if (pickedFile != null) {
                          // Lê a imagem em bytes (Funciona no telemóvel e na Web!)
                          final bytes = await pickedFile.readAsBytes();
                          setModalState(() => selectedImageBytes = bytes);
                        }
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey.shade200,
                            // Usa MemoryImage para exibir os bytes da imagem
                            backgroundImage: selectedImageBytes != null 
                              ? MemoryImage(selectedImageBytes!) as ImageProvider
                              : (bUser.photoUrl != null ? NetworkImage(bUser.photoUrl!) : null),
                            child: (selectedImageBytes == null && bUser.photoUrl == null)
                                ? const Icon(Icons.person, size: 50, color: Colors.grey)
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Color(0xFF1B5E20), shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // CAMPOS DE TEXTO
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: "Nome / Nome do Time", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: cpfCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "CPF (Para recebimento de prêmios)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: "WhatsApp / Telefone", border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                  ),
                  const Spacer(),

                  // BOTÃO DE SALVAR
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: isSaving ? null : () async {
                        if (nameCtrl.text.isEmpty || cpfCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha todos os campos!"), backgroundColor: Colors.orange));
                          return;
                        }

                        setModalState(() => isSaving = true);
                        try {
                          String? finalPhotoUrl;

                          // 1. Faz upload usando putData (para bytes)
                          if (selectedImageBytes != null) {
                            final ref = FirebaseStorage.instance.ref().child('bolao_avatars').child('$userId.jpg');
                            await ref.putData(selectedImageBytes!); // Usa putData em vez de putFile
                            finalPhotoUrl = await ref.getDownloadURL();
                          }

                          // 2. Salva os dados no Firestore
                          await _bolaoService.saveFullUserProfile(userId, nameCtrl.text.trim(), cpfCtrl.text.trim(), phoneCtrl.text.trim(), finalPhotoUrl);
                          
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Perfil atualizado! 🏆"), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
                        } finally {
                          setModalState(() => isSaving = false);
                        }
                      },
                      child: isSaving 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : const Text("SALVAR PERFIL COMPLETO", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          }
        );
      }
    );
  }

  // ===========================================================================
  // 🚨 CARTÃO DE CABEÇALHO INTERATIVO
  // ===========================================================================
  Widget _buildUserHeader(String userId, bool isGlobalLocked) {
    return StreamBuilder<BolaoUser?>(
      stream: _bolaoService.streamBolaoUser(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const SizedBox(
              height: 100, child: Center(child: CircularProgressIndicator()));

        // Se o utilizador ainda não existir no banco de dados, cria um mock básico
        final bUser =
            snapshot.data ?? BolaoUser(userId: userId, name: "Participante");

        final bool isProfileIncomplete = bUser.cpf == null ||
            bUser.cpf!.isEmpty ||
            bUser.phone == null ||
            bUser.phone!.isEmpty;

        return GestureDetector(
          onTap: () => _showEditProfileModal(bUser, userId),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14, left: 4, right: 4),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.green.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 6))
              ],
            ),
            child: Row(
              children: [
                // FOTO DE PERFIL NO CABEÇALHO
                Container(
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber, width: 2.5)),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    backgroundImage: bUser.photoUrl != null
                        ? NetworkImage(bUser.photoUrl!)
                        : null,
                    child: bUser.photoUrl == null
                        ? const Icon(Icons.sports_soccer,
                            color: Color(0xFF1B5E20), size: 30)
                        : null,
                  ),
                ),
                const SizedBox(width: 16),

                // INFORMAÇÕES E STATUS DO CADASTRO
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("TREINADOR FJF OFICIAL",
                          style: TextStyle(
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 4),
                      Text(
                        bUser.name == 'Utilizador'
                            ? 'Defina seu Nome'
                            : bUser.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),

                      // SELO DE CADASTRO
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: isProfileIncomplete
                                ? Colors.orangeAccent.withOpacity(0.2)
                                : Colors.greenAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: isProfileIncomplete
                                    ? Colors.orangeAccent
                                    : Colors.greenAccent)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                isProfileIncomplete
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle,
                                size: 12,
                                color: isProfileIncomplete
                                    ? Colors.orangeAccent
                                    : Colors.greenAccent),
                            const SizedBox(width: 4),
                            Text(
                              isProfileIncomplete
                                  ? "Completar Cadastro"
                                  : "Cadastro Completo",
                              style: TextStyle(
                                  color: isProfileIncomplete
                                      ? Colors.orangeAccent
                                      : Colors.greenAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const Icon(Icons.edit, color: Colors.white54, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMatchesTab(String userId, bool isGlobalLocked) {
    return StreamBuilder<List<BolaoMatch>>(
      stream: _bolaoService.streamMatches(),
      builder: (context, matchSnapshot) {
        if (matchSnapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!matchSnapshot.hasData || matchSnapshot.data!.isEmpty)
          return const Center(child: Text("Nenhum jogo cadastrado."));

        final rawMatches = matchSnapshot.data!;
        rawMatches.sort((a, b) => a.date.compareTo(b.date));

        return StreamBuilder<List<BolaoPrediction>>(
          stream: _bolaoService.streamMyPredictions(userId),
          builder: (context, predSnapshot) {
            final predictions = predSnapshot.data ?? [];
            final Map<String, BolaoPrediction> predMap = {
              for (var p in predictions) p.matchId: p
            };

            List<BolaoMatch> filteredMatches = rawMatches.where((match) {
              if (_selectedPhaseFilter != "Todas as Fases" &&
                  match.group != _selectedPhaseFilter) {
                return false;
              }

              final bool isFinished = match.status == 'finished';
              final now = DateTime.now();
              final earliestMatch = match
                  .date; // Simplificação para filtro, agrupamento resolve precisão do dia
              final bool isDayLockedLocally = now
                  .isAfter(earliestMatch.subtract(const Duration(minutes: 30)));
              final bool isLocked =
                  isGlobalLocked || isDayLockedLocally || isFinished;

              if (_selectedStatusFilter == "Em Aberto" && isLocked)
                return false;
              if (_selectedStatusFilter == "Encerrados" && !isLocked)
                return false;

              return true;
            }).toList();

            final Map<String, List<BolaoMatch>> matchesByDate = {};
            for (var match in filteredMatches) {
              final dateKey =
                  "${match.date.day.toString().padLeft(2, '0')}/${match.date.month.toString().padLeft(2, '0')}/${match.date.year}";
              if (!matchesByDate.containsKey(dateKey))
                matchesByDate[dateKey] = [];
              matchesByDate[dateKey]!.add(match);
            }

            final List<dynamic> listItems = [];
            final now = DateTime.now();

            for (var dateKey in matchesByDate.keys) {
              final matchesForDay = matchesByDate[dateKey]!;
              final earliestMatch = matchesForDay.first.date;
              final bool isDayLockedLocally = now
                  .isAfter(earliestMatch.subtract(const Duration(minutes: 30)));

              listItems.add({
                'type': 'header',
                'title': dateKey,
                'isDayLocked': isDayLockedLocally
              });
              for (var match in matchesForDay) {
                listItems.add({
                  'type': 'match',
                  'match': match,
                  'isDayLocked': isDayLockedLocally
                });
              }
            }

            if (listItems.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildUserHeader(userId, isGlobalLocked),
                  const SizedBox(height: 40),
                  const Center(
                      child: Text(
                          "Nenhum jogo corresponde aos filtros selecionados.",
                          style: TextStyle(color: Colors.grey))),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: listItems.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _buildUserHeader(userId, isGlobalLocked);

                final item = listItems[index - 1];

                if (item['type'] == 'header') {
                  final bool locked = item['isDayLocked'] || isGlobalLocked;
                  return Container(
                    margin: const EdgeInsets.only(
                        top: 20, bottom: 10, left: 4, right: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                        color:
                            locked ? Colors.red.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: locked
                                ? Colors.red.shade200
                                : Colors.green.shade200,
                            width: 1)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          locked
                              ? "Dia ${item['title']} - TRANCADO"
                              : "Dia ${item['title']} - PALPITES ABERTOS",
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: locked
                                  ? Colors.red[800]
                                  : const Color(0xFF1B5E20)),
                        ),
                        Icon(locked ? Icons.lock : Icons.lock_open,
                            size: 18,
                            color: locked
                                ? Colors.red[800]
                                : const Color(0xFF1B5E20))
                      ],
                    ),
                  );
                }

                final match = item['match'] as BolaoMatch;
                final myPred = predMap[match.id];

                if (!_homeControllers.containsKey(match.id)) {
                  _homeControllers[match.id] = TextEditingController();
                  _awayControllers[match.id] = TextEditingController();
                }

                if (myPred != null) {
                  if (_homeControllers[match.id]!.text.isEmpty)
                    _homeControllers[match.id]!.text =
                        myPred.scoreHome.toString();
                  if (_awayControllers[match.id]!.text.isEmpty)
                    _awayControllers[match.id]!.text =
                        myPred.scoreAway.toString();
                }

                final bool isMatchLocked = isGlobalLocked ||
                    item['isDayLocked'] ||
                    match.status != 'pending';
                return _buildMatchCard(match, userId, isMatchLocked, myPred);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMatchCard(
      BolaoMatch match, String userId, bool isLocked, BolaoPrediction? myPred) {
    final bool isFinished = match.status == 'finished';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(match.group,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                          fontSize: 10)),
                ),
                Row(
                  children: [
                    Text(
                        "${match.date.hour.toString().padLeft(2, '0')}:${match.date.minute.toString().padLeft(2, '0')}",
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold)),
                    if (isFinished) ...[
                      const SizedBox(width: 8),
                      const Text("• ENCERRADO",
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.redAccent)),
                    ]
                  ],
                ),
              ],
            ),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                    child: Column(children: [
                  Text(match.homeFlagUrl, style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 4),
                  Text(match.homeTeam,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14))
                ])),
                isFinished
                    ? _buildFinishedResult(match, myPred)
                    : Row(
                        children: [
                          _buildScoreInput(_homeControllers[match.id]!,
                              isLocked, match.id, userId, myPred),
                          const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text("X",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black38,
                                      fontSize: 16))),
                          _buildScoreInput(_awayControllers[match.id]!,
                              isLocked, match.id, userId, myPred),
                        ],
                      ),
                Expanded(
                    child: Column(children: [
                  Text(match.awayFlagUrl, style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 4),
                  Text(match.awayTeam,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14))
                ])),
              ],
            ),
            if (isLocked && !isFinished)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_outline, size: 12, color: Colors.black45),
                  SizedBox(width: 4),
                  Text("BLOQUEADO",
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black45))
                ]),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildFinishedResult(BolaoMatch match, BolaoPrediction? myPred) {
    final bool hasPredicted = myPred != null;
    final int points = myPred?.pointsEarned ?? 0;

    Color badgeColor = Colors.grey.shade200;
    Color textColor = Colors.black87;

    if (points == 5) {
      badgeColor = Colors.green.shade100;
      textColor = Colors.green.shade900;
    } else if (points > 0) {
      badgeColor = Colors.blue.shade50;
      textColor = Colors.blue.shade900;
    } else if (hasPredicted) {
      badgeColor = Colors.red.shade50;
      textColor = Colors.red.shade900;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.black87, borderRadius: BorderRadius.circular(8)),
          child: Text(
            "${match.realScoreHome ?? '-'}  x  ${match.realScoreAway ?? '-'}",
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: textColor.withOpacity(0.3))),
          child: Column(
            children: [
              Text(
                hasPredicted
                    ? "Seu Palpite: ${myPred!.scoreHome} x ${myPred.scoreAway}"
                    : "Você não palpitou",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: textColor),
              ),
              if (hasPredicted)
                Text(
                  points == 5
                      ? "Na Mosca! +5 Pts"
                      : (points > 0 ? "Ganhou +$points Pts" : "Não pontuou"),
                  style: TextStyle(fontSize: 10, color: textColor),
                ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildScoreInput(TextEditingController controller, bool isLocked,
      String matchId, String userId, BolaoPrediction? myPred) {
    return SizedBox(
      width: 44,
      height: 44,
      child: TextField(
        controller: controller,
        enabled: !isLocked,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 2,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
            counterText: "",
            filled: true,
            fillColor: isLocked ? Colors.grey.shade100 : Colors.white,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
        onChanged: (_) => _onScoreChanged(matchId, userId, myPred),
      ),
    );
  }

  // --- NOVA ABA DE BÔNUS (Com Filtro de Cabeças de Chave) ---
  Widget _buildBonusTab(String userId, bool isGlobalLocked) {
    // Prazo: 30 minutos antes de 11/06/2026 às 21:00 UTC (Abertura oficial)
    final deadline = DateTime.utc(2026, 6, 11, 20, 30, 00); 
    final bool isTimeOver = DateTime.now().toUtc().isAfter(deadline);
    final bool isBonusLocked = isTimeOver; 

    return StreamBuilder<BolaoUser?>(
      stream: _bolaoService.streamBolaoUser(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final bolaoUser = snapshot.data;
        
        // 1. Lista com todas as seleções para a maioria dos prêmios
        final List<String> availableTeams = _teamsFlagsMap.keys.toList()..sort();
        
        // 2. 🚨 LISTA EXCLUSIVA DE CABEÇAS DE CHAVE (Para a Grande Decepção)
        final List<String> seededTeams = [
          'Alemanha', 'Argentina', 'Bélgica', 'Brasil', 'Canadá', 
          'Espanha', 'Estados Unidos', 'França', 'Holanda', 
          'Inglaterra', 'México', 'Portugal'
        ];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: isBonusLocked ? Colors.red.shade50 : Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: isBonusLocked ? Colors.red.shade200 : Colors.amber.shade300)),
              child: Text(
                isBonusLocked ? "🔒 Opções Extras Trancadas Definitivamente!" : "Atenção: Estes palpites trancam 30 minutos antes do 1º jogo da Copa (11/06/2026). Pense bem!", 
                style: TextStyle(color: isBonusLocked ? Colors.red[800] : Colors.orange[800], fontWeight: FontWeight.bold), textAlign: TextAlign.center
              ),
            ),
            const SizedBox(height: 20),

            _buildBonusDropdown(
              title: "O Grande Campeão (20 pts)",
              description: "Qual seleção irá levantar a taça e sagrar-se campeã do mundo?",
              icon: Icons.emoji_events,
              currentValue: bolaoUser?.champion,
              isLocked: isBonusLocked,
              availableTeams: availableTeams,
              onChanged: (val) => _saveBonusPrediction(userId, 'bonus_champion', val),
            ),
            const SizedBox(height: 12),
            _buildBonusDropdown(
              title: "O Vice-Campeão (10 pts)",
              description: "Qual seleção chegará à Grande Final, mas irá perder o título?",
              icon: Icons.looks_two,
              currentValue: bolaoUser?.runnerUp,
              isLocked: isBonusLocked,
              availableTeams: availableTeams,
              onChanged: (val) => _saveBonusPrediction(userId, 'bonus_runner_up', val),
            ),
            const SizedBox(height: 12),
            _buildBonusDropdown(
              title: "Melhor Ataque (10 pts)",
              description: "A seleção que marcar o maior número de gols no total da Copa.",
              icon: Icons.sports_soccer,
              currentValue: bolaoUser?.bestOffense,
              isLocked: isBonusLocked,
              availableTeams: availableTeams,
              onChanged: (val) => _saveBonusPrediction(userId, 'bonus_best_offense', val),
            ),
            const SizedBox(height: 12),
            _buildBonusDropdown(
              title: "A Pior Defesa (10 pts)",
              description: "O 'Saco de Pancadas'. A seleção que sofrer o maior número de gols.",
              icon: Icons.shield,
              currentValue: bolaoUser?.worstDefense,
              isLocked: isBonusLocked,
              availableTeams: availableTeams,
              onChanged: (val) => _saveBonusPrediction(userId, 'bonus_worst_defense', val),
            ),
            const SizedBox(height: 12),
            _buildBonusDropdown(
              title: "A Grande Decepção (10 pts)",
              description: "O Fiasco. A primeira seleção 'Cabeça de Chave' a ser eliminada do torneio.",
              icon: Icons.trending_down,
              currentValue: bolaoUser?.disappointment,
              isLocked: isBonusLocked,
              availableTeams: seededTeams, // 🚨 Passamos apenas os 12 Cabeças de Chave aqui!
              onChanged: (val) => _saveBonusPrediction(userId, 'bonus_disappointment', val),
            ),
            const SizedBox(height: 30),
          ],
        );
      },
    );
  }

  Widget _buildBonusDropdown({
    required String title,
    required String description,
    required IconData icon,
    required String? currentValue,
    required bool isLocked,
    required List<String> availableTeams,
    required Function(String?) onChanged,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: Colors.amber.shade700, size: 24),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16))
            ]),
            const SizedBox(height: 6),
            Text(description,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              // 🚨 CORREÇÃO: isExpanded define um limite seguro para o menu não quebrar o layout!
              isExpanded: true,

              value:
                  availableTeams.contains(currentValue) ? currentValue : null,
              disabledHint: currentValue != null
                  ? Row(children: [
                      Text(_teamsFlagsMap[currentValue] ?? '❓',
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(currentValue,
                              style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis))
                    ])
                  : const Text("Bloqueado (Sem Palpite)",
                      style: TextStyle(color: Colors.red)),
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: isLocked,
                fillColor: Colors.grey.shade100,
              ),
              items: isLocked
                  ? null
                  : availableTeams.map((team) {
                      return DropdownMenuItem(
                        value: team,
                        child: Row(
                          children: [
                            Text(_teamsFlagsMap[team] ?? '❓',
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(team,
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    }).toList(),
              onChanged: isLocked ? null : onChanged,
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRankingTab(String currentUserId) {
    return FutureBuilder<List<BolaoUser>>(
      future: FirebaseFirestore.instance
          .collection('bolao_users')
          .get()
          .then((snap) {
        final users = snap.docs
            .map((d) =>
                BolaoUser.fromFirestore(d, d.data()['name'] ?? 'Participante'))
            .toList();

        users.sort((a, b) {
          int cmp = b.totalPoints.compareTo(a.totalPoints);
          if (cmp != 0) return cmp;
          cmp = b.exactHits.compareTo(a.exactHits);
          if (cmp != 0) return cmp;
          cmp = b.goalDifferenceHits.compareTo(a.goalDifferenceHits);
          if (cmp != 0) return cmp;
          cmp = b.winnerHits.compareTo(a.winnerHits);
          if (cmp != 0) return cmp;
          return b.bonusPoints.compareTo(a.bonusPoints);
        });
        return users;
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty)
          return const Center(
              child: Text("Nenhum participante pontuou ainda."));

        final leaderboard = snapshot.data!;

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: leaderboard.length,
            itemBuilder: (context, index) {
              final participant = leaderboard[index];
              final bool isMe = participant.userId == currentUserId;
              final int rank = index + 1;

              return Card(
                color: isMe ? Colors.green[50] : Colors.white,
                elevation: isMe ? 4 : 1,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isMe
                        ? const BorderSide(color: Color(0xFF1B5E20), width: 1.5)
                        : BorderSide.none),
                child: ExpansionTile(
                  // Na _buildRankingTab, substitua o CircleAvatar atual por este:
                  leading: CircleAvatar(
                    backgroundColor: rank == 1
                        ? Colors.amber
                        : (rank == 2
                            ? Colors.grey[400]
                            : (rank == 3
                                ? Colors.brown[400]
                                : Colors.grey[200])),
                    backgroundImage: participant.photoUrl != null
                        ? NetworkImage(participant.photoUrl!)
                        : null,
                    child: participant.photoUrl == null
                        ? Text("$rankº",
                            style: TextStyle(
                                color:
                                    rank <= 3 ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold))
                        : null,
                  ),
                  title: Text(participant.name,
                      style: TextStyle(
                          fontWeight:
                              isMe ? FontWeight.bold : FontWeight.w500)),
                  trailing: Text("${participant.totalPoints} pts",
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1B5E20))),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey[50],
                      child: Column(
                        children: [
                          _buildRankingStatRow("Pontuação Total Real",
                              "${participant.totalPoints} pts", Colors.black87,
                              isBold: true),
                          const Divider(),
                          _buildRankingStatRow("1º Placar Exato (Na Mosca)",
                              "${participant.exactHits} acertos", Colors.green),
                          const Divider(),
                          _buildRankingStatRow(
                              "2º Acerto de Vencedor + Saldo",
                              "${participant.goalDifferenceHits} acertos",
                              Colors.blue),
                          const Divider(),
                          _buildRankingStatRow(
                              "3º Acerto Simples de Vencedor",
                              "${participant.winnerHits} acertos",
                              Colors.orange),
                          const Divider(),
                          _buildRankingStatRow(
                              "4º Pontos Extras (Bônus Finais)",
                              "${participant.bonusPoints} pts",
                              Colors.purple),
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRankingStatRow(String label, String value, Color color,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w400,
                  color: Colors.black54)),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
