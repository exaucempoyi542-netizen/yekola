from django.urls import path

from . import views

from . import provincial_views as territorial



app_name = 'super_admin'



urlpatterns = [

    # Accueil + Auth (Ministère + Admin Provincial)
    path('', views.portal_index, name='portal_index'),
    path('login/', views.super_admin_login, name='login'),
    path('logout/', views.super_admin_logout, name='logout'),
    path('password/', views.change_password, name='change_password'),

    # Dashboard national
    path('dashboard/', views.super_admin_dashboard, name='dashboard'),



    # ---- Tutelle provinciale (même module, rôle PROVINCIAL_ADMIN) ----

    path('territorial/', territorial.territorial_dashboard, name='territorial_dashboard'),

    path('territorial/universities/', territorial.territorial_universities, name='territorial_universities'),

    path('territorial/universities/<int:pk>/', territorial.territorial_university_detail, name='territorial_university_detail'),

    path('territorial/structure/', territorial.territorial_manage_structure, name='territorial_manage_structure'),

    path('territorial/universities/add/', territorial.territorial_add_university, name='territorial_add_university'),

    path('territorial/universities/<int:pk>/delete/', territorial.territorial_delete_university, name='territorial_delete_university'),

    path('territorial/faculties/add/', territorial.territorial_add_faculty, name='territorial_add_faculty'),

    path('territorial/faculties/<int:pk>/delete/', territorial.territorial_delete_faculty, name='territorial_delete_faculty'),

    path('territorial/promotions/add/', territorial.territorial_add_promotion, name='territorial_add_promotion'),

    path('territorial/promotions/<int:pk>/delete/', territorial.territorial_delete_promotion, name='territorial_delete_promotion'),

    path('territorial/managers/add/', territorial.territorial_create_manager, name='territorial_create_manager'),

    path('territorial/managers/<int:pk>/toggle/', territorial.territorial_toggle_manager, name='territorial_toggle_manager'),

    path('territorial/reports/', territorial.territorial_reports, name='territorial_reports'),

    path('territorial/reports/consolidate/', territorial.territorial_consolidate, name='territorial_consolidate'),

    path('territorial/benchmark/', territorial.territorial_benchmark, name='territorial_benchmark'),

    path('territorial/alerts/', territorial.territorial_alerts, name='territorial_alerts'),

    path('territorial/alerts/<int:pk>/resolve/', territorial.territorial_resolve_alert, name='territorial_resolve_alert'),



    # Maquette

    path('maquette/', views.admin_manage_maquette, name='admin_manage_maquette'),

    path('maquette/faculties/add/', views.admin_add_national_faculty, name='admin_add_national_faculty'),

    path('maquette/add/', views.admin_add_national_course, name='admin_add_national_course'),

    path('maquette/<int:pk>/delete/', views.admin_delete_national_course, name='admin_delete_national_course'),



    # Structure

    path('structure/', views.admin_manage_structure, name='admin_manage_structure'),

    path('universities/add/', views.admin_add_university, name='admin_add_university'),

    path('universities/<int:pk>/delete/', views.admin_delete_university, name='admin_delete_university'),

    path('faculties/add/', views.admin_add_faculty, name='admin_add_faculty'),

    path('faculties/<int:pk>/delete/', views.admin_delete_faculty, name='admin_delete_faculty'),

    path('promotions/add/', views.admin_add_promotion, name='admin_add_promotion'),

    path('promotions/<int:pk>/delete/', views.admin_delete_promotion, name='admin_delete_promotion'),



    # Pilotage Provincial (vue nationale)

    path('provinces/', views.provincial_stats, name='provincial_stats'),

    path('provinces/api/', views.provincial_stats_api, name='provincial_stats_api'),

    path('provinces/<int:pk>/', views.province_detail, name='province_detail'),

    path('provinces/manage/', views.admin_manage_provinces, name='admin_manage_provinces'),

    path('provinces/add/', views.admin_add_province, name='admin_add_province'),



    # Rapports provinciaux → Ministère

    path('reports/', views.academic_reports, name='academic_reports'),

    path('reports/<int:report_id>/validate/', views.validate_academic_report, name='validate_academic_report'),



    # Gouvernance

    path('provincial-admins/', views.manage_provincial_admins, name='manage_provincial_admins'),

    path('provincial-admins/add/', views.create_provincial_admin, name='create_provincial_admin'),

    path('provincial-admins/<int:pk>/toggle/', views.toggle_provincial_admin, name='toggle_provincial_admin'),

    path('audit-logs/', views.audit_logs, name='audit_logs'),

]


