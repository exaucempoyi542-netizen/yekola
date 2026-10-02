"""
Cote les étudiants (hors William Booth) et remonte les résultats :
  Décanat → FacultyReport → UniversityReport (province) → ProvincialReport (national).

Usage :
  python manage.py seed_grades_and_reports --yes --reports-only
  python manage.py seed_grades_and_reports --yes --skip-course-grades
  python manage.py seed_grades_and_reports --yes --limit-universities 2
"""
from __future__ import annotations

import random
from decimal import Decimal

from django.core.cache import cache
from django.core.management.base import BaseCommand
from django.db import connection
from django.db.models import Count
from django.utils import timezone

ACADEMIC_YEAR = "2025-2026"
BATCH = 5000
DEFAULT_PASS_RATE = 0.78

_PASS_SCORES = [
    (Decimal("3.00"), Decimal("3.00"), Decimal("6.00")),
    (Decimal("3.50"), Decimal("3.50"), Decimal("7.00")),
    (Decimal("4.00"), Decimal("4.00"), Decimal("8.00")),
    (Decimal("4.50"), Decimal("4.50"), Decimal("9.00")),
]
_FAIL_SCORES = [
    (Decimal("1.00"), Decimal("1.00"), Decimal("2.00")),
    (Decimal("1.50"), Decimal("1.50"), Decimal("3.00")),
    (Decimal("2.00"), Decimal("2.00"), Decimal("4.00")),
    (Decimal("2.25"), Decimal("2.25"), Decimal("4.50")),
]


def _pick_score(must_pass: bool, rng: random.Random):
    pool = _PASS_SCORES if must_pass else _FAIL_SCORES
    return pool[rng.randrange(len(pool))]


class Command(BaseCommand):
    help = (
        "Cote les étudiants et envoie les résultats aux niveaux provincial et national "
        "(hors William Booth)."
    )

    def add_arguments(self, parser):
        parser.add_argument("--yes", action="store_true")
        parser.add_argument("--pass-rate", type=float, default=DEFAULT_PASS_RATE)
        parser.add_argument("--limit-universities", type=int, default=0)
        parser.add_argument(
            "--reports-only",
            action="store_true",
            help="Rapports agrégés seulement (rapide, provincial + national).",
        )
        parser.add_argument(
            "--skip-course-grades",
            action="store_true",
            help="StudentAudit seulement (pas CourseGrade).",
        )
        parser.add_argument(
            "--grades-only",
            action="store_true",
            help="Cotes par cours seulement (pas de nouveaux rapports).",
        )

    def _flush_audits(self, rows: list, totals: dict) -> None:
        if not rows:
            return
        sql = (
            "INSERT IGNORE INTO lms_studentaudit "
            "(student_id, teacher_id, course_id, full_name, tp, interro, examen, status, updated_at) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)"
        )
        with connection.cursor() as cursor:
            cursor.executemany(sql, rows)
        totals["audits"] += len(rows)

    def _flush_grades(self, rows: list, totals: dict) -> None:
        if not rows:
            return
        sql = (
            "INSERT IGNORE INTO lms_coursegrade "
            "(student_id, course_id, quiz_average, interrogation_score, exam_score, "
            "final_score, status, created_at, updated_at) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)"
        )
        with connection.cursor() as cursor:
            cursor.executemany(sql, rows)
        totals["grades"] += len(rows)

    def _seed_reports_fast(self, unis, pass_rate: float, now) -> dict:
        """Rapports agrégés sans lignes nominatives — rapide."""
        from lms.models import Faculty, Promotion, Province, University, User
        from super_admin.models import (
            FacultyReport,
            ProvincialReport,
            SemesterResultReport,
            UniversityReport,
        )

        self.stdout.write("Nettoyage des anciens rapports…")
        self.stdout.flush()
        with connection.cursor() as cursor:
            cursor.execute("SET FOREIGN_KEY_CHECKS=0")
            cursor.execute("TRUNCATE TABLE super_admin_semesterresultline")
            cursor.execute("TRUNCATE TABLE super_admin_semesterresultreport")
            cursor.execute("TRUNCATE TABLE super_admin_facultyreport")
            cursor.execute(
                "DELETE FROM super_admin_universityreport WHERE academic_year=%s",
                [ACADEMIC_YEAR],
            )
            cursor.execute(
                "DELETE FROM super_admin_provincialreport WHERE academic_year=%s",
                [ACADEMIC_YEAR],
            )
            cursor.execute("SET FOREIGN_KEY_CHECKS=1")
        self.stdout.write("Nettoyage OK.")
        self.stdout.flush()

        totals = {
            "faculty_reports": 0,
            "semester_reports": 0,
            "uni_reports": 0,
            "prov_reports": 0,
            "passed": 0,
            "failed": 0,
            "audits": 0,
            "grades": 0,
            "lines": 0,
            "skipped_grade_promos": 0,
        }

        uni_ids = [u.id for u in unis]
        # Compte étudiants par (university, faculty, promotion)
        rows = (
            User.objects.filter(
                role="STUDENT",
                class_group__promotion__faculty__university_id__in=uni_ids,
            )
            .exclude(class_group__promotion__faculty__university__name__icontains="William Booth")
            .values(
                "class_group__promotion__faculty__university_id",
                "class_group__promotion__faculty_id",
                "class_group__promotion_id",
            )
            .annotate(n=Count("id"))
        )
        counts = {}
        for r in rows:
            key = (
                r["class_group__promotion__faculty__university_id"],
                r["class_group__promotion__faculty_id"],
                r["class_group__promotion_id"],
            )
            counts[key] = r["n"]

        promo_map = {
            p.id: p
            for p in Promotion.objects.filter(
                faculty__university_id__in=uni_ids
            ).select_related("faculty")
        }
        fac_map = {
            f.id: f for f in Faculty.objects.filter(university_id__in=uni_ids)
        }
        managers = {
            u.assigned_university_id: u
            for u in User.objects.filter(
                role="MANAGER",
                assigned_university_id__in=uni_ids,
                is_active=True,
            ).order_by("id")
        }
        deans = {}
        for d in User.objects.filter(
            role="DEAN",
            assigned_university_id__in=uni_ids,
            is_active=True,
        ).order_by("id"):
            deans.setdefault((d.assigned_university_id, d.assigned_faculty_id), d)

        fr_buffer = []
        srr_buffer = []
        uni_agg = {u.id: {"passed": 0, "failed": 0} for u in unis}

        for (uni_id, fac_id, promo_id), n in counts.items():
            promo = promo_map.get(promo_id)
            fac = fac_map.get(fac_id)
            if not promo or not fac:
                continue
            n_pass = int(round(n * pass_rate))
            n_fail = n - n_pass
            uni_agg[uni_id]["passed"] += n_pass
            uni_agg[uni_id]["failed"] += n_fail
            totals["passed"] += n_pass
            totals["failed"] += n_fail
            title = (
                f"Rapport annuel consolidé — {fac.name} — {promo.display_label}"
            )
            dean = deans.get((uni_id, fac_id))
            fr_buffer.append(
                FacultyReport(
                    title=title,
                    university_id=uni_id,
                    faculty_id=fac_id,
                    academic_year=ACADEMIC_YEAR,
                    total_students=n,
                    passed_students=n_pass,
                    failed_students=n_fail,
                    submitted_by=dean,
                    is_validated=True,
                    validated_at=now,
                )
            )
            srr_buffer.append(
                SemesterResultReport(
                    university_id=uni_id,
                    faculty_id=fac_id,
                    promotion_id=promo_id,
                    semester=None,
                    academic_year=ACADEMIC_YEAR,
                    title=title,
                    credits_reference=60,
                    semester_credits_reference=30,
                    total_students=n,
                    passed_students=n_pass,
                    failed_students=n_fail,
                    submitted_by=dean,
                )
            )
            if len(fr_buffer) >= 500:
                FacultyReport.objects.bulk_create(fr_buffer, batch_size=500)
                SemesterResultReport.objects.bulk_create(srr_buffer, batch_size=500)
                totals["faculty_reports"] += len(fr_buffer)
                totals["semester_reports"] += len(srr_buffer)
                fr_buffer.clear()
                srr_buffer.clear()

        if fr_buffer:
            FacultyReport.objects.bulk_create(fr_buffer, batch_size=500)
            SemesterResultReport.objects.bulk_create(srr_buffer, batch_size=500)
            totals["faculty_reports"] += len(fr_buffer)
            totals["semester_reports"] += len(srr_buffer)

        ur_buffer = []
        for university in unis:
            agg = uni_agg.get(university.id, {"passed": 0, "failed": 0})
            total_stu = agg["passed"] + agg["failed"]
            if total_stu <= 0:
                continue
            ur_buffer.append(
                UniversityReport(
                    title=f"Rapport Annuel Consolidé - {university.name}",
                    academic_year=ACADEMIC_YEAR,
                    university=university,
                    total_students=total_stu,
                    passed_students=agg["passed"],
                    failed_students=agg["failed"],
                    submitted_by=managers.get(university.id),
                    is_validated=False,
                )
            )
            rate = round(100.0 * agg["passed"] / total_stu, 1)
            self.stdout.write(
                f"  {university.name}: {total_stu} étu | "
                f"{agg['passed']} OK / {agg['failed']} KO ({rate}%)"
            )

        UniversityReport.objects.bulk_create(ur_buffer, batch_size=200)
        totals["uni_reports"] = len(ur_buffer)
        self.stdout.flush()

        self.stdout.write("Consolidation provinciale → national…")
        for province in Province.objects.order_by("code"):
            pending = list(
                UniversityReport.objects.filter(
                    university__province=province,
                    academic_year=ACADEMIC_YEAR,
                    is_validated=False,
                )
            )
            if not pending:
                continue
            total_students = sum(r.total_students for r in pending)
            passed = sum(r.passed_students for r in pending)
            failed = sum(r.failed_students for r in pending)
            unis_reported = len({r.university_id for r in pending})
            total_unis = University.objects.filter(province=province).count()
            ProvincialReport.objects.create(
                title=f"Rapport Annuel Provincial — {province.name}",
                province=province,
                academic_year=ACADEMIC_YEAR,
                total_universities=total_unis,
                total_students=total_students,
                passed_students=passed,
                failed_students=failed,
                universities_reported=unis_reported,
                universities_pending=max(total_unis - unis_reported, 0),
                submitted_by=None,
                is_validated=False,
            )
            UniversityReport.objects.filter(id__in=[r.id for r in pending]).update(
                is_validated=True, validated_at=now
            )
            totals["prov_reports"] += 1
            self.stdout.write(
                f"  {province.name}: {unis_reported}/{total_unis} univ. | "
                f"{passed}/{total_students} réussite"
            )

        return totals

    def _seed_grades_sql(self, unis, now) -> dict:
        """Cotation massive via INSERT…SELECT (beaucoup plus rapide)."""
        from lms.models import StudentAudit

        totals = {"audits": 0, "grades": 0, "skipped_grade_promos": 0}
        before = StudentAudit.objects.count()

        sql = """
            INSERT INTO lms_studentaudit
                (student_id, teacher_id, course_id, full_name, tp, interro, examen, status, updated_at)
            SELECT
                u.id,
                c.teacher_id,
                c.id,
                LEFT(
                    COALESCE(
                        NULLIF(TRIM(CONCAT(IFNULL(u.first_name,''), ' ', IFNULL(u.last_name,''))), ''),
                        u.username
                    ),
                    255
                ),
                CASE WHEN MOD(u.id + c.id, 100) < 78 THEN 4.00 ELSE 1.50 END,
                CASE WHEN MOD(u.id + c.id, 100) < 78 THEN 4.00 ELSE 1.50 END,
                CASE WHEN MOD(u.id + c.id, 100) < 78 THEN 8.00 ELSE 3.00 END,
                'VALIDATED_BY_DEAN',
                %s
            FROM lms_user u
            INNER JOIN lms_classgroup cg ON u.class_group_id = cg.id
            INNER JOIN lms_course c ON c.promotion_id = cg.promotion_id AND c.teacher_id IS NOT NULL
            WHERE u.role = 'STUDENT'
              AND cg.promotion_id IN (
                  SELECT p.id FROM lms_promotion p
                  INNER JOIN lms_faculty f ON f.id = p.faculty_id
                  WHERE f.university_id = %s
              )
        """

        graded_uni_ids = set(
            StudentAudit.objects.exclude(course_id=None)
            .values_list("course__promotion__faculty__university_id", flat=True)
            .distinct()
        )

        for u_idx, university in enumerate(unis, start=1):
            if university.id in graded_uni_ids:
                totals["skipped_grade_promos"] += 1
                self.stdout.write(
                    f"  [{u_idx}/{len(unis)}] {university.name}: déjà cotée (skip)"
                )
                self.stdout.flush()
                continue

            with connection.cursor() as cursor:
                cursor.execute(sql, [now, university.id])
                added = cursor.rowcount if cursor.rowcount and cursor.rowcount > 0 else 0
            totals["audits"] += max(added, 0)
            graded_uni_ids.add(university.id)
            self.stdout.write(
                f"  [{u_idx}/{len(unis)}] {university.name}: +{max(added, 0)} cotes"
            )
            self.stdout.flush()

        after = StudentAudit.objects.count()
        totals["audits"] = max(after - before, totals["audits"])
        return totals

    def _seed_grades(self, unis, pass_rate: float, skip_cg: bool, now) -> dict:
        # Délègue à la voie SQL (pass_rate / skip_cg ignorés côté SQL pour la vitesse)
        return self._seed_grades_sql(unis, now)

    def handle(self, *args, **options):
        if not options["yes"]:
            self.stdout.write(self.style.WARNING("Ajoutez --yes pour lancer."))
            return

        from lms.models import University

        pass_rate = min(1.0, max(0.0, float(options["pass_rate"])))
        reports_only = bool(options["reports_only"])
        grades_only = bool(options["grades_only"])
        skip_cg = bool(options["skip_course_grades"]) or reports_only
        limit = int(options["limit_universities"] or 0)
        now = timezone.now()

        unis = list(
            University.objects.exclude(name__icontains="William Booth")
            .select_related("province")
            .order_by("id")
        )
        if limit > 0:
            unis = unis[:limit]

        self.stdout.write(
            f"{len(unis)} univ. | pass_rate={pass_rate:.0%} | "
            f"reports_only={reports_only} | grades_only={grades_only}"
        )
        self.stdout.flush()

        totals = {
            "audits": 0,
            "grades": 0,
            "faculty_reports": 0,
            "semester_reports": 0,
            "lines": 0,
            "uni_reports": 0,
            "prov_reports": 0,
            "passed": 0,
            "failed": 0,
            "skipped_grade_promos": 0,
        }

        if not grades_only:
            t = self._seed_reports_fast(unis, pass_rate, now)
            for k, v in t.items():
                totals[k] = totals.get(k, 0) + v

        if not reports_only:
            self.stdout.write("Cotation des étudiants…")
            self.stdout.flush()
            t = self._seed_grades(unis, pass_rate, skip_cg, now)
            for k, v in t.items():
                totals[k] = totals.get(k, 0) + v

        cache.clear()
        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS("Terminé."))
        self.stdout.write(f"  Audits               : {totals['audits']}")
        self.stdout.write(f"  CourseGrade          : {totals['grades']}")
        self.stdout.write(f"  Promos déjà cotées   : {totals['skipped_grade_promos']}")
        self.stdout.write(f"  Rapports faculté     : {totals['faculty_reports']}")
        self.stdout.write(f"  Rapports semestriels : {totals['semester_reports']}")
        self.stdout.write(f"  Rapports univ.       : {totals['uni_reports']}")
        self.stdout.write(f"  Rapports provinciaux : {totals['prov_reports']}")
        self.stdout.write(
            f"  Réussites / Échecs   : {totals['passed']} / {totals['failed']}"
        )
