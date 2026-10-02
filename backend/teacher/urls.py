from django.urls import path
from . import views

urlpatterns = [
    # Auth / portail
    path('', views.portal_index, name='teacher_portal_index'),
    path('login/', views.login_view, name='teacher_login'),
    path('logout/', views.logout_view, name='teacher_logout'),
    path('password/', views.change_password, name='teacher_change_password'),
    # --- Admin (Université) ---
    path('manager/', views.manager_dashboard, name='manager_dashboard'),
    path('manager/deans/create/', views.manager_create_dean, name='manager_create_dean'),
    path('manager/deans/<int:pk>/delete/', views.manager_delete_dean, name='manager_delete_dean'),
    path('manager/courses/create/', views.manager_create_course, name='manager_create_course'),
    path('manager/courses/assign-dean/', views.manager_assign_course_to_dean, name='manager_assign_course_to_dean'),
    path('manager/courses/<int:pk>/delete/', views.manager_delete_course, name='manager_delete_course'),
    path('manager/report/generate/', views.manager_generate_uni_report, name='manager_generate_uni_report'),
    path('manager/grades/', views.manager_consolidated_results, name='manager_grades_view'),
    path('manager/results/', views.manager_consolidated_results, name='manager_consolidated_results'),

    # --- Décanat : création / suppression de cours ---
    path('dean/courses/', views.dean_courses, name='dean_courses'),
    path('dean/courses/create/', views.dean_create_course, name='dean_create_course'),
    path('dean/courses/<int:pk>/delete/', views.dean_delete_course, name='dean_delete_course'),
    path('dean/students/', views.dean_students, name='dean_students'),
    path('dean/students/create/', views.dean_create_student, name='dean_create_student'),

    # --- Enseignant ---
    path('dashboard/', views.dashboard, name='teacher_dashboard'),
    
    # --- Décanat (Faculté) ---
    path('dean/', views.dean_dashboard, name='dean_dashboard'),
    path('dean/report/generate/', views.generate_academic_report, name='generate_academic_report'), # Generates FacultyReport
    path('dean/grades/', views.manager_grades_approval, name='manager_grades_approval'), # Renommable plus tard

    # Admin — Gestion des enseignants (Maintenant géré par le Décanat)
    path('dean/teachers/', views.dean_teachers, name='dean_teachers'),
    path('dean/teachers/', views.dean_teachers, name='teacher_admin_teachers'),
    path('dean/teachers/create/', views.admin_create_teacher, name='teacher_admin_create_teacher'),
    path('dean/teachers/assign-course/', views.admin_assign_course, name='admin_assign_course'),
    path('dean/teachers/<int:pk>/toggle/', views.admin_toggle_teacher, name='teacher_admin_toggle_teacher'),
    path('dean/teachers/<int:pk>/delete/', views.admin_delete_teacher, name='teacher_admin_delete_teacher'),
    path('dean/toggle-grading-lock/', views.manager_toggle_grading_lock, name='manager_toggle_grading_lock'),
    path('dean/toggle-semester-lock/<int:semester_num>/', views.manager_toggle_semester_lock, name='manager_toggle_semester_lock'),

    # (Structure management moved to super_admin)

    # Cours
    path('courses/new/', views.course_create, name='teacher_course_create'),
    path('courses/<int:course_id>/toggle-publish/', views.course_toggle_publish, name='teacher_course_toggle_publish'),
    path('courses/<int:course_id>/delete/', views.teacher_delete_course, name='teacher_course_delete'),
    path('courses/<int:course_id>/lessons/', views.lesson_management, name='teacher_lesson_management'),
    path('lessons/<int:lesson_id>/quiz/create/', views.lesson_create_quiz, name='teacher_lesson_create_quiz'),
    path('quizzes/<int:quiz_id>/edit/', views.quiz_edit, name='teacher_quiz_edit'),

    path('courses/<int:course_id>/enrollments/', views.course_enrollments, name='teacher_course_enrollments'),
    path('courses/<int:course_id>/grades/', views.course_grades_entry, name='teacher_course_grades'),

    # Commentaires & Chat
    path('comments/', views.comment_inbox, name='teacher_comments'),
    path('chat/', views.chat_inbox, name='teacher_chat_inbox'),
    path('chat/<int:room_id>/', views.chat_room, name='teacher_chat_room'),

    # Directs / Google Meet
    path('students/broadcast_meet/', views.teacher_broadcast_meet, name='teacher_broadcast_meet'),



    # Étudiants
    path('students/', views.teacher_students_dashboard, name='teacher_students_dashboard'),
    path('students/add/', views.teacher_add_student, name='teacher_add_student'),
    path('students/<int:student_id>/progress/', views.teacher_student_progress, name='teacher_student_progress'),
    path('students/update_audit/', views.teacher_update_audit, name='teacher_update_audit'),
    path('students/submit_audit/', views.teacher_submit_audit, name='teacher_submit_audit'),

    # TPs (Travaux Pratiques)
    path('assignments/', views.assignment_inbox, name='teacher_assignment_inbox'),
    path('assignments/create/', views.create_assignment, name='teacher_create_assignment'),
    path('assignments/<int:submission_id>/grade/', views.grade_submission, name='teacher_grade_submission'),
    path('assignments/<int:assignment_id>/delete/', views.delete_assignment, name='teacher_delete_assignment'),
]
