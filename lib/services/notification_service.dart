// lib/services/notification_service.dart
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Notificação em Background Recebida: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  final AndroidNotificationChannel _androidChannel = const AndroidNotificationChannel(
    'high_importance_channel', 
    'Notificações Importantes', 
    description: 'Canal usado para notificações importantes.', 
    importance: Importance.high,
  );

  Future<void> init() async {
    try {
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('Permissão de notificação concedida: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
         debugPrint('Usuário não concedeu permissão. As notificações não funcionarão.');
         return; 
      }

      String? token;
      if (kIsWeb) {
        // ATENÇÃO: Substitua pelo VAPID gerado no novo projeto Firebase
        token = await _firebaseMessaging.getToken(
          vapidKey: 'BJ-yqcN_XpqHv_MNTGDpCoiD1KaapzdNm_lfpTSxM7Uwn_kPYnyvIxU0xigtB5Kdb_G35EhITgMRVX2EoJesYVE',
        );
      } else {
        token = await _firebaseMessaging.getToken();
      }
      
      debugPrint("====================================================");
      debugPrint("TOKEN FCM DESTE DISPOSITIVO (para teste):");
      debugPrint(token);
      debugPrint("====================================================");

      if (!kIsWeb) {
        await _firebaseMessaging.subscribeToTopic('all_users');
        debugPrint('Inscrito no tópico "all_users" (Nativo)');
      } else {
        debugPrint('Inscrição em tópicos não suportada no PWA (Web).');
      }

      await _initLocalNotifications();
      _setupMessageHandlers();

    } catch (e) {
      debugPrint("Erro ao inicializar notificações: $e");
    }
  }

  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/ic_launcher'); 

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, 
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotificationsPlugin.initialize(initSettings);

    if (!kIsWeb) {
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }
  }

  void _setupMessageHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Notificação recebida (App em Primeiro Plano): ${message.notification?.title}');
      
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && !kIsWeb) {
        _localNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannel.id,
              _androidChannel.name,
              channelDescription: _androidChannel.description,
              icon: android?.smallIcon ?? '@mipmap/ic_launcher',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notificação clicada (App aberto do Background): ${message.messageId}');
    });

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
}