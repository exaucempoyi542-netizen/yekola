from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
import logging

logger = logging.getLogger(__name__)


# Les notifications de publication de cours sont gérées explicitement
# dans teacher.views (course_toggle_publish) via student_notifications,
# afin de cibler uniquement les étudiants affiliés à la promotion.


@receiver(post_save, sender='lms.Lesson')
def generate_ppt_preview_on_save(sender, instance, **kwargs):
    """Convertit automatiquement un PPT uploadé en PDF de lecture native."""
    update_fields = kwargs.get('update_fields')
    # Évite la boucle quand on ne met à jour que preview_file
    if update_fields is not None and set(update_fields) <= {'preview_file'}:
        return
    if instance.content_type != 'PPT' or not instance.content_file:
        return
    try:
        from lms.media_convert import ensure_lesson_preview
        ensure_lesson_preview(instance)
    except Exception as exc:
        logger.error("Conversion PPT→PDF leçon #%s: %s", instance.pk, exc)


# ─── Synchronisation ExternalResource → Firebase Firestore ──────────────────

def _sync_resource_to_firestore(instance):
    """Pousse un ExternalResource vers Firestore."""
    try:
        from .firebase_admin_config import get_firestore_client, EXTERNAL_RESOURCES_COLLECTION
        db = get_firestore_client()
        doc_ref = db.collection(EXTERNAL_RESOURCES_COLLECTION).document(str(instance.id))
        doc_ref.set({
            'id': instance.id,
            'title': instance.title,
            'description': instance.description,
            'url': instance.url,
            'thumbnail_url': instance.thumbnail_url or '',
            'category': instance.category or 'Formation en ligne',
            'created_at': instance.created_at.isoformat() if instance.created_at else None,
        })
        logger.info(f"[Firestore] ExternalResource #{instance.id} synchronisé.")
    except FileNotFoundError as e:
        logger.warning(f"[Firestore] Clé de service introuvable — sync ignorée : {e}")
    except Exception as e:
        logger.error(f"[Firestore] Erreur de synchronisation ExternalResource #{instance.id} : {e}")


@receiver(post_save, sender='lms.ExternalResource')
def sync_external_resource_on_save(sender, instance, **kwargs):
    """Synchronise avec Firestore après création ou modification."""
    _sync_resource_to_firestore(instance)


@receiver(post_delete, sender='lms.ExternalResource')
def delete_external_resource_from_firestore(sender, instance, **kwargs):
    """Supprime le document Firestore correspondant."""
    try:
        from .firebase_admin_config import get_firestore_client, EXTERNAL_RESOURCES_COLLECTION
        db = get_firestore_client()
        db.collection(EXTERNAL_RESOURCES_COLLECTION).document(str(instance.id)).delete()
        logger.info(f"[Firestore] ExternalResource #{instance.id} supprimé de Firestore.")
    except FileNotFoundError:
        pass
    except Exception as e:
        logger.error(f"[Firestore] Erreur suppression ExternalResource #{instance.id} : {e}")
