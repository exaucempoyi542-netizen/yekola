from __future__ import annotations

import re
import unicodedata

from django.contrib.auth.hashers import make_password
from django.core.management.base import BaseCommand

from lms.models import Faculty, University, User

DEFAULT_PASSWORD = "Test1234"


def _slugify(value: str) -> str:
    text = unicodedata.normalize("NFKD", value or "")
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "_", text).strip("_")
    return text[:28] or "univ"


class Command(BaseCommand):
    help = (
        "Crée un manager par université et un décanat par faculté (sans doublon). "
        f"Mot de passe commun : {DEFAULT_PASSWORD}"
    )

    def handle(self, *args, **options):
        pwd_hash = make_password(DEFAULT_PASSWORD)
        managers_created = managers_updated = 0
        deans_created = deans_updated = 0

        unis = University.objects.select_related("province").prefetch_related("faculties").order_by("name")
        self.stdout.write(
            f"{unis.count()} universites | MDP = {DEFAULT_PASSWORD}\n"
        )

        for uni in unis:
            uni_slug = _slugify(uni.name)
            manager_username = f"mgr_{uni.pk}_{uni_slug}"[:50]

            existing_mgr = User.objects.filter(
                role="MANAGER",
                assigned_university=uni,
                is_active=True,
            ).first()

            if existing_mgr:
                managers_updated += 1
                manager = existing_mgr
            else:
                # Réutiliser le username cible s'il existe déjà
                manager = User.objects.filter(username=manager_username).first()
                if manager:
                    manager.role = "MANAGER"
                    manager.assigned_university = uni
                    manager.is_active = True
                    manager.password = pwd_hash
                    if not manager.first_name:
                        manager.first_name = "Manager"
                    if not manager.last_name:
                        manager.last_name = (uni.name or "")[:40]
                    manager.save()
                    managers_updated += 1
                else:
                    User.objects.create(
                        username=manager_username,
                        email=f"{manager_username}@educ.cd",
                        password=pwd_hash,
                        first_name="Manager",
                        last_name=(uni.name or "")[:40],
                        role="MANAGER",
                        assigned_university=uni,
                        is_active=True,
                    )
                    managers_created += 1
                    manager = User.objects.get(username=manager_username)

            faculties = list(Faculty.objects.filter(university=uni).order_by("name"))
            for faculty in faculties:
                fac_slug = _slugify(faculty.name)[:12]
                dean_username = f"dean_{uni.pk}_{faculty.pk}_{fac_slug}"[:50]

                existing_dean = User.objects.filter(
                    role="DEAN",
                    assigned_faculty=faculty,
                    is_active=True,
                ).first()

                if existing_dean:
                    # Assurer le rattachement université
                    if existing_dean.assigned_university_id != uni.id:
                        existing_dean.assigned_university = uni
                        existing_dean.save(update_fields=["assigned_university"])
                    deans_updated += 1
                    continue

                dean = User.objects.filter(username=dean_username).first()
                if dean:
                    dean.role = "DEAN"
                    dean.assigned_university = uni
                    dean.assigned_faculty = faculty
                    dean.is_active = True
                    dean.password = pwd_hash
                    dean.save()
                    deans_updated += 1
                else:
                    User.objects.create(
                        username=dean_username,
                        email=f"{dean_username}@educ.cd",
                        password=pwd_hash,
                        first_name="Doyen",
                        last_name=(faculty.name or "")[:40],
                        role="DEAN",
                        assigned_university=uni,
                        assigned_faculty=faculty,
                        is_active=True,
                    )
                    deans_created += 1

            self.stdout.write(
                f"  {uni.name}: manager={manager.username} | {len(faculties)} decanat(s)"
            )

        self.stdout.write(
            self.style.SUCCESS(
                f"\nManagers : {managers_created} crees, {managers_updated} deja presents/maj\n"
                f"Decanats : {deans_created} crees, {deans_updated} deja presents/maj\n"
                f"Mot de passe : {DEFAULT_PASSWORD}\n"
                f"Connexion etablissement : /teacher/login/"
            )
        )
