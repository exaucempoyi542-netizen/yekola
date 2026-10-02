importScripts('https://www.gstatic.com/firebasejs/9.10.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.10.0/firebase-messaging-compat.js');

firebase.initializeApp({
    apiKey: "AIzaSyD8-zpr3SlfY-T5OKZHRVSFJKnqOYgr41g",
    authDomain: "edurdc-a0d8a.firebaseapp.com",
    projectId: "edurdc-a0d8a",
    storageBucket: "edurdc-a0d8a.firebasestorage.app",
    messagingSenderId: "1019671203810",
    appId: "1:1019671203810:web:c7fe7840778ac0a63eb3bb",
    measurementId: "G-LQ403WLZ4F"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Received background message ', payload);
    const notificationTitle = payload.notification.title;
    const notificationOptions = {
        body: payload.notification.body,
        icon: '/favicon.png'
    };

    return self.registration.showNotification(notificationTitle, notificationOptions);
});
