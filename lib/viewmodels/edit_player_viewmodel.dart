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
  String? selectedFoot;
  String? selectedStaffRole;
  
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
      }
      selectedFoot = ['Destro', 'Canhoto', 'Ambidestro'].contains(_existingPlayer.preferredFoot) 
          ? _existingPlayer.preferredFoot 
          : null;
    }
  }

  void setStaff(bool value) {
    isStaff = value;
    if (isStaff) {
      isGoalkeeper = false;
      selectedPosition = null;
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
  void setFoot(String? foot) { selectedFoot = foot; notifyListeners(); }
  void setStaffRole(String? role) { selectedStaffRole = role; notifyListeners(); }
  
  void setCreatePortalAccess(bool value) { createPortalAccess = value; notifyListeners(); }
  void setPortalPassword(String value) { portalPassword = value; notifyListeners(); }

  void clearImage() {
    photoUrl = null;
    imageFile = null;
    webImageBytes = null;
    notifyListeners();
  }

  Future<void> pickImage() async {
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.bytes != null) {
        webImageBytes = result.files.single.bytes;
        photoUrl = null;
        notifyListeners();
      }
    } else {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        imageFile = File(pickedFile.path);
        photoUrl = null;
        notifyListeners();
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

      final Map<String, dynamic> playerData = {
        'name': name.trim(),
        'jersey_number': jerseyNumber,
        'position': isStaff ? null : (isGoalkeeper ? 'Goleiro' : selectedPosition),
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
      };

      String currentId;
      if (_existingPlayer == null) {
        currentId = await _playerService.createPlayer(seasonId: seasonId, data: playerData);
      } else {
        await _playerService.updatePlayer(seasonId: seasonId, playerId: _existingPlayer!.id, data: playerData);
        currentId = _existingPlayer!.id;
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