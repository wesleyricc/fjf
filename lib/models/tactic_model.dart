import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/player_model.dart';
import '../widgets/tactical_drawing_painter.dart'; // Para ShapeType

class TacticModel {
  final String id;
  final String teamId;
  final String name;
  final DateTime createdAt;
  final int maxMoments;
  final double canvasWidth;
  final double canvasHeight;
  final List<TacticPlayer> players;
  final List<TacticLine> lines;

  TacticModel({
    required this.id,
    required this.teamId,
    required this.name,
    required this.createdAt,
    required this.maxMoments,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.players,
    required this.lines,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teamId': teamId,
      'name': name,
      'createdAt': Timestamp.fromDate(createdAt),
      'maxMoments': maxMoments,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
      'players': players.map((p) => p.toJson()).toList(),
      'lines': lines.map((l) => l.toJson()).toList(),
    };
  }

  factory TacticModel.fromJson(Map<String, dynamic> json) {
    return TacticModel(
      id: json['id'] as String,
      teamId: json['teamId'] as String,
      name: json['name'] as String,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      maxMoments: json['maxMoments'] as int? ?? 1,
      canvasWidth: (json['canvasWidth'] as num?)?.toDouble() ?? 1000.0,
      canvasHeight: (json['canvasHeight'] as num?)?.toDouble() ?? 1000.0,
      players: (json['players'] as List<dynamic>?)
              ?.map((e) => TacticPlayer.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      lines: (json['lines'] as List<dynamic>?)
              ?.map((e) => TacticLine.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }
}

class TacticPlayer {
  final Player player;
  final Offset initialPosition;
  final int appearAtMoment;
  final bool isOpponent;
  final double rotation;
  final Map<int, List<Offset>> trajectories;

  TacticPlayer({
    required this.player,
    required this.initialPosition,
    required this.appearAtMoment,
    required this.isOpponent,
    required this.rotation,
    required this.trajectories,
  });

  Map<String, dynamic> toJson() {
    return {
      'player': player.toMap(),
      'initialPosition': {'dx': initialPosition.dx, 'dy': initialPosition.dy},
      'appearAtMoment': appearAtMoment,
      'isOpponent': isOpponent,
      'rotation': rotation,
      'trajectories': trajectories.map((key, value) => MapEntry(
            key.toString(),
            value.map((e) => {'dx': e.dx, 'dy': e.dy}).toList(),
          )),
    };
  }

  factory TacticPlayer.fromJson(Map<String, dynamic> json) {
    return TacticPlayer(
      player: Player.fromMap(Map<String, dynamic>.from(json['player'] as Map)),
      initialPosition: Offset(
        (json['initialPosition']['dx'] as num).toDouble(),
        (json['initialPosition']['dy'] as num).toDouble(),
      ),
      appearAtMoment: json['appearAtMoment'] as int? ?? 0,
      isOpponent: json['isOpponent'] as bool? ?? false,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      trajectories: (json['trajectories'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              int.parse(key),
              (value as List<dynamic>)
                  .map((e) => Offset(
                        ((e as Map)['dx'] as num).toDouble(),
                        (e['dy'] as num).toDouble(),
                      ))
                  .toList(),
            ),
          ) ??
          {},
    );
  }
}

class TacticLine {
  final ShapeType type;
  final Color color;
  final double strokeWidth;
  final List<Offset> points;

  TacticLine({
    required this.type,
    required this.color,
    required this.strokeWidth,
    required this.points,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'color': color.value,
      'strokeWidth': strokeWidth,
      'points': points.map((e) => {'dx': e.dx, 'dy': e.dy}).toList(),
    };
  }

  factory TacticLine.fromJson(Map<String, dynamic> json) {
    return TacticLine(
      type: ShapeType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ShapeType.freehand,
      ),
      color: Color(json['color'] as int? ?? Colors.black.value),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 4.0,
      points: (json['points'] as List<dynamic>?)
              ?.map((e) => Offset(
                    ((e as Map)['dx'] as num).toDouble(),
                    (e['dy'] as num).toDouble(),
                  ))
              .toList() ??
          [],
    );
  }
}
