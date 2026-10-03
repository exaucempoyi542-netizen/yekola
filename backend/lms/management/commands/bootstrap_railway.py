"""Bootstrap minimal production data when Railway DB is empty."""
from __future__ import annotations

import os

from django.contrib.auth.hashers import make_password
from django.core.management import call_command
from django.core.management.base import BaseCommand

from lms.models import Province, User

SUPER_USERNAME = os.getenv("BOOTSTRAP_SUPER_USER", "superadmin")
SUPER_PASSWORD = os.getenv("BOOTSTRAP_SUPER_PASSWORD", "YekolaAdmin2026!")
SUPER_EMAIL = os.getenv("BOOTSTRAP_SUPER_EMAIL", "superadmin@yekola.cd")


class Command(BaseCommand):
    help = (
        "Initialise provinces, super-admin, jeu Kinshasa léger, admins provinciaux. "
        "Idempotent si des utilisateurs existent déjà (sauf --force)."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--force",
            action="store_true",
            help="Relance le seed même si des utilisateurs existent.",
        )
        parser.add_argument(
            "--students-per-promo",
            type=int,
            default=int(os.getenv("BOOTSTRAP_STUDENTS_PER_PROMO", "15")),
        )
        parser.add_argument(
            "--scope",
            choices=("single", "kinshasa", "national"),
            default=os.getenv("BOOTSTRAP_SCOPE", "kinshasa"),
        )

    def handle(self, *args, **options):
        if User.objects.exists() and not options["force"]:
            self.stdout.write("Bootstrap ignore: utilisateurs deja presents.")
            return

        for code, _label in Province.RDC_PROVINCES:
            Province.objects.get_or_create(code=code)

        pwd_hash = make_password(SUPER_PASSWORD)
        user, created = User.objects.update_or_create(
            username=SUPER_USERNAME,
            defaults={
                "email": SUPER_EMAIL,
                "password": pwd_hash,
                "first_name": "Super",
                "last_name": "Admin",
                "role": "SUPER_ADMIN",
                "is_staff": True,
                "is_superuser": True,
                "is_active": True,
            },
        )
        if not created:
            user.password = pwd_hash
            user.role = "SUPER_ADMIN"
            user.is_staff = True
            user.is_superuser = True
            user.is_active = True
            user.save()
        self.stdout.write(
            self.style.SUCCESS(
                f"SUPER_ADMIN ready: {SUPER_USERNAME} / {SUPER_PASSWORD}"
            )
        )

        call_command(
            "seed_full_test_data",
            scope=options["scope"],
            students_per_promo=options["students_per_promo"],
            yes=True,
            verbosity=1,
        )
        call_command("seed_provincial_admins", reset_passwords=True, verbosity=1)
        self.stdout.write(self.style.SUCCESS("Bootstrap Railway termine."))
