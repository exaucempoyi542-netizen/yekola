"""
Réinitialise les données opérationnelles pour repartir sur la nouvelle architecture :
Super Admin = pilotage / ressources ; Admin Provincial = gestion des universités.

Conserve : SUPER_ADMIN, PROVINCIAL_ADMIN, Province, ExternalResource.
Supprime : MANAGER / DEAN / TEACHER, cours (instances + maquette),
établissements et rapports académiques liés.
"""
from django.core.cache import cache
from django.core.management.base import BaseCommand
from django.db import transaction


class Command(BaseCommand):
    help = (
        "Purge Managers, Deans, Teachers, cours, établissements et rapports "
        "pour repartir à zéro (nouvelle architecture)."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--yes',
            action='store_true',
            help='Confirme la purge sans invite interactive.',
        )
        parser.add_argument(
            '--keep-students',
            action='store_true',
            default=True,
            help='Conserve les comptes STUDENT (défaut).',
        )
        parser.add_argument(
            '--delete-students',
            action='store_true',
            help='Supprime aussi les comptes STUDENT.',
        )
        parser.add_argument(
            '--super-admin-only',
            action='store_true',
            help='Conserve uniquement SUPER_ADMIN / is_superuser (supprime aussi PROVINCIAL_ADMIN).',
        )

    def handle(self, *args, **options):
        if not options['yes']:
            self.stderr.write(
                self.style.ERROR('Ajoutez --yes pour confirmer la purge définitive.')
            )
            return

        from lms.models import (
            AuditLog,
            Course,
            Enrollment,
            NationalCourse,
            University,
            User,
        )
        from super_admin.models import (
            FacultyReport,
            ProvincialReport,
            SemesterResultReport,
            TerritorialAlert,
            UniversityReport,
        )

        delete_students = options['delete_students'] or options['super_admin_only']
        super_admin_only = options['super_admin_only']

        with transaction.atomic():
            # Évite CASCADE University via University.teacher
            uni_teacher_cleared = University.objects.update(teacher=None)

            courses_deleted, _ = Course.objects.all().delete()
            national_deleted, _ = NationalCourse.objects.all().delete()

            fr_deleted, _ = FacultyReport.objects.all().delete()
            srr_deleted, _ = SemesterResultReport.objects.all().delete()
            ur_deleted, _ = UniversityReport.objects.all().delete()
            pr_deleted, _ = ProvincialReport.objects.all().delete()
            ta_deleted, _ = TerritorialAlert.objects.all().delete()

            # Structure universitaire (facultés / promotions / groupes en cascade)
            unis_deleted, _ = University.objects.all().delete()

            roles = ['MANAGER', 'DEAN', 'TEACHER']
            if delete_students:
                roles.append('STUDENT')
            if super_admin_only:
                roles.append('PROVINCIAL_ADMIN')

            staff_qs = User.objects.filter(role__in=roles)
            staff_count = staff_qs.count()
            staff_deleted, _ = staff_qs.delete()

            if super_admin_only:
                from django.db.models import Q

                extra_qs = User.objects.exclude(
                    Q(role='SUPER_ADMIN') | Q(is_superuser=True)
                )
                extra_count = extra_qs.count()
                extra_deleted, _ = extra_qs.delete()
                audit_deleted, _ = AuditLog.objects.all().delete()
            else:
                extra_count = 0
                extra_deleted = 0
                audit_deleted = 0

            # Orphelins éventuels côté étudiants conservés
            if not delete_students:
                User.objects.filter(role='STUDENT').update(
                    class_group=None,
                    assigned_university=None,
                    assigned_faculty=None,
                    assigned_promotion=None,
                )
                Enrollment.objects.all().delete()

            cache.clear()

        self.stdout.write(self.style.SUCCESS('Purge opérationnelle terminée.'))
        self.stdout.write(f'  University.teacher nullifiés : {uni_teacher_cleared}')
        self.stdout.write(f'  Course (cascade contenu)     : {courses_deleted}')
        self.stdout.write(f'  NationalCourse               : {national_deleted}')
        self.stdout.write(f'  FacultyReport                : {fr_deleted}')
        self.stdout.write(f'  SemesterResultReport         : {srr_deleted}')
        self.stdout.write(f'  UniversityReport             : {ur_deleted}')
        self.stdout.write(f'  ProvincialReport             : {pr_deleted}')
        self.stdout.write(f'  TerritorialAlert             : {ta_deleted}')
        self.stdout.write(f'  University (+ structure)     : {unis_deleted}')
        self.stdout.write(f'  Users {roles}                : {staff_count} (delete map {staff_deleted})')
        if super_admin_only:
            self.stdout.write(f'  Autres utilisateurs          : {extra_count} (delete map {extra_deleted})')
            self.stdout.write(f'  AuditLog                     : {audit_deleted}')
        self.stdout.write('  Cache Django vidé.')
        kept = 'SUPER_ADMIN, Province, ExternalResource, NationalFaculty'
        if super_admin_only:
            kept = 'SUPER_ADMIN uniquement, Province, ExternalResource, NationalFaculty'
        elif not delete_students:
            kept += ', PROVINCIAL_ADMIN, STUDENT'
        else:
            kept += ', PROVINCIAL_ADMIN'
        self.stdout.write(self.style.WARNING(f'Conservés : {kept}.'))
