from django.shortcuts import redirect
from django.urls import reverse
from django.views.csrf import csrf_failure as django_csrf_failure


def csrf_failure(request, reason=""):
    """Après un CSRF sur un login : page fraîche au lieu du 403 Django."""
    path = request.path or ''
    if path.startswith('/super-admin/login') or path.startswith('/provincial/login'):
        return redirect(f"{reverse('super_admin:login')}?csrf_error=1")
    if path.startswith('/teacher/login'):
        return redirect(f"{reverse('teacher_login')}?csrf_error=1")
    return django_csrf_failure(request, reason=reason)
