import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/player_model.dart';
import '../services/player_service.dart';
import '../services/portal_auth_service.dart';

class EditPlayerViewModel extends ChangeNotifier {
  final PlayerService _playerService;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Player? _existingPlayer;
  
  bool isUploading = false;
  bool isStaff = false;
  bool isGoalkeeper = false;
  
  String? selectedPosition;
  String? secondaryPosition; // NEW FIELD
  String? selectedFoot;
  String? selectedStaffRole;
  double? fantasyInitialPrice; // NEW FIELD
  
  bool createPortalAccess = false;
  String portalPassword = '';
  
  String? photoUrl;
  File? imageFile;
  Uint8List? webImageBytes;

  EditPlayerViewModel(this._playerService, this._existingPlayer) {
    if (_existingPlayer != null) {
      isStaff = _existingPlayer.isStaff;
      isGoalkeeper = _existingPlayer.isGoalkeeper;
      photoUrl = _existingPlayer.photoUrl;
      
      if (isStaff) {
        selectedStaffRole = _existingPlayer.staffRole;
      } else {
        selectedPosition = ['Fixo', 'Ala', 'Pivô'].contains(_existingPlayer.position) 
            ? _existingPlayer.position 
            : null;
        secondaryPosition = ['Fixo', 'Ala', 'Pivô'].contains(_existingPlayer.secondaryPosition) 
            ? _existingPlayer.secondaryPosition 
            : null;
      }
      selectedFoot = ['Destro', 'Canhoto', 'Ambidestro'].contains(_existingPlayer.preferredFoot) 
          ? _existingPlayer.preferredFoot 
          : null;
      fantasyInitialPrice = _existingPlayer.fantasyInitialPrice;
    }
  }

  void setStaff(bool value) {
    isStaff = value;
    if (isStaff) {
      isGoalkeeper = false;
      selectedPosition = null;
      secondaryPosition = null;
    } else {
      selectedStaffRole = null;
    }
    notifyListeners();
  }

  void setGoalkeeper(bool value) {
    isGoalkeeper = value;
    if (isGoalkeeper) selectedPosition = null;
    notifyListeners();
  }

  void setPosition(String? pos) { selectedPosition = pos; notifyListeners(); }
  void setSecondaryPosition(String? pos) { secondaryPosition = pos; notifyListeners(); }
  void setFoot(String? foot) { selectedFoot = foot; notifyListeners(); }
  void setStaffRole(String? role) { selectedStaffRole = role; notifyListeners(); }
  void setFantasyInitialPrice(double? val) { fantasyInitialPrice = val; notifyListeners(); }
  
  void setCreatePortalAccess(bool value) { createPortalAccess = value; notifyListeners(); }
  void setPortalPassword(String value) { portalPassword = value; notifyListeners(); }

  void clearImage() {
    photoUrl = null;
    imageFile = null;
    webImageBytes = null;
    notifyListeners();
  }

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 1000,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          webImageBytes = await pickedFile.readAsBytes();
        } else {
          imageFile = File(pickedFile.path);
        }
        photoUrl = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Erro ao selecionar imagem com ImagePicker: $e");
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(type: FileType.image);
        if (result != null && result.files.single.bytes != null) {
          webImageBytes = result.files.single.bytes;
          photoUrl = null;
          notifyListeners();
        }
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (imageFile == null && webImageBytes == null) return photoUrl;
    
    final String fileId = _existingPlayer?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    String fileName = 'players/$fileId.jpg';
    
    try {
      UploadTask uploadTask;
      final ref = _storage.ref().child(fileName);
      final metadata = SettableMetadata(contentType: 'image/jpeg');

      if (kIsWeb && webImageBytes != null) {
        uploadTask = ref.putData(webImageBytes!, metadata);
      } else if (imageFile != null) {
        uploadTask = ref.putFile(imageFile!, metadata);
      } else {
        return null;
      }

      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Erro upload: $e");
      return null;
    }
  }

  Future<String> savePlayer({
    required String seasonId,
    required String teamId,
    required String teamName,
    String? teamShieldUrl,
    required String name,
    required int? jerseyNumber,
    required Timestamp? dobTimestamp,
    required int? heightCm,
    required int? weightKg,
    required String instagram,
    required String phone,
    PortalAuthService? portalAuthService,
  }) async {
    if (isStaff && selectedStaffRole == null) {
      return "Selecione a função da comissão técnica.";
    }

    isUploading = true;
    notifyListeners();

    try {
      String? uploadedPhotoUrl = await _uploadImage();

      // Garante que o team_shield_url do atleta seja sempre preenchido com o escudo do time
      String? finalShieldUrl = teamShieldUrl;
      if (finalShieldUrl == null || finalShieldUrl.trim().isEmpty) {
        try {
          final teamPartDoc = await FirebaseFirestore.instance
              .collection('championships')
              .doc(seasonId)
              .collection('teams_participation')
              .doc(teamId)
              .get();
          if (teamPartDoc.exists) {
            finalShieldUrl = teamPartDoc.data()?['shield_url'];
          }
          if (finalShieldUrl == null || finalShieldUrl.trim().isEmpty) {
            final teamDirDoc = await FirebaseFirestore.instance
                .collection('teams_directory')
                .doc(teamId)
                .get();
            if (teamDirDoc.exists) {
              finalShieldUrl = teamDirDoc.data()?['shield_url'];
            }
          }
        } catch (e) {
          debugPrint("Aviso: falha ao buscar escudo do time para o atleta: $e");
        }
      }

      final Map<String, dynamic> playerData = {
        'name': name.trim(),
        'jersey_number': jerseyNumber,
        'position': isStaff ? null : (isGoalkeeper ? 'Goleiro' : selectedPosition),
        'secondary_position': isStaff ? null : (isGoalkeeper ? null : secondaryPosition),
        'fantasy_initial_price': fantasyInitialPrice,
        'date_of_birth': dobTimestamp,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'preferred_foot': selectedFoot,
        'instagram': instagram.trim(),
        'phone': phone.trim(),
        'is_staff': isStaff,
        'staff_role': isStaff ? selectedStaffRole : null,
        'is_goalkeeper': isGoalkeeper,
        'photo_url': uploadedPhotoUrl,
        'team_id': teamId,
        'team_name': teamName,
        if (finalShieldUrl != null && finalShieldUrl.trim().isNotEmpty)
          'team_shield_url': finalShieldUrl.trim(),
      };

      String currentId;
      if (_existingPlayer == null) {
        currentId = await _playerService.createPlayer(seasonId: seasonId, data: playerData);
      } else {
        await _playerService.updatePlayer(seasonId: seasonId, playerId: _existingPlayer.id, data: playerData);
        currentId = _existingPlayer.id;
      }

      // Criar acesso ao Portal se marcado
      if (createPortalAccess && portalAuthService != null && portalPassword.isNotEmpty) {
        final username = _generateUsername(name, jerseyNumber);
        final role = isStaff ? 'staff' : 'athlete';
        try {
          final err = await portalAuthService.createUserAccess(username, portalPassword, name, role, teamId: teamId, playerId: currentId);
          if (err != null) {
            return "Sucesso: Jogador salvo, mas erro no acesso: $err";
          }
        } catch (e) {
          debugPrint("Erro ao criar acesso ao portal: $e");
          return "Sucesso: Jogador salvo, mas falha ao gerar acesso.";
        }
      }
      
      return _existingPlayer == null ? "Sucesso: Jogador criado." : "Sucesso: Jogador atualizado.";
    } catch (e) {
      return "Erro: $e";
    } finally {
      isUploading = false;
      notifyListeners();
    }
  }

  String _generateUsername(String name, int? number) {
    // Basic normalization: lowercase, remove accents, take first and last name
    String normalized = name.toLowerCase().replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '');
    List<String> parts = normalized.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return "${parts.first}.${parts.last}";
    } else if (parts.isNotEmpty) {
      return "${parts.first}${number != null ? '.$number' : ''}";
    }
    return "atleta${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";
  }
}