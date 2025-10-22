// lib/screens/standings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';

class StandingsScreen extends StatelessWidget {

  StandingsScreen({super.key});
  
  // Instância do Firestore para o índice (se ainda não tiver)
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classificação'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        
        // --- A Query de Ordenação (de 5 campos) ---
        stream: _firestore // Use a instância
            .collection('teams')
            .orderBy('points', descending: true) 
            .orderBy('disciplinary_points', descending: false) 
            .orderBy('wins', descending: true) 
            .orderBy('goal_difference', descending: true) 
            .orderBy('goals_against', descending: false) 
            .snapshots(),
            
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) { // Verificação de erro (boa prática)
             return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Sem dados de classificação.'));
          }

          final teams = snapshot.data!.docs;

          // --- MUDANÇA AQUI: Adicionamos um Column ---
          return SingleChildScrollView(
            // Padding geral para a tela
            padding: const EdgeInsets.all(8.0), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- 1. A TABELA (envolvida em um SingleChildScrollView horizontal) ---
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 11.0,
                    dataRowMinHeight: 30.0,
                    dataRowMaxHeight: 30.0,
                    horizontalMargin: 5.0,
                    columns: const [
                      DataColumn(label: Text('Pos')),
                      DataColumn(label: Text('Time')),
                      DataColumn(label: Text('P')),  // Pontos
                      DataColumn(label: Text('J')),  // Jogos
                      DataColumn(label: Text('V')),  // Vitórias
                      DataColumn(label: Text('E')),  // Empates
                      DataColumn(label: Text('D')),  // Derrotas
                      DataColumn(label: Text('GP')), // Gols Pró
                      DataColumn(label: Text('GC')), // Gols Contra
                      DataColumn(label: Text('SG')), // Saldo de Gols
                      DataColumn(label: Text('PD')), // Pontos Disciplinares
                    ],
                    rows: teams.map((teamDoc) {
                      final data = teamDoc.data() as Map<String, dynamic>;
                      final index = teams.indexOf(teamDoc) + 1;

                      return DataRow(cells: [
                        DataCell(Text(index.toString())),
                        DataCell(
                          Row(
                            children: [
                              Image.network(data['shield_url'], width: 20),
                              const SizedBox(width: 8),
                              Text(data['name']),
                            ],
                          ),
                        ),
                        DataCell(Text(data['points']?.toString() ?? '0')),
                        DataCell(Text(data['games_played']?.toString() ?? '0')),
                        DataCell(Text(data['wins']?.toString() ?? '0')),
                        DataCell(Text(data['draws']?.toString() ?? '0')),
                        DataCell(Text(data['losses']?.toString() ?? '0')),
                        DataCell(Text(data['goals_for']?.toString() ?? '0')),
                        DataCell(Text(data['goals_against']?.toString() ?? '0')),
                        DataCell(Text(data['goal_difference']?.toString() ?? '0')),
                        DataCell(Text(data['disciplinary_points']?.toString() ?? '0')),
                      ]);
                    }).toList(),
                  ),
                ),
                
                // --- 2. A LEGENDA (NOVO CARD) ---
                const SizedBox(height: 12), // Espaçamento
                Card(
                  color: Colors.white, // Fundo branco para a legenda
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Legenda',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        _buildLegendRow('P', 'Pontos'),
                        _buildLegendRow('J', 'Jogos Disputados'),
                        _buildLegendRow('V', 'Vitórias'),
                        _buildLegendRow('E', 'Empates'),
                        _buildLegendRow('D', 'Derrotas'),
                        _buildLegendRow('GP', 'Gols Pró (Gols Marcados)'),
                        _buildLegendRow('GC', 'Gols Contra (Gols Sofridos)'),
                        _buildLegendRow('SG', 'Saldo de Gols (Gols Pró - Gols Contra)'),
                        _buildLegendRow('PD', 'Pontos Disciplinares (Amarelo = 10, Vermelho = 21)'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
          // --- FIM DA MUDANÇA ---
        },
      ),
    );
  }

  // --- 3. WIDGET AUXILIAR PARA A LEGENDA ---
  // Adicione este método dentro da classe StandingsScreen
  Widget _buildLegendRow(String abbreviation, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Text(
            '$abbreviation:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Expanded( // Garante que o texto longo quebre a linha
            child: Text(
              description,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}