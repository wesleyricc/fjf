import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart'; // Para debugPrint
import 'admin_service.dart'; // Para acessar regras globais

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "fjfapp.firebasestorage.app");

  // Constante para identificar o modo legado
  static const String LEGACY_ID = 'legacy_2025';

  // --- HELPER DE LOG DE ERRO DE ÍNDICE ---
  void _checkAndLogIndexError(Object e) {
    final err = e.toString();
    if (err.contains('failed-precondition') || err.contains('requires an index')) {
      debugPrint('\n🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥');
      debugPrint('LINK PARA CRIAR ÍNDICE:');
      debugPrint(err);
      debugPrint('🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥\n');
    }
  }

  // ===========================================================================
  // 📍 ROTEAMENTO INTELIGENTE (O Segredo da Arquitetura Híbrida)
  // ===========================================================================

  /// Retorna a referência para a coleção de JOGOS correta baseada na temporada.
  CollectionReference _getMatchesRef(String seasonId) {
    if (seasonId == LEGACY_ID) {
      return _firestore.collection('matches'); // Raiz (Antigo)
    } else {
      return _firestore.collection('championships').doc(seasonId).collection('matches'); // Novo
    }
  }

  /// Retorna a referência para a coleção de TIMES correta baseada na temporada.
  /// No novo modelo, isso aponta para 'teams_participation' (stats daquele ano).
  CollectionReference _getTeamsRef(String seasonId) {
    if (seasonId == LEGACY_ID) {
      return _firestore.collection('teams'); // Raiz (Antigo)
    } else {
      return _firestore.collection('championships').doc(seasonId).collection('teams_participation'); // Novo
    }
  }

  // Helper para pegar a referência de stats de jogadores da temporada
  CollectionReference _getPlayerStatsRef(String seasonId) {
    if (seasonId == LEGACY_ID) {
      return _firestore.collection('players'); // Modo antigo (Global)
    } else {
      return _firestore.collection('championships').doc(seasonId).collection('player_stats'); // Novo (Isolado)
    }
  }

  // NOTA: Por enquanto, manteremos 'players' e 'media_feed' na raiz como Diretórios Globais.
  // Isso facilita a transição sem precisar migrar tudo de uma vez.
  CollectionReference get _playersRef => _firestore.collection('players');
  CollectionReference get _mediaRef => _firestore.collection('media_feed');

  // ===========================================================================
  // 📰 MÍDIAS (Agora Híbridas: Global ou Por Temporada)
  // ===========================================================================

    // Helper para obter a referência correta
  CollectionReference _getMediaRef(String seasonId) {
    if (seasonId == LEGACY_ID) {
      return _firestore.collection('media_feed'); // Raiz (Antigo)
    } else {
      return _firestore.collection('championships').doc(seasonId).collection('news'); // Novo (Nome 'news' para ficar mais limpo)
    }
  }

  Future<int> getNextMediaOrder(String seasonId) async {
    try {
      final snapshot = await _getMediaRef(seasonId).orderBy('order', descending: true).limit(1).get();
      if (snapshot.docs.isEmpty) return 1;
      final lastOrder = (snapshot.docs.first.data() as Map<String, dynamic>)['order'] as num? ?? 0;
      return lastOrder.toInt() + 1;
    } catch (e) {
      _checkAndLogIndexError(e);
      return 1;
    }
  }

  Future<String> createMediaItem({
    required String seasonId, // <-- OBRIGATÓRIO
    required String title, required String targetUrl, required String imageUrl,
    required int order, required String author,
  }) async {
    try {
      await _getMediaRef(seasonId).add({
        'title': title, 'targetUrl': targetUrl, 'imageUrl': imageUrl,
        'order': order, 'author': author, 'isActive': true,
      });
      return "Sucesso: Mídia criada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> updateMediaItem({
    required String seasonId, // <-- OBRIGATÓRIO
    required String docId, required String title, required String targetUrl,
    required String imageUrl, required int order, required String author,
  }) async {
    try {
      await _getMediaRef(seasonId).doc(docId).update({
        'title': title, 'targetUrl': targetUrl, 'imageUrl': imageUrl,
        'order': order, 'author': author,
      });
      return "Sucesso: Mídia atualizada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> deleteMediaItem(DocumentSnapshot doc, String seasonId) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      if (data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty) {
        try { await _storage.refFromURL(data['imageUrl']).delete(); } catch (_) {}
      }
      
      // Usa a referência direta do documento para deletar (mais seguro)
      await doc.reference.delete();
      return "Sucesso: Mídia deletada.";
    } catch (e) { return "Erro: $e"; }
  }

  // ===========================================================================
  // ⚽ CÁLCULOS DE ESTATÍSTICAS (Adaptados para SeasonId)
  // ===========================================================================

  /// Recalcula estatísticas de um time específico dentro de uma temporada.
  Future<void> _recalculateTeamStats(String teamId, String seasonId) async {
    debugPrint("[RECALC] Iniciando para Time: $teamId | Season: $seasonId");
    
    int totalMatchPoints = 0;
    int totalGames = 0;
    int totalWins = 0, totalDraws = 0, totalLosses = 0;
    int totalGoalsFor = 0, totalGoalsAgainst = 0;

    // Busca jogos CASA e FORA na coleção correta da temporada
    final matchesRef = _getMatchesRef(seasonId);
    
    // Query auxiliar para processar resultados
    Future<void> processMatches(String side) async {
      final query = await matchesRef
          .where('team_${side}_id', isEqualTo: teamId)
          .where('status', whereIn: ['finished', 'in_progress']) // Considera jogos rolando
          .where('phase', isEqualTo: 'first')
          .get();

      for (final doc in query.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final scoreHome = (data['score_home'] ?? 0) as int;
        final scoreAway = (data['score_away'] ?? 0) as int;

        totalGames++;
        
        int myScore = (side == 'home') ? scoreHome : scoreAway;
        int opponentScore = (side == 'home') ? scoreAway : scoreHome;

        totalGoalsFor += myScore;
        totalGoalsAgainst += opponentScore;

        if (myScore > opponentScore) {
          totalMatchPoints += 3;
          totalWins++;
        } else if (myScore < opponentScore) {
          totalLosses++;
        } else {
          totalMatchPoints += 1;
          totalDraws++;
        }
      }
    }

    await processMatches('home');
    await processMatches('away');

    try {
      final teamRef = _getTeamsRef(seasonId).doc(teamId);
      
      // Precisamos ler os pontos extras atuais para somar
      final teamSnap = await teamRef.get();
      if (!teamSnap.exists) return; // Segurança

      final currentExtraPoints = (teamSnap.data() as Map<String, dynamic>)['extra_points'] as int? ?? 0;
      final int finalTotalPoints = totalMatchPoints + currentExtraPoints;
      final int finalGoalDifference = totalGoalsFor - totalGoalsAgainst;

      await teamRef.update({
        'match_points': totalMatchPoints,
        'points': finalTotalPoints,
        'games_played': totalGames,
        'wins': totalWins,
        'draws': totalDraws,
        'losses': totalLosses,
        'goals_for': totalGoalsFor,
        'goals_against': totalGoalsAgainst,
        'goal_difference': finalGoalDifference,
      });
      debugPrint("[RECALC] Sucesso para Time $teamId.");
    } catch (e) {
      _checkAndLogIndexError(e);
      debugPrint("[RECALC] Erro: $e");
    }
  }

  // ===========================================================================
  // 🏆 CRUD TIMES & JOGADORES (Híbrido)
  // ===========================================================================

  Future<String> createTeam({
    required String seasonId, // <-- OBRIGATÓRIO
    required String name,
    required String shortName,
    required String shieldUrl,
    required List<Map<String, dynamic>> championshipHistory,
  }) async {
    try {
      // Cria na coleção correta (Raiz ou TeamsParticipation)
      final newTeamRef = _getTeamsRef(seasonId).doc();

      await newTeamRef.set({
        'name': name,
        'short_name': shortName,
        'shield_url': shieldUrl,
        'championship_history': championshipHistory,
        // Inicializa stats zerados para a temporada
        'points': 0, 'match_points': 0, 'extra_points': 0,
        'games_played': 0, 'wins': 0, 'draws': 0, 'losses': 0,
        'goals_for': 0, 'goals_against': 0, 'goal_difference': 0,
        'phase1_rank': null,
        'disciplinary_points': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0,
        'default_starters': [],
      });
      return "Sucesso: Equipe '$name' criada.";
    } catch (e) { 
      _checkAndLogIndexError(e);
      return "Erro: $e";
      }
  }

  Future<String> updateTeam({
    required DocumentSnapshot teamDoc,
    required String name,
    required String shortName,
    required String shieldUrl,
    required List<Map<String, dynamic>> championshipHistory,
  }) async {
    try {
      await teamDoc.reference.update({
        'name': name,
        'short_name': shortName,
        'shield_url': shieldUrl,
        'championship_history': championshipHistory,
      });
      return "Sucesso: Equipe '$name' atualizada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> deleteTeam(DocumentSnapshot teamDoc, String seasonId) async {
    // Nota: Deletar time é complexo no modo híbrido.
    // No modo novo, deletaríamos apenas a 'participação' no ano.
    // No modo legado, deletamos tudo.
    
    final teamId = teamDoc.id;
    final WriteBatch batch = _firestore.batch();
    
    try {
      // Remove Jogadores (Global por enquanto, ou específico se fosse migrado)
      // Se estivermos na nova estrutura, deletamos o stats do jogador nesta temporada
      QuerySnapshot playersQ;
      if (seasonId == LEGACY_ID) {
         playersQ = await _playersRef.where('team_id', isEqualTo: teamId).get();
      } else {
         playersQ = await _getPlayerStatsRef(seasonId).where('team_id', isEqualTo: teamId).get();
      }
      for (var p in playersQ.docs) {
        batch.delete(p.reference);
      }

      // 2. Remove Partidas da Temporada (Casa)
      // Aqui usamos a variável que estava gerando o alerta
      final homeMatchesQ = await _getMatchesRef(seasonId)
          .where('team_home_id', isEqualTo: teamId).get();
      
      for (var m in homeMatchesQ.docs) {
        batch.delete(m.reference);
      }

      // 3. Remove Partidas da Temporada (Visitante)
      final awayMatchesQ = await _getMatchesRef(seasonId)
          .where('team_away_id', isEqualTo: teamId).get();
      
      for (var m in awayMatchesQ.docs) {
        batch.delete(m.reference);
      }

      // 4. Remove o Time
      batch.delete(teamDoc.reference);
      
      await batch.commit();
      return "Sucesso: Time, jogadores e partidas associadas foram excluídos.";
    } catch (e) { 
      _checkAndLogIndexError(e);
      return "Erro: $e";
      }
  }

  Future<String> createPlayer({
    required String seasonId, // <-- OBRIGATÓRIO
    required Map<String, dynamic> data,
  }) async {
    try {
      // 1. Cria no Diretório Global (Sempre)
      // Isso gera o ID único do jogador
      final DocumentReference globalRef = await _playersRef.add({
        ...data,
        'isActive': true,
        // Garante que campos de stats globais existam zerados se não vierem
        'goals': 0, 'assists': 0, 'yellow_cards': 0, 'red_cards': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0,
      });

      // 2. Se não for legado, cria também na Temporada Atual
      if (seasonId != LEGACY_ID) {
        final seasonPlayerRef = _getPlayerStatsRef(seasonId).doc(globalRef.id);
        
        // Copia os dados cadastrais, mas ZERA os stats da temporada
        final seasonData = Map<String, dynamic>.from(data);
        seasonData['isActive'] = true;
        seasonData['goals'] = 0;
        seasonData['assists'] = 0;
        seasonData['yellow_cards'] = 0;
        seasonData['red_cards'] = 0;
        seasonData['total_yellow_cards'] = 0;
        seasonData['total_red_cards'] = 0;
        seasonData['man_of_the_match_awards'] = 0;
        seasonData['goals_conceded'] = 0;
        seasonData['is_suspended'] = false;

        await seasonPlayerRef.set(seasonData);
      }

      return "Sucesso: Jogador criado.";
    } catch (e) {
      return "Erro ao criar jogador: $e";
    }
  }

  Future<String> updatePlayer({
    required String seasonId, // <-- OBRIGATÓRIO
    required String playerId,
    required Map<String, dynamic> data,
  }) async {
    try {
      // 1. Atualiza Global
      await _playersRef.doc(playerId).update(data);

      // 2. Se não for legado, atualiza na Temporada
      // (Apenas dados cadastrais: nome, número, foto, posição)
      if (seasonId != LEGACY_ID) {
        final seasonPlayerRef = _getPlayerStatsRef(seasonId).doc(playerId);
        
        // Verifica se o doc existe na temporada (pode ter sido criado antes da migração)
        final docSnap = await seasonPlayerRef.get();
        
        if (docSnap.exists) {
          await seasonPlayerRef.update(data);
        } else {
          // Se não existir na temporada (ex: jogador antigo reativado), cria agora
          // Mantendo stats zerados
          await seasonPlayerRef.set({
            ...data,
            'goals': 0, 'assists': 0, 'yellow_cards': 0, 'red_cards': 0,
            'total_yellow_cards': 0, 'total_red_cards': 0,
            'man_of_the_match_awards': 0, 'goals_conceded': 0,
            'is_suspended': false,
            'isActive': true,
          });
        }
      }
      return "Sucesso: Jogador atualizado.";
    } catch (e) {
      return "Erro ao atualizar jogador: $e";
    }
  }

  Future<String> deletePlayer(DocumentSnapshot doc, String seasonId) async {
    try {
      // Inativa no Global
      await _playersRef.doc(doc.id).update({'isActive': false});

      // Inativa na Temporada (se existir)
      if (seasonId != LEGACY_ID) {
        final seasonRef = _getPlayerStatsRef(seasonId).doc(doc.id);
        // Usamos set com merge ou update com catchError para evitar falha se não existir
        try {
          await seasonRef.update({'isActive': false});
        } catch (_) {}
      }
      return "Sucesso: Jogador inativado.";
    } catch (e) { return "Erro: $e"; }
  }

  // ===========================================================================
  // 🎮 CRUD PARTIDAS (Season Aware)
  // ===========================================================================

  Future<String> createMatch({
    required String seasonId,
    required DocumentSnapshot homeTeam,
    required DocumentSnapshot awayTeam,
    required String location,
    required int round,
    required DateTime dateTime,
  }) async {
    try {
      final hData = homeTeam.data() as Map<String, dynamic>;
      final aData = awayTeam.data() as Map<String, dynamic>;

      await _getMatchesRef(seasonId).add({
        'phase': 'first',
        'round': round,
        'datetime': Timestamp.fromDate(dateTime),
        'location': location,
        'status': 'pending',
        'score_home': null, 'score_away': null,
        'team_home_id': homeTeam.id,
        'team_home_name': hData['name'],
        'team_home_shield': hData['shield_url'],
        'team_away_id': awayTeam.id,
        'team_away_name': aData['name'],
        'team_away_shield': aData['shield_url'],
      });
      return "Sucesso: Partida criada.";
    } catch (e) { 
      _checkAndLogIndexError(e);
      return "Erro: $e"; 
      }
  }

  Future<String> updateMatchDetails({
    required DocumentSnapshot match,
    required DocumentSnapshot homeTeam,
    required DocumentSnapshot awayTeam,
    required String location,
    required int round,
    required DateTime dateTime,
    required String phase,
  }) async {
    try {
      final hData = homeTeam.data() as Map<String, dynamic>;
      final aData = awayTeam.data() as Map<String, dynamic>;

      await match.reference.update({
        'phase': phase, 'round': round,
        'datetime': Timestamp.fromDate(dateTime),
        'location': location,
        'team_home_id': homeTeam.id, 'team_home_name': hData['name'], 'team_home_shield': hData['shield_url'],
        'team_away_id': awayTeam.id, 'team_away_name': aData['name'], 'team_away_shield': aData['shield_url'],
      });
      return "Sucesso: Partida atualizada.";
    } catch (e) { return "Erro: $e"; }
  }

  Future<String> deleteMatch(DocumentSnapshot match, String seasonId) async {
    try {
      final data = match.data() as Map<String, dynamic>;
      final status = data['status'];
      final phase = data['phase'];
      
      await match.reference.delete();

      // Se o jogo estava valendo pontos, recalcula a tabela
      if (status == 'finished' && phase == 'first') {
        await _recalculateTeamStats(data['team_home_id'], seasonId);
        await _recalculateTeamStats(data['team_away_id'], seasonId);
      }
      return "Sucesso: Partida excluída.";
    } catch (e) { 
      _checkAndLogIndexError(e);
      return "Erro: $e"; 
      }
  }

  /// Copia times de uma temporada para outra, zerando estatísticas.
  // --- ATUALIZAR ESTE MÉTODO (Cópia de Temporada) ---
  Future<void> copySeasonData({
    required String sourceSeasonId,
    required String targetSeasonId,
    required bool includeRoster,
  }) async {
    debugPrint("[COPY] Copiando de $sourceSeasonId para $targetSeasonId...");
    final WriteBatch batch = _firestore.batch();
    
    // 1. Copiar Configurações (Settings) - NOVO
    // Vamos copiar do GLOBAL (/config) para a nova temporada para garantir um template limpo
    // Ou poderíamos copiar da temporada anterior. Vamos usar o Global como "Template Mestre".
    final configDocs = ['app_settings', 'disciplinary_rules', 'playoff_rules', 'tiebreaker_rules'];
    for (String docId in configDocs) {
        final docSnap = await _firestore.collection('config').doc(docId).get();
        if (docSnap.exists) {
           final targetRef = _firestore.collection('championships').doc(targetSeasonId).collection('settings').doc(docId);
           batch.set(targetRef, docSnap.data()!);
        }
    }

    // 2. Copiar Times (Mantido igual ao anterior)
    // ... (Lógica de leitura dos times mantida igual ao anterior)
    QuerySnapshot sourceTeamsSnapshot;
    if (sourceSeasonId == LEGACY_ID) {
      sourceTeamsSnapshot = await _firestore.collection('teams').get();
    } else {
      sourceTeamsSnapshot = await _firestore.collection('championships').doc(sourceSeasonId).collection('teams_participation').get();
    }

    final targetTeamsRef = _firestore.collection('championships').doc(targetSeasonId).collection('teams_participation');
    // Referência para os novos stats de jogadores
    final targetPlayerStatsRef = _firestore.collection('championships').doc(targetSeasonId).collection('player_stats');

    for (var teamDoc in sourceTeamsSnapshot.docs) {
      final teamData = teamDoc.data() as Map<String, dynamic>;
      final String teamId = teamDoc.id;

      // A. Cria o Time na Nova Temporada
      Map<String, dynamic> newTeamData = {
        'name': teamData['name'],
        'short_name': teamData['short_name'],
        'shield_url': teamData['shield_url'],
        'championship_history': teamData['championship_history'] ?? [],
        'points': 0, 'match_points': 0, 'extra_points': 0,
        'games_played': 0, 'wins': 0, 'draws': 0, 'losses': 0,
        'goals_for': 0, 'goals_against': 0, 'goal_difference': 0,
        'phase1_rank': null,
        'disciplinary_points': 0,
        'total_yellow_cards': 0, 'total_red_cards': 0,
        'default_starters': includeRoster ? (teamData['default_starters'] ?? []) : [],
      };
      batch.set(targetTeamsRef.doc(teamId), newTeamData);

      // B. (NOVO) Se for manter elenco, cria os stats zerados para os jogadores deste time
      if (includeRoster) {
        // Busca jogadores que pertenciam a este time na temporada de origem
        // Se for legado, busca na raiz. Se for nova, busca na subcoleção de stats.
        QuerySnapshot playersInTeamSnap;
        if (sourceSeasonId == LEGACY_ID) {
           playersInTeamSnap = await _firestore.collection('players')
               .where('team_id', isEqualTo: teamId)
               .where('isActive', isEqualTo: true)
               .get();
        } else {
           playersInTeamSnap = await _firestore.collection('championships').doc(sourceSeasonId).collection('player_stats')
               .where('team_id', isEqualTo: teamId)
               .get();
        }

        for (var playerDoc in playersInTeamSnap.docs) {
          final pData = playerDoc.data() as Map<String, dynamic>;
          
          // Cria o registro "Limpo" para 2026
          batch.set(targetPlayerStatsRef.doc(playerDoc.id), {
            'name': pData['name'],
            'photo_url': pData['photo_url'],
            'position': pData['position'],
            'is_goalkeeper': pData['is_goalkeeper'] ?? false,
            'is_staff': pData['is_staff'] ?? false,
            'jersey_number': pData['jersey_number'],
            'team_id': teamId, // Vincula ao time nesta temporada
            'team_name': teamData['name'],
            'team_shield_url': teamData['shield_url'],
            
            // Zera Stats
            'goals': 0, 'assists': 0, 'goals_conceded': 0,
            'yellow_cards': 0, 'red_cards': 0,
            'total_yellow_cards': 0, 'total_red_cards': 0,
            'man_of_the_match_awards': 0,
            'is_suspended': false,
            'isActive': true,
          });
        }
      }
    }

    await batch.commit();
    debugPrint("[COPY] Times e Jogadores migrados para a temporada.");
  }

  // ===========================================================================
  // 📈 ATUALIZAÇÃO DE STATS E TRANSAÇÃO PRINCIPAL
  // ===========================================================================

  // ===========================================================================
  // 📈 ATUALIZAÇÃO DE STATS E TRANSAÇÃO PRINCIPAL (COMPLETO)
  // ===========================================================================

  Future<String> updateMatchStats({
    required String seasonId,
    required DocumentSnapshot matchSnapshot,
    required String newStatus,
    required int newScoreHome,
    required int newScoreAway,
    required Map<String, int> newGoals,
    required Map<String, int> newAssists,
    required Map<String, int> newYellows,
    required Map<String, int> newReds,
    required Map<String, int> newGoalsConceded,
    required String? newManOfTheMatchId,
    required int? penaltyScoreHome,
    required int? penaltyScoreAway,
    required String? winnerTeamId,
    required String? newSumulaUrl,
    required List<Map<String, dynamic>> newMediaLinks,
  }) async {
    final String matchId = matchSnapshot.id;
    final matchDataBefore = matchSnapshot.data() as Map<String, dynamic>;
    
    final String? homeTeamId = matchDataBefore['team_home_id'];
    final String? awayTeamId = matchDataBefore['team_away_id'];

    if (homeTeamId == null || awayTeamId == null) {
      return "Erro: IDs dos times inválidos.";
    }

    debugPrint("[UPDATE] Season: $seasonId | Match: $matchId");

    // Define as referências corretas baseadas na Temporada
    final CollectionReference matchesRef = _getMatchesRef(seasonId);
    final CollectionReference teamsRef = _getTeamsRef(seasonId);
    // Jogadores continuam globais por enquanto
    final CollectionReference playersRef = _getPlayerStatsRef(seasonId);
    
    // Define onde salvar o log de suspensão (Raiz ou Sub-coleção)
    final CollectionReference suspensionLogRef = (seasonId == LEGACY_ID)
        ? _firestore.collection('suspension_log')
        : _firestore.collection('championships').doc(seasonId).collection('disciplinary_log');

    try {
      await _firestore.runTransaction((transaction) async {
        // 1. LEITURA (CRUCIAL: Deve ser a primeira operação)
        final freshMatchDoc = await transaction.get(matchesRef.doc(matchId));
        if (!freshMatchDoc.exists) throw Exception("Partida não encontrada!");
        
        final currentMatchData = freshMatchDoc.data() as Map<String, dynamic>;
        
        // Lê dados anteriores para calcular a diferença (Delta)
        final oldStats = currentMatchData['stats_applied'] as Map<String, dynamic>? ?? {};
        final oldPlayerStats = oldStats['player_stats'] as Map<String, dynamic>? ?? {};
        
        Map<String, int> oldGoals = Map<String, int>.from(oldPlayerStats['goals'] ?? {});
        Map<String, int> oldAssists = Map<String, int>.from(oldPlayerStats['assists'] ?? {});
        Map<String, int> oldYellows = Map<String, int>.from(oldPlayerStats['yellows'] ?? {});
        Map<String, int> oldReds = Map<String, int>.from(oldPlayerStats['reds'] ?? {});
        Map<String, int> oldGoalsConceded = Map<String, int>.from(oldPlayerStats['goals_conceded'] ?? {});
        String? oldManOfTheMatchId = oldStats['man_of_the_match'];

        // Identifica todos os jogadores envolvidos (antigos e novos) para ler de uma vez
        Set<String> playersToReadIds = {
          ...newGoals.keys, ...oldGoals.keys,
          ...newAssists.keys, ...oldAssists.keys,
          ...newYellows.keys, ...oldYellows.keys,
          ...newReds.keys, ...oldReds.keys,
          ...newGoalsConceded.keys, ...oldGoalsConceded.keys,
          if (newManOfTheMatchId != null) newManOfTheMatchId,
          if (oldManOfTheMatchId != null) oldManOfTheMatchId,
        };
        playersToReadIds.removeWhere((id) => id.isEmpty);

        // Lê documentos dos jogadores e dos times
        Map<String, DocumentSnapshot> playerSnaps = {};
        for (String playerId in playersToReadIds) {
          final snap = await transaction.get(playersRef.doc(playerId));
          if (snap.exists) playerSnaps[playerId] = snap;
        }

        final homeTeamSnap = await transaction.get(teamsRef.doc(homeTeamId));
        final awayTeamSnap = await transaction.get(teamsRef.doc(awayTeamId));
        
        // Recupera logos para o log de suspensão (compatibilidade com UI antiga)
        final homeLogoUrl = (homeTeamSnap.data() as Map<String, dynamic>?)?['shield_url'] ?? '';
        final awayLogoUrl = (awayTeamSnap.data() as Map<String, dynamic>?)?['shield_url'] ?? '';

        // 2. ESCRITA: Atualiza a Partida
        final Map<String, dynamic> newPlayerStatsToSave = {
          'goals': newGoals,
          'assists': newAssists,
          'yellows': newYellows,
          'reds': newReds,
          'goals_conceded': newGoalsConceded,
        };

        transaction.update(freshMatchDoc.reference, {
          'score_home': newScoreHome,
          'score_away': newScoreAway,
          'status': newStatus,
          'penalty_score_home': penaltyScoreHome,
          'penalty_score_away': penaltyScoreAway,
          'winner_team_id': winnerTeamId,
          'sumula_url': newSumulaUrl,
          'stats_applied': {
            'player_stats': newPlayerStatsToSave,
            'man_of_the_match': newManOfTheMatchId,
            'media_links': newMediaLinks,
            // Mantém campos legados vazios para não quebrar estrutura antiga
            'starters_home': [], 
            'starters_away': [],
          },
        });

        // 3. CÁLCULO DE DELTAS E ATUALIZAÇÃO DE JOGADORES
        
        // Variáveis para acumular impacto nos times
        int disciplinaryHomeDelta = 0;
        int disciplinaryAwayDelta = 0;
        int totalYellowHomeDelta = 0;
        int totalYellowAwayDelta = 0;
        int totalRedHomeDelta = 0;
        int totalRedAwayDelta = 0;

        // Calcula diferenças
        Map<String, int> goalDelta = _calculateDelta(oldGoals, newGoals);
        Map<String, int> assistDelta = _calculateDelta(oldAssists, newAssists);
        Map<String, int> goalsConcededDelta = _calculateDelta(oldGoalsConceded, newGoalsConceded);
        Map<String, int> yellowDelta = _calculateDelta(oldYellows, newYellows);
        Map<String, int> redDelta = _calculateDelta(oldReds, newReds);

        // Aplica Gols, Assistências e Gols Sofridos
        goalDelta.forEach((pid, d) {
          if (d != 0 && playerSnaps.containsKey(pid)) transaction.update(playerSnaps[pid]!.reference, {'goals': FieldValue.increment(d)});
        });
        assistDelta.forEach((pid, d) {
          if (d != 0 && playerSnaps.containsKey(pid)) transaction.update(playerSnaps[pid]!.reference, {'assists': FieldValue.increment(d)});
        });
        goalsConcededDelta.forEach((pid, d) {
          if (d != 0 && playerSnaps.containsKey(pid)) transaction.update(playerSnaps[pid]!.reference, {'goals_conceded': FieldValue.increment(d)});
        });

        // Aplica Craque do Jogo (troca de mãos)
        if (oldManOfTheMatchId != newManOfTheMatchId) {
          if (oldManOfTheMatchId != null && playerSnaps.containsKey(oldManOfTheMatchId)) {
            transaction.update(playerSnaps[oldManOfTheMatchId]!.reference, {'man_of_the_match_awards': FieldValue.increment(-1)});
          }
          if (newManOfTheMatchId != null && playerSnaps.containsKey(newManOfTheMatchId)) {
            transaction.update(playerSnaps[newManOfTheMatchId]!.reference, {'man_of_the_match_awards': FieldValue.increment(1)});
          }
        }

        // --- LÓGICA CRÍTICA: CARTÕES E SUSPENSÕES ---
        Set<String> affectedCardPlayerIds = {...yellowDelta.keys, ...redDelta.keys};
        
        for (String playerId in affectedCardPlayerIds) {
          if (!playerSnaps.containsKey(playerId)) continue;

          final playerSnap = playerSnaps[playerId]!;
          final playerData = playerSnap.data() as Map<String, dynamic>? ?? {};

          // Deltas deste jogador específico
          int yDelta = yellowDelta[playerId] ?? 0;
          int rDelta = redDelta[playerId] ?? 0;

          // Estado atual do jogador
          int currentYellows = playerData['yellow_cards'] ?? 0;
          int currentReds = playerData['red_cards'] ?? 0;
          bool currentlySuspended = playerData['is_suspended'] ?? false;
          int currentTotalYellows = playerData['total_yellow_cards'] ?? 0;
          int currentTotalReds = playerData['total_red_cards'] ?? 0;

          // Previsão do novo estado
          int theoreticalNewYellows = currentYellows + yDelta;
          if (theoreticalNewYellows < 0) theoreticalNewYellows = 0;
          
          // Variáveis finais para o update
          int finalYellows = theoreticalNewYellows;
          bool finalSuspension = currentlySuspended;
          String suspensionReason = ""; 

          // REGRA 1: Suspensão por Amarelos
          if (yDelta > 0 && 
              theoreticalNewYellows >= AdminService.suspensionYellowCards && 
              currentYellows < AdminService.suspensionYellowCards) {
             if (!currentlySuspended) {
               finalSuspension = true;
               suspensionReason = "Acúmulo de ${AdminService.suspensionYellowCards} CAs";
             }
             if (AdminService.resetYellowsOnSuspension) finalYellows = 0;
          }
          
          // REGRA 2: Suspensão por Vermelho
          if (rDelta > 0 && AdminService.suspensionOnRed) {
             if (!currentlySuspended) {
               finalSuspension = true;
               suspensionReason = (suspensionReason.isNotEmpty) ? "$suspensionReason + CV" : "Cartão Vermelho";
             }
             if (AdminService.resetYellowsOnRed) finalYellows = 0;
          }

          // REGRA 3: Reversão (Se o admin removeu o cartão que causou suspensão)
          if (yDelta < 0 && theoreticalNewYellows < AdminService.suspensionYellowCards && currentYellows >= AdminService.suspensionYellowCards && (currentReds + rDelta) == 0) {
             finalSuspension = false; // Remove suspensão se cair abaixo do limite e não tiver vermelho
          }
          if (rDelta < 0 && finalYellows < AdminService.suspensionYellowCards) {
             finalSuspension = false; // Remove suspensão se tirou o vermelho e não tem amarelos suficientes
          }

          // LOG DE SUSPENSÃO
          if (suspensionReason.isNotEmpty) {
            final DateTime matchDate = (currentMatchData['datetime'] as Timestamp? ?? Timestamp.now()).toDate();
            final DateTime returnDate = matchDate.add(const Duration(days: 7)); // Lógica simples de +7 dias ou 1 jogo
            
            String teamLogo = '';
            if (playerData['team_id'] == homeTeamId) teamLogo = homeLogoUrl;
            else if (playerData['team_id'] == awayTeamId) teamLogo = awayLogoUrl;

            transaction.set(suspensionLogRef.doc(), {
              'playerId': playerId,
              'playerName': playerData['name'] ?? '?',
              'teamId': playerData['team_id'] ?? '?',
              'teamName': playerData['team_name'] ?? '?',
              'teamLogoUrl': teamLogo,
              'is_staff': playerData['is_staff'] ?? false,
              'timestamp': Timestamp.fromDate(matchDate),
              'return_date': Timestamp.fromDate(returnDate),
              'reason': suspensionReason,
              'matchId_occurred': matchId,
              'match_description': "Rodada ${currentMatchData['round']}: ${currentMatchData['team_home_name']} vs ${currentMatchData['team_away_name']}",
              'status': 'pending', // Status para controle de cumprimento
            });
          }

          // Atualiza Jogador
          transaction.update(playerSnap.reference, {
            'yellow_cards': finalYellows,
            'red_cards': (currentReds + rDelta), // Vermelhos acumulam mas não zeram como os amarelos
            'total_yellow_cards': (currentTotalYellows + yDelta),
            'total_red_cards': (currentTotalReds + rDelta),
            'is_suspended': finalSuspension,
          });

          // Calcula impacto no Time (Pontos Disciplinares)
          final String? pTeamId = playerData['team_id'];
          final int discPoints = (yDelta * 10) + (rDelta * 21); // Regra: CA=10, CV=21
          
          if (pTeamId == homeTeamId) {
            disciplinaryHomeDelta += discPoints;
            totalYellowHomeDelta += yDelta;
            totalRedHomeDelta += rDelta;
          } else if (pTeamId == awayTeamId) {
            disciplinaryAwayDelta += discPoints;
            totalYellowAwayDelta += yDelta;
            totalRedAwayDelta += rDelta;
          }
        }

        // 4. ATUALIZAÇÃO DOS TIMES (DISCIPLINA)
        Map<String, dynamic> homeUpdateData = {};
        if (disciplinaryHomeDelta != 0) homeUpdateData['disciplinary_points'] = FieldValue.increment(disciplinaryHomeDelta);
        if (totalYellowHomeDelta != 0) homeUpdateData['total_yellow_cards'] = FieldValue.increment(totalYellowHomeDelta);
        if (totalRedHomeDelta != 0) homeUpdateData['total_red_cards'] = FieldValue.increment(totalRedHomeDelta);

        Map<String, dynamic> awayUpdateData = {};
        if (disciplinaryAwayDelta != 0) awayUpdateData['disciplinary_points'] = FieldValue.increment(disciplinaryAwayDelta);
        if (totalYellowAwayDelta != 0) awayUpdateData['total_yellow_cards'] = FieldValue.increment(totalYellowAwayDelta);
        if (totalRedAwayDelta != 0) awayUpdateData['total_red_cards'] = FieldValue.increment(totalRedAwayDelta);

        if (homeUpdateData.isNotEmpty) transaction.update(teamsRef.doc(homeTeamId), homeUpdateData);
        if (awayUpdateData.isNotEmpty) transaction.update(teamsRef.doc(awayTeamId), awayUpdateData);
      });

      // 5. PÓS-TRANSAÇÃO: Recálculo de Tabela (Pontos, Vitórias, etc.)
      // Se o status mudou para/de 'finished', ou se é jogo da 1ª fase
      bool needsRecalc = (newStatus == 'finished' || matchDataBefore['status'] == 'finished');
      if (needsRecalc && matchDataBefore['phase'] == 'first') {
        await _recalculateTeamStats(homeTeamId, seasonId);
        await _recalculateTeamStats(awayTeamId, seasonId);
      }

      // 6. AUTOMAÇÃO DE FASES (Opcional: Se for a última rodada)
      // (Mantive simplificado aqui para não extender demais, 
      // mas a lógica do arquivo anterior pode ser colada aqui se desejar automação total)

      return "Sucesso";
    } catch (e) {
      _checkAndLogIndexError(e);
      debugPrint("Erro Update Stats: $e");
      return "Erro: ${e.toString()}";
    }
  }

  // ===========================================================================
  // 🔄 UTILITÁRIOS (Cálculo Delta)
  // ===========================================================================
  Map<String, int> _calculateDelta(Map<String, int> oldMap, Map<String, int> newMap) {
    Map<String, int> delta = {};
    newMap.forEach((k, v) {
      int old = oldMap[k] ?? 0;
      if (v != old) delta[k] = v - old;
    });
    oldMap.forEach((k, v) {
      if (!newMap.containsKey(k) && v > 0) delta[k] = -v;
    });
    return delta;
  }
  
  // Helpers para Semi/Final usando Sorter
  Future<void> generateSemifinals(String seasonId) async {
     // Implementação adaptada lendo de _getTeamsRef(seasonId) e _getMatchesRef(seasonId)
     // e usando StandingsSorter.
  }
}