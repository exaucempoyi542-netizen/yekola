"""
Initialise des données de test LMD — une ou plusieurs universités.

Scopes :
  --scope single     Une seule université (--university-name)
  --scope kinshasa   WILLIAM BOOTH + INIKIN, ISIPA, IPC, IESP-Gombe, ISS
  --scope national   Kinshasa (6 univ.) + 1 université dans chaque autre province RDC

Usage :
  python manage.py seed_full_test_data --scope national --yes
  python manage.py seed_full_test_data --scope kinshasa --students-per-promo 300 --yes
  python manage.py seed_full_test_data --reset --scope national --yes
"""
from __future__ import annotations

import random
import re
from decimal import Decimal

from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone


FACULTIES = [
    ("Faculté de Médecine", "med", "MED"),
    ("Faculté d'Informatique", "info", "INF"),
    ("Faculté d'Économie", "eco", "ECO"),
    ("Faculté de Droit", "droit", "DRO"),
    ("Faculté ISTEM", "istem", "IST"),
    ("Faculté de Communication", "com", "COM"),
]

S1_CREDITS = [3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2]  # 12 → 30
S2_CREDITS = [3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2]  # 13 → 30

DEFAULT_PASSWORD = "Test1234"
ACADEMIC_YEAR = "2025-2026"
BATCH = 2500

# Kinshasa — en plus de WILLIAM BOOTH
KINSHASA_EXTRA_UNIVERSITIES = [
    ("INIKIN", "inikin"),
    ("ISIPA", "isipa"),
    ("IPC", "ipc"),
    ("IESP-Gombe", "iesp"),
    ("ISS", "iss"),
]

# Une université représentative par province (hors Kinshasa)
PROVINCE_UNIVERSITIES = {
    "BAS_UELE": ("Université de Buta", "unibuta"),
    "EQUATEUR": ("Université de Mbandaka", "unimbandaka"),
    "HAUT_KATANGA": ("Université de Lubumbashi", "unilu"),
    "HAUT_LOMAMI": ("Université de Kamina", "unikamina"),
    "HAUT_UELE": ("Université d'Isiro", "uniisiro"),
    "ITURI": ("Université de Bunia", "unibunia"),
    "KASAI": ("Université de Tshikapa", "unitshikapa"),
    "KASAI_CENTRAL": ("Université de Kananga", "unikananga"),
    "KASAI_ORIENTAL": ("Université de Mbuji-Mayi", "unimayi"),
    "KONGO_CENTRAL": ("Université de Matadi", "unimatadi"),
    "KWANGO": ("Université de Kenge", "unikenge"),
    "KWILU": ("Université de Kikwit", "unikikwit"),
    "LOMAMI": ("Université de Kabinda", "unikabinda"),
    "LUALABA": ("Université de Kolwezi", "unikolwezi"),
    "MANIEMA": ("Université de Kindu", "unikindu"),
    "MAI_NDOMBE": ("Université d'Inongo", "uniinongo"),
    "MONGALA": ("Université de Lisala", "unilisala"),
    "NORD_KIVU": ("Université de Goma", "unigoma"),
    "NORD_UBANGI": ("Université de Gbadolite", "unigbadolite"),
    "SANKURU": ("Université de Lodja", "unilodja"),
    "SUD_KIVU": ("Université de Bukavu", "unibukavu"),
    "SUD_UBANGI": ("Université de Gemena", "unigemena"),
    "TANGANYIKA": ("Université de Kalemie", "unikalemie"),
    "TSHOPO": ("Université de Kisangani", "unikis"),
    "TSHUAPA": ("Université de Boende", "uniboende"),
}


def _slugify(value: str) -> str:
    value = value.lower().strip()
    value = re.sub(r"[^a-z0-9]+", "", value)
    return value[:20] or "univ"


def _split_score(total: float) -> tuple[Decimal, Decimal, Decimal]:
    total = max(0.0, min(20.0, float(total)))
    tp = round(total * (5 / 20), 2)
    interro = round(total * (5 / 20), 2)
    examen = round(total - tp - interro, 2)
    tp = min(5.0, max(0.0, tp))
    interro = min(5.0, max(0.0, interro))
    examen = min(10.0, max(0.0, examen))
    drift = round(total - (tp + interro + examen), 2)
    if drift != 0:
        examen = min(10.0, max(0.0, round(examen + drift, 2)))
    return Decimal(str(tp)), Decimal(str(interro)), Decimal(str(examen))


def _make_total(must_pass: bool, rng: random.Random) -> float:
    if must_pass:
        return round(rng.uniform(10.0, 19.5), 2)
    return round(rng.uniform(0.0, 9.5), 2)


class Command(BaseCommand):
    help = "Seed LMD multi-universités (Kinshasa et/ou toutes les provinces RDC)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--reset",
            action="store_true",
            help="Purge opérationnelle avant seed (conserve SUPER_ADMIN / PROVINCIAL_ADMIN / Province).",
        )
        parser.add_argument(
            "--yes",
            action="store_true",
            help="Confirme les opérations destructives / longues.",
        )
        parser.add_argument(
            "--students-per-promo",
            type=int,
            default=300,
            help="Étudiants par promotion (défaut: 300).",
        )
        parser.add_argument(
            "--pass-rate",
            type=float,
            default=0.35,
            help="Taux de réussite annuelle 60/60 (défaut: 0.35).",
        )
        parser.add_argument(
            "--scope",
            choices=("single", "kinshasa", "national"),
            default="national",
            help="Étendue du seed (défaut: national).",
        )
        parser.add_argument(
            "--university-name",
            type=str,
            default="WILLIAM BOOTH",
            help="Nom utilisé avec --scope single.",
        )
        parser.add_argument(
            "--skip-existing",
            action="store_true",
            default=True,
            help="Ignore une université déjà peuplée (facultés présentes). Défaut: oui.",
        )
        parser.add_argument(
            "--force",
            action="store_true",
            help="Reseed même si l'université a déjà des facultés.",
        )

    def handle(self, *args, **options):
        students_per_promo = max(1, options["students_per_promo"])
        pass_rate = min(1.0, max(0.0, options["pass_rate"]))
        scope = options["scope"]
        skip_existing = options["skip_existing"] and not options["force"]

        if options["reset"]:
            if not options["yes"]:
                self.stderr.write(self.style.ERROR("Ajoutez --yes pour confirmer --reset."))
                return
            self._purge()

        # Volume estimé : demander confirmation pour national sans --yes
        targets = self._build_targets(scope, options["university_name"])
        est_students = len(targets) * 6 * 5 * students_per_promo
        est_audits = est_students * 25
        self.stdout.write(self.style.MIGRATE_HEADING("=== Seed LMD multi-universités ==="))
        self.stdout.write(
            f"Scope={scope} | univ={len(targets)} | étudiants/promo={students_per_promo} | "
            f"estime ~ {est_students:,} etudiants / {est_audits:,} cotes"
        )
        if scope == "national" and not options["yes"] and not options["reset"]:
            self.stderr.write(
                self.style.ERROR(
                    "Seed national volumineux : ajoutez --yes pour confirmer "
                    "(ou réduisez avec --students-per-promo 50)."
                )
            )
            return

        from lms.models import Province

        # Assurer les 26 provinces
        for code, _label in Province.RDC_PROVINCES:
            Province.objects.get_or_create(code=code)

        pwd_hash = make_password(DEFAULT_PASSWORD)
        started = timezone.now()
        grand = {
            "universities": 0,
            "skipped": 0,
            "faculties": 0,
            "deans": 0,
            "teachers": 0,
            "courses": 0,
            "students": 0,
            "audits": 0,
            "grades": 0,
            "reports": 0,
            "lines": 0,
            "reussite": 0,
            "echec": 0,
        }

        for idx, (uni_name, uni_slug, province_code) in enumerate(targets, start=1):
            self.stdout.write("")
            self.stdout.write(
                self.style.HTTP_INFO(f"[{idx}/{len(targets)}] {uni_name} ({province_code})")
            )
            stats = self._seed_university(
                uni_name=uni_name,
                uni_slug=uni_slug,
                province_code=province_code,
                students_per_promo=students_per_promo,
                pass_rate=pass_rate,
                pwd_hash=pwd_hash,
                skip_existing=skip_existing,
                seed_index=idx,
            )
            if stats.get("skipped"):
                grand["skipped"] += 1
                self.stdout.write(self.style.WARNING("  -> deja peuplee, ignoree (--force pour refaire)"))
                continue
            for k, v in stats.items():
                if k in grand:
                    grand[k] += v

        cache.clear()
        elapsed = (timezone.now() - started).total_seconds()
        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS("=== Seed termine ==="))
        self.stdout.write(f"Duree                 : {elapsed:.1f}s")
        self.stdout.write(f"Universites creees    : {grand['universities']}")
        self.stdout.write(f"Universites ignorees  : {grand['skipped']}")
        self.stdout.write(f"Facultes              : {grand['faculties']}")
        self.stdout.write(f"Decanats              : {grand['deans']}")
        self.stdout.write(f"Enseignants           : {grand['teachers']}")
        self.stdout.write(f"Cours                 : {grand['courses']}")
        self.stdout.write(f"Etudiants             : {grand['students']}")
        self.stdout.write(f"Cotes (audits)        : {grand['audits']}")
        self.stdout.write(f"CourseGrade           : {grand['grades']}")
        self.stdout.write(f"Rapports annuels      : {grand['reports']}")
        self.stdout.write(f"Lignes resultats      : {grand['lines']}")
        self.stdout.write(f"Reussites / Echecs    : {grand['reussite']} / {grand['echec']}")
        self.stdout.write("")
        self.stdout.write(self.style.WARNING(f"Mot de passe commun : {DEFAULT_PASSWORD}"))
        self.stdout.write("  Manager WILLIAM BOOTH : steve")
        self.stdout.write("  Autres managers       : mgr_<slug>  ex. mgr_inikin, mgr_unilu")
        self.stdout.write("  Decanats               : dean_<slug>_<fac>  ex. dean_isipa_med")
        self.stdout.write("  Enseignants           : ens_<slug>_<fac>_<promo>")
        self.stdout.write("  Etudiants             : etu_<slug>_<fac>_<promo>_001")

    def _build_targets(self, scope: str, single_name: str) -> list[tuple[str, str, str]]:
        """Liste (nom, slug, province_code)."""
        targets: list[tuple[str, str, str]] = []
        if scope == "single":
            name = (single_name or "WILLIAM BOOTH").strip()
            slug = "wb" if name.upper() == "WILLIAM BOOTH" else _slugify(name)
            targets.append((name, slug, "KINSHASA"))
            return targets

        # Kinshasa
        targets.append(("WILLIAM BOOTH", "wb", "KINSHASA"))
        for name, slug in KINSHASA_EXTRA_UNIVERSITIES:
            targets.append((name, slug, "KINSHASA"))

        if scope == "kinshasa":
            return targets

        # National : + 1 univ / autre province
        for code, (name, slug) in PROVINCE_UNIVERSITIES.items():
            targets.append((name, slug, code))
        return targets

    def _seed_university(
        self,
        *,
        uni_name: str,
        uni_slug: str,
        province_code: str,
        students_per_promo: int,
        pass_rate: float,
        pwd_hash: str,
        skip_existing: bool,
        seed_index: int,
    ) -> dict:
        from lms.models import (
            ClassGroup,
            Course,
            CourseGrade,
            Faculty,
            Promotion,
            Province,
            StudentAudit,
            University,
            User,
        )
        from super_admin.models import FacultyReport, SemesterResultLine, SemesterResultReport

        stats = {
            "universities": 0,
            "faculties": 0,
            "deans": 0,
            "teachers": 0,
            "courses": 0,
            "students": 0,
            "audits": 0,
            "grades": 0,
            "reports": 0,
            "lines": 0,
            "reussite": 0,
            "echec": 0,
        }

        province = Province.objects.filter(code=province_code).first()
        if province is None:
            province = Province.objects.create(code=province_code)

        university, uni_created = University.objects.get_or_create(
            name=uni_name,
            defaults={
                "province": province,
                "institution_type": "PUBLIC" if uni_slug != "wb" else "PRIVATE",
                "address": f"{province.name}, RDC",
                "email": f"contact@{uni_slug}.educ",
            },
        )
        if university.province_id != province.id:
            university.province = province
            university.save(update_fields=["province"])

        if skip_existing and not uni_created and university.faculties.exists():
            return {"skipped": True}

        if uni_created:
            stats["universities"] = 1

        # Manager : conserver steve pour WILLIAM BOOTH
        if uni_slug == "wb":
            manager_username = "steve"
            manager_defaults = {
                "first_name": "Steve",
                "last_name": "Manager",
                "email": "steve@williambooth.educ",
            }
        else:
            manager_username = f"mgr_{uni_slug}"
            manager_defaults = {
                "first_name": "Manager",
                "last_name": uni_name[:40],
                "email": f"{manager_username}@educ.cd",
            }

        manager, mgr_created = User.objects.get_or_create(
            username=manager_username,
            defaults={
                **manager_defaults,
                "role": "MANAGER",
                "assigned_university": university,
                "is_active": True,
                "password": pwd_hash,
            },
        )
        if not mgr_created:
            manager.role = "MANAGER"
            manager.assigned_university = university
            manager.is_active = True
            manager.password = pwd_hash
            manager.save()

        rng = random.Random(1000 + seed_index * 97)

        for fac_name, fac_slug, fac_code in FACULTIES:
            faculty, fac_created = Faculty.objects.get_or_create(
                university=university,
                name=fac_name,
            )
            if fac_created:
                stats["faculties"] += 1

            dean_username = f"dean_{uni_slug}_{fac_slug}"
            dean, dean_created = User.objects.get_or_create(
                username=dean_username,
                defaults={
                    "first_name": "Doyen",
                    "last_name": f"{fac_code}-{uni_slug.upper()}",
                    "email": f"{dean_username}@educ.cd",
                    "role": "DEAN",
                    "assigned_university": university,
                    "assigned_faculty": faculty,
                    "is_active": True,
                    "password": pwd_hash,
                },
            )
            if not dean_created:
                dean.role = "DEAN"
                dean.assigned_university = university
                dean.assigned_faculty = faculty
                dean.is_active = True
                dean.password = pwd_hash
                dean.save()
            else:
                stats["deans"] += 1

            Promotion.ensure_lmd_for_faculty(faculty)
            promotions = list(Promotion.lmd_ordered(Promotion.objects.filter(faculty=faculty)))

            for promo in promotions:
                class_group, _ = ClassGroup.objects.get_or_create(
                    promotion=promo,
                    name="Groupe Principal",
                )

                teacher_username = f"ens_{uni_slug}_{fac_slug}_{promo.name.lower()}"
                teacher, teacher_created = User.objects.get_or_create(
                    username=teacher_username,
                    defaults={
                        "first_name": f"Ens.{promo.name}",
                        "last_name": f"{fac_code}{uni_slug[:6].upper()}",
                        "email": f"{teacher_username}@educ.cd",
                        "role": "TEACHER",
                        "assigned_university": university,
                        "assigned_faculty": faculty,
                        "assigned_promotion": promo,
                        "is_active": True,
                        "password": pwd_hash,
                    },
                )
                if not teacher_created:
                    teacher.role = "TEACHER"
                    teacher.assigned_university = university
                    teacher.assigned_faculty = faculty
                    teacher.assigned_promotion = promo
                    teacher.is_active = True
                    teacher.password = pwd_hash
                    teacher.save()
                else:
                    stats["teachers"] += 1
                teacher.assigned_promotions.set([promo])

                courses_s1 = []
                courses_s2 = []
                for idx, credits in enumerate(S1_CREDITS, start=1):
                    title = f"{fac_code} {promo.name} S1 — Module {idx:02d}"
                    course, created = Course.objects.get_or_create(
                        university=university,
                        faculty=faculty,
                        promotion=promo,
                        title=title,
                        semester=1,
                        defaults={
                            "credits": credits,
                            "description": f"{uni_name} — {fac_name} — {promo.display_label} — S1",
                            "teacher": teacher,
                            "assigned_to_dean": dean,
                            "created_by": dean,
                            "is_published": True,
                            "is_free": True,
                        },
                    )
                    if not created:
                        course.credits = credits
                        course.teacher = teacher
                        course.assigned_to_dean = dean
                        course.created_by = dean
                        course.is_published = True
                        course.save()
                    else:
                        stats["courses"] += 1
                    courses_s1.append(course)

                for idx, credits in enumerate(S2_CREDITS, start=1):
                    title = f"{fac_code} {promo.name} S2 — Module {idx:02d}"
                    course, created = Course.objects.get_or_create(
                        university=university,
                        faculty=faculty,
                        promotion=promo,
                        title=title,
                        semester=2,
                        defaults={
                            "credits": credits,
                            "description": f"{uni_name} — {fac_name} — {promo.display_label} — S2",
                            "teacher": teacher,
                            "assigned_to_dean": dean,
                            "created_by": dean,
                            "is_published": True,
                            "is_free": True,
                        },
                    )
                    if not created:
                        course.credits = credits
                        course.teacher = teacher
                        course.assigned_to_dean = dean
                        course.created_by = dean
                        course.is_published = True
                        course.save()
                    else:
                        stats["courses"] += 1
                    courses_s2.append(course)

                all_courses = courses_s1 + courses_s2

                # Étudiants
                prefix = f"etu_{uni_slug}_{fac_slug}_{promo.name.lower()}"
                existing = set(
                    User.objects.filter(username__startswith=f"{prefix}_").values_list(
                        "username", flat=True
                    )
                )
                new_students = []
                for i in range(1, students_per_promo + 1):
                    username = f"{prefix}_{i:03d}"
                    if username in existing:
                        continue
                    new_students.append(
                        User(
                            username=username,
                            first_name=f"Etudiant{i}",
                            last_name=f"{fac_code}{promo.name}",
                            email=f"{username}@student.educ",
                            role="STUDENT",
                            matricule=f"{uni_slug.upper()[:6]}-{fac_code}-{promo.name}-{i:04d}",
                            class_group=class_group,
                            assigned_university=university,
                            assigned_faculty=faculty,
                            assigned_promotion=promo,
                            is_active=True,
                            password=pwd_hash,
                        )
                    )
                if new_students:
                    User.objects.bulk_create(new_students, batch_size=BATCH)
                    stats["students"] += len(new_students)

                students = list(
                    User.objects.filter(role="STUDENT", class_group=class_group).order_by("id")
                )[:students_per_promo]

                course_ids = [c.id for c in all_courses]
                student_ids = [s.id for s in students]
                StudentAudit.objects.filter(course_id__in=course_ids, student_id__in=student_ids).delete()
                CourseGrade.objects.filter(course_id__in=course_ids, student_id__in=student_ids).delete()

                audits_buffer = []
                grades_buffer = []
                n_pass_target = int(round(len(students) * pass_rate))

                for s_idx, student in enumerate(students):
                    annual_pass = s_idx < n_pass_target
                    fail_course_ids = set()
                    if not annual_pass:
                        fail_budget = rng.randint(8, 18)
                        shuffled = list(all_courses)
                        rng.shuffle(shuffled)
                        spent = 0
                        for c in shuffled:
                            if spent >= fail_budget:
                                break
                            fail_course_ids.add(c.id)
                            spent += c.credits

                    for course in all_courses:
                        must_pass = course.id not in fail_course_ids
                        total = _make_total(must_pass, rng)
                        tp, interro, examen = _split_score(total)
                        full_name = student.get_full_name() or student.username
                        audits_buffer.append(
                            StudentAudit(
                                student=student,
                                teacher=teacher,
                                course=course,
                                full_name=full_name,
                                tp=tp,
                                interro=interro,
                                examen=examen,
                                status="VALIDATED_BY_DEAN",
                            )
                        )
                        grades_buffer.append(
                            CourseGrade(
                                student=student,
                                course=course,
                                interrogation_score=interro,
                                exam_score=examen,
                                final_score=Decimal(str(round(float(tp + interro + examen), 2))),
                                status="VALIDATED_BY_DEAN",
                            )
                        )
                        if len(audits_buffer) >= BATCH:
                            StudentAudit.objects.bulk_create(audits_buffer, batch_size=BATCH)
                            CourseGrade.objects.bulk_create(grades_buffer, batch_size=BATCH)
                            stats["audits"] += len(audits_buffer)
                            stats["grades"] += len(grades_buffer)
                            audits_buffer.clear()
                            grades_buffer.clear()

                if audits_buffer:
                    StudentAudit.objects.bulk_create(audits_buffer, batch_size=BATCH)
                    CourseGrade.objects.bulk_create(grades_buffer, batch_size=BATCH)
                    stats["audits"] += len(audits_buffer)
                    stats["grades"] += len(grades_buffer)

                # Rapport annuel
                SemesterResultReport.objects.filter(
                    university=university,
                    faculty=faculty,
                    promotion=promo,
                    semester__isnull=True,
                ).delete()
                FacultyReport.objects.filter(
                    university=university,
                    faculty=faculty,
                    title__contains=promo.display_label,
                ).delete()

                audits = StudentAudit.objects.filter(
                    course_id__in=course_ids,
                    student_id__in=student_ids,
                    status__in=("SUBMITTED_TO_DEAN", "SUBMITTED_TO_MANAGER", "VALIDATED_BY_DEAN"),
                )
                audit_by_student: dict[int, dict[int, StudentAudit]] = {}
                for a in audits.iterator(chunk_size=2000):
                    audit_by_student.setdefault(a.student_id, {})[a.course_id] = a

                def credits_for(student_audits, course_list):
                    total = 0
                    for c in course_list:
                        audit = student_audits.get(c.id)
                        if audit and audit.total >= 10:
                            total += c.effective_credits
                    return total

                title = f"Rapport annuel consolidé — {faculty.name} — {promo.display_label}"
                report = SemesterResultReport.objects.create(
                    university=university,
                    faculty=faculty,
                    promotion=promo,
                    semester=None,
                    academic_year=ACADEMIC_YEAR,
                    title=title,
                    credits_reference=60,
                    semester_credits_reference=30,
                    submitted_by=dean,
                )

                lines = []
                passed = failed = 0
                for student in students:
                    student_audits = audit_by_student.get(student.id, {})
                    s1_earned = credits_for(student_audits, courses_s1)
                    s2_earned = credits_for(student_audits, courses_s2)
                    earned = s1_earned + s2_earned
                    result = "REUSSITE" if earned >= 60 else "ECHEC"
                    if result == "REUSSITE":
                        passed += 1
                    else:
                        failed += 1
                    full_name = student.get_full_name() or student.username
                    for a in student_audits.values():
                        if a.full_name:
                            full_name = a.full_name
                            break
                    lines.append(
                        SemesterResultLine(
                            report=report,
                            student=student,
                            full_name=full_name,
                            promotion_label=promo.display_label,
                            faculty_label=faculty.name,
                            s1_credits_earned=s1_earned,
                            s1_credits_total=30,
                            s2_credits_earned=s2_earned,
                            s2_credits_total=30,
                            credits_earned=earned,
                            credits_total=60,
                            result=result,
                        )
                    )

                SemesterResultLine.objects.bulk_create(lines, batch_size=BATCH)
                report.total_students = len(lines)
                report.passed_students = passed
                report.failed_students = failed
                report.save(update_fields=["total_students", "passed_students", "failed_students"])

                FacultyReport.objects.create(
                    title=title,
                    university=university,
                    faculty=faculty,
                    academic_year=ACADEMIC_YEAR,
                    total_students=report.total_students,
                    passed_students=passed,
                    failed_students=failed,
                    submitted_by=dean,
                )

                stats["reports"] += 1
                stats["lines"] += len(lines)
                stats["reussite"] += passed
                stats["echec"] += failed

                self.stdout.write(
                    f"  {fac_slug}/{promo.name}: {len(students)} etu | "
                    f"{passed} reussite / {failed} echec"
                )

        return stats

    def _purge(self):
        from lms.models import Course, Enrollment, NationalCourse, University, User
        from super_admin.models import (
            FacultyReport,
            ProvincialReport,
            SemesterResultReport,
            TerritorialAlert,
            UniversityReport,
        )

        self.stdout.write(self.style.WARNING("Purge des donnees operationnelles..."))
        with transaction.atomic():
            University.objects.update(teacher=None)
            SemesterResultReport.objects.all().delete()
            FacultyReport.objects.all().delete()
            UniversityReport.objects.all().delete()
            ProvincialReport.objects.all().delete()
            TerritorialAlert.objects.all().delete()
            Course.objects.all().delete()
            NationalCourse.objects.all().delete()
            Enrollment.objects.all().delete()
            University.objects.all().delete()
            User.objects.filter(role__in=["MANAGER", "DEAN", "TEACHER", "STUDENT"]).delete()
            cache.clear()
        self.stdout.write(self.style.SUCCESS("Purge terminee."))
