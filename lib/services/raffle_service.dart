import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/team_model.dart';
import '../models/player_model.dart';

enum RaffleMode {
  team,
  athlete,
  teamAndAthlete,
}

extension RaffleModeExt on RaffleMode {
  String get label {
    switch (this) {
      case RaffleMode.team:
        return '1 Time';
      case RaffleMode.athlete:
        return '1 Atleta';
      case RaffleMode.teamAndAthlete:
        return 'Time + Atleta';
    }
  }

  String get description {
    switch (this) {
      case RaffleMode.team:
        return 'Sortear 1 time daquela temporada';
      case RaffleMode.athlete:
        return 'Sortear 1 atleta daquela temporada';
      case RaffleMode.teamAndAthlete:
        return 'Sortear 1 time e um atleta daquela equipe naquela temporada';
    }
  }
}

class RaffleResult {
  final String id;
  final RaffleMode mode;
  final String seasonId;
  final String seasonName;
  final Team? team;
  final Player? athlete;
  final DateTime drawnAt;

  RaffleResult({
    required this.id,
    required this.mode,
    required this.seasonId,
    required this.seasonName,
    this.team,
    this.athlete,
    required this.drawnAt,
  });

  String get summaryText {
    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(drawnAt);
    final sb = StringBuffer();
    sb.writeln('🎉 *RESULTADO DO SORTEIO OFICIAL - FJF* 🎉');
    sb.writeln('🏆 Temporada: $seasonName');
    sb.writeln('📋 Modalidade: ${mode.description}');
    sb.writeln('📅 Data/Hora: $dateStr');
    sb.writeln('────────────────────────────');

    switch (mode) {
      case RaffleMode.team:
        if (team != null) {
          sb.writeln('🛡️ *Equipe Sorteada:* ${team!.name}${team!.shortName.isNotEmpty ? ' (${team!.shortName})' : ''}');
        }
        break;
      case RaffleMode.athlete:
        if (athlete != null) {
          final number = athlete!.jerseyNumber != null ? '#${athlete!.jerseyNumber} ' : '';
          sb.writeln('🏃 *Atleta Sorteado:* $number${athlete!.name}');
          if (athlete!.position != null && athlete!.position!.isNotEmpty) {
            sb.writeln('⚽ *Posição:* ${athlete!.position}');
          }
          if (athlete!.teamName.isNotEmpty) {
            sb.writeln('🛡️ *Equipe:* ${athlete!.teamName}');
          }
        }
        break;
      case RaffleMode.teamAndAthlete:
        if (team != null) {
          sb.writeln('🛡️ *Equipe Sorteada:* ${team!.name}');
        }
        if (athlete != null) {
          final number = athlete!.jerseyNumber != null ? '#${athlete!.jerseyNumber} ' : '';
          sb.writeln('🏃 *Atleta Sorteado:* $number${athlete!.name}');
          if (athlete!.position != null && athlete!.position!.isNotEmpty) {
            sb.writeln('⚽ *Posição:* ${athlete!.position}');
          }
        }
        break;
    }
    sb.writeln('────────────────────────────');
    sb.writeln('Gerado pelo App Força Jovem Fumacense');
    return sb.toString();
  }
}

class RaffleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Random _random = Random();

  /// Busca as temporadas disponíveis no Firestore
  Future<List<Map<String, dynamic>>> fetchSeasons() async {
    try {
      final snapshot = await _firestore.collection('championships').get();
      final seasons = snapshot.docs.map((doc) {
        final data = doc.data();
        int parsedYear = DateTime.now().year;
        if (data['year'] != null) {
          parsedYear = int.tryParse(data['year'].toString()) ?? parsedYear;
        }
        return {
          'id': doc.id,
          'name': data['name'] ?? doc.id,
          'year': parsedYear,
          'isActive': data['is_active'] ?? false,
        };
      }).toList();

      seasons.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
      return seasons;
    } catch (e) {
      debugPrint('Erro ao buscar temporadas para sorteio: $e');
      return [];
    }
  }

  /// Busca times participantes de uma temporada
  Future<List<Team>> fetchTeams(String seasonId) async {
    if (seasonId.isEmpty) return [];
    try {
      final snapshot = await _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('teams_participation')
          .get();

      List<Team> teams =
          snapshot.docs.map((doc) => Team.fromFirestore(doc)).toList();

      // Se algum time estiver com escudo vazio, busca em teams_directory e assets
      final bool hasMissingShield =
          teams.any((t) => t.shieldUrl.trim().isEmpty);

      if (hasMissingShield) {
        final Map<String, String> fallbackShields = {};

        // 1. Busca em teams_directory
        try {
          final dirSnap = await _firestore.collection('teams_directory').get();
          for (var doc in dirSnap.docs) {
            final data = doc.data();
            final url = (data['shield_url'] ??
                    data['shieldUrl'] ??
                    data['logo_url'] ??
                    '')
                .toString()
                .trim();
            if (url.isNotEmpty) {
              fallbackShields[doc.id.toLowerCase()] = url;
              if (data['name'] != null) {
                fallbackShields[data['name'].toString().trim().toLowerCase()] =
                    url;
              }
            }
          }
        } catch (e) {
          debugPrint('Aviso ao consultar teams_directory para escudos: $e');
        }

        // 2. Busca no arquivo local assets/data/teams.json como backup garantido
        try {
          final jsonString =
              await rootBundle.loadString('assets/data/teams.json');
          final Map<String, dynamic> localTeams = json.decode(jsonString);
          localTeams.forEach((key, val) {
            final url = (val['shield_url'] ?? val['shieldUrl'] ?? '')
                .toString()
                .trim();
            if (url.isNotEmpty) {
              fallbackShields[key.toLowerCase()] = url;
              final name = val['name']?.toString().trim().toLowerCase();
              if (name != null) {
                fallbackShields[name] = url;
              }
            }
          });
        } catch (e) {
          debugPrint('Aviso ao carregar assets/data/teams.json: $e');
        }

        // Aplica o escudo recuperado caso esteja vazio
        teams = teams.map((team) {
          if (team.shieldUrl.trim().isNotEmpty) return team;

          final resolved = fallbackShields[team.id.toLowerCase()] ??
              fallbackShields[team.name.trim().toLowerCase()] ??
              '';

          if (resolved.isNotEmpty) {
            return team.copyWith(shieldUrl: resolved);
          }
          return team;
        }).toList();
      }

      teams.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return teams;
    } catch (e) {
      debugPrint('Erro ao buscar times da temporada $seasonId: $e');
      return [];
    }
  }

  /// Busca atletas de uma temporada
  Future<List<Player>> fetchAthletes(
    String seasonId, {
    bool activeOnly = true,
    bool excludeStaff = true,
  }) async {
    if (seasonId.isEmpty) return [];
    try {
      final snapshot = await _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('player_stats')
          .get();

      List<Player> players =
          snapshot.docs.map((doc) => Player.fromFirestore(doc)).toList();

      if (activeOnly) {
        players = players.where((p) => p.isActive).toList();
      }

      if (excludeStaff) {
        players = players.where((p) => !p.isStaff).toList();
      }

      players.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return players;
    } catch (e) {
      debugPrint('Erro ao buscar atletas da temporada $seasonId: $e');
      return [];
    }
  }

  /// Sorteia 1 time aleatório da lista de times fornecida
  Team? drawRandomTeam(List<Team> teams) {
    if (teams.isEmpty) return null;
    final index = _random.nextInt(teams.length);
    return teams[index];
  }

  /// Sorteia 1 atleta aleatório da lista de atletas fornecida
  Player? drawRandomAthlete(List<Player> athletes) {
    if (athletes.isEmpty) return null;
    final index = _random.nextInt(athletes.length);
    return athletes[index];
  }

  /// Sorteia 1 time e 1 atleta daquela equipe
  ({Team? team, Player? athlete}) drawRandomTeamAndAthlete({
    required List<Team> teams,
    required List<Player> athletes,
    Team? preselectedTeam,
  }) {
    if (teams.isEmpty) return (team: null, athlete: null);

    // Se houver um time pré-selecionado, usa ele; senão, sorteia um time
    Team? selectedTeam = preselectedTeam;

    if (selectedTeam == null) {
      // Prioriza times que possuem ao menos 1 atleta na lista
      final teamsWithPlayers = teams.where((team) {
        return athletes.any((p) => _playerBelongsToTeam(p, team));
      }).toList();

      final pool = teamsWithPlayers.isNotEmpty ? teamsWithPlayers : teams;
      selectedTeam = pool[_random.nextInt(pool.length)];
    }

    // Filtra os atletas pertencentes à equipe sorteada
    final teamAthletes = athletes
        .where((p) => _playerBelongsToTeam(p, selectedTeam!))
        .toList();

    Player? selectedAthlete;
    if (teamAthletes.isNotEmpty) {
      selectedAthlete = teamAthletes[_random.nextInt(teamAthletes.length)];
    }

    return (team: selectedTeam, athlete: selectedAthlete);
  }

  bool _playerBelongsToTeam(Player player, Team team) {
    if (player.teamId.isNotEmpty && player.teamId == team.id) {
      return true;
    }
    if (player.teamName.isNotEmpty &&
        player.teamName.trim().toLowerCase() == team.name.trim().toLowerCase()) {
      return true;
    }
    return false;
  }
}
