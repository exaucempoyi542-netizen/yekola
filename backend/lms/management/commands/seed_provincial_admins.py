from django.core.management.base import BaseCommand
from django.contrib.auth.hashers import make_password

from lms.models import Province, User

DEFAULT_PASSWORD = "Provincial123!"


class Command(BaseCommand):
    help = (
        "Crée (ou met à jour) un administrateur provincial par province. "
        f"Mot de passe commun : {DEFAULT_PASSWORD}"
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--reset-passwords",
            action="store_true",
            help="Réinitialise aussi le mot de passe des comptes provinciaux déjà existants.",
        )

    def handle(self, *args, **options):
        reset = options["reset_passwords"]
        pwd_hash = make_password(DEFAULT_PASSWORD)
        created = updated = skipped = 0

        self.stdout.write(f"Mot de passe commun : {DEFAULT_PASSWORD}\n")
        self.stdout.write(f"{'Province':<22} {'Identifiant':<28} {'Action'}")
        self.stdout.write("-" * 70)

        for province in Province.objects.all().order_by("code"):
            username = f"admin_{province.code.lower()}"
            existing = User.objects.filter(role="PROVINCIAL_ADMIN", assigned_province=province).first()

            if existing:
                # Garder l'identifiant existant (ex. kabulu), optionnellement reset MDP
                if reset or not existing.has_usable_password():
                    existing.password = pwd_hash
                    existing.is_active = True
                    existing.save(update_fields=["password", "is_active"])
                    updated += 1
                    action = "MAJ mot de passe"
                else:
                    # Toujours reset pour pouvoir communiquer les accès
                    existing.password = pwd_hash
                    existing.is_active = True
                    existing.save(update_fields=["password", "is_active"])
                    updated += 1
                    action = "MAJ mot de passe"
                self.stdout.write(f"{province.name:<22} {existing.username:<28} {action}")
                continue

            if User.objects.filter(username=username).exists():
                user = User.objects.get(username=username)
                user.role = "PROVINCIAL_ADMIN"
                user.assigned_province = province
                user.password = pwd_hash
                user.is_active = True
                user.save()
                updated += 1
                self.stdout.write(f"{province.name:<22} {username:<28} rattache + MDP")
                continue

            User.objects.create(
                username=username,
                email=f"{username}@edurdc.cd",
                password=pwd_hash,
                first_name="Admin",
                last_name=province.name,
                role="PROVINCIAL_ADMIN",
                assigned_province=province,
                is_active=True,
            )
            created += 1
            self.stdout.write(f"{province.name:<22} {username:<28} cree")

        self.stdout.write(
            self.style.SUCCESS(
                f"\nTermine : {created} crees, {updated} mis a jour, {skipped} ignores."
            )
        )
        self.stdout.write(f"Connexion : /super-admin/login/  |  MDP : {DEFAULT_PASSWORD}")
