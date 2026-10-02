from __future__ import annotations

import sys

from django.contrib.auth.hashers import make_password
from django.core.management.base import BaseCommand
from django.db import transaction

from lms.models import ClassGroup, Faculty, Promotion, University, User

DEFAULT_PASSWORD = "Test1234"
BATCH = 150


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
        "Crée des étudiants par promotion (hors William Booth). "
        f"MDP : {DEFAULT_PASSWORD}"
    )

    def add_arguments(self, parser):
        parser.add_argument("--students-per-promo", type=int, default=100)
        parser.add_argument("--yes", action="store_true")

    def handle(self, *args, **options):
        per_promo = max(1, options["students_per_promo"])
        if not options["yes"]:
            self.stdout.write(self.style.WARNING("Ajoutez --yes pour lancer."))
            return

        self.stdout.write("Demarrage seed etudiants…")
        self.stdout.flush()

        pwd_hash = make_password(DEFAULT_PASSWORD)
        unis = list(
            University.objects.exclude(name__icontains="William Booth")
            .order_by("id")
            .only("id", "name")
        )
        uni_count = len(unis)
        self.stdout.write(
            f"{uni_count} universites | cible={per_promo}/promo | MDP={DEFAULT_PASSWORD}"
        )
        self.stdout.flush()

        students_created = 0

        for idx, uni in enumerate(unis, start=1):
            uni_added = 0
            faculties = list(Faculty.objects.filter(university_id=uni.id).only("id", "name"))
            buffer = []

            for faculty in faculties:
                Promotion.ensure_lmd_for_faculty(faculty)
                promotions = list(
                    Promotion.objects.filter(faculty_id=faculty.id).only("id", "name")
                )
                fac_code = _fac_code(faculty.name)

                for promo in promotions:
                    class_group, _ = ClassGroup.objects.get_or_create(
                        promotion_id=promo.id,
                        name="Groupe Principal",
                    )
                    already = User.objects.filter(
                        role="STUDENT", class_group_id=class_group.id
                    ).count()
                    to_create = per_promo - already
                    if to_create <= 0:
                        continue

                    prefix = f"etu_{uni.id}_f{faculty.id}_{promo.name.lower()}"
                    # Prochain numéro libre
                    start = already + 1
                    for num in range(start, start + to_create):
                        username = f"{prefix}_{num:04d}"
                        buffer.append(
                            User(
                                username=username,
                                first_name=f"Etudiant{num}",
                                last_name=f"{fac_code}{promo.name}",
                                email=f"{username}@student.educ",
                                role="STUDENT",
                                matricule=f"U{uni.id}-F{faculty.id}-{promo.name}-S{num:04d}",
                                class_group_id=class_group.id,
                                assigned_university_id=uni.id,
                                assigned_faculty_id=faculty.id,
                                assigned_promotion_id=promo.id,
                                is_active=True,
                                password=pwd_hash,
                            )
                        )
                        uni_added += 1
                        if len(buffer) >= BATCH:
                            with transaction.atomic():
                                User.objects.bulk_create(
                                    buffer, batch_size=BATCH, ignore_conflicts=True
                                )
                            students_created += len(buffer)
                            buffer = []

            if buffer:
                with transaction.atomic():
                    User.objects.bulk_create(buffer, batch_size=BATCH, ignore_conflicts=True)
                students_created += len(buffer)
                buffer = []

            self.stdout.write(
                f"[{idx}/{uni_count}] {uni.name}: +{uni_added} | session={students_created}"
            )
            self.stdout.flush()

        total = User.objects.filter(role="STUDENT").count()
        wb = User.objects.filter(
            role="STUDENT", assigned_university__name__icontains="William Booth"
        ).count()
        self.stdout.write(
            self.style.SUCCESS(
                f"\nTermine.\nEtudiants crees (tentative): {students_created}\n"
                f"Total etudiants: {total} (William Booth: {wb})\n"
                f"MDP: {DEFAULT_PASSWORD}"
            )
        )
