import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'fantasy_service.dart';

const String environment = String.fromEnvironment('ENV', defaultValue: 'prod');

class FantasyAuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Chaves mantidas e seguras
  final String _prodWebClientId = '893803829585-jp8uuugt42m2qknabm4lene03mimllai.apps.googleusercontent.com';
  final String _testWebClientId = '39829597186-27ckegqg46o1e825k19drdsdfdgtu99u.apps.googleusercontent.com';

  late final GoogleSignIn _googleSignIn;
  final FantasyService _fantasyService; 

  User? _user;
  bool _isLoading = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  FantasyAuthService(this._fantasyService) {
    // Inicialização correta com as chaves para Web
    _googleSignIn = GoogleSignIn(
      clientId: kIsWeb 
          ? (environment == 'test' ? _testWebClientId : _prodWebClientId) 
          : null,
    );
    
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<void> _handlePostLoginLogic(User user) async {
    try {
      await user.getIdToken(true);
      
      bool isTokenPropagated = false;
      int attempts = 0;
      
      while (!isTokenPropagated && attempts < 5) {
        attempts++;
        try {
          await Future.delayed(Duration(milliseconds: 600 * attempts));
          
          final docSnap = await FirebaseFirestore.instance
              .collection('fantasy_teams')
              .doc(user.uid)
              .get(const GetOptions(source: Source.server));

          if (!docSnap.exists) {
            await _fantasyService.createUserTeam(
              userId: user.uid,
              userName: user.displayName ?? 'Treinador',
              teamName: 'Time de ${user.displayName?.split(' ').first ?? 'Treinador'}',
            );
          }
          
          isTokenPropagated = true; 
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('permission') || errorStr.contains('insufficient')) {
            if (attempts == 5) rethrow; 
          } else {
            rethrow; 
          }
        }
      }
    } catch (e) {
      debugPrint("Erro no pós-login do Fantasy: $e");
    }
  }

  Future<String?> signInWithGoogle() async {
    try {
      _setLoading(true);

      // Fluxo direto e limpo usando o pacote Google Sign In
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        _setLoading(false);
        return "Login cancelado.";
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      if (userCredential.user != null) {
        await _handlePostLoginLogic(userCredential.user!);
      }

      _setLoading(false);
      return null;
      
    } on FirebaseAuthException catch (e) {
      _setLoading(false);
      return "Erro no Firebase: ${e.message}";
    } catch (e) {
      _setLoading(false);
      return "Falha de comunicação: $e";
    }
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
    await _auth.signOut();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}