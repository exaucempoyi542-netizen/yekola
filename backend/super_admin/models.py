from django.db import models
from lms.models import University, Faculty, Province, User, Promotion


class FacultyReport(models.Model):
    title = models.CharField(max_length=255)
    university = models.ForeignKey(University, on_delete=models.CASCADE, related_name='faculty_reports')
    faculty = models.ForeignKey(Faculty, on_delete=models.CASCADE, related_name='faculty_reports')
    academic_year = models.CharField(max_length=20, default="2023-2024")

    total_students = models.IntegerField(default=0)
    passed_students = models.IntegerField(default=0)
    failed_students = models.IntegerField(default=0)

    submitted_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='submitted_faculty_reports')
    submitted_at = models.DateTimeField(auto_now_add=True)

    is_validated = models.BooleanField(default=False)
    validated_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-submitted_at']

    def __str__(self):
        return f"{self.title} - {self.faculty.name} ({self.university.name})"


class SemesterResultReport(models.Model):
    """
    Rapport annuel consolidé du Décanat → Admin (Université).
    Affiche S1/30 + S2/30 = total/60 (Réussite ou Échec).
    """
    TITLE_YEAR_CREDITS = 60
    SEMESTER_CREDITS = 30

    university = models.ForeignKey(University, on_delete=models.CASCADE, related_name='semester_result_reports')
    faculty = models.ForeignKey(Faculty, on_delete=models.CASCADE, related_name='semester_result_reports')
    promotion = models.ForeignKey(Promotion, on_delete=models.CASCADE, related_name='semester_result_reports')
    # Conservé pour historique ; les nouveaux rapports sont annuels (semester=None)
    semester = models.PositiveSmallIntegerField(
        choices=((1, 'Semestre 1'), (2, 'Semestre 2')),
        null=True,
        blank=True,
        help_text='Null = rapport annuel consolidé S1+S2',
    )
    academic_year = models.CharField(max_length=20, default='2025-2026')
    title = models.CharField(max_length=255)

    credits_reference = models.PositiveIntegerField(default=60, help_text='Référence LMD annuelle (60 crédits)')
    semester_credits_reference = models.PositiveIntegerField(default=30, help_text='Référence par semestre (30 crédits)')
    total_students = models.IntegerField(default=0)
    passed_students = models.IntegerField(default=0)
    failed_students = models.IntegerField(default=0)

    submitted_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, related_name='submitted_semester_reports'
    )
    submitted_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-submitted_at']

    @property
    def is_annual(self):
        return self.semester is None

    def __str__(self):
        return self.title


class SemesterResultLine(models.Model):
    RESULT_CHOICES = (
        ('REUSSITE', 'Réussite'),
        ('ECHEC', 'Échec'),
    )
    report = models.ForeignKey(SemesterResultReport, on_delete=models.CASCADE, related_name='lines')
    student = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='semester_result_lines')
    full_name = models.CharField(max_length=255)
    promotion_label = models.CharField(max_length=64)
    faculty_label = models.CharField(max_length=255)

    s1_credits_earned = models.PositiveIntegerField(default=0)
    s1_credits_total = models.PositiveIntegerField(default=30)
    s2_credits_earned = models.PositiveIntegerField(default=0)
    s2_credits_total = models.PositiveIntegerField(default=30)

    credits_earned = models.PositiveIntegerField(default=0, help_text='Total annuel S1+S2')
    credits_total = models.PositiveIntegerField(default=60)
    result = models.CharField(max_length=20, choices=RESULT_CHOICES)

    class Meta:
        ordering = ['full_name']

    @property
    def s1_display(self):
        return f"{self.s1_credits_earned}/{self.s1_credits_total}"

    @property
    def s2_display(self):
        return f"{self.s2_credits_earned}/{self.s2_credits_total}"

    @property
    def credits_display(self):
        return f"{self.credits_earned}/{self.credits_total} crédits obtenus"

    def __str__(self):
        return f"{self.full_name} — {self.credits_display} ({self.result})"


class UniversityReport(models.Model):
    """Rapport consolidé par l'Admin (Université) → transmis à l'Administrateur Provincial."""
    title = models.CharField(max_length=255)
    university = models.ForeignKey(University, on_delete=models.CASCADE, related_name='university_reports')
    academic_year = models.CharField(max_length=20, default="2023-2024")

    total_students = models.IntegerField(default=0)
    passed_students = models.IntegerField(default=0)
    failed_students = models.IntegerField(default=0)

    submitted_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='submitted_uni_reports')
    submitted_at = models.DateTimeField(auto_now_add=True)

    # Consommé / consolidé par l'Admin Provincial
    is_validated = models.BooleanField(default=False)
    validated_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-submitted_at']

    def __str__(self):
        return f"{self.title} - {self.university.name}"

    @property
    def success_rate(self):
        if self.total_students <= 0:
            return 0.0
        return round((self.passed_students / self.total_students) * 100, 1)


class ProvincialReport(models.Model):
    """Rapport consolidé par l'Admin Provincial → transmis au Super-Admin (Ministère)."""
    title = models.CharField(max_length=255)
    province = models.ForeignKey(Province, on_delete=models.CASCADE, related_name='provincial_reports')
    academic_year = models.CharField(max_length=20, default="2023-2024")

    total_universities = models.IntegerField(default=0)
    total_students = models.IntegerField(default=0)
    passed_students = models.IntegerField(default=0)
    failed_students = models.IntegerField(default=0)
    universities_reported = models.IntegerField(default=0)
    universities_pending = models.IntegerField(default=0)

    submitted_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='submitted_provincial_reports')
    submitted_at = models.DateTimeField(auto_now_add=True)

    is_validated = models.BooleanField(default=False, help_text="Validé par le Super-Admin ministériel")
    validated_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-submitted_at']

    def __str__(self):
        return f"{self.title} - {self.province}"

    @property
    def success_rate(self):
        if self.total_students <= 0:
            return 0.0
        return round((self.passed_students / self.total_students) * 100, 1)


class TerritorialAlert(models.Model):
    """Alertes de conformité / anomalies territoriales pour l'Admin Provincial."""
    ALERT_TYPES = (
        ('FAILURE_SPIKE', 'Hausse anormale du taux d\'échec'),
        ('REPORT_LATE', 'Retard de dépôt de rapport'),
        ('SEMESTER_LOCK', 'Retard de clôture de session'),
        ('LMD_NONCOMPLIANCE', 'Non-conformité LMD'),
        ('OTHER', 'Autre anomalie'),
    )
    province = models.ForeignKey(Province, on_delete=models.CASCADE, related_name='territorial_alerts')
    university = models.ForeignKey(University, on_delete=models.CASCADE, null=True, blank=True, related_name='territorial_alerts')
    alert_type = models.CharField(max_length=30, choices=ALERT_TYPES, default='OTHER')
    title = models.CharField(max_length=255)
    message = models.TextField(blank=True)
    is_resolved = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"[{self.get_alert_type_display()}] {self.title}"
