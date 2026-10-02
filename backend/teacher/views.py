import json
from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required, user_passes_test
from django.http import JsonResponse
from django.contrib.auth import login, logout, authenticate
from django.contrib import messages
from django.conf import settings
from lms.models import Course, Lesson, User, LiveSession, University, Faculty, Promotion, ClassGroup, NationalCourse, AuditLog
from django.db.models import Q


# ---------------------------------------------------------------------------
# Permission helpers
# ---------------------------------------------------------------------------

def is_teacher(user):
    return user.is_authenticated and user.role == 'TEACHER' and user.is_active

def is_super_admin(user):
    return user.is_authenticated and (user.is_superuser or user.role == 'SUPER_ADMIN')

def is_manager(user):
    return user.is_authenticated and user.role == 'MANAGER'

def is_dean(user):
    return user.is_authenticated and user.role == 'DEAN'

def is_admin(user):
    # Rôle générique pour tout ce qui est administratif global
    return is_super_admin(user) or is_manager(user) or is_dean(user)
    
def is_manager_or_dean(user):
    return user.is_authenticated and user.role in ['MANAGER', 'DEAN']

super_admin_required = user_passes_test(is_super_admin, login_url='/login/')
manager_required = user_passes_test(is_manager, login_url='/login/')
dean_required = user_passes_test(is_dean, login_url='/login/')
admin_required = user_passes_test(is_admin, login_url='/login/')
manager_or_dean_required = user_passes_test(is_manager_or_dean, login_url='/login/')
admin_required = user_passes_test(is_admin, login_url='/login/')
teacher_required = user_passes_test(is_teacher, login_url='/login/')

# Cotes verrouillées côté enseignant (déjà transmises / validées)
LOCKED_AUDIT_STATUSES = frozenset({
    'SUBMITTED_TO_DEAN',
    'SUBMITTED_TO_MANAGER',
    'VALIDATED_BY_DEAN',
})
# Cotes visibles par le Décanat pour délibération
DEAN_VISIBLE_AUDIT_STATUSES = frozenset({
    'SUBMITTED_TO_DEAN',
    'SUBMITTED_TO_MANAGER',
    'VALIDATED_BY_DEAN',
})
YEAR_CREDITS_REFERENCE = 60
SEMESTER_CREDITS_REFERENCE = 30


def _get_teacher_promotions_queryset(teacher):
    """Promotions visibles = uniquement celles des cours réellement affectés à l'enseignant.
    Évite le mélange avec d'autres enseignants de la même faculté via assigned_promotions.
    """
    course_promotion_ids = Course.objects.filter(
        teacher=teacher,
        promotion__isnull=False,
    ).values_list('promotion_id', flat=True).distinct()

    return Promotion.lmd_ordered(
        Promotion.objects.filter(id__in=course_promotion_ids).select_related(
            'faculty', 'faculty__university'
        )
    )


def _students_for_teacher(teacher, selected_promotion=None):
    """Étudiants des promotions couvertes par les cours de cet enseignant."""
    from lms.visibility import affiliated_students_for_course

    courses = _teacher_course_queryset(teacher, selected_promotion)
    student_ids = set()
    for course in courses:
        if not course.promotion_id:
            continue
        student_ids.update(
            affiliated_students_for_course(course).values_list('id', flat=True)
        )
    return User.objects.filter(id__in=student_ids, role='STUDENT')


def _student_module_quizzes_status(student, courses):
    """
    Progression basée sur les quiz liés aux modules (leçons) de l'enseignant.
    « Terminé » = l'étudiant a passé tous les quiz publiés rattachés à un module.
    """
    from lms.models import Quiz, QuizAttempt

    quiz_ids = list(
        Quiz.objects.filter(
            course__in=courses,
            lesson__isnull=False,
            is_published=True,
        ).values_list('id', flat=True)
    )
    total = len(quiz_ids)
    if total == 0:
        return {
            'has_quizzes': False,
            'total': 0,
            'done': 0,
            'is_complete': False,
            'label': '—',
        }

    done = (
        QuizAttempt.objects.filter(student=student, quiz_id__in=quiz_ids)
        .values('quiz_id')
        .distinct()
        .count()
    )
    is_complete = done >= total
    return {
        'has_quizzes': True,
        'total': total,
        'done': done,
        'is_complete': is_complete,
        'label': 'Terminé' if is_complete else f'{done}/{total}',
    }


def _course_module_quizzes_detail(student, course):
    """Détail par module : chaque leçon avec son quiz et le statut de l'étudiant."""
    from lms.models import Lesson, QuizAttempt

    lessons = (
        Lesson.objects.filter(course=course)
        .select_related('module_quiz')
        .order_by('order', 'id')
    )
    rows = []
    for lesson in lessons:
        quiz = getattr(lesson, 'module_quiz', None)
        if quiz is None or not quiz.is_published:
            rows.append({
                'lesson': lesson,
                'quiz': None,
                'attempt': None,
                'is_complete': False,
                'status_label': 'Sans quiz',
            })
            continue
        attempt = (
            QuizAttempt.objects.filter(student=student, quiz=quiz)
            .order_by('-completed_at', '-started_at')
            .first()
        )
        is_complete = attempt is not None
        rows.append({
            'lesson': lesson,
            'quiz': quiz,
            'attempt': attempt,
            'is_complete': is_complete,
            'status_label': 'Terminé' if is_complete else 'En cours',
        })
    return rows


def _get_selected_teacher_promotion(request, teacher):
    """Résout la promotion active (GET/POST, sinon profil, sinon session, sinon première LMD)."""
    promotions = _get_teacher_promotions_queryset(teacher)
    session_key = f'teacher_selected_promotion_{teacher.id}'
    selected_id = request.GET.get('promotion') or request.POST.get('promotion_id')
    selected = None

    if selected_id:
        selected = promotions.filter(id=selected_id).first()
        if selected is not None:
            request.session[session_key] = selected.id
            # Garder le profil aligné avec le filtre UI (ex. après affectation décanat)
            if teacher.assigned_promotion_id != selected.id:
                teacher.assigned_promotion = selected
                teacher.save(update_fields=['assigned_promotion'])

    if selected is None and teacher.assigned_promotion_id:
        selected = promotions.filter(id=teacher.assigned_promotion_id).first()
        if selected is not None:
            request.session[session_key] = selected.id

    if selected is None:
        session_id = request.session.get(session_key)
        if session_id:
            selected = promotions.filter(id=session_id).first()

    if selected is None:
        selected = promotions.first()
        if selected is not None:
            request.session[session_key] = selected.id

    return promotions, selected


def _teacher_course_queryset(teacher, selected_promotion=None, published_only=None):
    """Tous les cours réellement affectés à l'enseignant (tous semestres)."""
    qs = Course.objects.filter(teacher=teacher).select_related(
        'national_course', 'promotion', 'promotion__faculty', 'promotion__faculty__university'
    )
    if selected_promotion:
        qs = qs.filter(promotion=selected_promotion)
    if published_only is True:
        qs = qs.filter(is_published=True)
    elif published_only is False:
        qs = qs.filter(is_published=False)
    return qs


# ---------------------------------------------------------------------------
# Auth views
# ---------------------------------------------------------------------------

def _redirect_portal_home(user):
    """Redirige un utilisateur déjà connecté vers son tableau de bord."""
    if is_super_admin(user):
        return redirect('super_admin:dashboard')
    if getattr(user, 'role', None) == 'PROVINCIAL_ADMIN':
        return redirect('super_admin:territorial_dashboard')
    if is_manager(user):
        return redirect('manager_dashboard')
    if is_dean(user):
        return redirect('dean_dashboard')
    if is_teacher(user):
        return redirect('teacher_dashboard')
    return None


def portal_index(request):
    """Page d'accueil du portail établissement (Manager, Décanat, Enseignant)."""
    if request.user.is_authenticated:
        dest = _redirect_portal_home(request.user)
        if dest is not None:
            return dest
        logout(request)
    return render(request, 'teacher/index.html')


def login_view(request):
    """Ancienne URL /teacher/login/ → connexion unique."""
    next_url = request.GET.get('next', '')
    if next_url:
        return redirect(f'/login/?next={next_url}')
    return redirect('unified_login')


def logout_view(request):
    logout(request)
    return redirect('unified_login')


@login_required(login_url='/login/')
def change_password(request):
    """Changement de mot de passe — Manager, Décanat, Enseignant."""
    from django.contrib.auth import update_session_auth_hash

    user = request.user
    if user.role not in ('TEACHER', 'DEAN', 'MANAGER') and not user.is_superuser:
        messages.error(request, "Accès non autorisé.")
        return redirect('unified_login')

    error = None
    if request.method == 'POST':
        current = request.POST.get('current_password', '')
        new_password = request.POST.get('new_password', '')
        confirm = request.POST.get('confirm_password', '')

        if not user.check_password(current):
            error = "Mot de passe actuel incorrect."
        elif len(new_password) < 8:
            error = "Le nouveau mot de passe doit contenir au moins 8 caractères."
        elif new_password != confirm:
            error = "La confirmation ne correspond pas au nouveau mot de passe."
        elif new_password == current:
            error = "Le nouveau mot de passe doit être différent de l'actuel."
        else:
            user.set_password(new_password)
            user.save(update_fields=['password'])
            update_session_auth_hash(request, user)
            AuditLog.objects.create(
                user=user,
                action='CHANGE_PASSWORD',
                details=f"Mot de passe modifié ({user.role}).",
                ip_address=request.META.get('REMOTE_ADDR'),
            )
            messages.success(request, "Mot de passe mis à jour avec succès.")
            if user.role == 'MANAGER':
                return redirect('manager_dashboard')
            if user.role == 'DEAN':
                return redirect('dean_dashboard')
            return redirect('teacher_dashboard')

    return render(request, 'teacher/change_password.html', {'error': error})


# ---------------------------------------------------------------------------
# Admin views — Gestion des enseignants
# ---------------------------------------------------------------------------

# (super_admin_dashboard moved to super_admin app)


def _dean_student_filters_from_request(request):
    """Filtres GET pour l'annuaire étudiant du décanat."""
    return {
        'promotion_id': (request.GET.get('promotion') or '').strip(),
        'q': (request.GET.get('q') or '').strip(),
    }


def _query_dean_faculty_students(faculty_id, filters=None):
    """Étudiants rattachés à la faculté, avec filtres optionnels."""
    qs = User.objects.filter(
        role='STUDENT',
    ).filter(
        Q(class_group__promotion__faculty_id=faculty_id)
        | Q(assigned_faculty_id=faculty_id, class_group__isnull=True)
    ).select_related('class_group__promotion').order_by(
        'class_group__promotion__name', 'matricule', 'last_name', 'username'
    )

    if not filters:
        return qs.distinct()

    promotion_id = filters.get('promotion_id') or ''
    if promotion_id.isdigit():
        qs = qs.filter(class_group__promotion_id=int(promotion_id))

    q = (filters.get('q') or '').strip()
    if q:
        qs = qs.filter(
            Q(matricule__icontains=q)
            | Q(username__icontains=q)
            | Q(email__icontains=q)
            | Q(first_name__icontains=q)
            | Q(last_name__icontains=q)
        )

    return qs.distinct()


@login_required(login_url='/login/')
@dean_required
def dean_dashboard(request):
    """Dashboard opérationnel de proximité (Décanat)."""
    from django.db.models import Avg
    from lms.models import QuizAttempt

    # Un manager ne voit que les enseignants de SON université/faculté
    teacher_qs = User.objects.filter(role='TEACHER')
    
    if not request.user.is_superuser:
        if request.user.assigned_university:
            teacher_qs = teacher_qs.filter(assigned_university=request.user.assigned_university)
        if request.user.assigned_faculty:
            teacher_qs = teacher_qs.filter(assigned_faculty=request.user.assigned_faculty)

    teachers = teacher_qs.select_related(
        'assigned_university', 'assigned_faculty', 'assigned_promotion'
    ).prefetch_related('assigned_promotions').order_by('-date_joined')

    for teacher in teachers:
        avg_score = QuizAttempt.objects.filter(
            quiz__course__teacher=teacher
        ).aggregate(Avg('score'))['score__avg'] or 0
        teacher.success_rate = round(float(avg_score), 1)
        teacher.assigned_courses = list(
            Course.objects.filter(teacher=teacher)
            .select_related('national_course', 'promotion')
            .order_by('semester', 'promotion__name', 'title')
        )
        teacher.promotion_scope = list(_get_teacher_promotions_queryset(teacher))

    # Cours de la faculté sans enseignant (créés par le Décanat, à affecter)
    pending_courses = Course.objects.filter(
        faculty_id=request.user.assigned_faculty_id,
        teacher__isnull=True,
    ).filter(
        Q(assigned_to_dean=request.user) | Q(assigned_to_dean__isnull=True)
    ).select_related('promotion', 'faculty').order_by('semester', 'title')

    faculty_courses = Course.objects.filter(
        faculty_id=request.user.assigned_faculty_id,
    ).select_related('promotion', 'teacher', 'created_by').order_by('-created_at')

    # Effectifs étudiants par promotion LMD
    faculty_id = request.user.assigned_faculty_id
    promotion_student_rows = []
    if faculty_id:
        for promo in Promotion.lmd_ordered(
            Promotion.objects.filter(faculty_id=faculty_id)
        ):
            total = _query_dean_faculty_students(
                faculty_id,
                {'promotion_id': str(promo.id)},
            ).count()
            promotion_student_rows.append({
                'id': promo.id,
                'name': promo.display_label[:28],
                'full_name': promo.display_label,
                'students': total,
            })
        promotion_student_rows.sort(key=lambda r: -r['students'])

    context = {
        'teachers': teachers,
        'active_teachers_count': teachers.filter(is_active=True).count(),
        'pending_courses': pending_courses,
        'faculty_courses': faculty_courses,
        'promotion_student_rows': promotion_student_rows,
    }
    return render(request, 'teacher/manager_dashboard.html', context)


@login_required(login_url='/login/')
@dean_required
def dean_courses(request):
    """Liste des cours de la faculté (Décanat)."""
    faculty_id = request.user.assigned_faculty_id
    faculty_courses = Course.objects.filter(
        faculty_id=faculty_id,
    ).select_related('promotion', 'teacher', 'created_by').order_by('-created_at') if faculty_id else Course.objects.none()

    context = {
        'faculty_courses': faculty_courses,
        'faculty_promotions': Promotion.lmd_ordered(
            Promotion.objects.filter(faculty_id=faculty_id).select_related('faculty')
        ) if faculty_id else Promotion.objects.none(),
    }
    return render(request, 'teacher/dean_courses.html', context)


@login_required(login_url='/login/')
@dean_required
def dean_teachers(request):
    """Registre des enseignants de la faculté (Décanat)."""
    from django.db.models import Avg
    from lms.models import QuizAttempt

    teacher_qs = User.objects.filter(role='TEACHER')
    if not request.user.is_superuser:
        if request.user.assigned_university:
            teacher_qs = teacher_qs.filter(assigned_university=request.user.assigned_university)
        if request.user.assigned_faculty:
            teacher_qs = teacher_qs.filter(assigned_faculty=request.user.assigned_faculty)

    teachers = teacher_qs.select_related(
        'assigned_university', 'assigned_faculty', 'assigned_promotion'
    ).prefetch_related('assigned_promotions').order_by('-date_joined')

    for teacher in teachers:
        avg_score = QuizAttempt.objects.filter(
            quiz__course__teacher=teacher
        ).aggregate(Avg('score'))['score__avg'] or 0
        teacher.success_rate = round(float(avg_score), 1)
        teacher.assigned_courses = list(
            Course.objects.filter(teacher=teacher)
            .select_related('national_course', 'promotion')
            .order_by('semester', 'promotion__name', 'title')
        )

    pending_courses = Course.objects.filter(
        faculty_id=request.user.assigned_faculty_id,
        teacher__isnull=True,
    ).filter(
        Q(assigned_to_dean=request.user) | Q(assigned_to_dean__isnull=True)
    ).select_related('promotion', 'faculty').order_by('semester', 'title')

    return render(request, 'teacher/dean_teachers.html', {
        'teachers': teachers,
        'pending_courses': pending_courses,
    })


@login_required(login_url='/login/')
@dean_required
def dean_students(request):
    """Comptes étudiants de la faculté (Décanat)."""
    faculty_id = request.user.assigned_faculty_id
    student_filters = _dean_student_filters_from_request(request)
    all_faculty_students = (
        _query_dean_faculty_students(faculty_id)
        if faculty_id else User.objects.none()
    )
    faculty_students = (
        _query_dean_faculty_students(faculty_id, student_filters)
        if faculty_id else User.objects.none()
    )
    return render(request, 'teacher/dean_students.html', {
        'faculty_promotions': Promotion.lmd_ordered(
            Promotion.objects.filter(faculty_id=faculty_id).select_related('faculty')
        ) if faculty_id else Promotion.objects.none(),
        'faculty_students': faculty_students,
        'students_total_count': all_faculty_students.count(),
        'students_filtered_count': faculty_students.count(),
        'student_filters': student_filters,
        'default_student_password': getattr(settings, 'STUDENT_DEFAULT_PASSWORD', 'uwb2026'),
    })


from django.views.decorators.csrf import csrf_exempt

@login_required(login_url='/login/')
@dean_required
def generate_academic_report(request):
    """
    Décanat → Manager : rapport annuel consolidé uniquement.
    Calcule S1/30 + S2/30 = total/60 (Réussite si 60/60, sinon Échec).
    """
    if request.method != 'POST':
        return redirect('dean_dashboard')

    from super_admin.models import FacultyReport, SemesterResultReport, SemesterResultLine
    from lms.models import StudentAudit, Course, CourseGrade, Notification, AuditLog

    university = request.user.assigned_university
    faculty = request.user.assigned_faculty
    if not university or not faculty:
        messages.error(request, "Profil Décanat invalide (université / faculté manquante).")
        return redirect('dean_dashboard')

    promotion_id = request.POST.get('promotion_id')
    if not promotion_id:
        messages.error(request, "Veuillez sélectionner une promotion.")
        return redirect('manager_grades_approval')

    promotion = get_object_or_404(Promotion, id=promotion_id, faculty=faculty)

    s1_courses = list(
        Course.objects.filter(promotion=promotion, semester=1).select_related('national_course')
    )
    s2_courses = list(
        Course.objects.filter(promotion=promotion, semester=2).select_related('national_course')
    )
    all_courses = s1_courses + s2_courses
    course_ids = [c.id for c in all_courses]

    if not s1_courses and not s2_courses:
        messages.error(request, "Aucun cours trouvé pour cette promotion.")
        return redirect('manager_grades_approval')

    students = User.objects.filter(
        role='STUDENT',
        class_group__promotion=promotion,
    ).order_by('last_name', 'first_name', 'username')

    audits = StudentAudit.objects.filter(
        course_id__in=course_ids,
        status__in=DEAN_VISIBLE_AUDIT_STATUSES,
    ).select_related('student', 'course')

    audit_by_student = {}
    for a in audits:
        audit_by_student.setdefault(a.student_id, {})[a.course_id] = a

    def credits_for(student_audits, course_list):
        total = 0
        for c in course_list:
            audit = student_audits.get(c.id)
            if audit and audit.total >= 10:
                total += c.effective_credits
        return total

    sem_ref = SEMESTER_CREDITS_REFERENCE
    year_ref = YEAR_CREDITS_REFERENCE
    promo_label = promotion.display_label
    faculty_label = faculty.name
    title = f"Rapport annuel consolidé — {faculty_label} — {promo_label}"

    report = SemesterResultReport.objects.create(
        university=university,
        faculty=faculty,
        promotion=promotion,
        semester=None,  # rapport annuel
        title=title,
        credits_reference=year_ref,
        semester_credits_reference=sem_ref,
        submitted_by=request.user,
    )

    passed = 0
    failed = 0
    lines = []
    for student in students:
        student_audits = audit_by_student.get(student.id, {})
        s1_earned = credits_for(student_audits, s1_courses)
        s2_earned = credits_for(student_audits, s2_courses)
        earned = s1_earned + s2_earned

        result = 'REUSSITE' if earned >= year_ref else 'ECHEC'
        if result == 'REUSSITE':
            passed += 1
        else:
            failed += 1

        full_name = student.get_full_name() or student.username

        lines.append(SemesterResultLine(
            report=report,
            student=student,
            full_name=full_name,
            promotion_label=promo_label,
            faculty_label=faculty_label,
            s1_credits_earned=s1_earned,
            s1_credits_total=sem_ref,
            s2_credits_earned=s2_earned,
            s2_credits_total=sem_ref,
            credits_earned=earned,
            credits_total=year_ref,
            result=result,
        ))

    SemesterResultLine.objects.bulk_create(lines)
    report.total_students = len(lines)
    report.passed_students = passed
    report.failed_students = failed
    report.save(update_fields=['total_students', 'passed_students', 'failed_students'])

    # Valider toutes les cotes S1+S2 soumises pour cette promotion
    StudentAudit.objects.filter(
        course_id__in=course_ids,
        status__in=('SUBMITTED_TO_DEAN', 'SUBMITTED_TO_MANAGER'),
    ).update(status='VALIDATED_BY_DEAN')
    CourseGrade.objects.filter(
        course_id__in=course_ids,
        status__in=('SUBMITTED_TO_DEAN', 'SUBMITTED_TO_MANAGER'),
    ).update(status='VALIDATED_BY_DEAN')

    FacultyReport.objects.create(
        title=title,
        university=university,
        faculty=faculty,
        total_students=report.total_students,
        passed_students=passed,
        failed_students=failed,
        submitted_by=request.user,
    )

    notif_msg = (
        f"Le Décanat de {faculty_label} a transmis le rapport annuel consolidé "
        f"« {title} » — {passed} réussite(s), {failed} échec(s) "
        f"(S1/30 + S2/30 = total/{year_ref})."
    )
    for manager in User.objects.filter(
        role='MANAGER',
        assigned_university=university,
        is_active=True,
    ):
        Notification.objects.create(
            user=manager,
            title="Rapport annuel reçu du Décanat",
            message=notif_msg,
            type='grade',
        )

    AuditLog.objects.create(
        user=request.user,
        action="SUBMIT_ANNUAL_REPORT_TO_MANAGER",
        details=(
            f"{title} — {report.total_students} étudiant(s), "
            f"{passed} réussite(s), {failed} échec(s)."
        ),
        ip_address=request.META.get('REMOTE_ADDR'),
    )
    messages.success(
        request,
        f"Rapport annuel transmis à l'Admin (Université) : {passed} réussite(s), {failed} échec(s) "
        f"sur {report.total_students} étudiant(s) (seuil {year_ref}/60 crédits).",
    )
    return redirect('manager_grades_approval')


# ---------------------------------------------------------------------------
# NOUVELLES VUES MANAGER (Université)
# ---------------------------------------------------------------------------

@login_required(login_url='/login/')
@manager_required
def manager_dashboard(request):
    """Dashboard Université : Décanats, consultation des cours et rapports."""
    from lms.models import User, Faculty
    from super_admin.models import FacultyReport

    university = request.user.assigned_university
    if not university:
        from django.contrib import messages
        messages.error(request, "Erreur : Aucune université assignée à cet admin (université).")
        return redirect('teacher_login')

    deans = User.objects.filter(role='DEAN', assigned_university=university).select_related('assigned_faculty')
    faculties = Faculty.objects.filter(university=university).prefetch_related('promotions')
    from super_admin.models import SemesterResultReport
    faculty_reports = FacultyReport.objects.filter(university=university).order_by('-submitted_at')
    pending_faculty_reports = faculty_reports.filter(is_validated=False)
    semester_reports = SemesterResultReport.objects.filter(university=university).select_related(
        'faculty', 'promotion'
    ).order_by('-submitted_at')[:20]
    courses = (
        Course.objects.filter(university=university)
        .select_related('faculty', 'promotion', 'assigned_to_dean', 'teacher', 'created_by')
        .order_by('-created_at')[:50]
    )

    promotions_by_faculty = {}
    for faculty in faculties:
        promotions_by_faculty[str(faculty.id)] = [
            {'id': p.id, 'label': p.display_label}
            for p in Promotion.lmd_ordered(faculty.promotions.all())
        ]

    from super_admin.models import UniversityReport
    latest_uni_report = (
        UniversityReport.objects.filter(university=university).order_by('-submitted_at').first()
    )

    # Comparaison taux de réussite par faculté (dernier rapport facultaire)
    faculty_success_rows = []
    latest_by_faculty = {}
    for report in FacultyReport.objects.filter(university=university).select_related('faculty').order_by('-submitted_at'):
        fid = report.faculty_id
        if fid not in latest_by_faculty:
            latest_by_faculty[fid] = report

    for faculty in faculties:
        report = latest_by_faculty.get(faculty.id)
        if report and report.total_students > 0:
            success_rate = round((report.passed_students / report.total_students) * 100, 1)
            failure_rate = round(100 - success_rate, 1)
        else:
            success_rate = None
            failure_rate = None
        short_name = faculty.name
        for prefix in ("Faculté d'", "Faculté de ", "Faculté des ", "Faculte d'", "Faculte de "):
            if short_name.lower().startswith(prefix.lower()):
                short_name = short_name[len(prefix):]
                break
        faculty_success_rows.append({
            'id': faculty.id,
            'name': short_name[:28],
            'full_name': faculty.name,
            'success_rate': success_rate,
            'failure_rate': failure_rate,
            'passed': report.passed_students if report else 0,
            'total': report.total_students if report else 0,
            'has_report': report is not None,
        })

    faculty_success_rows.sort(
        key=lambda r: (r['success_rate'] is None, -(r['success_rate'] or 0))
    )

    context = {
        'deans': deans,
        'faculties': faculties,
        'faculty_reports': faculty_reports[:15],
        'pending_faculty_reports_count': pending_faculty_reports.count(),
        'semester_reports': semester_reports,
        'university': university,
        'courses': courses,
        'promotions_by_faculty_json': json.dumps(promotions_by_faculty),
        'lmd_levels': Promotion.LMD_LEVELS,
        'latest_uni_report': latest_uni_report,
        'faculty_success_rows': faculty_success_rows,
    }
    return render(request, 'teacher/manager_university_dashboard.html', context)

@login_required(login_url='/login/')
@manager_required
def manager_create_dean(request):
    """Créer un compte Décanat pour une Faculté de l'Université du Manager."""
    from django.contrib import messages
    from lms.models import Faculty

    university = request.user.assigned_university
    if not university:
        messages.error(request, "Erreur : Aucune université assignée à votre profil.")
        return redirect('manager_dashboard')

    if request.method == 'POST':
        first_name  = request.POST.get('first_name', '').strip()
        last_name   = request.POST.get('last_name', '').strip()
        email       = request.POST.get('email', '').strip()
        username    = request.POST.get('username', '').strip()
        password    = request.POST.get('password', '').strip()
        faculty_id  = request.POST.get('faculty_id')

        if not all([first_name, last_name, email, username, password, faculty_id]):
            messages.error(request, "Tous les champs sont obligatoires.")
            return redirect('manager_dashboard')

        if User.objects.filter(username=username).exists():
            messages.error(request, f"Le nom d'utilisateur '{username}' est déjà utilisé.")
            return redirect('manager_dashboard')

        if User.objects.filter(email=email).exists():
            messages.error(request, f"L'adresse e-mail '{email}' est déjà utilisée.")
            return redirect('manager_dashboard')

        faculty = Faculty.objects.filter(id=faculty_id, university=university).first()
        if not faculty:
            messages.error(request, "Faculté invalide ou non rattachée à votre université.")
            return redirect('manager_dashboard')

        dean = User.objects.create_user(
            username=username,
            email=email,
            password=password,
            first_name=first_name,
            last_name=last_name,
            role='DEAN',
            assigned_university=university,
            assigned_faculty=faculty,
        )
        messages.success(request, f"Le Décanat '{first_name} {last_name}' pour la Faculté «\u202f{faculty.name}\u202f» a été créé avec succès.")
        return redirect('manager_dashboard')

    return redirect('manager_dashboard')


@login_required(login_url='/login/')
@manager_required
def manager_delete_dean(request, pk):
    """Le Manager supprime un compte Décanat de son université."""
    if request.method != 'POST':
        return redirect('manager_dashboard')

    university = request.user.assigned_university
    if not university:
        messages.error(request, "Aucune université assignée à votre profil.")
        return redirect('manager_dashboard')

    dean = get_object_or_404(
        User,
        pk=pk,
        role='DEAN',
        assigned_university=university,
    )
    label = dean.get_full_name() or dean.username

    # Libérer les cours encore adressés à ce décanat
    Course.objects.filter(assigned_to_dean=dean).update(assigned_to_dean=None)

    dean.delete()
    messages.success(request, f"Le Décanat « {label} » a été supprimé.")
    return redirect('manager_dashboard')


@login_required(login_url='/login/')
@manager_required
def manager_create_course(request):
    """Obsolète : la création de cours est désormais réservée au Décanat."""
    messages.error(
        request,
        "La création de cours est maintenant assurée par le Décanat de chaque faculté.",
    )
    return redirect('manager_dashboard')


@login_required(login_url='/login/')
@manager_required
def manager_assign_course_to_dean(request):
    """Obsolète : le Décanat crée directement ses cours."""
    messages.error(
        request,
        "L'attribution Admin (Université) → Décanat n'est plus nécessaire : le Décanat crée les cours de sa faculté.",
    )
    return redirect('manager_dashboard')


@login_required(login_url='/login/')
@dean_required
def dean_create_course(request):
    """Le Décanat crée un cours pour une promotion LMD de sa faculté."""
    university = request.user.assigned_university
    faculty = request.user.assigned_faculty
    if not university or not faculty:
        messages.error(request, "Profil Décanat invalide (université / faculté manquante).")
        return redirect('dean_courses')

    if request.method != 'POST':
        return redirect('dean_courses')

    title = request.POST.get('title', '').strip()
    promotion_id = request.POST.get('promotion_id')
    semester = request.POST.get('semester')
    credits = request.POST.get('credits', '1')
    description = request.POST.get('description', '').strip()

    if not all([title, promotion_id, semester]):
        messages.error(request, "Titre, promotion et semestre sont obligatoires.")
        return redirect('dean_courses')

    promotion = Promotion.objects.filter(id=promotion_id, faculty=faculty).first()
    if not promotion:
        messages.error(request, "Promotion invalide pour votre faculté. Activez d'abord le cycle LMD.")
        return redirect('dean_courses')

    try:
        semester_val = int(semester)
        credits_val = int(credits)
    except (TypeError, ValueError):
        messages.error(request, "Semestre ou crédits invalides.")
        return redirect('dean_courses')

    if semester_val not in (1, 2) or credits_val < 1:
        messages.error(request, "Semestre (1 ou 2) et crédits (≥ 1) sont requis.")
        return redirect('dean_courses')

    course = Course.objects.create(
        title=title,
        description=description or f"Cours de {title}.",
        university=university,
        faculty=faculty,
        promotion=promotion,
        semester=semester_val,
        credits=credits_val,
        created_by=request.user,
        assigned_to_dean=request.user,
        teacher=None,
        is_published=False,
    )
    AuditLog.objects.create(
        user=request.user,
        action='CREATE_COURSE',
        details=(
            f"Cours « {course.title} » créé par le Décanat pour {faculty.name} / "
            f"{promotion.display_label} (S{semester_val}, {credits_val} ECTS)."
        ),
        ip_address=request.META.get('REMOTE_ADDR'),
    )
    messages.success(
        request,
        f"Cours « {course.title} » créé. Affectez-le maintenant à un enseignant de votre faculté.",
    )
    return redirect('dean_courses')


@login_required(login_url='/login/')
@dean_required
def dean_delete_course(request, pk):
    """Le Décanat peut supprimer un cours de sa faculté non encore affecté."""
    faculty = request.user.assigned_faculty
    if not faculty:
        messages.error(request, "Profil Décanat invalide.")
        return redirect('dean_courses')

    course = get_object_or_404(Course, pk=pk, faculty=faculty)
    if course.teacher_id:
        messages.error(request, "Impossible de supprimer un cours déjà affecté à un enseignant.")
        return redirect('dean_courses')

    title = course.title
    course.delete()
    AuditLog.objects.create(
        user=request.user,
        action='DELETE_COURSE',
        details=f"Cours « {title} » supprimé par le Décanat ({faculty.name}).",
        ip_address=request.META.get('REMOTE_ADDR'),
    )
    messages.success(request, f"Cours « {title} » supprimé.")
    return redirect('dean_courses')


@login_required(login_url='/login/')
@dean_required
def dean_create_student(request):
    """Le Décanat crée un compte étudiant à partir du matricule."""
    from lms.student_accounts import gmail_from_prenom_nom, split_student_names
    from lms.visibility import sync_student_course_access

    faculty = request.user.assigned_faculty
    university = request.user.assigned_university
    if not faculty or not university:
        messages.error(request, "Profil Décanat invalide (université / faculté manquante).")
        return redirect('dean_students')

    if request.method != 'POST':
        return redirect('dean_students')

    matricule = (request.POST.get('matricule') or '').strip().upper()
    prenom = (request.POST.get('prenom') or '').strip()
    nom = (request.POST.get('nom') or '').strip()
    postnom = (request.POST.get('postnom') or '').strip()
    gender = (request.POST.get('gender') or '').strip().upper()
    promotion_id = request.POST.get('promotion_id')

    if not matricule:
        messages.error(request, "Le matricule est obligatoire.")
        return redirect('dean_students')
    if not prenom or not nom:
        messages.error(request, "Le prénom et le nom sont obligatoires.")
        return redirect('dean_students')
    if gender not in ('M', 'F'):
        messages.error(request, "Veuillez sélectionner le sexe (M ou F).")
        return redirect('dean_students')
    if not promotion_id:
        messages.error(request, "Veuillez sélectionner une promotion.")
        return redirect('dean_students')

    promotion = Promotion.objects.filter(id=promotion_id, faculty=faculty).first()
    if not promotion:
        messages.error(request, "Promotion invalide pour votre faculté.")
        return redirect('dean_students')

    if User.objects.filter(matricule__iexact=matricule).exists():
        messages.error(request, f"Un étudiant avec le matricule « {matricule} » existe déjà.")
        return redirect('dean_students')
    if User.objects.filter(username__iexact=matricule).exists():
        messages.error(request, f"Le matricule « {matricule} » est déjà utilisé comme identifiant.")
        return redirect('dean_students')

    system_default = getattr(settings, 'STUDENT_DEFAULT_PASSWORD', 'uwb2026')
    raw_password = (request.POST.get('password') or '').strip()
    initial_password = raw_password or system_default
    min_len = getattr(settings, 'STUDENT_PASSWORD_MIN_LENGTH', 6)
    if len(initial_password) < min_len:
        messages.error(
            request,
            f"Le mot de passe doit contenir au moins {min_len} caractères.",
        )
        return redirect('dean_students')

    first_name, last_name = split_student_names(nom, postnom, prenom)
    used_emails = {
        e.lower()
        for e in User.objects.exclude(email='').values_list('email', flat=True)
    }
    email = gmail_from_prenom_nom(prenom, nom, matricule, used=used_emails)

    student = User.objects.create_user(
        username=matricule,
        email=email,
        password=initial_password,
        role='STUDENT',
        matricule=matricule,
        first_name=first_name,
        last_name=last_name,
        gender=gender,
        profile_completed=True,
        assigned_university=university,
        assigned_faculty=faculty,
        is_active=True,
    )

    class_group = ClassGroup.objects.filter(promotion=promotion).first()
    if not class_group:
        class_group = ClassGroup.objects.create(
            promotion=promotion,
            name="Groupe Principal",
        )
    student.class_group = class_group
    student.save(update_fields=['class_group'])

    sync_student_course_access(student, teacher=None, promotion=promotion)
    from lms.models import Course
    from lms.visibility import sync_teacher_course_roster
    for course in Course.objects.filter(promotion=promotion, teacher__isnull=False):
        sync_teacher_course_roster(course)

    AuditLog.objects.create(
        user=request.user,
        action='CREATE_STUDENT',
        details=(
            f"Étudiant « {matricule} » créé pour {promotion.display_label} "
            f"({faculty.name}). Mot de passe initial défini par le décanat."
        ),
        ip_address=request.META.get('REMOTE_ADDR'),
    )
    messages.success(
        request,
        f"Compte étudiant « {matricule} » créé pour {promotion.display_label}. "
        f"Gmail : {email} · Mot de passe initial : {initial_password}",
    )
    return redirect('dean_students')


@login_required(login_url='/login/')
@manager_required
def manager_delete_course(request, pk):
    """Obsolète : la suppression des cours est réservée au Décanat."""
    messages.error(
        request,
        "La suppression des cours est maintenant assurée par le Décanat de la faculté.",
    )
    return redirect('manager_dashboard')


@login_required(login_url='/login/')
@manager_required
def manager_generate_uni_report(request):
    """Agrège les FacultyReports → UniversityReport transmis à l'Administrateur Provincial."""
    if request.method == 'POST':
        from super_admin.models import FacultyReport, UniversityReport, SemesterResultReport
        from django.contrib import messages
        from django.utils import timezone

        university = request.user.assigned_university
        if not university:
            messages.error(request, "Erreur : Aucune université assignée à votre profil.")
            return redirect('manager_dashboard')

        pending_reports = FacultyReport.objects.filter(university=university, is_validated=False)

        # Repli : si pas de FacultyReport en attente, agréger depuis les rapports annuels des décanats
        if not pending_reports.exists():
            sem_reports = SemesterResultReport.objects.filter(university=university)
            if not sem_reports.exists():
                messages.warning(
                    request,
                    "Aucun rapport de Décanat disponible. Attendez que les Décanats transmettent "
                    "leurs rapports annuels avant d'envoyer à l'Administrateur Provincial.",
                )
                return redirect('manager_consolidated_results')

            total_students = sum(r.total_students for r in sem_reports)
            passed_students = sum(r.passed_students for r in sem_reports)
            failed_students = sum(r.failed_students for r in sem_reports)
        else:
            total_students = sum(report.total_students for report in pending_reports)
            passed_students = sum(report.passed_students for report in pending_reports)
            failed_students = sum(report.failed_students for report in pending_reports)

        academic_year = f"{timezone.now().year - 1}-{timezone.now().year}"

        UniversityReport.objects.create(
            title=f"Rapport Annuel Consolidé - {university.name}",
            academic_year=academic_year,
            university=university,
            total_students=total_students,
            passed_students=passed_students,
            failed_students=failed_students,
            submitted_by=request.user,
        )

        if pending_reports.exists():
            pending_reports.update(is_validated=True, validated_at=timezone.now())

        province_name = university.province.name if university.province else "votre province"
        messages.success(
            request,
            f"Rapport annuel de {university.name} transmis à l'Administrateur Provincial ({province_name}) : "
            f"{passed_students} réussite(s) / {total_students} étudiant(s).",
        )
        return redirect('manager_consolidated_results')

    return redirect('manager_dashboard')


# (Maquette management moved to super_admin app)


# (Structure management moved to super_admin app)


@login_required(login_url='/login/')
@admin_required
def admin_create_teacher(request):
    user = request.user
    
    # Filtrer les universités accessibles pour le créateur
    if user.is_superuser:
        universities = University.objects.prefetch_related('faculties__promotions').all()
    else:
        # Un Manager ne voit que son université
        universities = University.objects.filter(id=user.assigned_university_id).prefetch_related('faculties__promotions')
        
    error = None

    if request.method == 'POST':
        username = request.POST.get('username', '').strip()
        email = request.POST.get('email', '').strip()
        password = request.POST.get('password', '').strip()
        university_id = request.POST.get('university_id') or None
        faculty_id = request.POST.get('faculty_id') or None
        promotion_ids = request.POST.getlist('promotion_ids')
        semester = request.POST.get('semester') or None

        # Force l'université du manager si pas superuser
        if not user.is_superuser:
            university_id = user.assigned_university_id
            # Si le manager est restreint à une faculté, on force aussi
            if user.assigned_faculty_id:
                faculty_id = user.assigned_faculty_id

        if User.objects.filter(username=username).exists():
            error = "Ce nom d'utilisateur est déjà pris."
        elif User.objects.filter(email__iexact=email).exists():
            error = "Un compte avec cet email existe déjà."
        elif len(password) < 6:
            error = "Le mot de passe doit contenir au moins 6 caractères."
        else:
            teacher = User.objects.create_user(
                username=username,
                email=email,
                password=password,
                role='TEACHER',
                is_active=True,
            )
            if university_id:
                teacher.assigned_university_id = university_id
            if faculty_id:
                teacher.assigned_faculty_id = faculty_id
            valid_promotions = Promotion.objects.none()
            if faculty_id:
                valid_promotions = Promotion.objects.filter(faculty_id=faculty_id)
            elif university_id:
                valid_promotions = Promotion.objects.filter(faculty__university_id=university_id)

            valid_promotion_ids = list(
                valid_promotions.filter(id__in=promotion_ids).values_list('id', flat=True)
            )
            if valid_promotion_ids:
                teacher.assigned_promotion_id = valid_promotion_ids[0]
            if semester:
                teacher.assigned_semester = int(semester)
            
            teacher.save()
            if valid_promotion_ids:
                teacher.assigned_promotions.set(valid_promotion_ids)
            messages.success(request, f"Enseignant « {username} » créé avec succès.")
            return redirect('dean_teachers')

    # Sérialiser la hiérarchie Université → Faculté → Promotion en JSON propre
    structure = {}
    for uni in universities:
        structure[str(uni.id)] = {}
        for fac in uni.faculties.all():
            structure[str(uni.id)][str(fac.id)] = {
                'name': fac.name,
                'promotions': [
                    {'id': str(p.id), 'name': p.display_label, 'code': p.name}
                    for p in Promotion.lmd_ordered(fac.promotions.all())
                ]
            }

    return render(request, 'teacher/admin_create_teacher.html', {
        'universities': universities,
        'error': error,
        'structure_json': json.dumps(structure),
        'is_dean': user.role == 'DEAN',
        'fixed_university': user.assigned_university if not user.is_superuser else None,
        'fixed_faculty': user.assigned_faculty if user.role == 'DEAN' else None,
        'faculty_promotions': (
            list(Promotion.lmd_ordered(
                Promotion.objects.filter(faculty_id=user.assigned_faculty_id)
            ))
            if user.role == 'DEAN' and user.assigned_faculty_id
            else []
        ),
    })


@login_required(login_url='/login/')
@dean_required
def admin_toggle_teacher(request, pk):
    teacher = get_object_or_404(User, pk=pk, role='TEACHER')
    # Restreindre au périmètre du décanat
    if not request.user.is_superuser:
        if request.user.assigned_university_id and teacher.assigned_university_id != request.user.assigned_university_id:
            messages.error(request, "Cet enseignant n'appartient pas à votre établissement.")
            return redirect('dean_teachers')
        if request.user.assigned_faculty_id and teacher.assigned_faculty_id != request.user.assigned_faculty_id:
            messages.error(request, "Cet enseignant n'appartient pas à votre faculté.")
            return redirect('dean_teachers')
    teacher.is_active = not teacher.is_active
    teacher.save()
    status_label = "activé" if teacher.is_active else "désactivé"
    messages.success(request, f"L'enseignant « {teacher.username} » a été {status_label}.")
    return redirect('dean_teachers')


@login_required(login_url='/login/')
@dean_required
def admin_delete_teacher(request, pk):
    """Le Décanat supprime définitivement un enseignant de sa faculté."""
    if request.method != 'POST':
        return redirect('dean_teachers')

    teacher = get_object_or_404(User, pk=pk, role='TEACHER')
    if not request.user.is_superuser:
        if request.user.assigned_university_id and teacher.assigned_university_id != request.user.assigned_university_id:
            messages.error(request, "Cet enseignant n'appartient pas à votre établissement.")
            return redirect('dean_teachers')
        if request.user.assigned_faculty_id and teacher.assigned_faculty_id != request.user.assigned_faculty_id:
            messages.error(request, "Cet enseignant n'appartient pas à votre faculté.")
            return redirect('dean_teachers')

    label = teacher.get_full_name() or teacher.username
    # Remettre les cours au décanat (disponibles pour réaffectation)
    Course.objects.filter(teacher=teacher).update(teacher=None, is_published=False)
    teacher.delete()
    messages.success(request, f"L'enseignant « {label} » a été supprimé. Ses cours sont de nouveau disponibles à l'affectation.")
    return redirect('dean_teachers')


@login_required(login_url='/login/')
@dean_required
def admin_assign_course(request):
    """Le Décanat attribue aux enseignants les cours de sa faculté."""
    if request.method == 'POST':
        teacher_id = request.POST.get('teacher_id')
        course_id = request.POST.get('course_id')

        teacher = get_object_or_404(User, pk=teacher_id, role='TEACHER', is_active=True)
        course = get_object_or_404(Course, pk=course_id)

        if not request.user.is_superuser:
            if request.user.assigned_university_id and teacher.assigned_university_id != request.user.assigned_university_id:
                messages.error(request, "Cet enseignant n'appartient pas à votre établissement.")
                return redirect('dean_teachers')
            if request.user.assigned_faculty_id and teacher.assigned_faculty_id != request.user.assigned_faculty_id:
                messages.error(request, "Cet enseignant n'appartient pas à votre faculté.")
                return redirect('dean_teachers')

            if course.faculty_id != request.user.assigned_faculty_id:
                messages.error(request, "Ce cours n'appartient pas à votre faculté.")
                return redirect('dean_teachers')
            if course.assigned_to_dean_id and course.assigned_to_dean_id != request.user.id:
                messages.error(request, "Ce cours n'appartient pas à votre Décanat.")
                return redirect('dean_teachers')
            if course.teacher_id:
                messages.error(request, "Ce cours est déjà attribué à un enseignant.")
                return redirect('dean_teachers')

        if course.promotion_id:
            teacher.assigned_promotions.add(course.promotion)
            teacher.assigned_promotion = course.promotion
            update_fields = ['assigned_promotion']
            # Ne pas bloquer l'affichage / saisie si le cours est d'un autre semestre
            if teacher.assigned_semester and course.semester != teacher.assigned_semester:
                teacher.assigned_semester = None
                update_fields.append('assigned_semester')
            teacher.save(update_fields=update_fields)

        course.teacher = teacher
        if not course.assigned_to_dean_id:
            course.assigned_to_dean = request.user
        course.save(update_fields=['teacher', 'assigned_to_dean'])

        from lms.visibility import sync_teacher_course_roster
        roster_count = sync_teacher_course_roster(course)

        AuditLog.objects.create(
            user=request.user,
            action='AFFECTATION_COURS',
            details=(
                f"Cours « {course.title} » ({course.promotion.display_label if course.promotion else '—'}, "
                f"S{course.semester}) affecté à {teacher.username}. "
                f"{roster_count} étudiant(s) de la promotion rattaché(s)."
            ),
            ip_address=request.META.get('REMOTE_ADDR'),
        )
        messages.success(
            request,
            f"Le cours « {course.title} » a été attribué à {teacher.get_full_name() or teacher.username}. "
            f"{roster_count} étudiant(s) de {course.promotion.display_label if course.promotion else 'la promotion'} "
            f"sont disponibles pour cet enseignant.",
        )

    return redirect('dean_teachers')


# ---------------------------------------------------------------------------
# Teacher views — Tableau de bord & cours
# ---------------------------------------------------------------------------

@login_required(login_url='/login/')
@teacher_required
def dashboard(request):
    from django.db.models import Count

    teacher_promotions, selected_promotion = _get_selected_teacher_promotion(request, request.user)

    courses = _teacher_course_queryset(request.user, selected_promotion)\
        .select_related('national_course')\
        .annotate(
            total_likes=Count('likes', distinct=True) + Count('lessons__likes', distinct=True),
            total_comments=Count('comments', distinct=True) + Count('lessons__comments', distinct=True)
        ).order_by('-created_at')

    published_count = courses.filter(is_published=True).count()

    # Compteur aligné sur « Mes étudiants » : inscrits aux cours de cet enseignant
    active_students = _students_for_teacher(request.user, selected_promotion).filter(
        is_active=True
    ).count()

    context = {
        'courses': courses,
        'published_count': published_count,
        'active_students_count': active_students,
        'teacher_promotions': teacher_promotions,
        'current_promotion': selected_promotion,
    }
    return render(request, 'teacher/dashboard.html', context)


@login_required(login_url='/login/')
@teacher_required
def course_create(request):
    """Création bloquée : seuls les cours affectés par le décanat sont accessibles."""
    messages.warning(
        request,
        "Vous ne pouvez pas créer de cours. Le décanat doit vous affecter un cours "
        "avant que vous puissiez y accéder et publier du contenu."
    )
    return redirect('teacher_dashboard')


@login_required(login_url='/login/')
@teacher_required
def course_toggle_publish(request, course_id):
    course = get_object_or_404(Course, id=course_id, teacher=request.user)

    if not course.is_published:
        if not course.lessons.exists():
            messages.error(
                request,
                f"Ajoutez au moins un module avant de publier « {course.title} ».",
            )
            return redirect('teacher_dashboard')
        course.is_published = True
        course.save(update_fields=['is_published'])
        try:
            from lms.student_notifications import notify_course_published
            from lms.visibility import affiliated_students_for_course, sync_student_course_access

            # Garantir l'accès mobile pour tous les étudiants de la promotion
            for student in affiliated_students_for_course(course):
                sync_student_course_access(student, teacher=request.user, promotion=course.promotion)

            count = notify_course_published(course)
            promo_label = course.promotion.display_label if course.promotion else "—"
            messages.success(
                request,
                f"Le cours « {course.title} » est publié ({promo_label}). "
                f"{count} étudiant(s) de cette promotion peuvent le voir sur mobile.",
            )
        except Exception:
            messages.success(
                request,
                f"Le cours « {course.title} » est maintenant visible pour les étudiants affiliés.",
            )
    else:
        course.is_published = False
        course.save(update_fields=['is_published'])
        messages.info(request, f"Le cours « {course.title} » a été retiré de la publication.")

    next_url = request.GET.get('next')
    if next_url:
        return redirect(next_url)
    return redirect('teacher_dashboard')


@login_required(login_url='/login/')
@teacher_required
def teacher_delete_course(request, course_id):
    """
    L'enseignant peut supprimer un module/cours qui lui est attribué
    (y compris s'il est déjà publié). Le cours revient au Décanat.
    """
    if request.method != 'POST':
        return redirect('teacher_dashboard')

    course = get_object_or_404(Course, id=course_id, teacher=request.user)
    title = course.title

    # Supprimer le contenu pédagogique (leçons / quizzes liés en cascade selon le modèle)
    course.lessons.all().delete()
    course.is_published = False
    course.teacher = None
    course.save(update_fields=['is_published', 'teacher'])

    messages.success(
        request,
        f"Le module « {title} » a été retiré de votre espace "
        f"(dépublié et rendu au Décanat pour réaffectation).",
    )
    return redirect('teacher_dashboard')


@login_required
@teacher_required
def lesson_management(request, course_id):
    course = get_object_or_404(Course, id=course_id, teacher=request.user)
    lessons = course.lessons.all()

    if request.method == 'POST' and request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        action = request.POST.get('action', 'create')
        lesson_id = request.POST.get('lesson_id')

        if action == 'delete' and lesson_id:
            lesson = get_object_or_404(Lesson, id=lesson_id, course=course)
            lesson.delete()
            return JsonResponse({'status': 'success', 'message': 'Leçon supprimée'})

        title = request.POST.get('title')
        content_type = request.POST.get('content_type')
        content_file = request.FILES.get('content_file')
        content_text = request.POST.get('content_text')

        if not title or not content_type:
            return JsonResponse({'status': 'error', 'message': 'Le titre et le format sont obligatoires'}, status=400)

        if content_type != 'TEXT' and not content_file and action == 'create':
            return JsonResponse({'status': 'error', 'message': 'Un fichier est requis pour ce type de contenu'}, status=400)

        if content_type == 'TEXT' and not content_text:
            return JsonResponse({'status': 'error', 'message': 'Le contenu texte est obligatoire'}, status=400)

        try:
            if action == 'edit' and lesson_id:
                lesson = get_object_or_404(Lesson, id=lesson_id, course=course)
                lesson.title = title
                lesson.content_type = content_type
                if content_file:
                    lesson.content_file = content_file
                lesson.content_text = content_text
                lesson.save()
                return JsonResponse({'status': 'success', 'message': 'Leçon mise à jour'})
            else:
                order = lessons.count() + 1
                lesson = Lesson.objects.create(
                    course=course,
                    title=title,
                    content_type=content_type,
                    content_file=content_file,
                    content_text=content_text,
                    order=order
                )

                if course.is_published:
                    try:
                        from lms.student_notifications import notify_lesson_published
                        notify_lesson_published(course, lesson)
                    except Exception:
                        pass
                
                attach_quiz = request.POST.get('attach_quiz') == 'true'
                redirect_url = None
                if attach_quiz:
                    from django.urls import reverse
                    redirect_url = reverse('teacher_lesson_create_quiz', kwargs={'lesson_id': lesson.id})
                
                return JsonResponse({
                    'status': 'success',
                    'message': 'Leçon créée avec succès',
                    'redirect_url': redirect_url,
                    'lesson': {
                        'id': lesson.id,
                        'title': lesson.title,
                        'type': lesson.content_type,
                    }
                })
        except Exception as e:
            return JsonResponse({'status': 'error', 'message': str(e)}, status=400)

    return render(request, 'teacher/lesson_form.html', {'course': course, 'lessons': lessons})


@login_required
@teacher_required
def course_preview(request, course_id):
    course = get_object_or_404(Course, id=course_id, teacher=request.user)
    lessons = course.lessons.all().order_by('order')

    lesson_id = request.GET.get('lesson')
    selected_lesson = None
    if lesson_id:
        selected_lesson = get_object_or_404(Lesson, id=lesson_id, course=course)
    elif lessons.exists():
        selected_lesson = lessons.first()

    return render(request, 'teacher/course_preview.html', {
        'course': course,
        'lessons': lessons,
        'selected_lesson': selected_lesson,
    })


@login_required
@teacher_required
def comment_inbox(request):
    from lms.models import CourseComment, LessonComment
    from itertools import chain
    from operator import attrgetter

    course_comments = CourseComment.objects.filter(course__teacher=request.user, parent=None)
    lesson_comments = LessonComment.objects.filter(lesson__course__teacher=request.user, parent=None)

    all_comments = sorted(
        chain(course_comments, lesson_comments),
        key=attrgetter('created_at'),
        reverse=True
    )
    return render(request, 'teacher/comments.html', {'comments': all_comments})


@login_required
@teacher_required
def live_management(request):
    courses = Course.objects.filter(teacher=request.user)
    active_lives = LiveSession.objects.filter(teacher=request.user, is_active=True)
    return render(request, 'teacher/live_management.html', {
        'courses': courses,
        'active_lives': active_lives,
    })


@login_required
@teacher_required
def live_room(request, session_id):
    session = get_object_or_404(LiveSession, id=session_id, teacher=request.user)
    if not session.is_active:
        return redirect('teacher_live_management')
    return render(request, 'teacher/live_room.html', {
        'session': session,
        'course': session.course,
    })


@login_required
@teacher_required
def chat_inbox(request):
    from lms.models import ChatRoom
    rooms = ChatRoom.objects.filter(participants=request.user).order_by('-created_at')
    return render(request, 'teacher/chat_list.html', {'rooms': rooms})


@login_required
@teacher_required
def chat_room(request, room_id):
    from lms.models import ChatRoom, ChatMessage
    room = get_object_or_404(ChatRoom, id=room_id, participants=request.user)

    if request.method == 'POST':
        content = request.POST.get('content')
        if content:
            ChatMessage.objects.create(room=room, sender=request.user, content=content)
            return redirect('teacher_chat_room', room_id=room_id)

    msgs = room.messages.all().order_by('created_at')
    room.messages.exclude(sender=request.user).update(is_read=True)
    return render(request, 'teacher/chat_room.html', {
        'room': room,
        'chat_messages': msgs,
    })


@login_required
@teacher_required
def lesson_create_quiz(request, lesson_id):
    from lms.models import Quiz, Lesson
    lesson = get_object_or_404(Lesson, id=lesson_id, course__teacher=request.user)
    
    quiz, created = Quiz.objects.get_or_create(
        lesson=lesson,
        defaults={
            'course': lesson.course,
            'title': f"Quiz de validation : {lesson.title}",
            'description': "Répondez aux questions suivantes pour valider le module.",
            'time_limit': 30,
            'quiz_type': 'EVALUATION',
            'order': lesson.order,
            'is_published': True
        }
    )
    return redirect('teacher_quiz_edit', quiz_id=quiz.id)

@login_required
@teacher_required
def quiz_management(request, course_id):
    from lms.models import Quiz
    course = get_object_or_404(Course, id=course_id, teacher=request.user)
    quizzes = course.quizzes.all()

    if request.method == 'POST':
        # Auto-calculer l'ordre si non fourni pour s'insérer après les leçons/quizz existants
        order = request.POST.get('order')
        if not order:
            order = course.lessons.count() + course.quizzes.count() + 1

        Quiz.objects.create(
            course=course,
            title=request.POST.get('title'),
            description=request.POST.get('description'),
            time_limit=request.POST.get('time_limit', 30),
            quiz_type=request.POST.get('quiz_type', 'EVALUATION'),
            order=order,
        )
        return redirect('teacher_quiz_management', course_id=course_id)

    return render(request, 'teacher/quiz_list.html', {'course': course, 'quizzes': quizzes})


@login_required
@teacher_required
def quiz_edit(request, quiz_id):
    from lms.models import Quiz, QuizQuestion, QuizChoice
    quiz = get_object_or_404(Quiz, id=quiz_id, course__teacher=request.user)
    questions = quiz.questions.all()

    if request.method == 'POST':
        action = request.POST.get('action')
        if action == 'add_question':
            text = request.POST.get('text')
            points = request.POST.get('points', 1)
            question = QuizQuestion.objects.create(quiz=quiz, text=text, points=points)
            choices_texts = request.POST.getlist('choices[]')
            correct_index = int(request.POST.get('correct_choice', 0))
            for i, c_text in enumerate(choices_texts):
                if c_text.strip():
                    QuizChoice.objects.create(
                        question=question, text=c_text, is_correct=(i == correct_index)
                    )
            return redirect('teacher_quiz_edit', quiz_id=quiz_id)

    from django.db.models import Sum
    total_points = questions.aggregate(total=Sum('points'))['total'] or 0
    return render(request, 'teacher/quiz_form.html', {
        'quiz': quiz,
        'questions': questions,
        'total_points': total_points,
    })


@login_required
@teacher_required
def quiz_toggle_publish(request, quiz_id):
    from lms.models import Quiz
    quiz = get_object_or_404(Quiz, id=quiz_id, course__teacher=request.user)
    
    if not quiz.is_published:
        if quiz.questions.count() == 0:
            messages.error(request, "Vous devez ajouter au moins une question avant de publier ce quiz.")
            return redirect('teacher_quiz_edit', quiz_id=quiz.id)
        quiz.is_published = True
        quiz.save()
        try:
            from lms.student_notifications import notify_quiz_published
            count = notify_quiz_published(quiz)
            messages.success(
                request,
                f"Quiz « {quiz.title} » publié ({count} notification(s) aux étudiants affiliés).",
            )
        except Exception:
            messages.success(request, f"Quiz « {quiz.title} » publié.")
    else:
        quiz.is_published = False
        quiz.save()
        messages.info(request, f"Quiz « {quiz.title} » retiré de la publication.")
    
    return redirect('teacher_quiz_management', course_id=quiz.course.id)


# ---------------------------------------------------------------------------
# Teacher views — Étudiants (lecture seule, structure définie par l'admin)
# ---------------------------------------------------------------------------

@login_required(login_url='/login/')
@teacher_required
def teacher_students_dashboard(request):
    from django.db.models import Avg
    from lms.models import Enrollment, StudentAudit
    from lms.visibility import affiliated_students_for_course

    teacher = request.user
    teacher_promotions, selected_promotion = _get_selected_teacher_promotion(request, teacher)
    courses_qs = _teacher_course_queryset(teacher, selected_promotion)

    # Garantir les inscriptions uniquement sur LES cours de cet enseignant
    for course in courses_qs:
        if not course.promotion_id:
            continue
        for student in affiliated_students_for_course(course):
            Enrollment.objects.get_or_create(student=student, course=course)

    # Uniquement les étudiants inscrits aux cours de CET enseignant
    students = list(
        _students_for_teacher(teacher, selected_promotion).select_related(
            'class_group', 'class_group__promotion',
            'class_group__promotion__faculty',
            'class_group__promotion__faculty__university'
        ).order_by('last_name', 'first_name', 'username')
    )

    progress_courses = list(courses_qs)
    for student in students:
        quiz_status = _student_module_quizzes_status(student, progress_courses)
        student.quiz_progress = quiz_status

        if quiz_status['is_complete']:
            student.progress_label = 'Terminé'
            student.progress_complete = True
            student.average_progress = 100
        elif quiz_status['has_quizzes']:
            student.progress_label = f"{quiz_status['done']}/{quiz_status['total']} quiz"
            student.progress_complete = False
            student.average_progress = round(
                (quiz_status['done'] / quiz_status['total']) * 100, 1
            ) if quiz_status['total'] else 0
        else:
            avg_progress = Enrollment.objects.filter(
                student=student,
                course__in=progress_courses
            ).aggregate(avg=Avg('progress'))['avg'] or 0
            student.progress_label = f"{round(float(avg_progress), 0):.0f}%"
            student.progress_complete = float(avg_progress) >= 100
            student.average_progress = round(float(avg_progress), 1)

        # Nom affiché : renseigné par le décanat sur le compte étudiant
        student.display_full_name = (student.get_full_name() or '').strip()

    return render(request, 'teacher/students_dashboard.html', {
        'students': students,
        'teacher': teacher,
        'teacher_promotions': teacher_promotions,
        'current_promotion': selected_promotion,
    })


def _parse_grade(value, default=0.0):
    if value is None or value == '':
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _teacher_can_access_student(teacher, student):
    """Vérifie que l'étudiant appartient à une promotion couverte par les cours de l'enseignant."""
    from lms.visibility import affiliated_students_for_course

    for course in _teacher_course_queryset(teacher):
        if not course.promotion_id:
            continue
        if affiliated_students_for_course(course).filter(id=student.id).exists():
            return True
    return False


@login_required(login_url='/login/')
@teacher_required
def teacher_update_audit(request):
    """Met à jour les cotes d'audit via AJAX (par cours)."""
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            student_id = data.get('student_id')
            course_id = data.get('course_id')
            tp = data.get('tp', 0.0)
            interro = data.get('interro', 0.0)
            examen = data.get('examen', 0.0)

            if not student_id or not course_id:
                return JsonResponse({
                    'status': 'error',
                    'message': 'student_id et course_id sont requis.',
                }, status=400)

            from lms.models import StudentAudit, Course, Enrollment
            student = get_object_or_404(User, id=student_id, role='STUDENT')
            teacher = request.user

            if not _teacher_can_access_student(teacher, student):
                return JsonResponse({'status': 'error', 'message': 'Étudiant hors de votre périmètre.'}, status=403)

            course = get_object_or_404(Course, id=course_id, teacher=request.user)

            if course.promotion_id:
                in_promo = (
                    student.class_group_id
                    and student.class_group.promotion_id == course.promotion_id
                )
                if in_promo:
                    Enrollment.objects.get_or_create(student=student, course=course)
                elif not Enrollment.objects.filter(course=course, student=student).exists():
                    return JsonResponse({
                        'status': 'error',
                        'message': 'Cet étudiant n’appartient pas à la promotion de ce cours.',
                    }, status=403)

            if course.university and course.university.is_grading_locked:
                return JsonResponse({'status': 'error', 'message': 'Saisie verrouillée par l\'admin (université).'}, status=403)
            if course.university:
                if course.semester == 1 and course.university.s1_closed:
                    return JsonResponse({'status': 'error', 'message': 'Semestre 1 clôturé.'}, status=403)
                if course.semester == 2 and course.university.s2_closed:
                    return JsonResponse({'status': 'error', 'message': 'Semestre 2 clôturé.'}, status=403)

            audit, _ = StudentAudit.objects.get_or_create(
                student_id=student_id, teacher=request.user, course=course
            )
            if audit.status in LOCKED_AUDIT_STATUSES:
                return JsonResponse({'status': 'error', 'message': 'Cotes déjà soumises — modification impossible.'}, status=403)

            audit.tp = _parse_grade(tp)
            audit.interro = _parse_grade(interro)
            audit.examen = _parse_grade(examen)
            audit.save()

            return JsonResponse({
                'status': 'success',
                'total': audit.total,
                'credits': audit.course_credits,
                'credits_earned': audit.credits_earned,
                'is_passed': audit.is_passed,
            })
        except Exception as e:
            return JsonResponse({'status': 'error', 'message': str(e)}, status=400)
    return JsonResponse({'status': 'error', 'message': 'Invalid method'}, status=405)


@login_required
@teacher_required
def teacher_submit_audit(request):
    """Soumission des cotes d'un cours au Décanat uniquement (+ sync CourseGrade)."""
    if request.method == 'POST':
        course_id = request.POST.get('course_id')
        from lms.models import StudentAudit, Course, CourseGrade, AuditLog, Notification
        from lms.visibility import affiliated_students_for_course

        if not course_id:
            messages.error(request, "Cours non précisé.")
            return redirect('teacher_dashboard')

        course = get_object_or_404(
            Course.objects.select_related('faculty', 'promotion', 'promotion__faculty', 'university'),
            id=course_id,
            teacher=request.user,
        )

        if course.university and course.university.is_grading_locked:
            messages.error(request, "La saisie des notes est verrouillée pour votre université.")
            return redirect('teacher_course_grades', course_id=course.id)
        if course.university:
            if course.semester == 1 and course.university.s1_closed:
                messages.error(request, "Le semestre 1 est clôturé.")
                return redirect('teacher_course_grades', course_id=course.id)
            if course.semester == 2 and course.university.s2_closed:
                messages.error(request, "Le semestre 2 est clôturé.")
                return redirect('teacher_course_grades', course_id=course.id)

        # Créer les fiches de cote manquantes pour tous les affiliés de la promotion
        if course.promotion_id:
            for student in affiliated_students_for_course(course):
                StudentAudit.objects.get_or_create(
                    student=student,
                    teacher=request.user,
                    course=course,
                )

        audits = list(StudentAudit.objects.filter(
            teacher=request.user, course=course, status='DRAFT'
        ).select_related('student', 'course', 'course__national_course'))

        if not audits:
            already = StudentAudit.objects.filter(
                teacher=request.user, course=course, status__in=LOCKED_AUDIT_STATUSES
            ).count()
            if already:
                messages.info(
                    request,
                    f"Les cotes de ce cours ont déjà été transmises au Décanat ({already} étudiant(s)).",
                )
            else:
                messages.warning(request, "Aucune cote à soumettre pour ce cours.")
            return redirect('teacher_course_grades', course_id=course.id)

        count = 0
        credits_label = course.effective_credits
        for audit in audits:
            audit.status = 'SUBMITTED_TO_DEAN'
            audit.save(update_fields=['status', 'updated_at'])

            grade_obj, _ = CourseGrade.objects.get_or_create(
                student=audit.student,
                course=course,
                defaults={'status': 'DRAFT'}
            )
            if grade_obj.status in ['DRAFT', 'SUBMITTED_TO_MANAGER', 'SUBMITTED_TO_DEAN']:
                grade_obj.final_score = audit.total
                grade_obj.interrogation_score = audit.interro
                grade_obj.exam_score = audit.examen
                grade_obj.status = 'SUBMITTED_TO_DEAN'
                grade_obj.save()
            count += 1

        teacher_label = request.user.get_full_name() or request.user.username
        promo_label = course.promotion.display_label if course.promotion_id else "—"
        notif_title = "Cotes reçues — validation Décanat"
        notif_message = (
            f"{teacher_label} a transmis les cotes du cours « {course.title} » "
            f"({promo_label}, S{course.semester}) — {count} étudiant(s). "
            f"À vérifier avant transmission du rapport à l'Admin (Université)."
        )

        # Destinataires : uniquement le Décanat de la faculté
        faculty = course.faculty or (course.promotion.faculty if course.promotion_id else None)
        recipients = []
        if faculty:
            recipients = list(User.objects.filter(
                role='DEAN',
                assigned_faculty=faculty,
                is_active=True,
            ))

        for recipient in recipients:
            Notification.objects.create(
                user=recipient,
                title=notif_title,
                message=notif_message,
                type='grade',
            )

        AuditLog.objects.create(
            user=request.user,
            action="SUBMIT_COURSE_AUDITS_TO_DEAN",
            details=(
                f"Cotes du cours {course.title} (S{course.semester}, {credits_label} crédits) "
                f"soumises au Décanat — {count} étudiant(s), "
                f"{len(recipients)} décanat(s) notifié(s)."
            ),
            ip_address=request.META.get('REMOTE_ADDR')
        )
        messages.success(
            request,
            f"{count} cote(s) transmise(s) au Décanat "
            f"({credits_label} crédits / cours — seuil : 10/20). "
            f"{len(recipients)} décanat(s) notifié(s)."
        )
        return redirect('teacher_course_grades', course_id=course.id)

    return redirect('teacher_dashboard')

@login_required(login_url='/login/')
@teacher_required
def teacher_broadcast_meet(request):
    """Partage le lien Google Meet et notifie les étudiants par Push notification Firebase."""
    if request.method == 'POST':
        meet_url = request.POST.get('meet_url', '').strip()
        if not meet_url:
            messages.error(request, "Veuillez fournir un lien valide.")
            target = 'teacher_students_dashboard'
            if request.POST.get('promotion_id'):
                return redirect(f"{redirect(target).url}?promotion={request.POST.get('promotion_id')}")
            return redirect(target)

        teacher = request.user
        teacher_promotions, selected_promotion = _get_selected_teacher_promotion(request, teacher)
        print(f"[Direct] Enseignant : {teacher.username} | Lien : {meet_url}")
        print(f"[Direct] selected_promotion: {selected_promotion}")
        print(f"[Direct] assigned_faculty: {teacher.assigned_faculty}")
        print(f"[Direct] assigned_university: {teacher.assigned_university}")
        
        # Uniquement les étudiants des cours de CET enseignant
        students = list(_students_for_teacher(teacher, selected_promotion))

        print(f"[Direct] {len(students)} étudiant(s) trouvé(s) : {[s.email for s in students]}")
            
        try:
            from lms.firebase_admin_config import send_firebase_notification
            count = 0
            for student in students:
                result = send_firebase_notification(
                    user=student,
                    title="🔴 Nouveau Direct (Google Meet)",
                    message=f"Le professeur {teacher.username} vient de lancer un cours en direct. Appuyez pour rejoindre la session.",
                    notif_type="LIVE_MEET",
                    extra_data={"meet_url": meet_url}
                )
                print(f"[Direct] Notif pour {student.email} : {'OK' if result else 'ECHEC'}")
                count += 1
            messages.success(request, f"Lien Google Meet partagé avec succès. {count} étudiant(s) notifié(s).")
        except Exception as e:
            import traceback
            print(f"[Direct] ERREUR : {e}")
            traceback.print_exc()
            messages.error(request, f"Une erreur s'est produite lors de la notification : {e}")
            
    target = redirect('teacher_students_dashboard').url
    if request.POST.get('promotion_id'):
        target = f"{target}?promotion={request.POST.get('promotion_id')}"
    return redirect(target)


@login_required
@teacher_required
def teacher_add_student(request):
    """Obsolète : les étudiants sont créés par le décanat et hérités via la promotion du cours."""
    messages.info(
        request,
        "L'affiliation manuelle est désactivée. Les étudiants de la promotion sont "
        "automatiquement disponibles lorsque le décanat vous attribue un cours.",
    )
    return redirect('teacher_students_dashboard')


@login_required(login_url='/login/')
@teacher_required
def teacher_student_progress(request, student_id):
    from django.db.models import Avg
    from lms.models import Enrollment, Grade, QuizAttempt

    student = get_object_or_404(User, id=student_id, role='STUDENT')
    # Accès limité aux étudiants des cours de cet enseignant
    if not Enrollment.objects.filter(student=student, course__teacher=request.user).exists():
        messages.error(request, "Cet étudiant n'est pas dans votre périmètre.")
        return redirect('teacher_students_dashboard')

    enrollments = Enrollment.objects.filter(
        student=student, course__teacher=request.user
    ).select_related('course')

    courses_progress = []
    for enrollment in enrollments:
        course = enrollment.course
        grades = Grade.objects.filter(student=student, lesson__course=course)
        quiz_attempts = QuizAttempt.objects.filter(
            student=student, quiz__course=course
        ).select_related('quiz')
        quiz_status = _student_module_quizzes_status(student, [course])
        module_rows = _course_module_quizzes_detail(student, course)
        courses_progress.append({
            'course': course,
            'enrollment': enrollment,
            'total_lessons': course.lessons.count(),
            'completed_lessons': grades.count(),
            'progress': float(enrollment.progress),
            'avg_score': round(float(grades.aggregate(avg=Avg('score'))['avg'] or 0), 1),
            'quiz_attempts': quiz_attempts,
            'quiz_status': quiz_status,
            'modules': module_rows,
            'is_complete': quiz_status['is_complete'],
        })

    return render(request, 'teacher/student_progress.html', {
        'student': student,
        'courses_progress': courses_progress,
    })


@login_required(login_url='/login/')
@teacher_required
def course_enrollments(request, course_id):
    from django.db.models import Avg
    course = get_object_or_404(Course, id=course_id, teacher=request.user)
    enrollments = list(
        course.enrollments.all().select_related('student').order_by('-enrolled_at')
    )

    for enrollment in enrollments:
        quiz_status = _student_module_quizzes_status(enrollment.student, [course])
        enrollment.quiz_status = quiz_status
        if quiz_status['is_complete']:
            enrollment.status_label = 'Terminé'
            enrollment.status_kind = 'done'
        elif quiz_status['has_quizzes'] and quiz_status['done'] > 0:
            enrollment.status_label = f"{quiz_status['done']}/{quiz_status['total']} quiz"
            enrollment.status_kind = 'progress'
        elif quiz_status['has_quizzes']:
            enrollment.status_label = 'En attente'
            enrollment.status_kind = 'wait'
        elif enrollment.progress >= 100.0:
            enrollment.status_label = 'Terminé'
            enrollment.status_kind = 'done'
        elif enrollment.progress > 0.0:
            enrollment.status_label = 'En cours'
            enrollment.status_kind = 'progress'
        else:
            enrollment.status_label = 'En attente'
            enrollment.status_kind = 'wait'

    avg_progress = (
        sum(float(e.progress) for e in enrollments) / len(enrollments)
        if enrollments else 0
    )
    finished_count = sum(1 for e in enrollments if e.status_kind == 'done')
    in_progress_count = sum(1 for e in enrollments if e.status_kind == 'progress')
    not_started_count = sum(1 for e in enrollments if e.status_kind == 'wait')

    return render(request, 'teacher/course_enrollments.html', {
        'course': course,
        'enrollments': enrollments,
        'total_enrolled': len(enrollments),
        'avg_progress': round(avg_progress, 1),
        'finished_count': finished_count,
        'in_progress_count': in_progress_count,
        'not_started_count': not_started_count,
    })


@login_required
@teacher_required
def quiz_results(request, quiz_id):
    from lms.models import Quiz, QuizAttempt
    quiz = get_object_or_404(Quiz, id=quiz_id, course__teacher=request.user)
    attempts = QuizAttempt.objects.filter(quiz=quiz).select_related('student').order_by('-completed_at')
    return render(request, 'teacher/quiz_results.html', {'quiz': quiz, 'attempts': attempts})


@login_required(login_url='/login/')
@dean_required
def manager_toggle_grading_lock(request):
    """Verrouiller / Déverrouiller la saisie des notes pour l'université."""
    university = request.user.assigned_university
    if not university:
        messages.error(request, "Erreur : Aucune université assignée à votre profil admin (université).")
        return redirect('manager_dashboard')
    
    university.is_grading_locked = not university.is_grading_locked
    university.save()
    
    # Audit Log
    AuditLog.objects.create(
        user=request.user,
        action="TOGGLE_GRADING_LOCK",
        details=f"Verrouillage des notes {'ACTIF' if university.is_grading_locked else 'INACTIF'} pour {university.name}",
        ip_address=request.META.get('REMOTE_ADDR')
    )
    
    status_label = "verrouillée" if university.is_grading_locked else "déverrouillée"
    messages.success(request, f"La saisie des notes pour {university.name} is désormais {status_label}.")
    return redirect('manager_dashboard')


@login_required(login_url='/login/')
@dean_required
def manager_toggle_semester_lock(request, semester_num):
    """Verrouiller / Déverrouiller un semestre spécifique pour l'université."""
    university = request.user.assigned_university
    if not university:
        messages.error(request, "Erreur : Aucune université assignée à votre profil admin (université).")
        return redirect('manager_dashboard')
    
    sem = int(semester_num)
    if sem == 1:
        university.s1_closed = not university.s1_closed
        university.save()
        action_name = "TOGGLE_S1_CLOSED"
        details_str = f"S1 {'CLOTURE' if university.s1_closed else 'OUVERT'} pour {university.name}"
        status_label = "clôturée" if university.s1_closed else "réouverte"
        messages.success(request, f"La saisie pour le Semestre 1 est désormais {status_label}.")
    elif sem == 2:
        university.s2_closed = not university.s2_closed
        university.save()
        action_name = "TOGGLE_S2_CLOSED"
        details_str = f"S2 {'CLOTURE' if university.s2_closed else 'OUVERT'} pour {university.name}"
        status_label = "clôturée" if university.s2_closed else "réouverte"
        messages.success(request, f"La saisie pour le Semestre 2 est désormais {status_label}.")
    else:
        messages.error(request, "Semestre invalide.")
        return redirect('manager_dashboard')
        
    # Audit Log
    AuditLog.objects.create(
        user=request.user,
        action=action_name,
        details=details_str,
        ip_address=request.META.get('REMOTE_ADDR')
    )
    
    return redirect('manager_dashboard')


@login_required(login_url='/login/')
@teacher_required
def course_grades_entry(request, course_id):
    from lms.models import Course, Enrollment, StudentAudit
    from lms.visibility import affiliated_students_for_course, sync_student_course_access

    course = get_object_or_404(
        Course.objects.select_related('national_course', 'university', 'promotion'),
        id=course_id,
        teacher=request.user
    )

    semester_mismatch = False

    # Tous les étudiants de la promotion du cours (pas seulement les Enrollment existants)
    if course.promotion_id:
        students = list(
            affiliated_students_for_course(course)
            .order_by('last_name', 'username')
        )
        for student in students:
            sync_student_course_access(student, teacher=request.user, promotion=course.promotion)
            Enrollment.objects.get_or_create(student=student, course=course)
    else:
        students = list(
            User.objects.filter(
                role='STUDENT',
                enrollments__course=course,
            ).distinct().order_by('last_name', 'username')
        )

    is_semester_closed = False
    if course.university:
        if course.semester == 1 and course.university.s1_closed:
            is_semester_closed = True
        elif course.semester == 2 and course.university.s2_closed:
            is_semester_closed = True

    grades_list = []
    for student in students:
        enrollment, _ = Enrollment.objects.get_or_create(student=student, course=course)
        audit, _ = StudentAudit.objects.get_or_create(
            student=student,
            teacher=request.user,
            course=course,
        )
        grades_list.append({
            'enrollment': enrollment,
            'audit': audit,
            'student': student,
            'is_submitted': audit.status in LOCKED_AUDIT_STATUSES,
        })

    is_locked = (
        (course.university.is_grading_locked if course.university else False)
        or is_semester_closed
        or semester_mismatch
    )
    course_credits = course.effective_credits

    return render(request, 'teacher/course_grades.html', {
        'course': course,
        'grades_list': grades_list,
        'students_count': len(grades_list),
        'is_locked': is_locked,
        'is_semester_closed': is_semester_closed,
        'semester_mismatch': semester_mismatch,
        'course_credits': course_credits,
    })


@login_required(login_url='/login/')
@dean_required
def manager_grades_approval(request):
    """Décanat — Gérer grilles (diagramme cas d'utilisation).

    Types : 1er semestre | 2ème semestre | annuelle.
    Pour S1 et S2 : session normale | rattrapage (étudiants en échec de la session normale).
    """
    from lms.models import Course, StudentAudit, Promotion, Faculty, User

    university = request.user.assigned_university
    faculty = request.user.assigned_faculty

    if not university or not faculty:
        messages.error(request, "Erreur : Profil Décanat invalide (université / faculté manquante).")
        return redirect('dean_dashboard')

    faculties = Faculty.objects.filter(id=faculty.id)
    promotions = Promotion.lmd_ordered(Promotion.objects.filter(faculty=faculty))

    promo_id = request.GET.get('promo_id')
    grille_type = (request.GET.get('grille_type') or '').strip().lower()
    session = (request.GET.get('session') or 'normale').strip().lower()

    # Compatibilité anciens liens ?semester=1|2
    legacy_semester = request.GET.get('semester')
    if not grille_type and legacy_semester:
        if str(legacy_semester) == '1':
            grille_type = 's1'
            session = 'normale'
        elif str(legacy_semester) == '2':
            grille_type = 'annual'
            session = 'normale'

    if grille_type not in ('s1', 's2', 'annual'):
        grille_type = None
    if session not in ('normale', 'rattrapage'):
        session = 'normale'
    if grille_type == 'annual':
        session = None  # pas de session pour la grille annuelle

    selected_promo = None
    courses = []
    students_data = []
    available_credits = 0
    can_transmit_annual = False
    show_annual_columns = False
    show_semester_columns = False
    grille_label = ''
    session_label = ''

    if promo_id and grille_type:
        selected_promo = get_object_or_404(Promotion, id=promo_id, faculty=faculty)

        s1_courses = list(
            Course.objects.filter(promotion=selected_promo, semester=1)
            .select_related('national_course', 'teacher')
            .order_by('title')
        )
        s2_courses = list(
            Course.objects.filter(promotion=selected_promo, semester=2)
            .select_related('national_course', 'teacher')
            .order_by('title')
        )

        if grille_type == 's1':
            courses = list(s1_courses)
            show_semester_columns = True
            can_transmit_annual = False
            grille_label = 'Grille 1er semestre'
        elif grille_type == 's2':
            courses = list(s2_courses)
            show_semester_columns = True
            can_transmit_annual = False
            grille_label = 'Grille 2ème semestre'
        else:  # annual
            courses = list(s1_courses) + list(s2_courses)
            show_annual_columns = True
            can_transmit_annual = bool(s1_courses or s2_courses)
            grille_label = 'Grille annuelle'

        if session == 'normale':
            session_label = 'Session normale'
        elif session == 'rattrapage':
            session_label = 'Session rattrapage'

        available_credits = sum(c.effective_credits for c in courses)

        students = User.objects.filter(
            role='STUDENT',
            class_group__promotion=selected_promo
        ).order_by('last_name', 'username')

        # Audits nécessaires : cours affichés + S1/S2 pour calculs crédits / filtre rattrapage
        course_ids_for_audits = (
            {c.id for c in s1_courses} | {c.id for c in s2_courses} | {c.id for c in courses}
        )

        audits = StudentAudit.objects.filter(
            course_id__in=course_ids_for_audits,
            status__in=DEAN_VISIBLE_AUDIT_STATUSES,
        ).select_related('course', 'course__national_course', 'student')

        audit_by_student = {}
        for a in audits:
            audit_by_student.setdefault(a.student_id, {})[a.course_id] = a

        def credits_for(student_audits, course_list):
            total = 0
            for c in course_list:
                audit = student_audits.get(c.id)
                if audit and audit.total >= 10:
                    total += c.effective_credits
            return total

        def course_row(c, student_audits):
            credits = c.effective_credits
            audit = student_audits.get(c.id)
            if audit:
                score = audit.total
                passed = score >= 10
                credit_got = credits if passed else 0
                return {
                    'course': c,
                    'audit': audit,
                    'score': score,
                    'credits': credits,
                    'credits_earned': credit_got,
                    'is_passed': passed,
                    'semester': c.semester,
                }
            return {
                'course': c,
                'audit': None,
                'score': None,
                'credits': credits,
                'credits_earned': 0,
                'is_passed': False,
                'semester': c.semester,
            }

        for student in students:
            student_audits = audit_by_student.get(student.id, {})
            student_courses = [course_row(c, student_audits) for c in courses]
            semester_credits_earned = sum(row['credits_earned'] for row in student_courses)

            s1_earned = credits_for(student_audits, s1_courses)
            s2_earned = credits_for(student_audits, s2_courses)
            year_earned = s1_earned + s2_earned

            if grille_type == 's1':
                is_success = s1_earned >= SEMESTER_CREDITS_REFERENCE
                result_label = 'Réussite S1' if is_success else 'Échec S1'
                focus_credits = s1_earned
            elif grille_type == 's2':
                is_success = s2_earned >= SEMESTER_CREDITS_REFERENCE
                result_label = 'Réussite S2' if is_success else 'Échec S2'
                focus_credits = s2_earned
            else:
                is_success = year_earned >= YEAR_CREDITS_REFERENCE
                result_label = 'Réussite' if is_success else 'Échec'
                focus_credits = year_earned

            # Rattrapage : uniquement les étudiants en échec de la session normale
            if session == 'rattrapage' and is_success:
                continue

            students_data.append({
                'student': student,
                'full_name': student.get_full_name() or student.username,
                'courses': student_courses,
                'semester_credits_earned': semester_credits_earned,
                's1_credits_earned': s1_earned,
                's2_credits_earned': s2_earned,
                'earned_credits': year_earned,
                'focus_credits': focus_credits,
                'semester_credits_total': SEMESTER_CREDITS_REFERENCE,
                'credits_total': YEAR_CREDITS_REFERENCE,
                'semester_credits_display': (
                    f"{semester_credits_earned}/{SEMESTER_CREDITS_REFERENCE} crédits"
                ),
                'credits_display': f"{year_earned}/{YEAR_CREDITS_REFERENCE} crédits obtenus",
                'result': result_label,
                'is_success': is_success,
                'faculty_name': faculty.name,
                'promotion_label': selected_promo.display_label,
            })

    success_count = sum(1 for item in students_data if item.get('is_success'))
    failure_count = max(0, len(students_data) - success_count)
    total_delib = len(students_data)
    success_rate = round((success_count / total_delib) * 100, 1) if total_delib else None
    failure_rate = round((failure_count / total_delib) * 100, 1) if total_delib else None

    # Alias pour templates / chart (compat)
    selected_semester = {'s1': 1, 's2': 2, 'annual': 2}.get(grille_type)

    return render(request, 'teacher/manager_grades.html', {
        'promotions': promotions,
        'faculties': faculties,
        'is_manager_view': False,
        'selected_promo': selected_promo,
        'selected_grille_type': grille_type,
        'selected_session': session,
        'selected_semester': selected_semester,
        'grille_label': grille_label,
        'session_label': session_label,
        'courses': courses,
        'students_data': students_data,
        'available_credits': available_credits,
        'credits_reference': YEAR_CREDITS_REFERENCE,
        'semester_credits_reference': SEMESTER_CREDITS_REFERENCE,
        'can_transmit_annual': can_transmit_annual,
        'success_count': success_count,
        'failure_count': failure_count,
        'success_rate': success_rate,
        'failure_rate': failure_rate,
        'show_annual_columns': show_annual_columns,
        'show_semester_columns': show_semester_columns,
    })


@login_required(login_url='/login/')
@manager_required
def manager_consolidated_results(request):
    """Manager : rapports annuels consolidés (S1/30 + S2/30 = total/60) uniquement."""
    from super_admin.models import FacultyReport, SemesterResultReport, UniversityReport

    university = request.user.assigned_university
    if not university:
        messages.error(request, "Erreur : Aucune université assignée à votre profil.")
        return redirect('manager_dashboard')

    reports = (
        SemesterResultReport.objects.filter(university=university)
        .select_related('faculty', 'promotion', 'submitted_by')
        .order_by('-submitted_at')
    )
    report_id = request.GET.get('report_id')
    selected_report = None
    lines = []
    if report_id:
        selected_report = get_object_or_404(
            SemesterResultReport.objects.select_related('faculty', 'promotion'),
            id=report_id,
            university=university,
        )
        lines = list(selected_report.lines.all())

    pending_faculty_reports_count = FacultyReport.objects.filter(
        university=university, is_validated=False
    ).count()
    latest_uni_report = (
        UniversityReport.objects.filter(university=university).order_by('-submitted_at').first()
    )

    return render(request, 'teacher/manager_consolidated_results.html', {
        'reports': reports,
        'selected_report': selected_report,
        'lines': lines,
        'credits_reference': YEAR_CREDITS_REFERENCE,
        'semester_credits_reference': SEMESTER_CREDITS_REFERENCE,
        'pending_faculty_reports_count': pending_faculty_reports_count,
        'latest_uni_report': latest_uni_report,
        'university': university,
    })


# ---------------------------------------------------------------------------
# TP (Travaux Pratiques) — Réception & Notation côté enseignant
# ---------------------------------------------------------------------------

@login_required(login_url='/login/')
@teacher_required
def assignment_inbox(request):
    """Vue principale des TPs de l'enseignant : liste par cours, toutes les soumissions."""
    from lms.models import Assignment, AssignmentSubmission

    teacher_promotions, selected_promotion = _get_selected_teacher_promotion(request, request.user)
    courses = _teacher_course_queryset(request.user, selected_promotion, published_only=True).order_by('title')
    
    # Construire la liste des TPs avec leurs soumissions
    assignments_data = []
    for course in courses:
        for assignment in Assignment.objects.filter(course=course).order_by('-created_at'):
            submissions = AssignmentSubmission.objects.filter(
                assignment=assignment
            ).select_related('student').order_by('-submitted_at')
            assignments_data.append({
                'assignment': assignment,
                'course': course,
                'submissions': submissions,
                'total': submissions.count(),
                'pending': submissions.filter(is_graded=False).count(),
            })

    return render(request, 'teacher/assignment_inbox.html', {
        'assignments_data': assignments_data,
        'courses': courses,
        'teacher_promotions': teacher_promotions,
        'current_promotion': selected_promotion,
    })


@login_required(login_url='/login/')
@teacher_required
def grade_submission(request, submission_id):
    """Attribuer une note à une soumission d'étudiant via AJAX ou POST."""
    from lms.models import AssignmentSubmission
    from django.utils import timezone

    submission = get_object_or_404(
        AssignmentSubmission,
        pk=submission_id,
        assignment__course__teacher=request.user
    )

    if request.method == 'POST':
        try:
            grade_val = float(request.POST.get('grade', 0))
            comment = request.POST.get('grade_comment', '').strip()
            if grade_val < 0 or grade_val > 20:
                messages.error(request, "La note doit être comprise entre 0 et 20.")
            else:
                submission.grade = grade_val
                submission.grade_comment = comment
                submission.is_graded = True
                submission.graded_at = timezone.now()
                submission.save()

                try:
                    from lms.firebase_admin_config import send_firebase_notification
                    send_firebase_notification(
                        user=submission.student,
                        title=f"TP Corrigé : {submission.assignment.title}",
                        message=f"Votre TP a été corrigé avec une note de {grade_val}/20.",
                        notif_type="TP_GRADED"
                    )
                except Exception:
                    pass

                messages.success(request, f"Note {grade_val}/20 attribuée à {submission.student.username}.")
        except (ValueError, TypeError):
            messages.error(request, "Valeur de note invalide.")

    return redirect('teacher_assignment_inbox')


@login_required(login_url='/login/')
@teacher_required
def create_assignment(request):
    """Créer un nouveau TP pour un cours de l'enseignant."""
    from lms.models import Assignment

    if request.method == 'POST':
        course_id = request.POST.get('course_id')
        title = request.POST.get('title', '').strip()
        description = request.POST.get('description', '').strip()
        due_date = request.POST.get('due_date') or None

        if not course_id or not title:
            messages.error(request, "Le cours et le titre sont obligatoires.")
            return redirect('teacher_assignment_inbox')

        course = get_object_or_404(Course, id=course_id, teacher=request.user)
        assignment = Assignment.objects.create(
            course=course,
            teacher=request.user,
            title=title,
            description=description,
            due_date=due_date,
        )

        try:
            from lms.firebase_admin_config import send_firebase_notification
            from lms.models import Enrollment
            from lms.visibility import affiliated_students_for_course

            # Inscrire / notifier tous les étudiants de la promotion du cours
            if course.promotion_id:
                recipients = list(affiliated_students_for_course(course))
                for student in recipients:
                    Enrollment.objects.get_or_create(student=student, course=course)
            else:
                recipients = [
                    e.student for e in Enrollment.objects.filter(course=course).select_related('student')
                ]

            for student in recipients:
                send_firebase_notification(
                    user=student,
                    title=f"Nouveau TP : {assignment.title}",
                    message=f"Un nouveau TP a été publié dans le cours {course.title}.",
                    notif_type="TP_NEW"
                )
        except Exception:
            pass

        messages.success(request, f"TP « {title} » créé avec succès pour le cours {course.title}.")

    return redirect('teacher_assignment_inbox')


@login_required(login_url='/login/')
@teacher_required
def delete_assignment(request, assignment_id):
    """Supprimer un TP existant."""
    from lms.models import Assignment
    assignment = get_object_or_404(Assignment, pk=assignment_id, teacher=request.user)
    assignment.delete()
    messages.success(request, f"TP « {assignment.title} » supprimé.")
    return redirect('teacher_assignment_inbox')


