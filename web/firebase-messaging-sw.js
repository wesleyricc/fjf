// web/firebase-messaging-sw.js
importScripts("https://www.gstatic.com/firebasejs/9.0.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.0.0/firebase-messaging-compat.js");

// NOTA: Use as configurações do seu projeto
// (Copie isso do seu firebase_options.dart ou do Console do Firebase)
const firebaseConfig = {
  apiKey: 'AIzaSyAI3SJkOCdY5Z5lC5hiSiXPeKUwsYu-u2w',
  authDomain: 'fjfapp.firebaseapp.com',
  projectId: 'fjfapp',
  storageBucket: 'fjfapp.firebasestorage.app',
  messagingSenderId: '211551139323',
  appId: '1:211551139323:web:f583360c18907986adc75e',
  measurementId: 'G-GNBBWGHX3G',
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

// Opcional: handler de background (mas o FCM cuida disso se o app não estiver em foco)
messaging.onBackgroundMessage((payload) => {
  console.log(
    "[firebase-messaging-sw.js] Received background message ",
    payload,
  );
  // Personalize a notificação aqui se desejar
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png' // Ícone do seu manifest.json
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});