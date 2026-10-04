from django.core.management.base import BaseCommand

from lms.media_convert import ensure_lesson_preview, libreoffice_available
from lms.models import Lesson


class Command(BaseCommand):
    help = "Génère les PDF de prévisualisation pour toutes les leçons PowerPoint."

    def handle(self, *args, **options):
        if not libreoffice_available():
            self.stderr.write(self.style.ERROR(
                "LibreOffice (soffice) introuvable. Installez libreoffice-impress."
            ))
            return

        qs = Lesson.objects.filter(content_type='PPT').exclude(content_file='')
        total = qs.count()
        ok = 0
        fail = 0
        self.stdout.write(f"{total} leçon(s) PPT à traiter…")
        for lesson in qs.iterator():
            if ensure_lesson_preview(lesson):
                ok += 1
                self.stdout.write(self.style.SUCCESS(f"  OK #{lesson.id} {lesson.title}"))
            else:
                fail += 1
                self.stdout.write(self.style.WARNING(f"  ÉCHEC #{lesson.id} {lesson.title}"))
        self.stdout.write(self.style.NOTICE(f"Terminé : {ok} OK, {fail} échec(s)."))
