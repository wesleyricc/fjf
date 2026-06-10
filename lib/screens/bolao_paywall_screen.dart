import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/bolao_service.dart';
import 'bolao_predictions_screen.dart';
import '../theme/app_theme.dart'; // <-- NOVO IMPORT

class BolaoPaywallScreen extends StatefulWidget {
  const BolaoPaywallScreen({super.key});

  @override
  State<BolaoPaywallScreen> createState() => _BolaoPaywallScreenState();
}

class _BolaoPaywallScreenState extends State<BolaoPaywallScreen> {
  final BolaoService _bolaoService = BolaoService();
  bool _isLoadingPix = false;
  String? _pixCode;

  Stream<DocumentSnapshot>? _bolaoUserStream;
  String? _lastInitializedUid;

  void _initUserStream(String uid) {
    if (_lastInitializedUid == uid && _bolaoUserStream != null) return;
    _lastInitializedUid = uid;
    _bolaoUserStream = FirebaseFirestore.instance
        .collection('bolao_users')
        .doc(uid)
        .snapshots();
  }

  Future<void> _generatePix(String userId, String email) async {
    setState(() => _isLoadingPix = true);
    try {
      final result = await _bolaoService.generatePixForBolao(userId, email);
      setState(() {
        _pixCode = result['pix_code'];
        _isLoadingPix = false;
      });
    } catch (e) {
      setState(() => _isLoadingPix = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<FantasyAuthService>(context);
    final user = auth.user;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text("Bolão da Copa 2026", style: TextStyle(fontWeight: FontWeight.bold)),
          // 🚨 NOVO: Gradiente da Copa aplicado
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.brazilGradient,
            ),
          ),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(FontAwesomeIcons.trophy, size: 80, color: Colors.amber),
                const SizedBox(height: 24),
                const Text(
                  "Identificação Necessária",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Para dar os seus palpites, salvar seus bônus e disputar o topo do Ranking da Copa, faça login com sua conta do Google.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.4, fontSize: 14),
                ),
                const SizedBox(height: 40),
                auth.isLoading 
                  ? const CircularProgressIndicator(color: AppTheme.primaryColor)
                  : ElevatedButton.icon(
                      onPressed: () async {
                        final error = await auth.signInWithGoogle();
                        if (error != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                        }
                      },
                      icon: const FaIcon(FontAwesomeIcons.google, color: Colors.white),
                      label: const Text(
                        "ENTRAR COM O GOOGLE",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
              ],
            ),
          ),
        ),
      );
    }

    _initUserStream(user.uid);

    return StreamBuilder<DocumentSnapshot>(
      stream: _bolaoUserStream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final rawPaid = data?['has_paid'];
          final bool isPaid = rawPaid == true || rawPaid.toString().trim().toLowerCase() == 'true';

          if (isPaid) {
            return const KeyedSubtree(
              key: ValueKey('bolao_predictions_active'),
              child: BolaoPredictionsScreen(),
            );
          }
        }

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            // 🚨 NOVO: Gradiente da Copa aplicado
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: AppTheme.brazilGradient,
              ),
            ),
            elevation: 0,
            title: const Text("Bolão FJF - Copa 2026", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: const BoxDecoration(
                    gradient: AppTheme.brazilGradient,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(FontAwesomeIcons.trophy, size: 36, color: Colors.amber),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("PREMIAÇÃO DO BOLÃO", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              Text("30% DE TODO O ARRECADADO", style: TextStyle(color: AppTheme.yellowColor, fontSize: 16, fontWeight: FontWeight.w900)),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("Inscrição Única: ", style: TextStyle(color: Colors.white70, fontSize: 14)),
                            Text("R\$ 20,00", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_pixCode == null) ...[
                        _isLoadingPix 
                            ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
                            : ElevatedButton.icon(
                                onPressed: () => _generatePix(user.uid, user.email ?? ''),
                                icon: const Icon(Icons.pix, color: Colors.tealAccent, size: 22),
                                label: const Text("GERAR PIX PARA ENTRAR AGORA", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.secondaryColor, 
                                  padding: const EdgeInsets.symmetric(vertical: 14), 
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                              ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade300, width: 1.5)),
                          child: Column(
                            children: [
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                                  SizedBox(width: 8),
                                  Text("PIX Copia e Cola Gerado!", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text("Pague no aplicativo do seu banco. A liberação será automática após o processamento.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _pixCode!));
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código PIX copiado com sucesso!")));
                                },
                                icon: const Icon(Icons.copy, size: 18),
                                label: const Text("COPIAR CÓDIGO PIX"),
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryColor, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 44)),
                              )
                            ],
                          ),
                        )
                      ],

                      const SizedBox(height: 24),
                      const Text("Dúvidas sobre o funcionamento?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                      const SizedBox(height: 8),

                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.black12)),
                        child: ExpansionTile(
                          leading: const Icon(Icons.sports_soccer, color: AppTheme.secondaryColor),
                          title: const Text("Como pontuar nos Jogos?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                          children: [
                            Padding(
                              padding: EdgeInsets.only(left: 16, right: 16, bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Navigator.canPop(context) ? SizedBox.shrink() : Divider(),
                                  SizedBox(height: 4),
                                  Text("🎯 Na Mosca (Placar Exato): +5 Pontos", style: TextStyle(fontSize: 13, height: 1.5)),
                                  Text("⚖️ Acerto de Vencedor + Saldo: +3 Pontos", style: TextStyle(fontSize: 13, height: 1.5)),
                                  Text("✔️ Acerto Simples (Apenas Vencedor): +1 Ponto", style: TextStyle(fontSize: 13, height: 1.5)),
                                  Text("💡 Dica de Empate: Se apostar 0x0 e o jogo terminar 1x1, você ganha 3 pontos! (Acertou o empate e o saldo de gols, que é zero).", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54)),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.black12)),
                        child: ExpansionTile(
                          leading: const Icon(Icons.star, color: Colors.purple),
                          title: const Text("Quais são as Regras dos Bônus?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.purple)),
                          children: [
                            Padding(
                              padding: EdgeInsets.only(left: 16, right: 16, bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Navigator.canPop(context) ? SizedBox.shrink() : Divider(),
                                  SizedBox(height: 4),
                                  Text("🏆 O Grande Campeão: +20 Pontos", style: TextStyle(fontSize: 13, height: 1.5)),
                                  Text("🥈 O Vice-Campeão: +10 Pontos", style: TextStyle(fontSize: 13, height: 1.5)),
                                  Text("⚽ Melhor Ataque da Copa: +10 Pontos", style: TextStyle(fontSize: 13, height: 1.5)),
                                  Text("🛡️ Pior Defesa da Copa: +10 Pontos", style: TextStyle(fontSize: 13, height: 1.5)),
                                  Text("📉 A Grande Decepção: +10 Pontos", style: TextStyle(fontSize: 13, height: 1.5)),
                                  SizedBox(height: 8),
                                  Text("*Os palpites para os bônus extras trancam no dia 17/06/2026 às 23h59.", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}