from __future__ import annotations

from django.contrib.auth.hashers import make_password
from django.core.management.base import BaseCommand
from django.db import transaction

from lms.models import Course, Faculty, Promotion, University, User

DEFAULT_PASSWORD = "Test1234"
S1_CREDITS = [3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2]  # 12 → 30 ECTS
S2_CREDITS = [3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2]  # 13 → 30 ECTS
BATCH = 200


def _fac_code(name: str) -> str:
    low = (name or "").lower()
    if "médecine" in low or "medecine" in low:
        return "MED"
    if "informatique" in low:
        return "INF"
    if "économie" in low or "economie" in low:
        return "ECO"
    if "droit" in low:
        return "DRO"
    if "istem" in low:
        return "IST"
    if "communication" in low:
        return "COM"
    if "lettres" in low:
        return "LET"
    if "science" in low:
        return "SCI"
    return "FAC"


class Command(BaseCommand):
    help = (
        "Crée un enseignant et les cours S1/S2 (30 ECTS) pour chaque promotion, "
        f"sauf William Booth. MDP enseignant : {DEFAULT_PASSWORD}"
    )

    def add_arguments(self, parser):
        parser.add_argument("--yes", action="store_true")

    def handle(self, *args, **options):
        if not options["yes"]:
            self.stdout.write(self.style.WARNING("Ajoutez --yes pour lancer."))
            return

        self.stdout.write("Demarrage cours + enseignants…")
        self.stdout.flush()

        pwd_hash = make_password(DEFAULT_PASSWORD)
        unis = list(
            University.objects.exclude(name__icontains="William Booth")
            .order_by("id")
            .only("id", "name")
        )
        uni_count = len(unis)
        self.stdout.write(
            f"{uni_count} universites | "
            f"{len(S1_CREDITS)} cours S1 + {len(S2_CREDITS)} cours S2 / promo | "
            f"MDP={DEFAULT_PASSWORD}"
        )
        self.stdout.flush()

        teachers_created = 0
        courses_created = 0

        for idx, uni in enumerate(unis, start=1):
            uni_teachers = 0
            uni_courses = 0
            faculties = list(Faculty.objects.filter(university_id=uni.id).only("id", "name"))
            course_buffer = []

            for faculty in faculties:
                Promotion.ensure_lmd_for_faculty(faculty)
                promotions = list(
                    Promotion.objects.filter(faculty_id=faculty.id).only("id", "name")
                )
                fac_code = _fac_code(faculty.name)
                dean = (
                    User.objects.filter(
                        role="DEAN",
                        assigned_faculty_id=faculty.id,
                        is_active=True,
                    )
                    .only("id")
                    .first()
                )

                for promo in promotions:
                    teacher_username = f"ens_{uni.id}_f{faculty.id}_{promo.name.lower()}"
                    teacher = User.objects.filter(username=teacher_username).first()
                    if not teacher:
                        teacher = User.objects.filter(
                            role="TEACHER",
                            assigned_university_id=uni.id,
                            assigned_faculty_id=faculty.id,
                            assigned_promotion_id=promo.id,
                            is_active=True,
                        ).first()

                    if not teacher:
                        teacher = User(
                            username=teacher_username,
                            email=f"{teacher_username}@educ.cd",
                            password=pwd_hash,
                            first_name=f"Ens.{promo.name}",
                            last_name=f"{fac_code}{uni.id}",
                            role="TEACHER",
                            assigned_university_id=uni.id,
                            assigned_faculty_id=faculty.id,
                            assigned_promotion_id=promo.id,
                            is_active=True,
                        )
                        try:
                            teacher.save()
                            teachers_created += 1
                            uni_teachers += 1
                        except Exception:
                            teacher = User.objects.get(username=teacher_username)
                    else:
                        changed = False
                        if teacher.role != "TEACHER":
                            teacher.role = "TEACHER"
                            changed = True
                        if teacher.assigned_university_id != uni.id:
                            teacher.assigned_university_id = uni.id
                            changed = True
                        if teacher.assigned_faculty_id != faculty.id:
                            teacher.assigned_faculty_id = faculty.id
                            changed = True
                        if teacher.assigned_promotion_id != promo.id:
                            teacher.assigned_promotion_id = promo.id
                            changed = True
                        if not teacher.is_active:
                            teacher.is_active = True
                            changed = True
                        if changed:
                            teacher.save()

                    try:
                        teacher.assigned_promotions.add(promo.id)
                    except Exception:
                        pass

                    existing_titles = set(
                        Course.objects.filter(
                            university_id=uni.id,
                            faculty_id=faculty.id,
                            promotion_id=promo.id,
                        ).values_list("title", flat=True)
                    )

                    for semester, credits_list in ((1, S1_CREDITS), (2, S2_CREDITS)):
                        for mod_idx, credits in enumerate(credits_list, start=1):
                            title = f"{fac_code} {promo.name} S{semester} — Module {mod_idx:02d}"
                            if title in existing_titles:
                                continue
                            course_buffer.append(
                                Course(
                                    title=title,
                                    university_id=uni.id,
                                    faculty_id=faculty.id,
                                    promotion_id=promo.id,
                                    description=(
                                        f"{uni.name} — {faculty.name} — "
                                        f"{promo.name} — S{semester}"
                                    ),
                                    credits=credits,
                                    teacher_id=teacher.id,
                                    assigned_to_dean_id=dean.id if dean else None,
                                    created_by_id=dean.id if dean else teacher.id,
                                    semester=semester,
                                    is_published=True,
                                    is_free=True,
                                )
                            )
                            uni_courses += 1
                            if len(course_buffer) >= BATCH:
                                with transaction.atomic():
                                    Course.objects.bulk_create(
                                        course_buffer,
                                        batch_size=BATCH,
                                        ignore_conflicts=True,
                                    )
                                courses_created += len(course_buffer)
                                course_buffer = []

            if course_buffer:
                with transaction.atomic():
                    Course.objects.bulk_create(
                        course_buffer, batch_size=BATCH, ignore_conflicts=True
                    )
                courses_created += len(course_buffer)
                course_buffer = []

            self.stdout.write(
                f"[{idx}/{uni_count}] {uni.name}: "
                f"+{uni_teachers} ens., +{uni_courses} cours | "
                f"session_ens={teachers_created} session_cours={courses_created}"
            )
            self.stdout.flush()

        total_t = User.objects.filter(role="TEACHER").exclude(
            assigned_university__name__icontains="William Booth"
        ).count()
        total_c = Course.objects.exclude(
            university__name__icontains="William Booth"
        ).count()
        self.stdout.write(
            self.style.SUCCESS(
                f"\nTermine.\n"
                f"Enseignants crees : {teachers_created}\n"
                f"Cours crees : {courses_created}\n"
                f"Total enseignants (hors WB) : {total_t}\n"
                f"Total cours (hors WB) : {total_c}\n"
                f"MDP enseignants : {DEFAULT_PASSWORD}\n"
                f"Connexion : /teacher/login/"
            )
        )
