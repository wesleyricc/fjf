import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FantasyScoutAppeal {
  final String id;
  final String userId;
  final String userName;
  final String userTeamName;
  final String seasonId;
  final int round;
  final String matchId;
  final String matchLabel;
  final String period;
  final String minute;
  final String playerId;
  final String playerName;
  final String playerTeamName;
  final String scoutType;
  final String actionType;
  final String description;
  final String? videoUrl;
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? adminFeedback;

  FantasyScoutAppeal({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userTeamName,
    required this.seasonId,
    required this.round,
    required this.matchId,
    required this.matchLabel,
    required this.period,
    required this.minute,
    required this.playerId,
    required this.playerName,
    required this.playerTeamName,
    required this.scoutType,
    required this.actionType,
    required this.description,
    this.videoUrl,
    this.status = 'pending',
    required this.createdAt,
    this.reviewedAt,
    this.reviewedBy,
    this.adminFeedback,
  });

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'user_name': userName,
      'user_team_name': userTeamName,
      'season_id': seasonId,
      'round': round,
      'match_id': matchId,
      'match_label': matchLabel,
      'period': period,
      'minute': minute,
      'player_id': playerId,
      'player_name': playerName,
      'player_team_name': playerTeamName,
      'scout_type': scoutType,
      'action_type': actionType,
      'description': description,
      'video_url': videoUrl,
      'status': status,
      'created_at': Timestamp.fromDate(createdAt),
      'reviewed_at': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewed_by': reviewedBy,
      'admin_feedback': adminFeedback,
    };
  }

  factory FantasyScoutAppeal.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return FantasyScoutAppeal(
      id: doc.id,
      userId: data['user_id'] ?? '',
      userName: data['user_name'] ?? 'Cartoleiro',
      userTeamName: data['user_team_name'] ?? 'Time',
      seasonId: data['season_id'] ?? '',
      round: (data['round'] as num?)?.toInt() ?? 1,
      matchId: data['match_id'] ?? '',
      matchLabel: data['match_label'] ?? 'Partida',
      period: data['period'] ?? '1º Tempo',
      minute: data['minute'] ?? '',
      playerId: data['player_id'] ?? '',
      playerName: data['player_name'] ?? '',
      playerTeamName: data['player_team_name'] ?? '',
      scoutType: data['scout_type'] ?? 'Outro',
      actionType: data['action_type'] ?? 'Adicionar scout',
      description: data['description'] ?? '',
      videoUrl: data['video_url'],
      status: data['status'] ?? 'pending',
      createdAt: parseDate(data['created_at']),
      reviewedAt: data['reviewed_at'] != null ? parseDate(data['reviewed_at']) : null,
      reviewedBy: data['reviewed_by'],
      adminFeedback: data['admin_feedback'],
    );
  }

  String get statusLabel {
    switch (status) {
      case 'approved':
        return 'Aprovada';
      case 'rejected':
        return 'Recusada';
      case 'pending':
      default:
        return 'Em Análise';
    }
  }

  Color get statusColor {
    switch (status) {
      case 'approved':
        return Colors.green.shade700;
      case 'rejected':
        return Colors.red.shade700;
      case 'pending':
      default:
        return Colors.amber.shade800;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'approved':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      case 'pending':
      default:
        return Icons.hourglass_top_rounded;
    }
  }
}
