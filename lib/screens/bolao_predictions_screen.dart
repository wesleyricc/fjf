import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/bolao_service.dart';
import '../../models/bolao_models.dart';
import 'dart:typed_data'; 
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import 'package:url_launcher/url_launcher.dart';

class BolaoPredictionsScreen extends StatefulWidget {
  const BolaoPredictionsScreen({super.key});

  @override
  State<BolaoPredictionsScreen> createState() => _BolaoPredictionsScreenState();
}

class _BolaoPredictionsScreenState extends State<BolaoPredictionsScreen> with SingleTickerProviderStateMixin {
  final BolaoService _bolaoService = BolaoService();
  late TabController _tabController;

  final Map<String, TextEditingController> _homeControllers = {};
  final Map<String, TextEditingController> _awayControllers = {};
  final TextEditingController _nameController = TextEditingController();

  Timer? _debounce;
  late String _userId;

  // 🚨 VARIÁVEIS DE CACHE (Evita que a tela pisque ao trocar de abas)
  late Stream<DocumentSnapshot> _settingsStream;
  late Stream<BolaoUser?> _userStream;
  late Future<List<BolaoMatch>> _matchesFuture;
  late Future<List<BolaoPrediction>> _predictionsFuture;

  // VARIÁVEIS DE ESTADO DOS FILTROS
  String _selectedStatusFilter = "Todos";
  String _selectedPhaseFilter = "Todas as Fases";

  final List<String> _phaseOptions = [
    "Todas as Fases", "Grupo A", "Grupo B", "Grupo C", "Grupo D", "Grupo E", "Grupo F",
    "Grupo G", "Grupo H", "Grupo I", "Grupo J", "Grupo K", "Grupo L", "16 Avos de Final",
    "Oitavas de Final", "Quartas de Final", "Semifinal", "Disputa 3º Lugar", "Final"
  ];

  final Map<String, String> _teamsFlagsMap = {
    'México': '🇲🇽', 'África do Sul': '🇿🇦', 'Coreia do Sul': '🇰🇷', 'República Tcheca': '🇨🇿',
    'Canadá': '🇨🇦', 'Bósnia e Herzegovina': '🇧🇦', 'Estados Unidos': '🇺🇸', 'Paraguai': '🇵🇾',
    'Espanha': '🇪🇸', 'Camboja': '🇰🇭', 'França': '🇫🇷', 'Irã': '🇮🇷', 'Brasil': '🇧🇷',
    'Marrocos': '🇲🇦', 'Escócia': '🏴󠁧󠁢󠁳󠁣󠁴󠁿', 'Haiti': '🇭🇹', 'Argentina': '🇦🇷', 'Senegal': '🇸🇳',
    'Gana': '🇬🇭', 'Croácia': '🇭🇷', 'Bélgica': '🇧🇪', 'Egito': '🇪🇬', 'Tunísia': '🇹🇳',
    'Japão': '🇯🇵', 'Suíça': '🇨🇭', 'Catar': '🇶🇦', 'Nigéria': '🇳🇬', 'Uruguai': '🇺🇾',
    'Colômbia': '🇨🇴', 'Portugal': '🇵🇹', 'Cabo Verde': '🇨🇻', 'Gales': '🏴󠁧󠁢󠁷󠁬󠁳󠁿',
    'Panamá': '🇵🇦', 'Inglaterra': '🇬🇧', 'Nova Zelândia': '🇳🇿', 'Itália': '🇮🇹',
    'Argélia': '🇩🇿', 'Jamaica': '🇯🇲', 'Equador': '🇪🇨', 'Holanda': '🇳🇱', 'Alemanha': '🇩🇪',
    'Curaçau': '🇨🇼', 'Costa do Marfim': '🇨🇮', 'Austrália': '🇦🇺', 'Arábia Saudita': '🇸🇦',
    'Honduras': '🇭🇳', 'Peru': '🇵🇪', 'Venezuela': '🇻🇪',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Atualiza a tela para ocultar/mostrar filtros na aba correta
    });

    // 🚨 INICIALIZAÇÃO ÚNICA DOS STREAMS (Impede os "piscos" na tela)
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    _userId = authService.user?.uid ?? '';
    
    _settingsStream = FirebaseFirestore.instance.collection('bolao_config').doc('settings').snapshots();
    _userStream = _bolaoService.streamBolaoUser(_userId);
    _matchesFuture = _bolaoService.getMatches();
    _predictionsFuture = _bolaoService.getMyPredictions(_userId);
  }

  @override
  void dispose() {
    BolaoService.commitPendingPredictions(); 
    _tabController.dispose();
    _nameController.dispose();
    _debounce?.cancel();
    for (var c in _homeControllers.values) c.dispose();
    for (var c in _awayControllers.values) c.dispose();
    super.dispose();
  }

  // ===========================================================================
  // 🚨 ALERTAS, MODAIS E SUPORTE
  // ===========================================================================
  
  // 🚨 NOVA FUNÇÃO: Redirecionamento para o WhatsApp
  Future<void> _contactSupport() async {
    // Utilizando o mesmo número de suporte configurado no app
    final Uri url = Uri.parse("https://wa.me/5548996381626?text=Ol%C3%A1%2C%20preciso%20de%20suporte%20no%20Bol%C3%A3o%20da%20FJF");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Não foi possível abrir o WhatsApp.");
    }
  }

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
              const Text("💡 Dica de Empate: Se apostar 0x0 e o jogo terminar 1x1, você ganha 3 pontos!", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54)),
              const Divider(height: 30),
              const Text("🏆 BÔNUS EXTRAS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
              const SizedBox(height: 4),
              const Text("• O Grande Campeão: +20 Pontos\n• Vice-Campeão: +10 Pontos\n• Melhor Ataque: +10 Pontos\n• Pior Defesa: +10 Pontos\n• A Grande Decepção: +10 Pontos", style: TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 30),
              
              // 🚨 NOVO BOTÃO DE SUPORTE NO WHATSAPP
              SizedBox(
                width: double.infinity, height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1B5E20),
                    side: const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  icon: const Icon(Icons.support_agent),
                  label: const Text("PRECISO DE SUPORTE", style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context); // Fecha o modal
                    _contactSupport();      // Abre o WhatsApp
                  },
                ),
              ),
              const SizedBox(height: 12),
              
              SizedBox(
                width: double.infinity, height: 50,
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

  void _showProfileRequiredDialog(BolaoUser currentUser) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 8), Text("Cadastro Incompleto")]),
        content: const Text("Para garantir a segurança e a correta entrega dos prêmios em dinheiro ao final da Copa, você precisa completar o seu cadastro (Nome, CPF e WhatsApp) antes de começar a palpitar."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Agora não", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _showEditProfileModal(currentUser, currentUser.userId); 
            },
            child: const Text("Completar Cadastro"),
          ),
        ],
      ),
    );
  }

  // --- AUTO-SAVE DOS PALPITES ---
  void _onScoreChanged(String matchId, String userId, BolaoPrediction? currentPred) {
    final homeStr = _homeControllers[matchId]?.text ?? '';
    final awayStr = _awayControllers[matchId]?.text ?? '';

    if (homeStr.isNotEmpty && awayStr.isNotEmpty) {
      final newHomeScore = int.parse(homeStr);
      final newAwayScore = int.parse(awayStr);

      if (currentPred != null && currentPred.scoreHome == newHomeScore && currentPred.scoreAway == newAwayScore) return; 

      _bolaoService.savePrediction(userId, matchId, newHomeScore, newAwayScore);
    }
  }

  Future<void> _saveBonusPrediction(String userId, String field, String? value) async {
    if (value == null) return;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('submitBolaoBonus');
      await callable.call({'field': field, 'teamName': value});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bônus salvo com sucesso! 🏆"), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erro: O prazo encerrou!"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId.isEmpty) return const Scaffold(body: Center(child: Text("Sessão expirada.")));

    return StreamBuilder<DocumentSnapshot>(
      stream: _settingsStream, // Usando a variável isolada no initState
      builder: (context, settingsSnapshot) {
        bool isGlobalLocked = true;
        if (settingsSnapshot.hasData && settingsSnapshot.data!.exists) {
          final settingsData = settingsSnapshot.data!.data() as Map<String, dynamic>?;
          if (settingsData != null && settingsData.containsKey('is_predictions_open')) {
            isGlobalLocked = !(settingsData['is_predictions_open'] as bool);
          }
        }

        return StreamBuilder<BolaoUser?>(
          stream: _userStream, // Usando a variável isolada no initState
          builder: (context, userSnapshot) {
            final currentUser = userSnapshot.data;

            return Scaffold(
              backgroundColor: Colors.grey[100],
              appBar: AppBar(
                title: const Text("Bolão Copa do Mundo", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                backgroundColor: const Color(0xFF1B5E20),
                iconTheme: const IconThemeData(color: Colors.white),
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
                      width: double.infinity, color: Colors.red[800], padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      child: const Row(children: [Icon(Icons.lock, color: Colors.white, size: 20), SizedBox(width: 12), Expanded(child: Text("MERCADO GERAL FECHADO PELO ADMIN!", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))]),
                    ),
                  
                  if (_tabController.index == 0) 
                    _buildFilterBar(),
                  
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildMatchesTab(_userId, isGlobalLocked, currentUser),
                        _buildBonusTab(_userId, isGlobalLocked, currentUser),
                        _BolaoRankingTab(currentUserId: _userId),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  // ===========================================================================
  // WIDGETS DA TELA E FILTROS
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
            _buildFilterChip("Todos", _selectedStatusFilter == "Todos", (selected) { if (selected) setState(() => _selectedStatusFilter = "Todos"); }),
            _buildFilterChip("Em Aberto", _selectedStatusFilter == "Em Aberto", (selected) { if (selected) setState(() => _selectedStatusFilter = "Em Aberto"); }),
            _buildFilterChip("Encerrados", _selectedStatusFilter == "Encerrados", (selected) { if (selected) setState(() => _selectedStatusFilter = "Encerrados"); }),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(height: 20, child: VerticalDivider(thickness: 1.5, color: Colors.black12)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: _selectedPhaseFilter != "Todas as Fases" ? const Color(0xFF1B5E20).withOpacity(0.1) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _selectedPhaseFilter != "Todas as Fases" ? const Color(0xFF1B5E20) : Colors.black12)
              ),
              child: DropdownButton<String>(
                value: _selectedPhaseFilter, underline: const SizedBox(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _selectedPhaseFilter != "Todas as Fases" ? const Color(0xFF1B5E20) : Colors.black87),
                icon: Icon(Icons.arrow_drop_down, color: _selectedPhaseFilter != "Todas as Fases" ? const Color(0xFF1B5E20) : Colors.black54),
                items: _phaseOptions.map((phase) => DropdownMenuItem(value: phase, child: Text(phase))).toList(),
                onChanged: (val) { if (val != null) setState(() => _selectedPhaseFilter = val); },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, ValueChanged<bool> onSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected, selectedColor: const Color(0xFF1B5E20), backgroundColor: Colors.grey[100],
        onSelected: onSelected, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: isSelected ? const Color(0xFF1B5E20) : Colors.black12), showCheckmark: false,
      ),
    );
  }

  // ===========================================================================
  // 🚨 MODAL DE EDIÇÃO DE PERFIL
  // ===========================================================================
  Future<void> _showEditProfileModal(BolaoUser bUser, String userId) async {
    final nameCtrl = TextEditingController(text: bUser.name == 'Utilizador' ? '' : bUser.name);
    final cpfCtrl = TextEditingController(text: bUser.cpf);
    final phoneCtrl = TextEditingController(text: bUser.phone);
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
                  
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                        if (pickedFile != null) {
                          final bytes = await pickedFile.readAsBytes();
                          setModalState(() => selectedImageBytes = bytes);
                        }
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50, backgroundColor: Colors.grey.shade200,
                            backgroundImage: selectedImageBytes != null ? MemoryImage(selectedImageBytes!) as ImageProvider : (bUser.photoUrl != null ? NetworkImage(bUser.photoUrl!) : null),
                            child: (selectedImageBytes == null && bUser.photoUrl == null) ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                          ),
                          Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0xFF1B5E20), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 20))
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nome / Nome do Time", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
                  const SizedBox(height: 16),
                  TextField(controller: cpfCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "CPF (Para recebimento de prêmios)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))),
                  const SizedBox(height: 16),
                  TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "WhatsApp / Telefone", border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
                  const Spacer(),

                  SizedBox(
                    width: double.infinity, height: 50,
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
                          if (selectedImageBytes != null) {
                            final ref = FirebaseStorage.instance.ref().child('bolao_avatars').child('$userId.jpg');
                            await ref.putData(selectedImageBytes!); 
                            finalPhotoUrl = await ref.getDownloadURL();
                          }
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
                      child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SALVAR PERFIL COMPLETO", style: TextStyle(fontWeight: FontWeight.bold)),
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
  // ABA 1: PARTIDAS
  // ===========================================================================
  Widget _buildMatchesTab(String userId, bool isGlobalLocked, BolaoUser? currentUser) {
    return FutureBuilder<List<BolaoMatch>>(
      future: _matchesFuture, // Chamado através da variável preservada no initState
      builder: (context, matchSnapshot) {
        if (matchSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!matchSnapshot.hasData || matchSnapshot.data!.isEmpty) return const Center(child: Text("Nenhum jogo cadastrado."));

        final rawMatches = matchSnapshot.data!;
        rawMatches.sort((a, b) => a.date.compareTo(b.date));

        return FutureBuilder<List<BolaoPrediction>>(
          future: _predictionsFuture, // Chamado através da variável preservada no initState
          builder: (context, predSnapshot) {
            if (predSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

            final predictions = predSnapshot.data ?? [];
            final Map<String, BolaoPrediction> predMap = { for (var p in predictions) p.matchId: p };

            List<BolaoMatch> filteredMatches = rawMatches.where((match) {
              if (_selectedPhaseFilter != "Todas as Fases" && match.group != _selectedPhaseFilter) return false;

              final bool isFinished = match.status == 'finished';
              final now = DateTime.now();
              final earliestMatch = match.date; 
              final bool isDayLockedLocally = now.isAfter(earliestMatch.subtract(const Duration(minutes: 30)));
              final bool isLocked = isGlobalLocked || isDayLockedLocally || isFinished;

              if (_selectedStatusFilter == "Em Aberto" && isLocked) return false;
              if (_selectedStatusFilter == "Encerrados" && !isLocked) return false;
              return true;
            }).toList();

            final Map<String, List<BolaoMatch>> matchesByDate = {};
            for (var match in filteredMatches) {
              final dateKey = "${match.date.day.toString().padLeft(2, '0')}/${match.date.month.toString().padLeft(2, '0')}/${match.date.year}";
              if (!matchesByDate.containsKey(dateKey)) matchesByDate[dateKey] = [];
              matchesByDate[dateKey]!.add(match);
            }

            final List<dynamic> listItems = [];
            final now = DateTime.now();

            for (var dateKey in matchesByDate.keys) {
              final matchesForDay = matchesByDate[dateKey]!;
              final earliestMatch = matchesForDay.first.date;
              final bool isDayLockedLocally = now.isAfter(earliestMatch.subtract(const Duration(minutes: 30)));

              listItems.add({'type': 'header', 'title': dateKey, 'isDayLocked': isDayLockedLocally});
              for (var match in matchesForDay) {
                listItems.add({'type': 'match', 'match': match, 'isDayLocked': isDayLockedLocally});
              }
            }

            if (listItems.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildUserHeader(currentUser),
                  const SizedBox(height: 40),
                  const Center(child: Text("Nenhum jogo corresponde aos filtros selecionados.", style: TextStyle(color: Colors.grey))),
                ],
              );
            }

            return RefreshIndicator(
              color: const Color(0xFF1B5E20),
              onRefresh: () async {
                // 🚨 Para forçar o refresh, criamos novos futures na memória.
                setState(() {
                  _matchesFuture = _bolaoService.getMatches(forceRefresh: true);
                  _predictionsFuture = _bolaoService.getMyPredictions(userId, forceRefresh: true);
                });
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: listItems.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return _buildUserHeader(currentUser);

                  final item = listItems[index - 1];

                  if (item['type'] == 'header') {
                    final bool locked = item['isDayLocked'] || isGlobalLocked;
                    return Container(
                      margin: const EdgeInsets.only(top: 20, bottom: 10, left: 4, right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: locked ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: locked ? Colors.red.shade200 : Colors.green.shade200, width: 1)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(locked ? "Dia ${item['title']} - TRANCADO" : "Dia ${item['title']} - PALPITES ABERTOS", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: locked ? Colors.red[800] : const Color(0xFF1B5E20))),
                          Icon(locked ? Icons.lock : Icons.lock_open, size: 18, color: locked ? Colors.red[800] : const Color(0xFF1B5E20))
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
                    if (_homeControllers[match.id]!.text.isEmpty) _homeControllers[match.id]!.text = myPred.scoreHome.toString();
                    if (_awayControllers[match.id]!.text.isEmpty) _awayControllers[match.id]!.text = myPred.scoreAway.toString();
                  }

                  final bool isMatchLocked = isGlobalLocked || item['isDayLocked'] || match.status != 'pending';
                  return _buildMatchCard(match, userId, isMatchLocked, myPred, currentUser);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserHeader(BolaoUser? bUser) {
    if (bUser == null) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));

    final bool isProfileIncomplete = !bUser.isProfileComplete;

    return GestureDetector(
      onTap: () => _showEditProfileModal(bUser, bUser.userId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, left: 4, right: 4),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.amber, width: 2.5)),
              child: CircleAvatar(
                radius: 28, backgroundColor: Colors.white,
                backgroundImage: bUser.photoUrl != null ? NetworkImage(bUser.photoUrl!) : null,
                child: bUser.photoUrl == null ? const Icon(Icons.sports_soccer, color: Color(0xFF1B5E20), size: 30) : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TREINADOR FJF OFICIAL", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text(
                    bUser.name == 'Utilizador' ? 'Defina seu Nome' : bUser.name,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: isProfileIncomplete ? Colors.orangeAccent.withOpacity(0.2) : Colors.greenAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isProfileIncomplete ? Colors.orangeAccent : Colors.greenAccent)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isProfileIncomplete ? Icons.warning_amber_rounded : Icons.check_circle, size: 12, color: isProfileIncomplete ? Colors.orangeAccent : Colors.greenAccent),
                        const SizedBox(width: 4),
                        Text(isProfileIncomplete ? "Completar Cadastro" : "Cadastro Completo", style: TextStyle(color: isProfileIncomplete ? Colors.orangeAccent : Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
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
  }

  Widget _buildMatchCard(BolaoMatch match, String userId, bool isLocked, BolaoPrediction? myPred, BolaoUser? currentUser) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF1B5E20).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Text(match.group, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20), fontSize: 10)),
                ),
                Row(
                  children: [
                    Text("${match.date.hour.toString().padLeft(2, '0')}:${match.date.minute.toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.bold)),
                    if (isFinished) ...[
                      const SizedBox(width: 8),
                      const Text("• ENCERRADO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.redAccent)),
                    ]
                  ],
                ),
              ],
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(child: Column(children: [Text(match.homeFlagUrl, style: const TextStyle(fontSize: 32)), const SizedBox(height: 4), Text(match.homeTeam, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))])),
                isFinished
                    ? _buildFinishedResult(match, myPred)
                    : Row(
                        children: [
                          _buildScoreInput(_homeControllers[match.id]!, isLocked, match.id, userId, myPred, currentUser),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("X", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black38, fontSize: 16))),
                          _buildScoreInput(_awayControllers[match.id]!, isLocked, match.id, userId, myPred, currentUser),
                        ],
                      ),
                Expanded(child: Column(children: [Text(match.awayFlagUrl, style: const TextStyle(fontSize: 32)), const SizedBox(height: 4), Text(match.awayTeam, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))])),
              ],
            ),
            if (isLocked && !isFinished)
              Container(
                margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock_outline, size: 12, color: Colors.black45), SizedBox(width: 4), Text("BLOQUEADO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black45))]),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildFinishedResult(BolaoMatch match, BolaoPrediction? myPred) {
    final bool hasPredicted = myPred != null;
    final int points = myPred?.pointsEarned ?? 0;

    Color badgeColor = Colors.grey.shade200; Color textColor = Colors.black87;
    if (points == 5) { badgeColor = Colors.green.shade100; textColor = Colors.green.shade900; } 
    else if (points > 0) { badgeColor = Colors.blue.shade50; textColor = Colors.blue.shade900; } 
    else if (hasPredicted) { badgeColor = Colors.red.shade50; textColor = Colors.red.shade900; }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
          child: Text("${match.realScoreHome ?? '-'}  x  ${match.realScoreAway ?? '-'}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: textColor.withOpacity(0.3))),
          child: Column(
            children: [
              Text(hasPredicted ? "Seu Palpite: ${myPred!.scoreHome} x ${myPred.scoreAway}" : "Você não palpitou", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
              if (hasPredicted) Text(points == 5 ? "Na Mosca! +5 Pts" : (points > 0 ? "Ganhou +$points Pts" : "Não pontuou"), style: TextStyle(fontSize: 10, color: textColor)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildScoreInput(TextEditingController controller, bool isLocked, String matchId, String userId, BolaoPrediction? myPred, BolaoUser? currentUser) {
    final bool isProfileIncomplete = currentUser == null || !currentUser.isProfileComplete;

    return GestureDetector(
      onTap: () {
        if (isProfileIncomplete && !isLocked) {
           _showProfileRequiredDialog(currentUser!);
        }
      },
      child: AbsorbPointer(
        absorbing: isProfileIncomplete,
        child: SizedBox(
          width: 44, height: 44,
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
        ),
      ),
    );
  }

  // ===========================================================================
  // ABA 2: BÔNUS EXTRAS
  // ===========================================================================
  Widget _buildBonusTab(String userId, bool isGlobalLocked, BolaoUser? currentUser) {
    final deadline = DateTime.utc(2026, 6, 11, 20, 30, 00); 
    final bool isTimeOver = DateTime.now().toUtc().isAfter(deadline);
    final bool isBonusLocked = isTimeOver; 

    final List<String> availableTeams = _teamsFlagsMap.keys.toList()..sort();
    final List<String> seededTeams = ['Alemanha', 'Argentina', 'Bélgica', 'Brasil', 'Canadá', 'Espanha', 'Estados Unidos', 'França', 'Holanda', 'Inglaterra', 'México', 'Portugal'];

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
          title: "O Grande Campeão (20 pts)", description: "Qual seleção irá levantar a taça e sagrar-se campeã do mundo?", icon: Icons.emoji_events,
          currentValue: currentUser?.champion, isLocked: isBonusLocked, availableTeams: availableTeams, currentUser: currentUser,
          onChanged: (val) => _saveBonusPrediction(userId, 'bonus_champion', val),
        ),
        const SizedBox(height: 12),
        _buildBonusDropdown(
          title: "O Vice-Campeão (10 pts)", description: "Qual seleção chegará à Grande Final, mas irá perder o título?", icon: Icons.looks_two,
          currentValue: currentUser?.runnerUp, isLocked: isBonusLocked, availableTeams: availableTeams, currentUser: currentUser,
          onChanged: (val) => _saveBonusPrediction(userId, 'bonus_runner_up', val),
        ),
        const SizedBox(height: 12),
        _buildBonusDropdown(
          title: "Melhor Ataque (10 pts)", description: "A seleção que marcar o maior número de gols no total da Copa.", icon: Icons.sports_soccer,
          currentValue: currentUser?.bestOffense, isLocked: isBonusLocked, availableTeams: availableTeams, currentUser: currentUser,
          onChanged: (val) => _saveBonusPrediction(userId, 'bonus_best_offense', val),
        ),
        const SizedBox(height: 12),
        _buildBonusDropdown(
          title: "A Pior Defesa (10 pts)", description: "O 'Saco de Pancadas'. A seleção que sofrer o maior número de gols.", icon: Icons.shield,
          currentValue: currentUser?.worstDefense, isLocked: isBonusLocked, availableTeams: availableTeams, currentUser: currentUser,
          onChanged: (val) => _saveBonusPrediction(userId, 'bonus_worst_defense', val),
        ),
        const SizedBox(height: 12),
        _buildBonusDropdown(
          title: "A Grande Decepção (10 pts)", description: "O Fiasco. A primeira seleção 'Cabeça de Chave' a ser eliminada do torneio.", icon: Icons.trending_down,
          currentValue: currentUser?.disappointment, isLocked: isBonusLocked, availableTeams: seededTeams, currentUser: currentUser,
          onChanged: (val) => _saveBonusPrediction(userId, 'bonus_disappointment', val),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildBonusDropdown({
    required String title, required String description, required IconData icon, required String? currentValue,
    required bool isLocked, required List<String> availableTeams, required Function(String?) onChanged, required BolaoUser? currentUser,
  }) {
    final bool isProfileIncomplete = currentUser == null || !currentUser.isProfileComplete;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, color: Colors.amber.shade700, size: 24), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
            const SizedBox(height: 6),
            Text(description, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            
            GestureDetector(
              onTap: () {
                if (isProfileIncomplete && !isLocked) {
                  _showProfileRequiredDialog(currentUser!);
                }
              },
              child: AbsorbPointer(
                absorbing: isProfileIncomplete,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: availableTeams.contains(currentValue) ? currentValue : null,
                  disabledHint: currentValue != null
                      ? Row(children: [Text(_teamsFlagsMap[currentValue] ?? '❓', style: const TextStyle(fontSize: 20)), const SizedBox(width: 8), Expanded(child: Text(currentValue, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))])
                      : const Text("Bloqueado (Sem Palpite)", style: TextStyle(color: Colors.red)),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: isLocked,
                    fillColor: Colors.grey.shade100,
                  ),
                  items: isLocked ? null : availableTeams.map((team) {
                          return DropdownMenuItem(value: team, child: Row(children: [Text(_teamsFlagsMap[team] ?? '❓', style: const TextStyle(fontSize: 20)), const SizedBox(width: 12), Expanded(child: Text(team, overflow: TextOverflow.ellipsis))]));
                        }).toList(),
                  onChanged: isLocked ? null : onChanged,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 🚨 ABA 3: RANKING GERAL (CORRIGIDO TEXTFIELD E BLINK)
// ===========================================================================
class _BolaoRankingTab extends StatefulWidget {
  final String currentUserId;
  const _BolaoRankingTab({required this.currentUserId});

  @override
  State<_BolaoRankingTab> createState() => _BolaoRankingTabState();
}

class _BolaoRankingTabState extends State<_BolaoRankingTab> {
  // 🚨 Usar TextEditingController mantém o texto fixo mesmo se a tela redesenhar
  final TextEditingController _searchController = TextEditingController();
  
  // 🚨 Variável isolada para o Stream não reiniciar durante o setState
  late Stream<List<BolaoUser>> _leaderboardStream;

  String _searchQuery = '';
  int _displayLimit = 10; 

  @override
  void initState() {
    super.initState();
    _leaderboardStream = BolaoService().streamLeaderboard();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BolaoUser>>(
      stream: _leaderboardStream, // Usa o cache para não piscar
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Nenhum participante pontuou ainda."));

        final allUsers = snapshot.data!;

        // 1. Aplica o filtro de pesquisa
        final filteredUsers = allUsers.where((u) {
          return u.name.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        // 2. Aplica a paginação
        final bool hasMore = filteredUsers.length > _displayLimit;
        final displayCount = hasMore ? _displayLimit : filteredUsers.length;
        final int itemCount = displayCount + (hasMore ? 1 : 0);

        return Column(
          children: [
            // --- CAMPO DE BUSCA ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController, // Adicionado o controller
                onChanged: (value) => setState(() {
                  _searchQuery = value;
                  _displayLimit = 10; // Reseta a paginação ao pesquisar
                }),
                decoration: InputDecoration(
                  hintText: 'Pesquisar participante...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),

            // --- LISTA DO RANKING ---
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  // --- BOTÃO CARREGAR MAIS ---
                  if (index == displayCount) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _displayLimit += 10),
                        icon: const Icon(Icons.add),
                        label: const Text("VER MAIS PARTICIPANTES"),
                      ),
                    );
                  }

                  final participant = filteredUsers[index];
                  final bool isMe = participant.userId == widget.currentUserId;
                  
                  // Se tivermos pesquisando, a posição real dele é o index da lista global.
                  final int realRank = _searchQuery.isEmpty ? (index + 1) : (allUsers.indexOf(participant) + 1);

                  return Card(
                    color: isMe ? Colors.green[50] : Colors.white,
                    elevation: isMe ? 4 : 1,
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isMe ? const BorderSide(color: Color(0xFF1B5E20), width: 1.5) : BorderSide.none),
                    child: ExpansionTile(
                      // 🚨 POSIÇÃO ANTES DO NOME E FOTO
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 25,
                            child: Text(
                              '$realRankº',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: realRank == 1 ? Colors.amber[600] : 
                                       realRank == 2 ? Colors.grey[500] : 
                                       realRank == 3 ? Colors.brown[400] : Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: Colors.grey[200],
                            backgroundImage: (participant.photoUrl != null && participant.photoUrl!.isNotEmpty)
                                ? CachedNetworkImageProvider(participant.photoUrl!)
                                : null,
                            child: (participant.photoUrl == null || participant.photoUrl!.isEmpty)
                                ? const Icon(Icons.person, color: Colors.grey)
                                : null,
                          ),
                        ],
                      ),
                      title: Text(participant.name, style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.w500)),
                      trailing: Text("${participant.totalPoints} pts", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1B5E20))),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: Colors.grey[50],
                          child: Column(
                            children: [
                              _buildRankingStatRow("Pontuação Total Real", "${participant.totalPoints} pts", Colors.black87, isBold: true),
                              const Divider(),
                              _buildRankingStatRow("1º Placar Exato (Na Mosca)", "${participant.exactHits} acertos", Colors.green),
                              const Divider(),
                              _buildRankingStatRow("2º Acerto de Vencedor + Saldo", "${participant.goalDifferenceHits} acertos", Colors.blue),
                              const Divider(),
                              _buildRankingStatRow("3º Acerto Simples de Vencedor", "${participant.winnerHits} acertos", Colors.orange),
                              const Divider(),
                              _buildRankingStatRow("4º Pontos Extras (Bônus Finais)", "${participant.bonusPoints} pts", Colors.purple),
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildRankingStatRow(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w400, color: Colors.black54)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}