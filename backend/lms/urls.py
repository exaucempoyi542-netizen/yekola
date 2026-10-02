from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from .views import (
    CourseViewSet, LessonViewSet, NotificationViewSet, RegisterView, UserViewSet, 
    ChatRoomViewSet, ChatMessageViewSet, QuizViewSet, quiz_share_view, AdminStatsView, 
    ExternalResourceViewSet, StudentGradesView, AssignmentViewSet, CustomTokenObtainPairView,
    FirebaseSyncTokenView,
)

router = DefaultRouter()
router.register(r'courses', CourseViewSet)
router.register(r'lessons', LessonViewSet)
router.register(r'notifications', NotificationViewSet)
router.register(r'users', UserViewSet)
router.register(r'chat-rooms', ChatRoomViewSet, basename='chat-room')
router.register(r'chat-messages', ChatMessageViewSet, basename='chat-message')
router.register(r'quizzes', QuizViewSet, basename='quiz')
router.register(r'external-resources', ExternalResourceViewSet, basename='external-resource')
router.register(r'assignments', AssignmentViewSet, basename='assignment')

urlpatterns = [
    path('', include(router.urls)),
    path('quizzes/<int:pk>/submit/', QuizViewSet.as_view({'post': 'submit'}), name='quiz_submit'),
    path('quiz/<uuid:id_code>/', quiz_share_view, name='quiz_share_link'),
    path('students/grades/', StudentGradesView.as_view(), name='student_grades'),
    path('admin/stats/', AdminStatsView.as_view(), name='admin_stats'),
    path('register/', RegisterView.as_view(), name='register'),
    path('token/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/firebase-sync/', FirebaseSyncTokenView.as_view(), name='token_firebase_sync'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
]
