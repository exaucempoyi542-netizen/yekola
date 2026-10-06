"""Vues de tutelle provinciale — module super_admin (même portail que le Ministère)."""
from datetime import timedelta

from django.contrib import messages
from django.contrib.auth.decorators import login_required, user_passes_test
from django.db.models import Count, Sum
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone

from lms.models import AuditLog, Course, Faculty, NationalCourse, NationalFaculty, Promotion, Province, University, User
from .models import ProvincialReport, SemesterResultReport, TerritorialAlert, UniversityReport

import json

LOGIN_URL = '/login/'


def is_provincial_admin(user):
    return user.is_authenticated and user.role == 'PROVINCIAL_ADMIN' and user.is_active


provincial_required = user_passes_test(is_provincial_admin, login_url=LOGIN_URL)


def _province_or_redirect(request):
    province = request.user.assigned_province
    if not province:
        messages.error(request, "Aucune province n'est assignée à votre compte. Contactez le Ministère.")
        return None
    return province


def _dedupe_open_alerts(province):
    """Supprime les doublons d'alertes ouvertes (même uni + type)."""
    seen = set()
    dup_ids = []
    qs = (
        TerritorialAlert.objects.filter(province=province, is_resolved=False)
        .order_by('id')
        .only('id', 'university_id', 'alert_type')
    )
    for alert in qs:
        key = (alert.university_id, alert.alert_type)
        if key in seen:
            dup_ids.append(alert.id)
        else:
            seen.add(key)
    if dup_ids:
        TerritorialAlert.objects.filter(id__in=dup_ids).delete()


def _ensure_alert(province, university, alert_type, title, message):
    """Crée une alerte ouverte si absente — tolère les doublons existants."""
    existing = (
        TerritorialAlert.objects.filter(
            province=province,
            university=university,
            alert_type=alert_type,
            is_resolved=False,
        )
        .order_by('id')
        .first()
    )
    if existing:
        return existing
    return TerritorialAlert.objects.create(
        province=province,
        university=university,
        alert_type=alert_type,
        title=title,
        message=message,
        is_resolved=False,
    )


def _scan_alerts(province):
    _dedupe_open_alerts(province)
    unis = University.objects.filter(province=province)
    for uni in unis:
        has_pending = UniversityReport.objects.filter(university=uni, is_validated=False).exists()
        has_recent = UniversityReport.objects.filter(
            university=uni,
            submitted_at__gte=timezone.now() - timedelta(days=365),
        ).exists()
        if not has_pending and not has_recent:
            _ensure_alert(
                province,
                uni,
                'REPORT_LATE',
                f"Rapport manquant — {uni.name}",
                "Aucun rapport annuel d'établissement déposé sur les 12 derniers mois.",
            )

        if not uni.s1_closed or not uni.s2_closed:
            _ensure_alert(
                province,
                uni,
                'SEMESTER_LOCK',
                f"Sessions ouvertes — {uni.name}",
                (
                    f"S1 {'ouvert' if not uni.s1_closed else 'clôturé'} · "
                    f"S2 {'ouvert' if not uni.s2_closed else 'clôturé'}."
                ),
            )

        latest = UniversityReport.objects.filter(university=uni).order_by('-submitted_at').first()
        if latest and latest.total_students > 0:
            fail_rate = (latest.failed_students / latest.total_students) * 100
            if fail_rate >= 60:
                _ensure_alert(
                    province,
                    uni,
                    'FAILURE_SPIKE',
                    f"Taux d'échec élevé — {uni.name}",
                    f"Taux d'échec observé : {fail_rate:.1f}% sur le dernier rapport.",
                )


def _territorial_structure_payload(province):
    universities = University.objects.filter(province=province).prefetch_related('faculties__promotions').order_by('name')
    managers = User.objects.filter(
        role='MANAGER',
        assigned_university__province=province,
    ).select_related('assigned_university').order_by('username')
    return {
        'province': province,
        'universities': universities,
        'managers': managers,
        'managers_suspended': managers.filter(is_active=False).count(),
        'national_faculties': NationalFaculty.objects.filter(is_active=True).order_by('name'),
    }


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_dashboard(request):
    from django.core.cache import cache

    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    universities = list(
        University.objects.filter(province=province).select_related('province').order_by('name')
    )
    uni_ids = [u.id for u in universities]
    total_unis = len(universities)

    pending_qs = UniversityReport.objects.filter(
        university_id__in=uni_ids, is_validated=False
    )
    pending_uni_ids = set(pending_qs.values_list('university_id', flat=True))
    submitted_count = len(pending_uni_ids)
    pending_unis = max(total_unis - submitted_count, 0)
    pending_reports = list(
        pending_qs.select_related('university', 'submitted_by').order_by('-submitted_at')[:40]
    )

    # Dernier rapport / uni — évite Count() sur des centaines de milliers d'étudiants
    latest_by_uni = {}
    for report in (
        UniversityReport.objects.filter(university_id__in=uni_ids)
        .order_by('-submitted_at')
        .iterator(chunk_size=200)
    ):
        if report.university_id not in latest_by_uni:
            latest_by_uni[report.university_id] = report

    # Enseignants : COUNT indexé + cache 10 min
    teacher_cache_key = f'territorial_teacher_counts_{province.pk}'
    teacher_counts = cache.get(teacher_cache_key)
    if not isinstance(teacher_counts, dict):
        teacher_counts = dict(
            User.objects.filter(
                role='TEACHER',
                assigned_university_id__in=uni_ids,
                is_active=True,
            )
            .values('assigned_university_id')
            .annotate(c=Count('id'))
            .values_list('assigned_university_id', 'c')
        )
        cache.set(teacher_cache_key, teacher_counts, 600)


    uni_stats = []
    total_students = 0
    for uni in universities:
        latest = latest_by_uni.get(uni.id)
        students = int(latest.total_students) if latest else 0
        total_students += students
        uni_stats.append({
            'university': uni,
            'students': students,
            'teachers': teacher_counts.get(uni.id, 0),
            'has_pending_report': uni.id in pending_uni_ids,
            'latest_report': latest,
            'success_rate': latest.success_rate if latest else None,
        })

    open_alerts_qs = TerritorialAlert.objects.filter(province=province, is_resolved=False)
    alerts_count = open_alerts_qs.count()
    open_alerts = list(open_alerts_qs.select_related('university')[:8])
    provincial_reports = list(
        ProvincialReport.objects.filter(province=province).order_by('-submitted_at')[:5]
    )

    return render(request, 'super_admin/territorial/dashboard.html', {
        'province': province,
        'total_unis': total_unis,
        'submitted_count': submitted_count,
        'pending_unis': pending_unis,
        'total_students': total_students,
        'pending_reports': pending_reports,
        'uni_stats': uni_stats,
        'open_alerts': open_alerts,
        'provincial_reports': provincial_reports,
        'alerts_count': alerts_count,
    })

@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_universities(request):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    universities = list(
        University.objects.filter(province=province).annotate(
            faculty_count=Count('faculties', distinct=True),
        ).order_by('name')
    )
    uni_ids = [u.id for u in universities]

    managers = {
        m.assigned_university_id: m
        for m in User.objects.filter(
            role='MANAGER',
            assigned_university_id__in=uni_ids,
            is_active=True,
        ).only('id', 'username', 'first_name', 'last_name', 'email', 'assigned_university_id')
    }
    from django.core.cache import cache
    teacher_cache_key = f'territorial_teacher_counts_{province.pk}'
    teacher_counts = cache.get(teacher_cache_key)
    if not isinstance(teacher_counts, dict):
        teacher_counts = dict(
            User.objects.filter(role='TEACHER', assigned_university_id__in=uni_ids)
            .values('assigned_university_id')
            .annotate(c=Count('id'))
            .values_list('assigned_university_id', 'c')
        )
        cache.set(teacher_cache_key, teacher_counts, 600)

    latest_by_uni = {}
    pending_uni_ids = set()
    validated_uni_ids = set()
    for report in (
        UniversityReport.objects.filter(university_id__in=uni_ids)
        .order_by('-submitted_at')
        .iterator(chunk_size=200)
    ):
        if report.university_id not in latest_by_uni:
            latest_by_uni[report.university_id] = report
        if not report.is_validated:
            pending_uni_ids.add(report.university_id)
        else:
            validated_uni_ids.add(report.university_id)

    rows = []
    managers_count = 0
    reports_received = 0
    reports_missing = 0
    for uni in universities:
        if uni.id in pending_uni_ids:
            report_status = 'submitted'
        elif uni.id in validated_uni_ids:
            report_status = 'validated'
        else:
            report_status = 'missing'

        manager = managers.get(uni.id)
        if manager:
            managers_count += 1
        if report_status == 'missing':
            reports_missing += 1
        else:
            reports_received += 1

        latest = latest_by_uni.get(uni.id)
        rows.append({
            'university': uni,
            'manager': manager,
            'students': int(latest.total_students) if latest else 0,
            'teachers': teacher_counts.get(uni.id, 0),
            'report_status': report_status,
        })
    return render(request, 'super_admin/territorial/universities.html', {
        'province': province,
        'rows': rows,
        'total_unis': len(rows),
        'managers_count': managers_count,
        'reports_received': reports_received,
        'reports_missing': reports_missing,
    })

@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_university_detail(request, pk):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    uni = get_object_or_404(University, pk=pk, province=province)

    if request.method == 'POST' and request.POST.get('action') == 'update_identity':
        address = request.POST.get('address', '').strip()
        phone = request.POST.get('phone', '').strip()
        email = request.POST.get('email', '').strip()
        capacity_raw = request.POST.get('capacity', '').strip()
        institution_type = request.POST.get('institution_type', uni.institution_type).strip() or uni.institution_type

        capacity = None
        if capacity_raw:
            try:
                capacity = max(0, int(capacity_raw))
            except ValueError:
                messages.error(request, "La capacité doit être un nombre entier.")
                return redirect('super_admin:territorial_university_detail', pk=uni.pk)

        if institution_type not in dict(University.INSTITUTION_TYPES):
            institution_type = uni.institution_type

        uni.address = address
        uni.phone = phone
        uni.email = email
        uni.capacity = capacity
        uni.institution_type = institution_type
        uni.save(update_fields=['address', 'phone', 'email', 'capacity', 'institution_type'])
        messages.success(request, "Identité de l'établissement mise à jour.")
        return redirect('super_admin:territorial_university_detail', pk=uni.pk)

    faculties = Faculty.objects.filter(university=uni).annotate(
        promo_count=Count('promotions', distinct=True),
        student_count=Count('promotions__classes__students', distinct=True),
    )
    reports = list(
        UniversityReport.objects.filter(university=uni).order_by('-submitted_at')[:12]
    )
    latest_report = reports[0] if reports else None

    # Effectifs : préférer le dernier rapport (évite COUNT massif)
    if latest_report and latest_report.total_students > 0:
        students = latest_report.total_students
        passed = latest_report.passed_students
        failed = latest_report.failed_students
        success_rate = latest_report.success_rate
        failure_rate = round(100 - success_rate, 1) if latest_report.total_students else None
    else:
        students = User.objects.filter(
            role='STUDENT',
            assigned_university=uni,
        ).count()
        if students == 0:
            students = User.objects.filter(
                role='STUDENT',
                class_group__promotion__faculty__university=uni,
            ).count()
        passed = failed = None
        success_rate = failure_rate = None

    teachers = User.objects.filter(
        role='TEACHER', assigned_university=uni, is_active=True
    ).count()

    # Évolution du taux de réussite par année académique (dernier rapport / année)
    chronologic = list(
        UniversityReport.objects.filter(university=uni).order_by('submitted_at')
    )
    by_year = {}
    for report in chronologic:
        by_year[report.academic_year] = report
    evolution_labels = list(by_year.keys())
    evolution_success = [by_year[y].success_rate for y in evolution_labels]
    evolution_failure = [
        round(100 - by_year[y].success_rate, 1) if by_year[y].total_students else 0
        for y in evolution_labels
    ]

    # Complément semestriel si disponible
    semester_rows = (
        SemesterResultReport.objects.filter(university=uni)
        .values('academic_year', 'semester')
        .annotate(
            total=Sum('total_students'),
            passed=Sum('passed_students'),
        )
        .order_by('academic_year', 'semester')
    )
    semester_labels = []
    semester_success = []
    for row in semester_rows:
        total = row['total'] or 0
        passed_n = row['passed'] or 0
        if row['semester']:
            label = f"{row['academic_year']} · S{row['semester']}"
        else:
            label = f"{row['academic_year']} · Annuel"
        semester_labels.append(label)
        semester_success.append(round((passed_n / total) * 100, 1) if total else 0)

    # Courbe affichée : semestres si assez de points, sinon années
    if len(semester_labels) >= 2:
        chart_labels = semester_labels
        chart_success = semester_success
        chart_mode = 'semestres'
    else:
        chart_labels = evolution_labels
        chart_success = evolution_success
        chart_mode = 'années'

    return render(request, 'super_admin/territorial/university_detail.html', {
        'province': province,
        'university': uni,
        'faculties': faculties,
        'reports': reports,
        'manager': uni.manager,
        'students': students,
        'teachers': teachers,
        'passed_students': passed,
        'failed_students': failed,
        'success_rate': success_rate,
        'failure_rate': failure_rate,
        'latest_report': latest_report,
        'chart_labels_json': json.dumps(chart_labels, ensure_ascii=False),
        'chart_success_json': json.dumps(chart_success),
        'chart_failure_json': json.dumps(
            [round(100 - s, 1) for s in chart_success] if chart_labels else []
        ),
        'chart_mode': chart_mode,
        'has_chart_data': len(chart_labels) > 0,
    })


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_manage_structure(request):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')
    return render(request, 'super_admin/territorial/structure_management.html', _territorial_structure_payload(province))


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_add_university(request):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    if request.method == 'POST':
        name = request.POST.get('name', '').strip()
        institution_type = request.POST.get('institution_type', 'PUBLIC').strip() or 'PUBLIC'
        if not name:
            messages.error(request, "Le nom de l'université est obligatoire.")
        else:
            uni, created = University.objects.get_or_create(
                name=name,
                province=province,
                defaults={'institution_type': institution_type},
            )
            if created:
                messages.success(request, f"Université « {name} » créée pour {province.name}.")
                AuditLog.objects.create(
                    user=request.user,
                    action='CREATE_UNIVERSITY',
                    details=f"Université '{name}' créée dans la province {province.name}.",
                    ip_address=request.META.get('REMOTE_ADDR'),
                )
            else:
                messages.warning(request, f"L'université « {name} » existe déjà dans votre province.")
    return redirect('super_admin:territorial_manage_structure')


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_delete_university(request, pk):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    uni = get_object_or_404(University, pk=pk, province=province)
    name = uni.name
    uni.delete()
    messages.success(request, f"Université « {name} » supprimée.")
    return redirect('super_admin:territorial_manage_structure')


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_add_faculty(request):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    if request.method == 'POST':
        university_id = request.POST.get('university_id')
        national_faculty_id = request.POST.get('national_faculty_id')
        if not university_id or not national_faculty_id:
            messages.error(request, "Université et faculté nationale sont obligatoires.")
        else:
            university = get_object_or_404(University, pk=university_id, province=province)
            national_faculty = get_object_or_404(NationalFaculty, pk=national_faculty_id, is_active=True)
            faculty, created = Faculty.objects.get_or_create(
                university=university,
                name=national_faculty.name,
                defaults={'national_faculty': national_faculty},
            )
            if created:
                messages.success(request, f"Faculté « {national_faculty.name} » ajoutée à {university.name}.")
            else:
                if not faculty.national_faculty_id:
                    faculty.national_faculty = national_faculty
                    faculty.save(update_fields=['national_faculty'])
                messages.warning(request, f"La faculté « {national_faculty.name} » existe déjà dans {university.name}.")
    return redirect('super_admin:territorial_manage_structure')


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_delete_faculty(request, pk):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    faculty = get_object_or_404(Faculty, pk=pk, university__province=province)
    name = faculty.name
    faculty.delete()
    messages.success(request, f"Faculté « {name} » supprimée.")
    return redirect('super_admin:territorial_manage_structure')


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_add_promotion(request):
    """Crée la faculté si besoin, puis active le cycle LMD complet (L1→M2)."""
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    if request.method == 'POST':
        faculty_id = request.POST.get('faculty_id', '').strip()
        university_id = request.POST.get('university_id', '').strip()
        national_faculty_id = request.POST.get('national_faculty_id', '').strip()

        faculty = None
        if faculty_id:
            faculty = get_object_or_404(Faculty, pk=faculty_id, university__province=province)
        elif university_id and national_faculty_id:
            university = get_object_or_404(University, pk=university_id, province=province)
            national_faculty = get_object_or_404(NationalFaculty, pk=national_faculty_id, is_active=True)
            faculty, created_fac = Faculty.objects.get_or_create(
                university=university,
                name=national_faculty.name,
                defaults={'national_faculty': national_faculty},
            )
            if created_fac:
                messages.success(request, f"Faculté « {faculty.name} » créée dans {university.name}.")
            elif not faculty.national_faculty_id:
                faculty.national_faculty = national_faculty
                faculty.save(update_fields=['national_faculty'])
        else:
            messages.error(
                request,
                "Choisissez une université et une faculté nationale pour activer le LMD.",
            )
            return redirect('super_admin:territorial_manage_structure')

        created = Promotion.ensure_lmd_for_faculty(faculty)
        if created:
            messages.success(
                request,
                f"Cycle LMD activé pour « {faculty.name} » ({len(created)} niveau(x) : L1–M2).",
            )
        else:
            messages.info(request, f"Le cycle LMD est déjà actif pour « {faculty.name} ».")
    return redirect('super_admin:territorial_manage_structure')


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_delete_promotion(request, pk):
    """Désactive le cycle LMD d'une faculté (supprime tous les niveaux L1→M2)."""
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    faculty = get_object_or_404(Faculty, pk=pk, university__province=province)
    deleted_count, _ = faculty.promotions.all().delete()
    if deleted_count:
        messages.success(request, f"Cycle LMD désactivé pour « {faculty.name} ».")
    else:
        messages.info(request, f"Aucun cycle LMD à désactiver pour « {faculty.name} ».")
    return redirect('super_admin:territorial_manage_structure')


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_create_manager(request):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    if request.method != 'POST':
        return redirect('super_admin:territorial_manage_structure')

    username = request.POST.get('username', '').strip()
    email = request.POST.get('email', '').strip()
    password = request.POST.get('password', '').strip()
    first_name = request.POST.get('first_name', '').strip()
    last_name = request.POST.get('last_name', '').strip()
    university_id = request.POST.get('university_id')

    if not username or not password or not university_id:
        messages.error(request, "Identifiant, mot de passe et université sont obligatoires.")
        return redirect('super_admin:territorial_manage_structure')
    if User.objects.filter(username=username).exists():
        messages.error(request, "Ce nom d'utilisateur existe déjà.")
        return redirect('super_admin:territorial_manage_structure')
    if email and User.objects.filter(email__iexact=email).exists():
        messages.error(request, "Cette adresse email existe déjà.")
        return redirect('super_admin:territorial_manage_structure')

    university = get_object_or_404(University, pk=university_id, province=province)
    User.objects.create_user(
        username=username,
        email=email,
        password=password,
        first_name=first_name,
        last_name=last_name,
        role='MANAGER',
        assigned_university=university,
        is_active=True,
    )
    messages.success(request, f"Admin (Université) « {username} » créé pour {university.name}.")
    return redirect('super_admin:territorial_manage_structure')


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_toggle_manager(request, pk):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    manager = get_object_or_404(
        User,
        pk=pk,
        role='MANAGER',
        assigned_university__province=province,
    )
    manager.is_active = not manager.is_active
    manager.save(update_fields=['is_active'])
    state = "réactivé" if manager.is_active else "suspendu"
    messages.success(request, f"Compte admin (université) « {manager.username} » {state}.")
    return redirect('super_admin:territorial_manage_structure')


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_reports(request):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    pending = UniversityReport.objects.filter(
        university__province=province, is_validated=False
    ).select_related('university', 'submitted_by')
    history = ProvincialReport.objects.filter(province=province).order_by('-submitted_at')[:20]

    reception = []
    received_count = 0
    late_count = 0
    ok_count = 0
    for uni in University.objects.filter(province=province):
        pending_r = UniversityReport.objects.filter(university=uni, is_validated=False).first()
        recent = UniversityReport.objects.filter(
            university=uni,
            submitted_at__gte=timezone.now() - timedelta(days=365),
        ).exists()
        if pending_r:
            status = 'received'
            received_count += 1
        elif recent:
            status = 'ok'
            ok_count += 1
        else:
            status = 'late'
            late_count += 1
        reception.append({
            'university': uni,
            'pending': pending_r,
            'status': status,
        })

    return render(request, 'super_admin/territorial/reports.html', {
        'province': province,
        'pending': pending,
        'history': history,
        'reception': reception,
        'received_count': received_count,
        'late_count': late_count,
        'ok_count': ok_count,
        'pending_count': pending.count(),
    })


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_consolidate(request):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    if request.method != 'POST':
        return redirect('super_admin:territorial_reports')

    pending = UniversityReport.objects.filter(
        university__province=province, is_validated=False
    )
    if not pending.exists():
        messages.warning(request, "Aucun rapport d'établissement en attente à consolider.")
        return redirect('super_admin:territorial_reports')

    total_students = sum(r.total_students for r in pending)
    passed = sum(r.passed_students for r in pending)
    failed = sum(r.failed_students for r in pending)
    unis_reported = pending.values('university').distinct().count()
    total_unis = University.objects.filter(province=province).count()
    academic_year = f"{timezone.now().year - 1}-{timezone.now().year}"

    report = ProvincialReport.objects.create(
        title=f"Rapport Annuel Provincial — {province.name}",
        province=province,
        academic_year=academic_year,
        total_universities=total_unis,
        total_students=total_students,
        passed_students=passed,
        failed_students=failed,
        universities_reported=unis_reported,
        universities_pending=max(total_unis - unis_reported, 0),
        submitted_by=request.user,
    )
    pending.update(is_validated=True, validated_at=timezone.now())

    AuditLog.objects.create(
        user=request.user,
        action='SUBMIT_PROVINCIAL_REPORT',
        details=f"Rapport provincial {province.name} transmis au Ministère (id={report.id}).",
        ip_address=request.META.get('REMOTE_ADDR'),
    )
    messages.success(
        request,
        f"Rapport provincial consolidé et transmis au Ministère "
        f"({unis_reported} établissement(s), {total_students} étudiants).",
    )
    return redirect('super_admin:territorial_reports')


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_benchmark(request):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    rows = []
    for uni in University.objects.filter(province=province).order_by('name'):
        latest = UniversityReport.objects.filter(university=uni).order_by('-submitted_at').first()
        students = User.objects.filter(
            role='STUDENT', class_group__promotion__faculty__university=uni
        ).count()
        teachers = User.objects.filter(role='TEACHER', assigned_university=uni, is_active=True).count()
        ratio = round(students / teachers, 1) if teachers else None
        rows.append({
            'university': uni,
            'students': students,
            'teachers': teachers,
            'ratio': ratio,
            'success_rate': latest.success_rate if latest else None,
            'latest': latest,
        })

    rows_sorted = sorted(
        rows,
        key=lambda r: (r['success_rate'] is not None, r['success_rate'] or 0),
        reverse=True,
    )
    with_data = sum(1 for r in rows_sorted if r['success_rate'] is not None)
    return render(request, 'super_admin/territorial/benchmark.html', {
        'province': province,
        'rows': rows_sorted,
        'with_data': with_data,
        'no_data': len(rows_sorted) - with_data,
        'best_rate': rows_sorted[0]['success_rate'] if rows_sorted else None,
        'best_uni': rows_sorted[0]['university'].name if rows_sorted else None,
    })


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_alerts(request):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    _scan_alerts(province)
    return render(request, 'super_admin/territorial/alerts.html', {
        'province': province,
        'open_alerts': TerritorialAlert.objects.filter(province=province, is_resolved=False),
        'resolved': TerritorialAlert.objects.filter(province=province, is_resolved=True)[:20],
    })


@login_required(login_url=LOGIN_URL)
@provincial_required
def territorial_resolve_alert(request, pk):
    province = _province_or_redirect(request)
    if not province:
        return redirect('super_admin:logout')

    alert = get_object_or_404(TerritorialAlert, pk=pk, province=province)
    if request.method == 'POST':
        alert.is_resolved = True
        alert.resolved_at = timezone.now()
        alert.save(update_fields=['is_resolved', 'resolved_at'])
        messages.success(request, "Alerte marquée comme résolue.")
    return redirect('super_admin:territorial_alerts')
