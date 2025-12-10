// lib/screens/voting/voting_menu_screen.dart
import 'dart:async'; // Import necessário para StreamSubscription
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Necessário para checar o bloqueio
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/sponsor_banner_rotator.dart';
import 'voting_list_screen.dart';
import 'voting_selection_screen.dart'; 

class VotingMenuScreen extends StatefulWidget {
  const VotingMenuScreen({super.key});

  @override
  State<VotingMenuScreen> createState() => _VotingMenuScreenState();
}

class _VotingMenuScreenState extends State<VotingMenuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Estado da Votação
  bool _isVotingEnabled = true; // Padrão aberto até carregar
  bool _isLoading = true;
  
  // Cache local de votos
  Map<String, bool> _hasVotedMap = {};

  // Listener para ouvir o bloqueio em tempo real
  StreamSubscription? _configSubscription;

  @override
  void initState() {
    super.initState();
    _setupRealtimeConfigListener();
    _checkLocalVotes();
  }

  @override
  void dispose() {
    _configSubscription?.cancel();
    super.dispose();
  }

  // 1. Ouve alterações no Firebase (Bloqueio/Desbloqueio) em Tempo Real
  void _setupRealtimeConfigListener() {
    _configSubscription = _firestore
        .collection('config')
        .doc('app_settings')
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data();
            if (mounted) {
              setState(() {
                _isVotingEnabled = data?['voting_enabled'] ?? true;
                _isLoading = false;
              });
            }
          } else {
            // Se o documento não existir, assume liberado
            if (mounted) setState(() => _isLoading = false);
          }
        }, onError: (e) {
           debugPrint("Erro no listener de config: $e");
           if (mounted) setState(() => _isLoading = false);
        });
  }

  // 2. Verifica votos locais (SharedPreferences)
  Future<void> _checkLocalVotes() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hasVotedMap = {
          'craque': prefs.getBool('voted_craque') ?? false,
          'melhor_jogador': prefs.getBool('voted_melhor_jogador') ?? false,
          'selecao': prefs.getBool('voted_selecao') ?? false,
          'revelacao': prefs.getBool('voted_revelacao') ?? false,
          'bola_cheia': prefs.getBool('voted_bola_cheia') ?? false,
          'bola_murcha': prefs.getBool('voted_bola_murcha') ?? false,
          'treinador': prefs.getBool('voted_treinador') ?? false,
        };
      });
    }
  }

  void _refresh() {
    _checkLocalVotes();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Tela de Carregamento
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 2. TELA DE BLOQUEIO (Se voting_enabled = false)
    if (!_isVotingEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Votação Encerrada')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_clock, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 20),
                const Text(
                  "A votação está encerrada ou pausada no momento.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Fique ligado para os resultados!", 
                  style: TextStyle(color: Colors.grey)
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(), 
                  child: const Text("Voltar")
                )
              ],
            ),
          ),
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      );
    }

    // 3. TELA DE MENU (Se liberado)
    return Scaffold(
      appBar: AppBar(title: const Text('Votação Destaques da FJF')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text(
              'Atenção: É permitido apenas 1 voto por categoria.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          
          _buildMenuItem(
            context, 
            'Craque da Galera', 
            Icons.star, 
            'craque',
            'O queridinho da torcida! Aquele que joga bonito e ainda conquista no carisma.'
          ),
          
          _buildMenuItem(
            context, 
            'Melhor Jogador', 
            Icons.military_tech, 
            'melhor_jogador',
            'O brabo do campeonato. Joga muito, carrega o time e faz a diferença em qualquer partida.'
          ),

          _buildMenuItem(
            context, 
            'Revelação', 
            Icons.auto_awesome, 
            'revelacao',
            'O “surpresa boa” do torneio. Chegou quieto… e saiu fazendo barulho!'
          ),
          
          _buildMenuItem(
            context, 
            'Treinador do Campeonato', 
            Icons.content_paste, 
            'treinador',
            'O professor que entende tudo de futsal — estratégia afiada e dedo mágico nas partidas.'
          ),
          
          _buildMenuItem(
            context, 
            'Bola Cheia', 
            Icons.thumb_up, 
            'bola_cheia',
            'Aquele momento de brilhar os olhos! Um lance mágico, um drible, um gol que arrancou aplausos da torcida!'
          ),
          
          _buildMenuItem(
            context, 
            'Bola Murcha', 
            Icons.thumb_down, 
            'bola_murcha',
            'Aquela escorregada marota. A bola não entrou, o passe não saiu… mas faz parte do jogo!'
          ),

          const SizedBox(height: 8),
          _buildSelecaoItem(context),
          const SizedBox(height: 8),
        ],
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, IconData icon, String categoryKey, String description) {
    final bool hasVoted = _hasVotedMap[categoryKey] ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0), 
      elevation: hasVoted ? 0 : 2,
      color: hasVoted ? Colors.grey[200] : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: hasVoted ? null : () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => VotingListScreen(
                categoryTitle: title,
                categoryKey: categoryKey,
              ),
            ),
          );
          _refresh(); 
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center, 
            children: [
              CircleAvatar(
                backgroundColor: hasVoted ? Colors.grey : Theme.of(context).primaryColor.withOpacity(0.1),
                radius: 20, 
                child: Icon(hasVoted ? Icons.check : icon, size: 20, color: hasVoted ? Colors.white : Theme.of(context).primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 15,
                        color: hasVoted ? Colors.grey : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 2, 
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11, 
                        color: hasVoted ? Colors.grey : Colors.grey[700],
                        height: 1.2,
                      ),
                    ),
                    if (hasVoted)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          "Voto computado",
                          style: TextStyle(
                            color: Colors.green[700], 
                            fontWeight: FontWeight.bold, 
                            fontSize: 10
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!hasVoted)
                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelecaoItem(BuildContext context) {
    final bool hasVoted = _hasVotedMap['selecao'] ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      elevation: hasVoted ? 0 : 3, 
      color: hasVoted ? Colors.grey[200] : Colors.amber[50], 
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: hasVoted ? BorderSide.none : BorderSide(color: Colors.amber.shade700, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: hasVoted ? null : () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => const VotingSelectionScreen(),
            ),
          );
          _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: hasVoted ? Colors.grey : Colors.amber,
                radius: 22, 
                child: Icon(hasVoted ? Icons.check : Icons.groups, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seleção do Campeonato',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 15,
                        color: hasVoted ? Colors.grey : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Escale a equipe ideal do campeonato.",
                      style: TextStyle(
                        fontSize: 11, 
                        color: hasVoted ? Colors.grey : Colors.brown[700],
                      ),
                    ),
                    if (hasVoted)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          "Voto computado",
                          style: TextStyle(
                            color: Colors.green[700], 
                            fontWeight: FontWeight.bold, 
                            fontSize: 10
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!hasVoted)
                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.amber),
            ],
          ),
        ),
      ),
    );
  }
}