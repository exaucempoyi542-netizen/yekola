"""
URL configuration for core project.
"""
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from django.shortcuts import redirect

from django.contrib import admin
from core.portal_auth import unified_login, unified_logout


def redirect_provincial_root(request):
    return redirect('/super-admin/')


def redirect_provincial_path(request, path=''):
    """Ancienne URL /provincial/… → module unifié /super-admin/…"""
    if path.startswith('login'):
        return redirect('/login/')
    return redirect(f'/super-admin/territorial/{path}')


urlpatterns = [
    path('admin/', admin.site.urls),
    path('login/', unified_login, name='unified_login'),
    path('logout/', unified_logout, name='unified_logout'),
    path('super-admin/', include('super_admin.urls')),
    path('provincial/', redirect_provincial_root),
    path('provincial/<path:path>', redirect_provincial_path),
    path('teacher/', include('teacher.urls')),
    path('api/', include('lms.urls')),
    path('', include('lms.urls')),
]

# Médias uploadés (PDF/vidéos) — volume Railway recommandé sur /app/media
from django.urls import re_path
from django.views.static import serve as media_serve

urlpatterns += [
    re_path(
        r'^media/(?P<path>.*)$',
        media_serve,
        {'document_root': str(settings.MEDIA_ROOT)},
    ),
]
