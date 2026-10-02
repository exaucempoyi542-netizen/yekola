from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required, user_passes_test
from django.contrib.auth import authenticate, login, logout
from django.contrib import messages
from django.http import JsonResponse
from django.views.decorators.csrf import ensure_csrf_cookie
from django.views.decorators.cache import never_cache
from lms.models import User, University, Faculty, Promotion, NationalCourse, NationalFaculty, AuditLog, Province, Grade, QuizAttempt
from django.db.models import Count, Avg, Q, Case, When, IntegerField
from django.db.models import FloatField, ExpressionWrapper
from django.core.cache import cache

# ---------------------------------------------------------------------------
# Permission helpers
# ---------------------------------------------------------------------------

def is_super_admin(user):
    return user.is_authenticated and (user.is_superuser or user.role == 'SUPER_ADMIN')

def is_staff_or_manager(user):
    return user.is_authenticated and (user.is_superuser or user.role in ['SUPER_ADMIN', 'MANAGER'])

super_admin_required = user_passes_test(is_super_admin, login_url='/login/')
staff_or_manager_required = user_passes_test(is_staff_or_manager, login_url='/login/')


def ensure_all_provinces():
    """Garantit les 26 provinces RDC en base."""
    created = 0
    for code, _label in Province.RDC_PROVINCES:
        _, was_created = Province.objects.get_or_create(code=code)
        if was_created:
            created += 1
    return created

# ---------------------------------------------------------------------------
# Super Admin Auth
# ---------------------------------------------------------------------------

def _redirect_admin_home(user):
    if is_super_admin(user):
        return redirect('super_admin:dashboard')
    if getattr(user, 'role', None) == 'PROVINCIAL_ADMIN':
        return redirect('super_admin:territorial_dashboard')
    return None


def portal_index(request):
    """Page d'accueil du portail Ministère / Admin provinciale."""
    if request.user.is_authenticated:
        dest = _redirect_admin_home(request.user)
        if dest is not None:
            return dest
        logout(request)
    return render(request, 'super_admin/index.html')


@never_cache
@ensure_csrf_cookie
def super_admin_login(request):
    """Ancienne URL /super-admin/login/ → connexion unique."""
    next_url = request.GET.get('next', '')
    if next_url:
        return redirect(f'/login/?next={next_url}')
    return redirect('unified_login')


def super_admin_logout(request):
    """Déconnexion — retour à la connexion unique."""
    logout(request)
    return redirect('unified_login')


@login_required(login_url='/login/')
def change_password(request):
    """Changement de mot de passe — Ministère et Admin Provincial."""
    from django.contrib.auth import update_session_auth_hash

    user = request.user
    if not (is_super_admin(user) or user.role == 'PROVINCIAL_ADMIN'):
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
            if user.role == 'PROVINCIAL_ADMIN':
                return redirect('super_admin:territorial_dashboard')
            return redirect('super_admin:dashboard')

    base_template = (
        'super_admin/territorial_base.html'
        if user.role == 'PROVINCIAL_ADMIN'
        else 'super_admin/base.html'
    )
    return render(request, 'super_admin/change_password.html', {
        'error': error,
        'base_template': base_template,
    })


# ---------------------------------------------------------------------------
# Strategic Dashboards
# ---------------------------------------------------------------------------

@login_required(login_url='/login/')
@super_admin_required
def super_admin_dashboard(request):
    """Dashboard de pilotage stratégique national (rapports provinciaux + KPI)."""
    from super_admin.models import ProvincialReport, UniversityReport, FacultyReport, TerritorialAlert

    cache_key = 'super_admin_dashboard_stats_v6'
    dashboard_data = cache.get(cache_key)

    if not dashboard_data:
        ensure_all_provinces()
        provinces = list(Province.objects.all().order_by('code'))
        provincial_reports = list(
            ProvincialReport.objects.select_related('province', 'submitted_by').order_by('-submitted_at')[:12]
        )

        province_rows = []
        success_sum = 0
        success_count = 0
        zone_counts = {'green': 0, 'orange': 0, 'red': 0, 'nodata': 0}
        evolution = []

        uni_counts = dict(
            University.objects.values('province_id')
            .annotate(c=Count('id'))
            .values_list('province_id', 'c')
        )
        # Effectifs issus des rapports (évite Count massif sur lms_user)
        for province in provinces:
            latest = (
                ProvincialReport.objects.filter(province=province)
                .order_by('-submitted_at')
                .first()
            )
            uni_count = uni_counts.get(province.id, 0)
            student_count = int(latest.total_students) if latest else 0

            if latest and latest.total_students > 0:
                rate = latest.success_rate
                fail_rate = round(100 - rate, 1)
                if rate >= 70:
                    zone = 'green'
                elif rate >= 50:
                    zone = 'orange'
                else:
                    zone = 'red'
                success_sum += rate
                success_count += 1
            else:
                rate = None
                fail_rate = None
                zone = 'nodata'

            zone_counts[zone] += 1
            province_rows.append({
                'id': province.id,
                'name': province.name,
                'code': province.code,
                'university_count': uni_count,
                'student_count': student_count,
                'success_rate': rate,
                'failure_rate': fail_rate,
                'zone': zone,
                'report_title': latest.title if latest else None,
                'report_validated': bool(latest and latest.is_validated),
                'submitted_at': latest.submitted_at.isoformat() if latest else None,
            })
        for report in reversed(list(ProvincialReport.objects.order_by('submitted_at')[:18])):
            evolution.append({
                'label': f"{report.province.name[:10]} · {report.submitted_at.strftime('%m/%y')}",
                'success_rate': report.success_rate,
                'students': report.total_students,
            })

        pending_provincial = ProvincialReport.objects.filter(is_validated=False).count()
        validated_provincial = ProvincialReport.objects.filter(is_validated=True).count()
        open_alerts = TerritorialAlert.objects.filter(is_resolved=False).count()

        national_success = round(success_sum / success_count, 1) if success_count else None
        national_failure = round(100 - national_success, 1) if national_success is not None else None

        institutions_stats = []
        sample_unis = list(University.objects.select_related('province').order_by('name')[:40])
        sample_ids = [u.id for u in sample_unis]
        latest_uni_map = {}
        for report in (
            UniversityReport.objects.filter(university_id__in=sample_ids)
            .order_by('-submitted_at')
            .iterator(chunk_size=100)
        ):
            if report.university_id not in latest_uni_map:
                latest_uni_map[report.university_id] = report
        for uni in sample_unis:
            latest_uni = latest_uni_map.get(uni.id)
            if latest_uni and latest_uni.total_students > 0:
                rate = latest_uni.success_rate
                status = 'success' if rate >= 50 else 'failure'
            else:
                rate = 0
                status = 'nodata'
            institutions_stats.append({
                'name': uni.name,
                'province': uni.province.name if uni.province else '—',
                'student_count': int(latest_uni.total_students) if latest_uni else 0,
                'avg_success_rate': rate,
                'report_status': status,
            })
        faculties_with_reports = FacultyReport.objects.values_list('faculty_id', flat=True).distinct()
        anomalies_count = Faculty.objects.exclude(id__in=faculties_with_reports).count()

        dashboard_data = {
            'institutions_data': institutions_stats,
            'province_rows': province_rows,
            'zone_counts': zone_counts,
            'evolution_data': evolution,
            'recent_reports': [
                {
                    'id': r.id,
                    'title': r.title,
                    'province': r.province.name,
                    'success_rate': r.success_rate,
                    'total_students': r.total_students,
                    'passed_students': r.passed_students,
                    'failed_students': r.failed_students,
                    'is_validated': r.is_validated,
                    'submitted_at': r.submitted_at.strftime('%d/%m/%Y'),
                }
                for r in provincial_reports
            ],
            'national_success': national_success,
            'national_failure': national_failure,
            'pending_provincial': pending_provincial,
            'validated_provincial': validated_provincial,
            'open_alerts': open_alerts,
            'anomalies_count': anomalies_count,
            'dropout_risk_count': zone_counts['red'],
            'critical_courses_count': anomalies_count,
            'total_universities': University.objects.count(),
            'total_provinces': len(provinces),
            'total_teachers': User.objects.filter(role='TEACHER').count(),
            'total_students': User.objects.filter(role='STUDENT').count(),
            'total_managers': User.objects.filter(role='MANAGER').count(),
            'total_deans': User.objects.filter(role='DEAN').count(),
            'maquette_count': NationalCourse.objects.filter(is_active=True).count(),
        }
        cache.set(cache_key, dashboard_data, 600)

    return render(request, 'super_admin/dashboard.html', dashboard_data)

# ---------------------------------------------------------------------------
# National Maquette Management
# ---------------------------------------------------------------------------

@login_required(login_url='/login/')
@super_admin_required
def admin_manage_maquette(request):
    """Pilotage des facultés nationales (référentiel pour les admins provinciaux)."""
    national_faculties = NationalFaculty.objects.filter(is_active=True).order_by('name')
    selected_faculty_id = request.GET.get('faculty', '')
    courses = NationalCourse.objects.filter(is_active=True).select_related('national_faculty')
    if selected_faculty_id:
        courses = courses.filter(national_faculty_id=selected_faculty_id)
    return render(request, 'super_admin/maquette_management.html', {
        'national_faculties': national_faculties,
        'courses': courses.order_by('national_faculty__name', 'code'),
        'selected_faculty_id': selected_faculty_id,
    })

@login_required(login_url='/login/')
@super_admin_required
def admin_add_national_faculty(request):
    if request.method != 'POST':
        return redirect('super_admin:admin_manage_maquette')

    name = request.POST.get('name', '').strip()
    code = request.POST.get('code', '').strip().upper()
    if not name:
        messages.error(request, "Le nom de la faculté nationale est obligatoire.")
        return redirect('super_admin:admin_manage_maquette')

    if not code:
        import re
        code = re.sub(r'[^A-Z0-9]+', '_', name.upper())[:40].strip('_') or 'FAC'

    base_code = code
    suffix = 1
    while NationalFaculty.objects.filter(code=code).exists():
        code = f"{base_code[:36]}_{suffix}"
        suffix += 1

    if NationalFaculty.objects.filter(name__iexact=name).exists():
        messages.warning(request, f"La faculté nationale « {name} » existe déjà.")
        return redirect('super_admin:admin_manage_maquette')

    NationalFaculty.objects.create(code=code, name=name, is_active=True)
    messages.success(request, f"Faculté nationale « {name} » créée.")
    AuditLog.objects.create(
        user=request.user,
        action='CREATE_NATIONAL_FACULTY',
        details=f"Faculté nationale '{name}' ({code}) créée.",
        ip_address=request.META.get('REMOTE_ADDR'),
    )
    return redirect('super_admin:admin_manage_maquette')

@login_required(login_url='/login/')
@super_admin_required
def admin_add_national_course(request):
    messages.error(request, "Action indisponible : la création des cours relève de l'Admin (Université).")
    return redirect('super_admin:dashboard')

@login_required(login_url='/login/')
@super_admin_required
def admin_delete_national_course(request, pk):
    messages.error(request, "Action indisponible : la gestion des cours relève de l'Admin (Université).")
    return redirect('super_admin:dashboard')

# ---------------------------------------------------------------------------
# Provincial Statistics Dashboard
# ---------------------------------------------------------------------------

def _compute_province_stats(selected_faculty=None):
    """
    Calcule les statistiques de performance par province.
    Affiche toujours les 26 provinces RDC.
    """
    ensure_all_provinces()
    all_provinces = list(Province.objects.all().order_by('code'))
    province_stats = []

    from super_admin.models import UniversityReport, FacultyReport

    uni_counts = {
        row['province_id']: row['n']
        for row in University.objects.values('province_id').annotate(n=Count('id'))
        if row['province_id']
    }

    # Effectifs étudiants (via assigned_university — plus rapide)
    if selected_faculty:
        student_qs = (
            User.objects.filter(
                role='STUDENT',
                assigned_faculty_id=selected_faculty,
                assigned_university__province_id__isnull=False,
            )
            .values('assigned_university__province_id')
            .annotate(n=Count('id'))
        )
        student_counts = {
            row['assigned_university__province_id']: row['n'] for row in student_qs
        }
    else:
        student_qs = (
            User.objects.filter(
                role='STUDENT',
                assigned_university__province_id__isnull=False,
            )
            .values('assigned_university__province_id')
            .annotate(n=Count('id'))
        )
        student_counts = {
            row['assigned_university__province_id']: row['n'] for row in student_qs
        }

    # Derniers rapports par université (une requête)
    latest_uni_reports = {}
    for rep in UniversityReport.objects.order_by('university_id', '-submitted_at'):
        if rep.university_id not in latest_uni_reports:
            latest_uni_reports[rep.university_id] = rep

    latest_fac_reports = {}
    if selected_faculty:
        for rep in FacultyReport.objects.filter(faculty_id=selected_faculty).order_by(
            'university_id', '-submitted_at'
        ):
            if rep.university_id not in latest_fac_reports:
                latest_fac_reports[rep.university_id] = rep

    unis_by_province = {}
    for uni in University.objects.filter(province_id__isnull=False).only('id', 'province_id'):
        unis_by_province.setdefault(uni.province_id, []).append(uni.id)

    for province in all_provinces:
        uni_ids = unis_by_province.get(province.id, [])
        total_evaluated = 0
        admitted_count = 0

        for uni_id in uni_ids:
            if selected_faculty:
                latest_rep = latest_fac_reports.get(uni_id)
            else:
                latest_rep = latest_uni_reports.get(uni_id)
            if latest_rep:
                total_evaluated += latest_rep.total_students
                admitted_count += latest_rep.passed_students

        success_rate = (
            round((admitted_count / total_evaluated * 100), 1) if total_evaluated > 0 else None
        )
        student_count = student_counts.get(province.id, 0)

        if success_rate is None:
            zone, zone_label, zone_emoji = 'nodata', 'Sans données', '⚪'
        elif success_rate >= 70:
            zone, zone_label, zone_emoji = 'green', 'Performante', '🟢'
        elif success_rate >= 50:
            zone, zone_label, zone_emoji = 'orange', 'Sous vigilance', '🟠'
        else:
            zone, zone_label, zone_emoji = 'red', 'En alerte', '🔴'

        province_stats.append({
            'province': province,
            'name': province.name,
            'university_count': uni_counts.get(province.id, 0),
            'student_count': student_count,
            'total_evaluated': total_evaluated,
            'admitted_count': admitted_count if total_evaluated > 0 else 0,
            'success_rate': success_rate,
            'zone': zone,
            'zone_label': zone_label,
            'zone_emoji': zone_emoji,
        })

    zone_order = {'red': 0, 'orange': 1, 'green': 2, 'nodata': 3}
    province_stats.sort(key=lambda x: (zone_order.get(x['zone'], 99), x['success_rate'] or 999))

    provinces_with_data = [p for p in province_stats if p['success_rate'] is not None]
    alert_count = sum(1 for p in provinces_with_data if p['zone'] == 'red')
    orange_count = sum(1 for p in provinces_with_data if p['zone'] == 'orange')
    green_count = sum(1 for p in provinces_with_data if p['zone'] == 'green')

    return {
        'province_stats': province_stats,
        'total_provinces': len(all_provinces),
        'alert_count': alert_count,
        'orange_count': orange_count,
        'green_count': green_count,
    }


@login_required(login_url='/login/')
@super_admin_required
def provincial_stats(request):
    """Dashboard géographique : Taux de réussite par province (RDC)."""
    selected_faculty = request.GET.get('faculty', '').strip() or None
    try:
        selected_faculty_int = int(selected_faculty) if selected_faculty else None
    except (ValueError, TypeError):
        selected_faculty_int = None

    cache_key = f'provincial_stats_v5_{selected_faculty or "all"}'
    cached_payload = cache.get(cache_key)

    if cached_payload:
        data = cached_payload
        from_cache = True
    else:
        data = _compute_province_stats(selected_faculty)
        # Ne pas mettre en cache les objets Province bruts : sérialiser d'abord
        cache.set(cache_key, {
            'province_stats': [
                {
                    'id': p['province'].pk,
                    'name': p['name'],
                    'code': p['province'].code,
                    'university_count': p['university_count'],
                    'student_count': p['student_count'],
                    'total_evaluated': p['total_evaluated'],
                    'admitted_count': p['admitted_count'],
                    'success_rate': p['success_rate'],
                    'zone': p['zone'],
                    'zone_label': p['zone_label'],
                    'zone_emoji': p['zone_emoji'],
                }
                for p in data['province_stats']
            ],
            'total_provinces': data['total_provinces'],
            'alert_count': data['alert_count'],
            'orange_count': data['orange_count'],
            'green_count': data['green_count'],
        }, 900)
        from_cache = False
        # Adapter au format template (province_stats avec objets)
        # data reste avec objets Province pour le rendu serveur
        pass

    # Si cache sérialisé, reconstruire pour le template
    if from_cache and data.get('province_stats') and isinstance(data['province_stats'][0], dict) and 'province' not in data['province_stats'][0]:
        by_code = {p.code: p for p in Province.objects.all()}
        rebuilt = []
        for row in data['province_stats']:
            prov = by_code.get(row['code'])
            if not prov:
                continue
            rebuilt.append({
                'province': prov,
                'name': row['name'],
                'university_count': row['university_count'],
                'student_count': row['student_count'],
                'total_evaluated': row.get('total_evaluated', 0),
                'admitted_count': row.get('admitted_count', 0),
                'success_rate': row['success_rate'],
                'zone': row['zone'],
                'zone_label': row['zone_label'],
                'zone_emoji': row['zone_emoji'],
            })
        data = {**data, 'province_stats': rebuilt}

    faculties_raw = Faculty.objects.all().values('id', 'name').order_by('name').distinct()
    all_faculties = [
        {'id': f['id'], 'name': f['name'], 'selected': (str(f['id']) == (selected_faculty or ''))}
        for f in faculties_raw
    ]

    return render(request, 'super_admin/provincial_stats.html', {
        **data,
        'all_faculties': all_faculties,
        'selected_faculty': selected_faculty,
        'selected_faculty_int': selected_faculty_int,
        'from_cache': from_cache,
    })


@login_required(login_url='/login/')
@super_admin_required
def provincial_stats_api(request):
    """API JSON pour le chargement asynchrone des stats provinciales."""
    selected_faculty = request.GET.get('faculty', '').strip() or None
    cache_key = f'provincial_stats_v5_{selected_faculty or "all"}'
    data = cache.get(cache_key)
    if not data:
        raw = _compute_province_stats(selected_faculty)
        data = {
            'province_stats': [
                {
                    'id': p['province'].pk,
                    'name': p['name'],
                    'code': p['province'].code,
                    'university_count': p['university_count'],
                    'student_count': p['student_count'],
                    'total_evaluated': p['total_evaluated'],
                    'admitted_count': p['admitted_count'],
                    'success_rate': p['success_rate'],
                    'zone': p['zone'],
                    'zone_label': p['zone_label'],
                    'zone_emoji': p['zone_emoji'],
                }
                for p in raw['province_stats']
            ],
            'total_provinces': raw['total_provinces'],
            'alert_count': raw['alert_count'],
            'orange_count': raw['orange_count'],
            'green_count': raw['green_count'],
        }
        cache.set(cache_key, data, 900)

    serialized = []
    for p in data['province_stats']:
        if isinstance(p, dict) and 'id' in p:
            serialized.append({
                'id': p['id'],
                'name': p['name'],
                'code': p['code'],
                'university_count': p['university_count'],
                'student_count': p['student_count'],
                'total_attempts': p.get('total_evaluated', 0),
                'success_rate': p['success_rate'],
                'zone': p['zone'],
                'zone_label': p['zone_label'],
                'zone_emoji': p.get('zone_emoji', ''),
            })
        else:
            serialized.append({
                'id': p['province'].pk,
                'name': p['name'],
                'code': p['province'].code,
                'university_count': p['university_count'],
                'student_count': p['student_count'],
                'total_attempts': p.get('total_evaluated', 0),
                'success_rate': p['success_rate'],
                'zone': p['zone'],
                'zone_label': p['zone_label'],
                'zone_emoji': p['zone_emoji'],
            })

    return JsonResponse({
        'provinces': serialized,
        'total_provinces': data['total_provinces'],
        'alert_count': data['alert_count'],
        'orange_count': data.get('orange_count', 0),
        'green_count': data['green_count'],
    })


@login_required(login_url='/login/')
@super_admin_required
def province_detail(request, pk):
    """Détail d'une province : KPI, courbe de réussite, liste des universités."""
    province = get_object_or_404(Province, pk=pk)
    from lms.models import Course
    from super_admin.models import UniversityReport, ProvincialReport
    import json

    universities_detail = []
    total_students = 0
    total_passed = 0
    total_failed = 0
    reports_count = 0

    for uni in province.universities.all():
        latest_report = UniversityReport.objects.filter(university=uni).order_by('-submitted_at').first()

        if latest_report and latest_report.total_students > 0:
            total_evaluated = latest_report.total_students
            passing = latest_report.passed_students
            rate = round((passing / total_evaluated * 100), 1)
            total_students += latest_report.total_students
            total_passed += latest_report.passed_students
            total_failed += latest_report.failed_students
            reports_count += 1
        else:
            total_evaluated = 0
            passing = 0
            rate = None

        active_courses = Course.objects.filter(university=uni, is_published=True).count()
        total_courses = Course.objects.filter(university=uni).count()

        if rate is None:
            zone = 'nodata'
        elif rate >= 70:
            zone = 'green'
        elif rate >= 50:
            zone = 'orange'
        else:
            zone = 'red'

        universities_detail.append({
            'university': uni,
            'total_evaluated': total_evaluated,
            'success_rate': rate,
            'zone': zone,
            'active_courses': active_courses,
            'total_courses': total_courses,
            'student_count': (latest_report.total_students if latest_report else 0),
        })

    universities_detail.sort(key=lambda x: (x['success_rate'] is None, x['success_rate'] or 999))

    success_rate = round((total_passed / total_students) * 100, 1) if total_students else None
    failure_rate = round(100 - success_rate, 1) if success_rate is not None else None

    # Courbe : rapports provinciaux dans le temps
    prov_reports = list(
        ProvincialReport.objects.filter(province=province).order_by('submitted_at')
    )
    by_year = {}
    for r in prov_reports:
        by_year[r.academic_year] = r
    if by_year:
        chart_labels = list(by_year.keys())
        chart_success = [by_year[y].success_rate for y in chart_labels]
    else:
        # fallback : moyenne des derniers rapports univ par année
        uni_reports = UniversityReport.objects.filter(
            university__province=province
        ).order_by('submitted_at')
        agg = {}
        for r in uni_reports:
            bucket = agg.setdefault(r.academic_year, {'t': 0, 'p': 0})
            bucket['t'] += r.total_students
            bucket['p'] += r.passed_students
        chart_labels = list(agg.keys())
        chart_success = [
            round((agg[y]['p'] / agg[y]['t']) * 100, 1) if agg[y]['t'] else 0
            for y in chart_labels
        ]

    return render(request, 'super_admin/province_detail.html', {
        'province': province,
        'universities_detail': universities_detail,
        'kpi_students': total_students,
        'kpi_passed': total_passed,
        'kpi_failed': total_failed,
        'kpi_success_rate': success_rate,
        'kpi_failure_rate': failure_rate,
        'kpi_universities': len(universities_detail),
        'kpi_reports': reports_count,
        'chart_labels_json': json.dumps(chart_labels, ensure_ascii=False),
        'chart_success_json': json.dumps(chart_success),
        'chart_failure_json': json.dumps(
            [round(100 - s, 1) for s in chart_success] if chart_labels else []
        ),
        'has_chart_data': len(chart_labels) > 0,
    })


# ---------------------------------------------------------------------------
# Province Management (Add/Delete from admin panel)
# ---------------------------------------------------------------------------

@login_required(login_url='/login/')
@super_admin_required
def admin_manage_provinces(request):
    ensure_all_provinces()
    provinces = Province.objects.all().order_by('code')
    return render(request, 'super_admin/province_management.html', {
        'provinces': provinces,
        'total_provinces': provinces.count(),
        'expected_provinces': len(Province.RDC_PROVINCES),
        'rdc_provinces': Province.RDC_PROVINCES,
    })


@login_required(login_url='/login/')
@super_admin_required
def admin_add_province(request):
    if request.method == 'POST':
        code = request.POST.get('code', '').strip().upper()
        valid_codes = {c for c, _ in Province.RDC_PROVINCES}
        if code in valid_codes:
            _, created = Province.objects.get_or_create(code=code)
            if created:
                messages.success(request, f"Province « {dict(Province.RDC_PROVINCES).get(code, code)} » ajoutée.")
            else:
                messages.info(request, "Cette province existe déjà.")
        else:
            # Synchroniser toutes les provinces manquantes
            n = ensure_all_provinces()
            if n:
                messages.success(request, f"{n} province(s) manquante(s) ajoutée(s). Total : 26.")
            else:
                messages.warning(request, "Code province invalide. Choisissez une province de la liste.")
    else:
        ensure_all_provinces()
    return redirect('super_admin:admin_manage_provinces')


@login_required(login_url='/login/')
@super_admin_required
def admin_manage_structure(request):
    messages.info(
        request,
        "La gestion des universités, facultés et promotions est désormais confiée aux Administrateurs Provinciaux."
    )
    return redirect('super_admin:dashboard')

@login_required(login_url='/login/')
@super_admin_required
def admin_add_university(request):
    messages.error(request, "Action indisponible : les universités sont gérées au niveau provincial.")
    return redirect('super_admin:dashboard')

@login_required(login_url='/login/')
@super_admin_required
def admin_delete_university(request, pk):
    messages.error(request, "Action indisponible : les universités sont gérées au niveau provincial.")
    return redirect('super_admin:dashboard')

@login_required(login_url='/login/')
@super_admin_required
def admin_add_faculty(request):
    messages.error(request, "Action indisponible : les facultés sont gérées au niveau provincial.")
    return redirect('super_admin:dashboard')

@login_required(login_url='/login/')
@super_admin_required
def admin_delete_faculty(request, pk):
    messages.error(request, "Action indisponible : les facultés sont gérées au niveau provincial.")
    return redirect('super_admin:dashboard')

@login_required(login_url='/login/')
@super_admin_required
def admin_add_promotion(request):
    messages.error(request, "Action indisponible : les promotions sont gérées au niveau provincial.")
    return redirect('super_admin:dashboard')

@login_required(login_url='/login/')
@super_admin_required
def admin_delete_promotion(request, pk):
    messages.error(request, "Action indisponible : les promotions sont gérées au niveau provincial.")
    return redirect('super_admin:dashboard')


# ---------------------------------------------------------------------------
# Reports Management
# ---------------------------------------------------------------------------

from .models import UniversityReport, ProvincialReport

@login_required(login_url='/login/')
@super_admin_required
def academic_reports(request):
    """Réception nationale : rapports provinciaux consolidés (plus les rapports univ. directs)."""
    reports = ProvincialReport.objects.select_related('province', 'submitted_by').order_by('-submitted_at')
    return render(request, 'super_admin/academic_reports.html', {'reports': reports})


@login_required(login_url='/login/')
@super_admin_required
def validate_academic_report(request, report_id):
    report = get_object_or_404(ProvincialReport, id=report_id)
    if request.method == 'POST':
        action = request.POST.get('action')
        from django.utils import timezone
        if action == 'validate':
            report.is_validated = True
            report.validated_at = timezone.now()
            report.save()
            messages.success(request, f"Le rapport provincial '{report.title}' a été validé.")
        elif action == 'reject':
            report.delete()
            messages.info(request, "Le rapport provincial a été rejeté et supprimé.")
    return redirect('super_admin:academic_reports')


@login_required(login_url='/login/')
@super_admin_required
def manage_provincial_admins(request):
    """Création / suspension des comptes Administrateurs Provinciaux (26 provinces)."""
    ensure_all_provinces()
    provinces = Province.objects.all().order_by('code')
    admins = User.objects.filter(role='PROVINCIAL_ADMIN').select_related('assigned_province').order_by('username')
    return render(request, 'super_admin/provincial_admins.html', {
        'provinces': provinces,
        'admins': admins,
    })


@login_required(login_url='/login/')
@super_admin_required
def create_provincial_admin(request):
    if request.method != 'POST':
        return redirect('super_admin:manage_provincial_admins')

    username = request.POST.get('username', '').strip()
    email = request.POST.get('email', '').strip()
    password = request.POST.get('password', '').strip()
    province_id = request.POST.get('province_id')
    first_name = request.POST.get('first_name', '').strip()
    last_name = request.POST.get('last_name', '').strip()

    if not username or not password or not province_id:
        messages.error(request, "Identifiant, mot de passe et province sont obligatoires.")
        return redirect('super_admin:manage_provincial_admins')

    if User.objects.filter(username=username).exists():
        messages.error(request, "Ce nom d'utilisateur existe déjà.")
        return redirect('super_admin:manage_provincial_admins')

    province = get_object_or_404(Province, id=province_id)
    User.objects.create_user(
        username=username,
        email=email,
        password=password,
        first_name=first_name,
        last_name=last_name,
        role='PROVINCIAL_ADMIN',
        assigned_province=province,
        is_active=True,
    )
    AuditLog.objects.create(
        user=request.user,
        action='CREATE_PROVINCIAL_ADMIN',
        details=f"Compte provincial '{username}' créé pour {province.name}.",
        ip_address=request.META.get('REMOTE_ADDR'),
    )
    messages.success(request, f"Administrateur provincial '{username}' créé pour {province.name}.")
    return redirect('super_admin:manage_provincial_admins')


@login_required(login_url='/login/')
@super_admin_required
def toggle_provincial_admin(request, pk):
    admin_user = get_object_or_404(User, pk=pk, role='PROVINCIAL_ADMIN')
    admin_user.is_active = not admin_user.is_active
    admin_user.save(update_fields=['is_active'])
    state = "réactivé" if admin_user.is_active else "suspendu"
    messages.success(request, f"Compte '{admin_user.username}' {state}.")
    AuditLog.objects.create(
        user=request.user,
        action='TOGGLE_PROVINCIAL_ADMIN',
        details=f"Compte '{admin_user.username}' {state}.",
        ip_address=request.META.get('REMOTE_ADDR'),
    )
    return redirect('super_admin:manage_provincial_admins')


@login_required(login_url='/login/')
@super_admin_required
def audit_logs(request):
    logs = AuditLog.objects.select_related('user').order_by('-timestamp')[:200]
    return render(request, 'super_admin/audit_logs.html', {'logs': logs})
