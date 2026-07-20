import 'package:flutter/material.dart';

class BolaoRulesModal {
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))
          ),
          padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.rule, color: Color(0xFF1B5E20), size: 28),
                      SizedBox(width: 8),
                      Text("Regras do Mini Bolão", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("💰 PREMIAÇÃO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
                      const SizedBox(height: 4),
                      const Text("O prêmio final é distribuído para o grande vencedor da sala (1º Lugar). O valor cresce conforme novos participantes entram! A taxa de administração do app já é descontada do valor exibido.", style: TextStyle(fontSize: 14)),
                      const Divider(height: 30),
                      const Text("⚽ PONTUAÇÃO DO PLACAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                      const SizedBox(height: 8),
                      const Text("🎯 Na Mosca (+50 Pontos)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou o vencedor e o placar exato.", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("⚖️ Vencedor + Saldo (+30 Pontos)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou quem venceu e a diferença de gols, mas errou o placar exato.", style: TextStyle(fontSize: 12, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("✔️ Vencedor Simples (+15 Pontos)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou apenas quem venceu a partida.", style: TextStyle(fontSize: 14, height: 1.5)),
                      const Divider(height: 30),
                      const Text("⭐ PONTUAÇÃO EXTRA (PERGUNTAS)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
                      const SizedBox(height: 8),
                      const Text("👟 O Craque do Jogo (+2 Pontos por acerto)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Você escolhe até 2 atletas. Se o atleta escolhido marcar PELO MENOS 1 gol na partida, você ganha +2 pontos por ele.", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("⚡ Primeiro Gol (+2 Pontos)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou qual seleção balançou as redes primeiro (ou se o jogo terminou 0x0).", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("⏱️ Empate no Intervalo (+1 Ponto)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou se o 1º Tempo terminou empatado ou não.", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 8),
                      const Text("📊 Metade com Mais Gols (+1 Ponto)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("Acertou em qual tempo saíram mais gols (ou se houve a mesma quantidade nos dois tempos).", style: TextStyle(fontSize: 14, height: 1.5)),
                      const Divider(height: 30),
                      
                      const Text("⚖️ CRITÉRIOS DE DESEMPATE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
                      const SizedBox(height: 4),
                      const Text("1º Maior pontuação total (Soma do Placar + Extras)\n2º Minuto do 1º Gol (Quem chegar mais perto do minuto real)", style: TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20), 
                      foregroundColor: Colors.white, 
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("ENTENDI!", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              )
            ],
          ),
        );
      }
    );
  }
}
