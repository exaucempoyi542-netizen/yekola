"""Connexion / déconnexion unifiée Yekola — tous les rôles."""
from django.contrib.auth import authenticate, login, logout
from django.shortcuts import redirect, render
from django.views.decorators.cache import never_cache
from django.views.decorators.csrf import ensure_csrf_cookie


def redirect_after_login(user):
    """Envoie chaque rôle vers son tableau de bord."""
    if not user or not user.is_authenticated:
        return None
    role = getattr(user, 'role', None)
    if user.is_superuser or role == 'SUPER_ADMIN':
        return redirect('super_admin:dashboard')
    if role == 'PROVINCIAL_ADMIN':
        return redirect('super_admin:territorial_dashboard')
    if role == 'MANAGER':
        return redirect('manager_dashboard')
    if role == 'DEAN':
        return redirect('dean_dashboard')
    if role == 'TEACHER':
        return redirect('teacher_dashboard')
    return None


ALLOWED_PORTAL_ROLES = frozenset({
    'SUPER_ADMIN',
    'PROVINCIAL_ADMIN',
    'MANAGER',
    'DEAN',
    'TEACHER',
})


@never_cache
@ensure_csrf_cookie
def unified_login(request):
    """Une seule entrée pour Ministère, Province, Université, Décanat, Enseignant."""
    if request.user.is_authenticated:
        dest = redirect_after_login(request.user)
        if dest is not None:
            return dest
        logout(request)

    error = None
    if request.GET.get('csrf_error'):
        error = "Session de sécurité expirée. Rechargez la page puis reconnectez-vous."

    if request.method == 'POST':
        username = (request.POST.get('username') or '').strip()
        password = request.POST.get('password') or ''
        user = authenticate(request, username=username, password=password)
        if user:
            if not user.is_active:
                error = "Votre compte est désactivé. Contactez l'administrateur."
            elif user.is_superuser or getattr(user, 'role', None) in ALLOWED_PORTAL_ROLES:
                login(request, user)
                next_url = request.GET.get('next') or request.POST.get('next')
                if next_url and next_url.startswith('/') and not next_url.startswith('//'):
                    return redirect(next_url)
                dest = redirect_after_login(user)
                if dest is not None:
                    return dest
                error = "Aucun espace n'est associé à ce compte."
            else:
                error = "Ce compte n'a pas accès au portail Yekola."
        else:
            error = "Identifiants invalides. Veuillez réessayer."

    return render(request, 'portal/login.html', {
        'error': error,
        'next': request.GET.get('next', ''),
    })


def unified_logout(request):
    logout(request)
    return redirect('unified_login')
