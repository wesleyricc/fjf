import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Estado Local
  bool _isAuthenticated = false;
  String? _adminUsername;
  bool _isLoading = true; // Para mostrar splash enquanto verificamos o disco

  // Getters para a UI consumir
  bool get isAuthenticated => _isAuthenticated;
  String? get adminUsername => _adminUsername;
  bool get isLoading => _isLoading;

  // Construtor: Tenta recuperar sessão anterior ao iniciar
  AuthService() {
    _tryAutoLogin();
  }

  // --- Lógica de Hash (Encapsulada) ---
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // --- Login ---
  Future<String?> login(String username, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      final String inputHash = _hashPassword(password);
      
      // Busca no Firestore (Coleção Global)
      final docRef = _firestore.collection('admin_users').doc(username);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        _isLoading = false;
        notifyListeners();
        return 'Usuário não encontrado.';
      }

      final storedHash = docSnap.data()?['password_hash'];

      if (inputHash == storedHash) {
        // Sucesso! Atualiza estado e persiste
        _isAuthenticated = true;
        _adminUsername = username;
        
        await _persistSession(username);
        
        _isLoading = false;
        notifyListeners(); // Avisa todos os widgets que o login mudou
        return null; // Null significa sucesso (sem erro)
      } else {
        _isLoading = false;
        notifyListeners();
        return 'Senha incorreta.';
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Erro de conexão: $e';
    }
  }

  // --- Logout ---
  Future<void> logout() async {
    _isAuthenticated = false;
    _adminUsername = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Limpa dados do disco
    
    notifyListeners();
  }

  // --- Persistência (Para PWA não deslogar no Refresh) ---
  Future<void> _persistSession(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_username', username);
    await prefs.setBool('is_auth', true);
  }

  Future<void> _tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('is_auth')) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final isAuth = prefs.getBool('is_auth') ?? false;
      if (isAuth) {
        _adminUsername = prefs.getString('admin_username');
        _isAuthenticated = true;
      }
    } catch (e) {
      debugPrint("Erro ao tentar auto-login: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}