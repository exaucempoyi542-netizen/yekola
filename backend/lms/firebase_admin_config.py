"""
Configuration Firebase Admin SDK pour Yekola Backend.
Ce module initialise la connexion à Firebase Firestore.

Le fichier de clé de service (serviceAccountKey.json) doit être placé à :
    e:/MEMOIRE/backend/serviceAccountKey.json

Pour obtenir ce fichier :
1. Aller sur https://console.firebase.google.com/
2. Projet → Paramètres du projet → Comptes de service
3. Cliquer sur "Générer une nouvelle clé privée"
4. Sauvegarder le JSON sous le nom serviceAccountKey.json dans e:/MEMOIRE/backend/
"""

import firebase_admin
from firebase_admin import credentials, firestore
from pathlib import Path
import os

BASE_DIR = Path(__file__).resolve().parent.parent

# Singleton: évite d'initialiser Firebase plusieurs fois
_db = None

def get_firestore_client():
    """Retourne un client Firestore initialisé (singleton)."""
    global _db

    if _db is not None:
        return _db

    if not firebase_admin._apps:
        key_path = os.environ.get(
            'FIREBASE_SERVICE_ACCOUNT_KEY',
            str(BASE_DIR / 'serviceAccountKey.json')
        )

        if not Path(key_path).exists():
            raise FileNotFoundError(
                f"Fichier de clé Firebase introuvable : {key_path}\n"
                "Téléchargez-le depuis Firebase Console → Paramètres → Comptes de service."
            )

        cred = credentials.Certificate(key_path)
        firebase_admin.initialize_app(cred)

    _db = firestore.client()
    return _db


# Collection Firestore pour les ressources externes
EXTERNAL_RESOURCES_COLLECTION = 'external_resources'

def send_firebase_notification(user, title, message, notif_type='system', extra_data=None):
    """
    Recherche l'UID Firebase de l'utilisateur par son email dans Firestore (user_tokens)
    et crée une notification dans la collection 'notifications', avec données supplémentaires éventuelles.
    """
    try:
        db = get_firestore_client()
        # Rechercher le token par email pour récupérer l'UID Firebase
        tokens_ref = db.collection('user_tokens')
        query = tokens_ref.where('email', '==', user.email).limit(1).stream()
        
        user_uid = None
        for doc in query:
            user_uid = doc.id
            break
            
        # Créer la notification en rattachant l'email.
        # Ainsi, même sans user_uid (l'app mobile ne s'est jamais lancée),
        # la notification sera en attente et l'app la verra en filtrant par email.
        notif_data = {
            'user_uid': user_uid,
            'email': user.email,  # CLÉ IMPORTANTE POUR LA RÉCUPÉRATION
            'title': title,
            'message': message,
            'type': notif_type,
            'created_at': firestore.SERVER_TIMESTAMP,
            'is_read': False
        }
        if extra_data:
            notif_data.update(extra_data)

        db.collection('notifications').add(notif_data)
        
        # Envoi Push réel si token existe
        if user_uid:
            from firebase_admin import messaging
            token_doc = db.collection('user_tokens').document(user_uid).get()
            if token_doc.exists:
                token = token_doc.to_dict().get('token')
                if token:
                    message_push = messaging.Message(
                        notification=messaging.Notification(
                            title=title,
                            body=message,
                        ),
                        data={
                            'type': notif_type,
                            **({k: str(v) for k, v in extra_data.items()} if extra_data else {})
                        },
                        token=token,
                    )
                    try:
                        messaging.send(message_push)
                        print(f"[Firebase Push] Push FCM envoyé à {user.email}")
                    except Exception as e:
                        print(f"[Firebase Push] Erreur Push FCM : {e}")
                        
        print(f"[Firebase Notif] Notification enregistrée avec succès pour {user.email}")
        return True
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"[Firebase Notif] Erreur lors de l'envoi de la notification : {e}")
        return False
