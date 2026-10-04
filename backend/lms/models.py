from django.db import models
from django.contrib.auth.models import AbstractUser
import uuid
import os
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import UploadedFile
from django.conf import settings

def validate_lesson_file(file):
    """Valide la taille et le type du fichier pour les leçons"""
    # Vérifier la taille
    if file.size > settings.LESSON_FILE_UPLOAD_SIZE:
        max_size_mb = settings.LESSON_FILE_UPLOAD_SIZE / (1024 * 1024)
        raise ValidationError(f"Le fichier dépasse la taille maximale de {max_size_mb:.0f}MB")
    
    # Vérifier l'extension
    ext = os.path.splitext(file.name)[1].lower()
    
    allowed_extensions = (
        settings.ALLOWED_VIDEO_EXTENSIONS +
        settings.ALLOWED_PDF_EXTENSIONS +
        settings.ALLOWED_PPT_EXTENSIONS
    )
    
    if ext not in allowed_extensions:
        raise ValidationError(
            f"Format de fichier non autorisé. Extensions acceptées: {', '.join(allowed_extensions)}"
        )

class User(AbstractUser):
    ROLE_CHOICES = (
        ('SUPER_ADMIN', 'Super Administrateur (Ministère)'),
        ('PROVINCIAL_ADMIN', 'Administrateur Provincial'),
        ('MANAGER', 'Admin (Université)'),
        ('DEAN', 'Décanat (Faculté)'),
        ('TEACHER', 'Enseignant'),
        ('STUDENT', 'Étudiant'),
    )
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default='STUDENT', db_index=True)
    phone = models.CharField(max_length=20, blank=True, null=True)
    matricule = models.CharField(max_length=50, unique=True, null=True, blank=True)
    class_group = models.ForeignKey('ClassGroup', on_delete=models.SET_NULL, null=True, blank=True, related_name='students')
    # Affectations hiérarchiques
    assigned_province = models.ForeignKey(
        'Province', on_delete=models.SET_NULL, null=True, blank=True,
        related_name='provincial_admins',
        help_text="Province de tutelle pour l'Administrateur Provincial"
    )
    assigned_university = models.ForeignKey('University', on_delete=models.SET_NULL, null=True, blank=True, related_name='assigned_teachers')
    assigned_faculty = models.ForeignKey('Faculty', on_delete=models.SET_NULL, null=True, blank=True, related_name='assigned_teachers')
    assigned_promotion = models.ForeignKey('Promotion', on_delete=models.SET_NULL, null=True, blank=True, related_name='assigned_teachers')
    assigned_promotions = models.ManyToManyField(
        'Promotion',
        blank=True,
        related_name='multi_assigned_teachers',
        help_text="Promotions que le décanat peut confier à cet enseignant.",
    )
    assigned_semester = models.IntegerField(choices=((1, '1er Semestre'), (2, '2ème Semestre')), null=True, blank=True)
    firebase_uid = models.CharField(
        max_length=128, blank=True, null=True, db_index=True,
        help_text="UID Firebase Auth — utilisé pour le chat temps réel",
    )
    profile_completed = models.BooleanField(
        default=True,
        help_text="False tant que l'étudiant n'a pas renseigné son adresse Gmail.",
    )
    GENDER_CHOICES = (
        ('M', 'Masculin'),
        ('F', 'Féminin'),
    )
    gender = models.CharField(
        max_length=1,
        choices=GENDER_CHOICES,
        blank=True,
        default='',
        help_text="Sexe de l'étudiant (renseigné par le décanat).",
    )

    @property
    def s1_credits(self):
        from lms.models import CourseGrade
        grades = CourseGrade.objects.filter(
            student=self,
            course__semester=1,
            status__in=['APPROVED', 'SUBMITTED_TO_MINISTRY'],
            final_score__gte=10
        )
        return sum(g.course.effective_credits for g in grades.select_related('course', 'course__national_course'))

    @property
    def s2_credits(self):
        from lms.models import CourseGrade
        grades = CourseGrade.objects.filter(
            student=self,
            course__semester=2,
            status__in=['APPROVED', 'SUBMITTED_TO_MINISTRY'],
            final_score__gte=10
        )
        return sum(g.course.effective_credits for g in grades.select_related('course', 'course__national_course'))

    @property
    def total_credits(self):
        return self.s1_credits + self.s2_credits

    @property
    def admission_status(self):
        if self.total_credits >= 60:
            return "ADMIS"
        return "ECHOUE"

class NationalFaculty(models.Model):
    """Référentiel national des domaines / facultés (piloté par le Super Admin)."""
    code = models.CharField(max_length=40, unique=True)
    name = models.CharField(max_length=255)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['name']
        verbose_name_plural = 'national faculties'

    def __str__(self):
        return self.name


class NationalCourse(models.Model):
    """Maquette Nationale (Référentiel LMD) gérée par le Super Admin, par faculté."""
    national_faculty = models.ForeignKey(
        NationalFaculty,
        on_delete=models.CASCADE,
        related_name='courses',
        null=True,
        blank=True,
        help_text="Faculté nationale à laquelle ce cours est rattaché.",
    )
    code = models.CharField(max_length=20)  # ex: INF101
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    credits = models.PositiveIntegerField(default=1)
    semester = models.IntegerField(choices=((1, '1er Semestre'), (2, '2ème Semestre')), default=1)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['national_faculty__name', 'semester', 'code']
        constraints = [
            models.UniqueConstraint(
                fields=['national_faculty', 'code'],
                name='unique_national_course_code_per_faculty',
            ),
        ]

    def __str__(self):
        faculty = self.national_faculty.name if self.national_faculty_id else 'Général'
        return f"[{self.code}] {self.title} ({faculty})"

class AuditLog(models.Model):
    """Journal d'activité pour surveiller les actions critiques."""
    user = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    action = models.CharField(max_length=255)
    details = models.TextField(blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-timestamp']

    def __str__(self):
        return f"{self.timestamp} - {self.user} - {self.action}"

class Province(models.Model):
    """Référentiel des 26 provinces de la RDC."""
    RDC_PROVINCES = [
        ('BAS_UELE', 'Bas-Uélé'),
        ('EQUATEUR', 'Équateur'),
        ('HAUT_KATANGA', 'Haut-Katanga'),
        ('HAUT_LOMAMI', 'Haut-Lomami'),
        ('HAUT_UELE', 'Haut-Uélé'),
        ('ITURI', 'Ituri'),
        ('KASAI', 'Kasaï'),
        ('KASAI_CENTRAL', 'Kasaï-Central'),
        ('KASAI_ORIENTAL', 'Kasaï-Oriental'),
        ('KINSHASA', 'Kinshasa'),
        ('KONGO_CENTRAL', 'Kongo-Central'),
        ('KWANGO', 'Kwango'),
        ('KWILU', 'Kwilu'),
        ('LOMAMI', 'Lomami'),
        ('LUALABA', 'Lualaba'),
        ('MANIEMA', 'Maniema'),
        ('MAI_NDOMBE', 'Maï-Ndombe'),
        ('MONGALA', 'Mongala'),
        ('NORD_KIVU', 'Nord-Kivu'),
        ('NORD_UBANGI', 'Nord-Ubangi'),
        ('SANKURU', 'Sankuru'),
        ('SUD_KIVU', 'Sud-Kivu'),
        ('SUD_UBANGI', 'Sud-Ubangi'),
        ('TANGANYIKA', 'Tanganyika'),
        ('TSHOPO', 'Tshopo'),
        ('TSHUAPA', 'Tshuapa'),
    ]
    code = models.CharField(max_length=30, choices=RDC_PROVINCES, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['code']

    @property
    def name(self):
        return dict(self.RDC_PROVINCES).get(self.code, self.code)

    def __str__(self):
        return self.name


class University(models.Model):
    INSTITUTION_TYPES = (
        ('PUBLIC', 'Public'),
        ('PRIVATE', 'Privé'),
    )
    name = models.CharField(max_length=255)
    province = models.ForeignKey('Province', on_delete=models.SET_NULL, null=True, blank=True, related_name='universities')
    teacher = models.ForeignKey('User', on_delete=models.CASCADE, limit_choices_to={'role': 'TEACHER'}, related_name='universities', null=True)
    institution_type = models.CharField(max_length=10, choices=INSTITUTION_TYPES, default='PUBLIC')
    address = models.CharField(max_length=255, blank=True, default='')
    phone = models.CharField(max_length=40, blank=True, default='')
    email = models.EmailField(blank=True, default='')
    capacity = models.PositiveIntegerField(null=True, blank=True, help_text="Capacité d'accueil estimée")
    is_grading_locked = models.BooleanField(default=False, help_text="Verrouille la saisie et modification des notes pour tout l'établissement")
    s1_closed = models.BooleanField(default=False, help_text="Clôture et bloque le 1er semestre au niveau établissement")
    s2_closed = models.BooleanField(default=False, help_text="Clôture et bloque le 2ème semestre au niveau établissement")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('name', 'teacher')
        verbose_name_plural = 'universities'

    def __str__(self):
        return self.name

    @property
    def manager(self):
        return User.objects.filter(role='MANAGER', assigned_university=self, is_active=True).first()

class Faculty(models.Model):
    university = models.ForeignKey(University, on_delete=models.CASCADE, related_name='faculties')
    national_faculty = models.ForeignKey(
        'NationalFaculty',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='local_faculties',
        help_text="Correspondance avec le référentiel national de facultés.",
    )
    name = models.CharField(max_length=255)
    
    class Meta:
        unique_together = ('university', 'name')

    def __str__(self):
        return f"{self.name} ({self.university.name})"

class Promotion(models.Model):
    """Niveau académique LMD rattaché à une faculté (L1→M2)."""

    LMD_LEVELS = (
        ('L1', 'L1 (Licence 1)'),
        ('L2', 'L2 (Licence 2)'),
        ('L3', 'L3 (Licence 3)'),
        ('M1', 'M1 (Master 1)'),
        ('M2', 'M2 (Master 2)'),
    )
    LMD_CODES = tuple(code for code, _ in LMD_LEVELS)
    LMD_LABELS = dict(LMD_LEVELS)

    faculty = models.ForeignKey(Faculty, on_delete=models.CASCADE, related_name='promotions')
    name = models.CharField(max_length=10, choices=LMD_LEVELS, help_text='Niveau LMD (L1 à M2)')

    class Meta:
        unique_together = ('faculty', 'name')
        ordering = ['name']

    def __str__(self):
        return f"{self.display_label} - {self.faculty.name}"

    @property
    def display_label(self):
        return self.LMD_LABELS.get(self.name, self.name)

    @classmethod
    def lmd_ordered(cls, queryset=None):
        from django.db.models import Case, IntegerField, When

        qs = queryset if queryset is not None else cls.objects.all()
        whens = [When(name=code, then=idx) for idx, code in enumerate(cls.LMD_CODES)]
        return qs.annotate(
            _lmd_order=Case(*whens, default=99, output_field=IntegerField())
        ).order_by('_lmd_order', 'name')

    @classmethod
    def ensure_lmd_for_faculty(cls, faculty):
        """Crée les 5 niveaux LMD pour une faculté (idempotent)."""
        created = []
        for code, _label in cls.LMD_LEVELS:
            obj, was_created = cls.objects.get_or_create(faculty=faculty, name=code)
            if was_created:
                created.append(obj)
        return created

    @classmethod
    def has_full_lmd(cls, faculty):
        existing = set(cls.objects.filter(faculty=faculty, name__in=cls.LMD_CODES).values_list('name', flat=True))
        return existing == set(cls.LMD_CODES)

class ClassGroup(models.Model):
    promotion = models.ForeignKey(Promotion, on_delete=models.CASCADE, related_name='classes')
    name = models.CharField(max_length=255) # ex: Groupe A, Info Matin
    
    class Meta:
        unique_together = ('promotion', 'name')

    def __str__(self):
        return f"{self.promotion.name} {self.name}"

class Course(models.Model):
    title = models.CharField(max_length=255)
    national_course = models.ForeignKey(NationalCourse, on_delete=models.SET_NULL, null=True, blank=True, related_name='instances')
    prerequisite_quiz = models.ForeignKey('Quiz', on_delete=models.SET_NULL, null=True, blank=True, related_name='locked_courses', help_text="Quiz à réussir (50%) pour débloquer ce cours")
    university = models.ForeignKey(University, on_delete=models.CASCADE, related_name='courses', null=True)
    faculty = models.ForeignKey(Faculty, on_delete=models.CASCADE, related_name='courses', null=True)
    promotion = models.ForeignKey(Promotion, on_delete=models.CASCADE, related_name='courses', null=True)
    description = models.TextField(blank=True, default='')
    credits = models.PositiveIntegerField(default=1, help_text='Crédits ECTS du cours (définis par le Décanat).')
    teacher = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        limit_choices_to={'role': 'TEACHER'},
        related_name='courses',
        help_text='Enseignant titulaire (attribué par le Décanat).',
    )
    assigned_to_dean = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        limit_choices_to={'role': 'DEAN'},
        related_name='dean_courses',
        help_text='Décanat propriétaire du cours (créateur / responsable facultaire).',
    )
    created_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='created_courses',
        help_text='Utilisateur ayant créé le cours (Décanat).',
    )
    semester = models.IntegerField(choices=((1, '1er Semestre'), (2, '2ème Semestre')), default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    is_published = models.BooleanField(default=False)
    price = models.DecimalField(max_digits=10, decimal_places=2, default=0.0)
    is_free = models.BooleanField(default=True)
    thumbnail = models.FileField(upload_to='courses/thumbnails/', blank=True, null=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['teacher', 'title', 'promotion'],
                condition=models.Q(teacher__isnull=False),
                name='unique_teacher_title_promotion_assigned',
            ),
        ]

    def __str__(self):
        return self.title

    @property
    def effective_credits(self):
        if self.credits:
            return self.credits
        if self.national_course_id and self.national_course:
            return self.national_course.credits
        return 0

    @property
    def assignment_status(self):
        if self.teacher_id:
            return 'assigned_teacher'
        if self.assigned_to_dean_id:
            return 'assigned_dean'
        return 'draft'

class Lesson(models.Model):
    CONTENT_TYPES = (
        ('VIDEO', 'Vidéo'),
        ('PDF', 'Document PDF'),
        ('PPT', 'PowerPoint'),
        ('TEXT', 'Texte'),
    )
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='lessons')
    title = models.CharField(max_length=255)
    content_type = models.CharField(max_length=10, choices=CONTENT_TYPES)
    content_file = models.FileField(upload_to='lessons/', blank=True, null=True, validators=[validate_lesson_file])
    # PDF de prévisualisation (PPT converti) — lecture native dans l'app, sans navigateur
    preview_file = models.FileField(upload_to='lessons/previews/', blank=True, null=True)
    content_text = models.TextField(blank=True, null=True)
    order = models.PositiveIntegerField()

    class Meta:
        ordering = ['order']

    def __str__(self):
        return f"{self.course.title} - {self.title}"

    def save(self, *args, **kwargs):
        if self.content_type == 'TEXT' and self.content_text:
            import re
            # Supprimer les balises VML/Word (v:*, o:*, w:*)
            self.content_text = re.sub(r'<v:[^>]*>.*?</v:[^>]*>', '', self.content_text, flags=re.DOTALL | re.IGNORECASE)
            self.content_text = re.sub(r'<o:[^>]*>.*?</o:[^>]*>', '', self.content_text, flags=re.DOTALL | re.IGNORECASE)
            self.content_text = re.sub(r'<w:[^>]*>.*?</w:[^>]*>', '', self.content_text, flags=re.DOTALL | re.IGNORECASE)
            # Supprimer les attributs de style Word excessifs
            self.content_text = re.sub(r'class="Mso[^"]*"', '', self.content_text, flags=re.IGNORECASE)
            self.content_text = re.sub(r'style="[^"]*mso-[^"]*"', '', self.content_text, flags=re.IGNORECASE)
            # Supprimer les balises vides ou inutiles qui pourraient casser l'affichage
            self.content_text = self.content_text.strip()
        super().save(*args, **kwargs)

    @property
    def likes_count(self):
        return self.likes.count()

    @property
    def comments_count(self):
        return self.comments.count()

class Enrollment(models.Model):
    student = models.ForeignKey(User, on_delete=models.CASCADE, limit_choices_to={'role': 'STUDENT'}, related_name='enrollments')
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='enrollments')
    enrolled_at = models.DateTimeField(auto_now_add=True)
    progress = models.DecimalField(max_digits=5, decimal_places=2, default=0.0)

    class Meta:
        unique_together = ('student', 'course')

    def __str__(self):
        return f"{self.student.username} -> {self.course.title}"

class Evaluation(models.Model):
    lesson = models.ForeignKey(Lesson, on_delete=models.CASCADE, related_name='evaluations')
    question = models.TextField()
    option_a = models.CharField(max_length=255)
    option_b = models.CharField(max_length=255)
    option_c = models.CharField(max_length=255)
    option_d = models.CharField(max_length=255)
    correct_option = models.CharField(max_length=1, choices=[('A','A'), ('B','B'), ('C','C'), ('D','D')])

class Grade(models.Model):
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='grades')
    lesson = models.ForeignKey(Lesson, on_delete=models.CASCADE)
    score = models.DecimalField(max_digits=5, decimal_places=2)
    completed_at = models.DateTimeField(auto_now_add=True)

class Notification(models.Model):
    NOTIFICATION_TYPES = (
        ('course', 'Nouveau Cours'),
        ('grade', 'Note'),
        ('reply', 'Réponse'),
        ('grade', 'Note'),
        ('reminder', 'Rappel'),
        ('system', 'Système'),
    )
    title = models.CharField(max_length=255)
    message = models.TextField()
    type = models.CharField(max_length=20, choices=NOTIFICATION_TYPES, default='system')
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='notifications', blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.title

class CourseLike(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='course_likes')
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='likes')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'course')

class CourseComment(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='course_comments')
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='comments')
    parent = models.ForeignKey('self', on_delete=models.CASCADE, null=True, blank=True, related_name='replies')
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']

class CourseFavorite(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='course_favorites')
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='favorited_by')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'course')

class TeacherFollow(models.Model):
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='following')
    teacher = models.ForeignKey(User, on_delete=models.CASCADE, limit_choices_to={'role': 'TEACHER'}, related_name='followers')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('student', 'teacher')

class LessonLike(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='lesson_likes')
    lesson = models.ForeignKey(Lesson, on_delete=models.CASCADE, related_name='likes')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'lesson')

class LessonComment(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='lesson_comments')
    lesson = models.ForeignKey(Lesson, on_delete=models.CASCADE, related_name='comments')
    parent = models.ForeignKey('self', on_delete=models.CASCADE, null=True, blank=True, related_name='replies')
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']

class LessonFavorite(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='lesson_favorites')
    lesson = models.ForeignKey(Lesson, on_delete=models.CASCADE, related_name='favorited_by')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'lesson')

class LiveSession(models.Model):
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='live_sessions')
    teacher = models.ForeignKey(User, on_delete=models.CASCADE, related_name='hosted_lives')
    room_name = models.CharField(max_length=100, unique=True) # UUID based unique name
    is_active = models.BooleanField(default=True)
    started_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-started_at']

    def __str__(self):
        return f"Live: {self.course.title} by {self.teacher.username}"

class ChatRoom(models.Model):
    name = models.CharField(max_length=255, blank=True)
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='chat_rooms', null=True, blank=True)
    participants = models.ManyToManyField(User, related_name='chat_rooms')
    is_group = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        if self.is_group and self.course:
            return f"Groupe: {self.course.title}"
        return f"Chat {self.id}"

class ChatMessage(models.Model):
    room = models.ForeignKey(ChatRoom, on_delete=models.CASCADE, related_name='messages')
    sender = models.ForeignKey(User, on_delete=models.CASCADE, related_name='messages')
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    is_read = models.BooleanField(default=False)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f"{self.sender.username}: {self.content[:20]}"

class Quiz(models.Model):
    id_code = models.UUIDField(default=uuid.uuid4, editable=False, unique=True)
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='quizzes')
    lesson = models.OneToOneField('Lesson', on_delete=models.CASCADE, null=True, blank=True, related_name='module_quiz')
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    time_limit = models.PositiveIntegerField(help_text="Durée en minutes", default=30)
    created_at = models.DateTimeField(auto_now_add=True)
    is_published = models.BooleanField(default=False)
    
    QUIZ_TYPE_CHOICES = (
        ('SIMPLE', 'Exercice d\'entraînement'),
        ('EVALUATION', 'Quiz de validation (bloquant)'),
    )
    quiz_type = models.CharField(max_length=20, choices=QUIZ_TYPE_CHOICES, default='EVALUATION')
    order = models.PositiveIntegerField(default=1)

    class Meta:
        ordering = ['order', 'created_at']

    def __str__(self):
        return f"Quiz: {self.title} ({self.course.title})"

class QuizQuestion(models.Model):
    quiz = models.ForeignKey(Quiz, on_delete=models.CASCADE, related_name='questions')
    text = models.TextField()
    points = models.PositiveIntegerField(default=1)

    def __str__(self):
        return self.text[:50]

class QuizChoice(models.Model):
    question = models.ForeignKey(QuizQuestion, on_delete=models.CASCADE, related_name='choices')
    text = models.CharField(max_length=255)
    is_correct = models.BooleanField(default=False)

    def __str__(self):
        return self.text

class QuizAttempt(models.Model):
    SESSION_CHOICES = (
        ('1ere', '1ère Session'),
        ('2eme', '2ème Session (Rattrapage)'),
    )
    quiz = models.ForeignKey(Quiz, on_delete=models.CASCADE, related_name='attempts')
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='quiz_attempts')
    score = models.DecimalField(max_digits=5, decimal_places=2, default=0.0)
    session = models.CharField(max_length=10, choices=SESSION_CHOICES, default='1ere')
    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    @property
    def score_percentage(self):
        total_points = sum(q.points for q in self.quiz.questions.all())
        if total_points == 0: return 0
        return (self.score / total_points) * 100

    @property
    def is_passed(self):
        return self.score_percentage >= 50

class ExternalResource(models.Model):
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    url = models.URLField()
    thumbnail_url = models.URLField(blank=True, null=True)
    thumbnail = models.FileField(upload_to='external_resources/thumbnails/', blank=True, null=True)
    category = models.CharField(max_length=100, blank=True, default="Formation en ligne")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.title

class CourseGrade(models.Model):
    STATUS_CHOICES = (
        ('DRAFT', 'Brouillon Enseignant'),
        ('SUBMITTED_TO_DEAN', 'Soumis au Décanat'),
        ('SUBMITTED_TO_MANAGER', 'Soumis à l\'Admin (Université) (historique)'),
        ('VALIDATED_BY_DEAN', 'Validé par le Décanat'),
        ('APPROVED', 'Approuvé / Consolidé'),
        ('SUBMITTED_TO_MINISTRY', 'Soumis au Ministère (Verrouillé)'),
    )
    student = models.ForeignKey(User, on_delete=models.CASCADE, limit_choices_to={'role': 'STUDENT'}, related_name='course_grades')
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='course_grades')
    
    quiz_average = models.DecimalField(max_digits=5, decimal_places=2, default=0.0)
    interrogation_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    exam_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    final_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    
    status = models.CharField(max_length=30, choices=STATUS_CHOICES, default='DRAFT')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('student', 'course')

    def __str__(self):
        return f"{self.student.username} - {self.course.title} ({self.status})"

class StudentAudit(models.Model):
    """
    Système de cotation direct type "Excel" pour l'enseignant.
    Permet à l'enseignant de saisir directement les cotes de TP, Interro et Examen pour ses étudiants.
    """
    STATUS_CHOICES = (
        ('DRAFT', 'Brouillon Enseignant'),
        ('SUBMITTED_TO_DEAN', 'Soumis au Décanat'),
        ('SUBMITTED_TO_MANAGER', 'Soumis à l\'Admin (Université) (historique)'),
        ('VALIDATED_BY_DEAN', 'Validé par le Décanat'),
    )
    student = models.ForeignKey(User, on_delete=models.CASCADE, limit_choices_to={'role': 'STUDENT'}, related_name='audits')
    teacher = models.ForeignKey(User, on_delete=models.CASCADE, limit_choices_to={'role': 'TEACHER'}, related_name='given_audits')
    course = models.ForeignKey('Course', on_delete=models.CASCADE, null=True, blank=True, related_name='audits')
    full_name = models.CharField(max_length=255, blank=True, null=True, help_text="Nom complet défini par l'enseignant")
    tp = models.DecimalField(max_digits=5, decimal_places=2, default=0.0)
    interro = models.DecimalField(max_digits=5, decimal_places=2, default=0.0)
    examen = models.DecimalField(max_digits=5, decimal_places=2, default=0.0)
    status = models.CharField(max_length=30, choices=STATUS_CHOICES, default='DRAFT')
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        # Assurer qu'un étudiant n'a qu'un seul audit par enseignant et par cours
        unique_together = ('student', 'teacher', 'course')

    @property
    def total(self):
        return float(self.tp) + float(self.interro) + float(self.examen)

    @property
    def course_credits(self):
        """Nombre de crédits du cours (définis par l'Admin (Université))."""
        if self.course:
            return self.course.effective_credits
        return 0

    @property
    def is_passed(self):
        """Réussite LMD : cote ≥ 10/20."""
        return self.total >= 10

    @property
    def credits_earned(self):
        """Crédits obtenus si cote ≥ 10/20, sinon 0."""
        return self.course_credits if self.is_passed else 0

    def __str__(self):
        return f"Audit: {self.student.username} par {self.teacher.username}"



def tp_upload_path(instance, filename):
    """Chemin de téléversement pour les soumissions de TP"""
    return f"tp_submissions/{instance.assignment.course_id}/{instance.student_id}/{filename}"


class Assignment(models.Model):
    """Travail Pratique (TP) créé par un enseignant pour un cours."""
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='assignments')
    teacher = models.ForeignKey(User, on_delete=models.CASCADE, limit_choices_to={'role': 'TEACHER'}, related_name='assignments_given')
    title = models.CharField(max_length=255)
    description = models.TextField()
    due_date = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"[TP] {self.title} — {self.course.title}"


def submission_upload_path(instance, filename):
    return f"tp_submissions/course_{instance.assignment.course_id}/assignment_{instance.assignment_id}/student_{instance.student_id}/{filename}"


class AssignmentSubmission(models.Model):
    """Soumission d'un TP par un étudiant, avec correction de l'enseignant."""
    assignment = models.ForeignKey(Assignment, on_delete=models.CASCADE, related_name='submissions')
    student = models.ForeignKey(User, on_delete=models.CASCADE, limit_choices_to={'role': 'STUDENT'}, related_name='tp_submissions')
    file = models.FileField(upload_to=submission_upload_path, null=True, blank=True)
    submitted_at = models.DateTimeField(auto_now_add=True)
    # Résultat de la correction
    grade = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, help_text="Note sur 20")
    grade_comment = models.TextField(blank=True, null=True)
    graded_at = models.DateTimeField(null=True, blank=True)
    is_graded = models.BooleanField(default=False)

    class Meta:
        unique_together = ('assignment', 'student')
        ordering = ['-submitted_at']

    def __str__(self):
        status = f"Noté {self.grade}/20" if self.is_graded else "En attente"
        return f"{self.student.username} → {self.assignment.title} ({status})"
