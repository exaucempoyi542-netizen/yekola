# -*- coding: utf-8 -*-
"""Visibilité des cours : étudiants affiliés (promotion) ou inscrits (Enrollment)."""
from django.db.models import Q, QuerySet


def affiliated_students_for_course(course) -> QuerySet:
    """Étudiants officiellement rattachés à la promotion du cours."""
    from lms.models import User

    if not course or not getattr(course, "promotion_id", None):
        return User.objects.none()

    return User.objects.filter(
        role="STUDENT",
        class_group__promotion_id=course.promotion_id,
        is_active=True,
    ).distinct()


def student_can_access_course(user, course) -> bool:
    if not user or not getattr(user, "is_authenticated", False):
        return False
    role = getattr(user, "role", None)
    if role in ("SUPER_ADMIN", "PROVINCIAL_ADMIN", "MANAGER", "DEAN"):
        return True
    if role == "TEACHER":
        return course.teacher_id == user.id
    if role != "STUDENT":
        return False
    if not course.is_published or not course.teacher_id:
        return False

    # Accès par inscription explicite
    if course.enrollments.filter(student=user).exists():
        return True

    # Accès par affiliation de promotion
    if not course.promotion_id:
        return False
    class_group = getattr(user, "class_group", None)
    if not class_group or not class_group.promotion_id:
        return False
    return class_group.promotion_id == course.promotion_id


def visible_courses_queryset(user) -> QuerySet:
    """Cours publiés visibles pour un utilisateur (catalogue mobile)."""
    from lms.models import Course

    # Pas de prefetch lessons ici : la liste catalogue reste légère ;
    # le détail (retrieve) précharge lessons/quizzes dans CourseViewSet.
    base = (
        Course.objects.filter(is_published=True, teacher__isnull=False)
        .select_related("teacher", "promotion", "faculty", "prerequisite_quiz")
        .order_by("-created_at")
    )

    if not user or not getattr(user, "is_authenticated", False):
        return Course.objects.none()

    role = getattr(user, "role", None)
    if role in ("SUPER_ADMIN", "PROVINCIAL_ADMIN", "MANAGER", "DEAN"):
        return base
    if role == "TEACHER":
        return base.filter(teacher=user)

    if role == "STUDENT":
        # Deux requêtes indexées (promotion + inscriptions) plutôt qu'un OR
        # sur toute la table lms_course (~100k+ lignes) — trop lent sur MariaDB.
        from lms.models import Enrollment

        enrolled_ids = list(
            Enrollment.objects.filter(student=user).values_list("course_id", flat=True)
        )
        class_group = getattr(user, "class_group", None)
        promo_id = getattr(class_group, "promotion_id", None) if class_group else None

        course_ids: set[int] = set(enrolled_ids)
        if promo_id:
            course_ids.update(
                Course.objects.filter(
                    is_published=True,
                    teacher__isnull=False,
                    promotion_id=promo_id,
                ).values_list("id", flat=True)
            )

        if not course_ids:
            return Course.objects.none()

        return (
            Course.objects.filter(id__in=course_ids)
            .select_related("teacher", "promotion", "faculty", "prerequisite_quiz")
            .order_by("-created_at")
        )

    return Course.objects.none()


def visible_lessons_queryset(user) -> QuerySet:
    from lms.models import Lesson

    if not user or not getattr(user, "is_authenticated", False):
        return Lesson.objects.none()

    role = getattr(user, "role", None)
    if role == "TEACHER":
        return Lesson.objects.filter(course__teacher=user)
    if role in ("SUPER_ADMIN", "PROVINCIAL_ADMIN", "MANAGER", "DEAN"):
        return Lesson.objects.filter(course__is_published=True)

    courses = visible_courses_queryset(user)
    return Lesson.objects.filter(course__in=courses)


def visible_quizzes_queryset(user) -> QuerySet:
    from lms.models import Quiz

    if not user or not getattr(user, "is_authenticated", False):
        return Quiz.objects.none()

    role = getattr(user, "role", None)
    if role == "TEACHER":
        return Quiz.objects.filter(course__teacher=user)
    if role in ("SUPER_ADMIN", "PROVINCIAL_ADMIN", "MANAGER", "DEAN"):
        return Quiz.objects.filter(is_published=True)

    courses = visible_courses_queryset(user)
    return Quiz.objects.filter(is_published=True, course__in=courses)


def sync_student_course_access(student, teacher=None, promotion=None):
    """
    Assure les Enrollment pour un étudiant affilié :
    tous les cours (publiés ou non) du périmètre promotion (+ enseignant optionnel).
    """
    from lms.models import Course, Enrollment

    if not student or getattr(student, "role", None) != "STUDENT":
        return 0

    qs = Course.objects.filter(teacher__isnull=False)
    if promotion is not None:
        qs = qs.filter(promotion=promotion)
    elif getattr(student, "class_group", None) and student.class_group.promotion_id:
        qs = qs.filter(promotion_id=student.class_group.promotion_id)
    else:
        return 0

    if teacher is not None:
        qs = qs.filter(teacher=teacher)

    created = 0
    for course in qs:
        _, was_created = Enrollment.objects.get_or_create(student=student, course=course)
        if was_created:
            created += 1
    return created


def sync_teacher_course_roster(course):
    """
    Après affectation d'un cours à un enseignant :
    inscrit tous les étudiants de la promotion et prépare les fiches de cotes.
    """
    from lms.models import Enrollment, StudentAudit

    if not course or not course.teacher_id or not course.promotion_id:
        return 0

    synced = 0
    for student in affiliated_students_for_course(course):
        Enrollment.objects.get_or_create(student=student, course=course)
        StudentAudit.objects.get_or_create(
            student=student,
            teacher=course.teacher,
            course=course,
        )
        synced += 1
    return synced
