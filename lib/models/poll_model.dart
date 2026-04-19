import 'package:cloud_firestore/cloud_firestore.dart';

class Poll {
  final String id;
  final String title;
  final String category; // Ex: 'craque_rodada', 'bola_cheia', 'selecao'
  final bool isActive;
  final String? videoUrl; // Link do YouTube ou Instagram

  Poll({
    required this.id,
    required this.title,
    required this.category,
    required this.isActive,
    this.videoUrl,
  });

  factory Poll.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Poll(
      id: doc.id,
      title: data['title'] ?? 'Votação',
      category: data['category'] ?? 'geral',
      isActive: data['is_active'] ?? false,
      videoUrl: data['video_url'],
    );
  }
}

class Nominee {
  final String id;
  final String playerId;
  final String playerName;
  final String playerPhotoUrl;
  final String teamName;
  final String teamShieldUrl;
  final int voteCount;

  Nominee({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.playerPhotoUrl,
    required this.teamName,
    required this.teamShieldUrl,
    required this.voteCount,
  });

  factory Nominee.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Nominee(
      id: doc.id,
      playerId: data['player_id'] ?? '',
      playerName: data['player_name'] ?? 'Atleta',
      playerPhotoUrl: data['player_photo_url'] ?? '',
      teamName: data['team_name'] ?? '',
      teamShieldUrl: data['team_shield_url'] ?? '',
      voteCount: data['vote_count'] ?? 0,
    );
  }
}