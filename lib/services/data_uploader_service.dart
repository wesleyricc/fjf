// lib/services/data_uploader_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';

class DataUploaderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> uploadInitialData() async {
    try {
      final WriteBatch batch = _firestore.batch();

      // --- 1. Processar Times e Criar o Cache ---
      final String teamsString = await rootBundle.loadString('assets/data/teams.json');
      final Map<String, dynamic> teamsData = json.decode(teamsString);

      // O 'teamsData' agora age como nosso cache.
      // Ex: teamsData['flamengo'] -> { "name": "Flamengo", "shield_url": "..." }

      teamsData.forEach((teamId, teamInfo) {
        final DocumentReference teamRef = _firestore.collection('teams').doc(teamId);
        
        // Copia os dados do JSON para um novo mapa (para não modificar o original)
        final Map<String, dynamic> finalTeamData = Map<String, dynamic>.from(teamInfo);

        // Adiciona os campos de estatísticas zerados
        finalTeamData['points'] = 0;
        finalTeamData['match_points'] = 0;
        finalTeamData['extra_points'] = 0;
        finalTeamData['games_played'] = 0;
        finalTeamData['wins'] = 0;
        finalTeamData['draws'] = 0;
        finalTeamData['losses'] = 0;
        finalTeamData['goals_for'] = 0;
        finalTeamData['goals_against'] = 0;
        finalTeamData['goal_difference'] = 0;
        finalTeamData['disciplinary_points'] = 0;

        batch.set(teamRef, finalTeamData);
      });

      // --- 2. Processar Jogadores (usando o cache) ---
      final String playersString = await rootBundle.loadString('assets/data/players.json');
      final List<dynamic> playersData = json.decode(playersString);

      for (var playerInfo in playersData) {
        final DocumentReference playerRef = _firestore.collection('players').doc();
        
        // --- LÓGICA DE BUSCA NO CACHE ---
        final String teamId = playerInfo['team_id'];
        final dynamic teamInfo = teamsData[teamId];

        if (teamInfo == null) {
          debugPrint('Erro de ID: Jogador ${playerInfo['name']} com ID de time inválido ($teamId). Pulando...');
          continue; // Pula este jogador se o ID não for encontrado
        }
        
        // Injeta o nome do time vindo do cache
        playerInfo['team_name'] = teamInfo['name'];
        playerInfo['team_shield_url'] = teamInfo['shield_url'];
        // --- FIM DA LÓGICA DE BUSCA ---

        playerInfo['goals'] = 0;
        playerInfo['assists'] = 0;
        playerInfo['yellow_cards'] = 0;
        playerInfo['red_cards'] = 0;
        playerInfo['goals_conceded'] = 0;
        playerInfo['is_goalkeeper'] = playerInfo['is_goalkeeper'] ?? false; // Se não existir no JSON, é false
        playerInfo['man_of_the_match_awards'] = 0;
        playerInfo['is_suspended'] = false;
        playerInfo['total_yellow_cards'] = 0;
        playerInfo['total_red_cards'] = 0;

        batch.set(playerRef, playerInfo);
      }

      // --- 3. Processar Jogos (usando o cache) ---
      final String matchesString = await rootBundle.loadString('assets/data/matches.json');
      final List<dynamic> matchesData = json.decode(matchesString);

      for (var matchInfo in matchesData) {
        final DocumentReference matchRef = _firestore.collection('matches').doc();
        
        // --- LÓGICA DE BUSCA NO CACHE ---
        final String homeId = matchInfo['team_home_id'];
        final String awayId = matchInfo['team_away_id'];

        final dynamic homeTeamInfo = teamsData[homeId];
        final dynamic awayTeamInfo = teamsData[awayId];

        if (homeTeamInfo == null || awayTeamInfo == null) {
          debugPrint('Erro de ID: Jogo com ID de time inválido ($homeId ou $awayId). Pulando...');
          continue; // Pula este jogo
        }

        // Injeta os dados encontrados no mapa do jogo
        matchInfo['team_home_name'] = homeTeamInfo['name'];
        matchInfo['team_home_shield'] = homeTeamInfo['shield_url'];
        matchInfo['team_away_name'] = awayTeamInfo['name'];
        matchInfo['team_away_shield'] = awayTeamInfo['shield_url'];
        // --- FIM DA LÓGICA DE BUSCA ---

        // Converte a string de data (ISO 8601) para Timestamp do Firebase
        if (matchInfo['datetime'] != null) {
          matchInfo['datetime'] = Timestamp.fromDate(DateTime.parse(matchInfo['datetime']));
        }
        
        matchInfo['status'] = 'pending';
        matchInfo['score_home'] = null;
        matchInfo['score_away'] = null;

        batch.set(matchRef, matchInfo);
      }

      // --- 4. Enviar tudo de uma vez ---
      await batch.commit();
      
      return "Sucesso! ${teamsData.length} times, ${playersData.length} jogadores e ${matchesData.length} jogos carregados.";

    } catch (e) {
      debugPrint('Erro ao carregar dados: $e');
      return "Erro: ${e.toString()}";
    }
  }
}