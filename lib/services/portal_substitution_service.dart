import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/player_model.dart';
import '../models/portal_substitution_model.dart';

class PortalSubstitutionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache em memória para garantir funcionamento mesmo se houver falha transitória de rede/permissão
  static final Map<String, TeamSubstitutionSession> _memoryFallbackCache = {};

  CollectionReference get _collection =>
      _firestore.collection('portal_substitutions');

  /// Stream em tempo real da sessão de substituições da equipe
  Stream<TeamSubstitutionSession?> streamSession(String teamId) {
    if (teamId.isEmpty) return Stream.value(null);
    return _collection.doc(teamId).snapshots().map((doc) {
      if (!doc.exists) {
        return _memoryFallbackCache[teamId];
      }
      final session = TeamSubstitutionSession.fromFirestore(doc);
      _memoryFallbackCache[teamId] = session;
      return session;
    }).handleError((error) {
      debugPrint("Aviso no stream de substituições: $error");
      return _memoryFallbackCache[teamId];
    });
  }

  /// Busca pontual da sessão atual
  Future<TeamSubstitutionSession?> getSession(String teamId) async {
    if (teamId.isEmpty) return null;
    try {
      final doc = await _collection.doc(teamId).get();
      if (doc.exists) {
        final session = TeamSubstitutionSession.fromFirestore(doc);
        _memoryFallbackCache[teamId] = session;
        return session;
      }
    } catch (e) {
      debugPrint("Aviso ao buscar sessão de substituições: $e");
    }
    return _memoryFallbackCache[teamId];
  }

  /// Sincroniza o elenco com o documento no Firestore
  /// Mantém o progresso dos atletas já cadastrados e adiciona novos jogadores da equipe
  Future<TeamSubstitutionSession> syncRosterWithSession({
    required String teamId,
    required String teamName,
    required List<Player> roster,
    String matchName = 'Partida Atual',
  }) async {
    final now = DateTime.now();
    Map<String, PlayerSubstitutionState> existingStates = {};
    DateTime startedAt = now;
    String currentMatchName = matchName;
    bool docExists = false;

    try {
      final docRef = _collection.doc(teamId);
      final docSnap = await docRef.get();
      if (docSnap.exists) {
        docExists = true;
        final existingSession = TeamSubstitutionSession.fromFirestore(docSnap);
        existingStates = Map.from(existingSession.playerStates);
        startedAt = existingSession.startedAt;
        currentMatchName = existingSession.matchName;
      }
    } catch (e) {
      debugPrint("Aviso ao ler sessão do Firestore: $e");
      if (_memoryFallbackCache.containsKey(teamId)) {
        final cached = _memoryFallbackCache[teamId]!;
        existingStates = Map.from(cached.playerStates);
        startedAt = cached.startedAt;
        currentMatchName = cached.matchName;
        docExists = true;
      }
    }

    // Filtra apenas atletas (exclui comissão técnica pura sem número/posição de jogo se aplicável)
    final athletes = roster.where((p) => !p.isStaff || p.position != null).toList();

    bool hasNewAthletes = false;
    for (var athlete in athletes) {
      if (!existingStates.containsKey(athlete.id)) {
        hasNewAthletes = true;
        existingStates[athlete.id] = PlayerSubstitutionState(
          playerId: athlete.id,
          playerName: athlete.name,
          jerseyNumber: athlete.jerseyNumber,
          photoUrl: athlete.photoUrl,
          position: athlete.position,
          isGoalkeeper: athlete.isGoalkeeper,
          isOnCourt: false,
          currentEnteredAt: null,
          initialOffsetSeconds: 0,
          maxContinuousSeconds: 0,
          totalSecondsPlayed: 0,
          stints: [],
        );
      }
    }

    final session = TeamSubstitutionSession(
      id: teamId,
      teamId: teamId,
      teamName: teamName,
      matchName: currentMatchName,
      startedAt: startedAt,
      updatedAt: now,
      playerStates: existingStates,
    );

    _memoryFallbackCache[teamId] = session;

    if (!docExists || hasNewAthletes) {
      try {
        await _collection.doc(teamId).set(session.toMap(), SetOptions(merge: true));
      } catch (e) {
        debugPrint("Aviso ao persistir sessão no Firestore: $e");
      }
    }

    return session;
  }

  /// Registra a entrada de um atleta em quadra
  /// Pode simultaneamente registrar a saída de outro atleta (substituição casada)
  Future<void> recordPlayerEntry({
    required String teamId,
    required String playerId,
    int initialOffsetSeconds = 0,
    String? playerOutId,
  }) async {
    final session = await getSession(teamId);
    if (session == null) return;

    final states = Map<String, PlayerSubstitutionState>.from(session.playerStates);
    final now = DateTime.now();

    // 1. Processa saída de quem estava em quadra (se informado)
    if (playerOutId != null && states.containsKey(playerOutId)) {
      final playerOut = states[playerOutId]!;
      if (playerOut.isOnCourt) {
        final elapsed = playerOut.getCurrentStintElapsedSeconds(now: now);
        final newStints = List<PlayerStint>.from(playerOut.stints)
          ..add(PlayerStint(
            enteredAt: playerOut.currentEnteredAt ?? now,
            leftAt: now,
            durationSeconds: elapsed,
            initialOffsetSeconds: playerOut.initialOffsetSeconds,
            note: 'Substituído por ${states[playerId]?.playerName ?? 'atleta'}',
          ));

        states[playerOutId] = playerOut.copyWith(
          isOnCourt: false,
          currentEnteredAt: null,
          initialOffsetSeconds: 0,
          maxContinuousSeconds: math.max(playerOut.maxContinuousSeconds, elapsed),
          totalSecondsPlayed: playerOut.totalSecondsPlayed + elapsed,
          stints: newStints,
        );
      }
    }

    // 2. Processa entrada do atleta
    if (states.containsKey(playerId)) {
      final playerIn = states[playerId]!;
      states[playerId] = playerIn.copyWith(
        isOnCourt: true,
        currentEnteredAt: now,
        initialOffsetSeconds: initialOffsetSeconds,
      );
    }

    final updatedSession = TeamSubstitutionSession(
      id: teamId,
      teamId: teamId,
      teamName: session.teamName,
      matchName: session.matchName,
      startedAt: session.startedAt,
      updatedAt: now,
      playerStates: states,
    );
    _memoryFallbackCache[teamId] = updatedSession;

    try {
      await _collection.doc(teamId).update({
        'player_states': states.map((k, v) => MapEntry(k, v.toMap())),
        'updated_at': Timestamp.fromDate(now),
      });
    } catch (e) {
      debugPrint("Aviso ao atualizar entrada no Firestore: $e");
    }
  }

  /// Registra a saída de um atleta de quadra
  Future<void> recordPlayerExit({
    required String teamId,
    required String playerId,
  }) async {
    final session = await getSession(teamId);
    if (session == null) return;

    final states = Map<String, PlayerSubstitutionState>.from(session.playerStates);
    final now = DateTime.now();

    if (states.containsKey(playerId)) {
      final player = states[playerId]!;
      if (player.isOnCourt) {
        final elapsed = player.getCurrentStintElapsedSeconds(now: now);
        final newStints = List<PlayerStint>.from(player.stints)
          ..add(PlayerStint(
            enteredAt: player.currentEnteredAt ?? now,
            leftAt: now,
            durationSeconds: elapsed,
            initialOffsetSeconds: player.initialOffsetSeconds,
            note: 'Ida para o banco',
          ));

        states[playerId] = player.copyWith(
          isOnCourt: false,
          currentEnteredAt: null,
          initialOffsetSeconds: 0,
          maxContinuousSeconds: math.max(player.maxContinuousSeconds, elapsed),
          totalSecondsPlayed: player.totalSecondsPlayed + elapsed,
          stints: newStints,
        );

        final updatedSession = TeamSubstitutionSession(
          id: teamId,
          teamId: teamId,
          teamName: session.teamName,
          matchName: session.matchName,
          startedAt: session.startedAt,
          updatedAt: now,
          playerStates: states,
        );
        _memoryFallbackCache[teamId] = updatedSession;

        try {
          await _collection.doc(teamId).update({
            'player_states': states.map((k, v) => MapEntry(k, v.toMap())),
            'updated_at': Timestamp.fromDate(now),
          });
        } catch (e) {
          debugPrint("Aviso ao atualizar saída no Firestore: $e");
        }
      }
    }
  }

  /// Ajusta o tempo do atleta (para correções manuais durante a partida)
  Future<void> adjustPlayerTime({
    required String teamId,
    required String playerId,
    required int additionalSeconds,
  }) async {
    final session = await getSession(teamId);
    if (session == null) return;

    final states = Map<String, PlayerSubstitutionState>.from(session.playerStates);
    final now = DateTime.now();

    if (states.containsKey(playerId)) {
      final player = states[playerId]!;
      if (player.isOnCourt) {
        final newOffset = math.max(0, player.initialOffsetSeconds + additionalSeconds);
        states[playerId] = player.copyWith(initialOffsetSeconds: newOffset);
      } else {
        final newMax = math.max(0, player.maxContinuousSeconds + additionalSeconds);
        final newTotal = math.max(0, player.totalSecondsPlayed + additionalSeconds);
        states[playerId] = player.copyWith(
          maxContinuousSeconds: newMax,
          totalSecondsPlayed: newTotal,
        );
      }

      final updatedSession = TeamSubstitutionSession(
        id: teamId,
        teamId: teamId,
        teamName: session.teamName,
        matchName: session.matchName,
        startedAt: session.startedAt,
        updatedAt: now,
        playerStates: states,
      );
      _memoryFallbackCache[teamId] = updatedSession;

      try {
        await _collection.doc(teamId).update({
          'player_states': states.map((k, v) => MapEntry(k, v.toMap())),
          'updated_at': Timestamp.fromDate(now),
        });
      } catch (e) {
        debugPrint("Aviso ao ajustar tempo no Firestore: $e");
      }
    }
  }

  /// Reseta todos os cronômetros e histórico para iniciar uma nova partida
  Future<void> resetSession({
    required String teamId,
    required String teamName,
    required List<Player> roster,
    String matchName = 'Partida Atual',
  }) async {
    final now = DateTime.now();
    final athletes = roster.where((p) => !p.isStaff || p.position != null).toList();
    final Map<String, PlayerSubstitutionState> freshStates = {};

    for (var athlete in athletes) {
      freshStates[athlete.id] = PlayerSubstitutionState(
        playerId: athlete.id,
        playerName: athlete.name,
        jerseyNumber: athlete.jerseyNumber,
        photoUrl: athlete.photoUrl,
        position: athlete.position,
        isGoalkeeper: athlete.isGoalkeeper,
        isOnCourt: false,
        currentEnteredAt: null,
        initialOffsetSeconds: 0,
        maxContinuousSeconds: 0,
        totalSecondsPlayed: 0,
        stints: [],
      );
    }

    final session = TeamSubstitutionSession(
      id: teamId,
      teamId: teamId,
      teamName: teamName,
      matchName: matchName,
      startedAt: now,
      updatedAt: now,
      playerStates: freshStates,
    );

    _memoryFallbackCache[teamId] = session;

    try {
      await _collection.doc(teamId).set(session.toMap());
    } catch (e) {
      debugPrint("Aviso ao resetar sessão no Firestore: $e");
    }
  }
}
