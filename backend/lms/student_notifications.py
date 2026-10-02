# -*- coding: utf-8 -*-
"""Notifications Firebase vers les étudiants affiliés à un cours."""
import logging

logger = logging.getLogger(__name__)


def notify_affiliated_students(
    course,
    *,
    title,
    message,
    notif_type,
    extra_data=None,
    auto_enroll=False,
):
    """
    Envoie une notification (Firestore + FCM) à tous les étudiants
    de la promotion du cours. Retourne le nombre de destinataires ciblés.
    """
    from lms.visibility import affiliated_students_for_course
    from lms.firebase_admin_config import send_firebase_notification

    students = list(affiliated_students_for_course(course).select_related("class_group"))
    if not students:
        logger.info(
            "[Notify] Aucun étudiant affilié pour le cours #%s (%s).",
            getattr(course, "id", "?"),
            getattr(course, "title", ""),
        )
        return 0

    if auto_enroll:
        from lms.models import Enrollment

        for student in students:
            Enrollment.objects.get_or_create(student=student, course=course)

    payload = {
        "course_id": str(course.id),
        "route": "course",
    }
    if extra_data:
        payload.update({k: str(v) for k, v in extra_data.items()})

    sent = 0
    for student in students:
        ok = send_firebase_notification(
            student,
            title,
            message,
            notif_type=notif_type,
            extra_data=payload,
        )
        if ok:
            sent += 1

    logger.info(
        "[Notify] %s/%s notification(s) pour cours #%s type=%s",
        sent,
        len(students),
        course.id,
        notif_type,
    )
    return len(students)


def notify_course_published(course) -> int:
    teacher_name = ""
    if course.teacher_id:
        teacher_name = course.teacher.get_full_name() or course.teacher.username
    return notify_affiliated_students(
        course,
        title="Nouveau cours disponible",
        message=(
            f"{teacher_name} a publié le cours « {course.title} ». "
            "Appuyez pour le consulter."
        ),
        notif_type="COURSE_PUBLISHED",
        extra_data={"route": "course"},
        auto_enroll=True,
    )


def notify_lesson_published(course, lesson) -> int:
    if not course.is_published:
        return 0
    kind = "document" if lesson.content_type != "TEXT" else "module"
    label = "document" if kind == "document" else "module"
    return notify_affiliated_students(
        course,
        title=f"Nouveau {label} disponible",
        message=(
            f"Un nouveau {label} « {lesson.title} » a été ajouté au cours "
            f"« {course.title} ». Appuyez pour le consulter."
        ),
        notif_type="LESSON_NEW",
        extra_data={
            "route": "lesson",
            "lesson_id": lesson.id,
            "content_type": lesson.content_type,
        },
    )


def notify_quiz_published(quiz) -> int:
    course = quiz.course
    if not course or not course.is_published:
        return 0
    return notify_affiliated_students(
        course,
        title="Nouveau quiz disponible",
        message=(
            f"Un nouveau quiz « {quiz.title} » est disponible dans le cours "
            f"« {course.title} ». Appuyez pour le consulter."
        ),
        notif_type="QUIZ_PUBLISHED",
        extra_data={
            "route": "quiz",
            "quiz_id": quiz.id,
            "id_code": getattr(quiz, "id_code", "") or "",
        },
    )
