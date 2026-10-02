from django.core.management.base import BaseCommand

from lms.models import Faculty, NationalFaculty, University


class Command(BaseCommand):
    help = "Ajoute toutes les facultés nationales actives à chaque université (sans doublon)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--university-id",
            type=int,
            default=0,
            help="Limiter à une université (id). 0 = toutes.",
        )

    def handle(self, *args, **options):
        national = list(NationalFaculty.objects.filter(is_active=True).order_by("name"))
        if not national:
            self.stderr.write(self.style.ERROR("Aucune faculté nationale active."))
            return

        unis = University.objects.all().order_by("name")
        uni_id = options.get("university_id") or 0
        if uni_id:
            unis = unis.filter(pk=uni_id)

        created = 0
        linked = 0
        skipped = 0

        self.stdout.write(f"{len(national)} facultes nationales x {unis.count()} universites\n")

        for uni in unis.iterator():
            uni_created = 0
            for nf in national:
                faculty, was_created = Faculty.objects.get_or_create(
                    university=uni,
                    name=nf.name,
                    defaults={"national_faculty": nf},
                )
                if was_created:
                    created += 1
                    uni_created += 1
                elif not faculty.national_faculty_id:
                    faculty.national_faculty = nf
                    faculty.save(update_fields=["national_faculty"])
                    linked += 1
                else:
                    skipped += 1
            if uni_created:
                self.stdout.write(f"  + {uni.name}: {uni_created} facultes")

        self.stdout.write(
            self.style.SUCCESS(
                f"\nTermine : {created} creees, {linked} rattachees, {skipped} deja presentes."
            )
        )
        self.stdout.write(f"Total Faculte en base : {Faculty.objects.count()}")
