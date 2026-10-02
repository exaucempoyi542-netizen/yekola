from django.shortcuts import render, get_object_or_404
from rest_framework import viewsets, permissions, status, serializers
from rest_framework.response import Response
from rest_framework.decorators import action
from .models import Course, Lesson, Notification, CourseLike, CourseFavorite, CourseComment, LiveSession, Enrollment, User, TeacherFollow, ChatRoom, ChatMessage, Quiz, QuizQuestion, QuizChoice, QuizAttempt, ExternalResource, Assignment, AssignmentSubmission
from .serializers import CourseSerializer, CourseListSerializer, LessonSerializer, NotificationSerializer, CommentSerializer, LiveSessionSerializer, RegisterSerializer, UserSerializer, AdminUserSerializer, CreateTeacherSerializer, ChatRoomSerializer, ChatMessageSerializer, QuizSerializer, ExternalResourceSerializer, AssignmentSerializer, AssignmentSubmissionSerializer
import uuid
from django.utils import timezone
from rest_framework.views import APIView
from rest_framework.permissions import IsAdminUser

# JWT personnalisé : accepte email, username ou matricule comme identifiant
from rest_framework_simplejwt.views import TokenObtainPairView as BaseTokenObtainPairView
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from django.db.models import Q

class FlexTokenSerializer(TokenObtainPairSerializer):
    def validate(self, attrs):
        username_field = self.username_field  # 'username' par défaut
        credential = (attrs.get(username_field) or '').strip()
        password = attrs.get('password') or ''

        if credential:
            if '@' in credential:
                user_obj = User.objects.filter(email__iexact=credential).first()
            else:
                user_obj = User.objects.filter(
                    Q(username__iexact=credential) | Q(matricule__iexact=credential)
                ).first()
            if user_obj:
                attrs[username_field] = user_obj.username

        # Trim du mot de passe (espaces collés depuis le copier-coller mobile)
        attrs['password'] = password.strip() if isinstance(password, str) else password

        data = super().validate(attrs)
        user = self.user
        data['user'] = {
            'id': user.id,
            'username': user.username,
            'email': user.email or '',
            'role': user.role,
            'matricule': user.matricule or '',
            'profile_completed': user.profile_completed,
            'requires_email_setup': (
                user.role == 'STUDENT'
                and not user.profile_completed
                and not (user.email or '').strip()
            ),
        }
        return data

class CustomTokenObtainPairView(BaseTokenObtainPairView):
    """Endpoint JWT qui accepte username OU email comme identifiant."""
    serializer_class = FlexTokenSerializer


class FirebaseSyncTokenView(APIView):
    """
    Pont Firebase → JWT Django.
    Appelé après une connexion Firebase réussie : aligne le mot de passe Django
    si besoin, puis délivre access/refresh.
    """
    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    def post(self, request):
        from django.contrib.auth import authenticate
        from rest_framework_simplejwt.tokens import RefreshToken

        email = (request.data.get('email') or '').strip().lower()
        password = request.data.get('password') or ''
        firebase_uid = (request.data.get('firebase_uid') or '').strip()
        if not email or not password:
            return Response({'detail': 'email et password requis'}, status=status.HTTP_400_BAD_REQUEST)

        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            # Créer un profil Django minimal pour les comptes Firebase orphelins
            base = email.split('@')[0][:30] or 'user'
            username = base
            n = 1
            while User.objects.filter(username=username).exists():
                username = f'{base}{n}'
                n += 1
            user = User.objects.create_user(
                username=username,
                email=email,
                password=password,
                role='STUDENT',
            )
        else:
            authed = authenticate(username=user.username, password=password)
            if authed is None:
                # Firebase a déjà validé le couple e-mail/mdp → resync Django
                user.set_password(password)
                user.save(update_fields=['password'])

        if firebase_uid and user.firebase_uid != firebase_uid:
            user.firebase_uid = firebase_uid
            user.save(update_fields=['firebase_uid'])

        if not user.is_active:
            return Response({'detail': 'Compte désactivé'}, status=status.HTTP_403_FORBIDDEN)

        refresh = RefreshToken.for_user(user)
        return Response({
            'refresh': str(refresh),
            'access': str(refresh.access_token),
            'user': {
                'id': user.id,
                'username': user.username,
                'email': user.email,
                'role': user.role,
                'firebase_uid': user.firebase_uid,
            },
        })


class AdminStatsView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        total_users = User.objects.count()
        total_teachers = User.objects.filter(role='TEACHER').count()
        total_students = User.objects.filter(role='STUDENT').count()
        active_teachers = User.objects.filter(role='TEACHER', is_active=True).count()
        active_students = User.objects.filter(role='STUDENT', is_active=True).count()
        total_courses = Course.objects.count()
        published_quizzes = Quiz.objects.filter(is_published=True).count()
        total_resources = ExternalResource.objects.count()
        
        return Response({
            'total_users': total_users,
            'total_teachers': total_teachers,
            'total_students': total_students,
            'active_teachers': active_teachers,
            'active_students': active_students,
            'total_courses': total_courses,
            'published_quizzes': published_quizzes,
            'total_resources': total_resources,
        })

class IsTeacherOrAdmin(permissions.BasePermission):
    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        return request.user.role in ['TEACHER', 'ADMIN']

class StudentGradesView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        attempts = QuizAttempt.objects.filter(student=request.user).select_related('quiz__course')
        grades_data = [
            {
                'id': attempt.id,
                'course_id': attempt.quiz.course.id,
                'course_title': attempt.quiz.course.title,
                'score': float(attempt.score),
                'session': attempt.session,
                'date_graded': attempt.completed_at.strftime('%d/%m/%Y') if attempt.completed_at else attempt.started_at.strftime('%d/%m/%Y'),
            }
            for attempt in attempts
        ]
        return Response(grades_data)

class CourseViewSet(viewsets.ModelViewSet):
    queryset = Course.objects.all()
    serializer_class = CourseSerializer
    
    def get_permissions(self):
        # Catalogue : authentifié requis (visibilité limitée aux étudiants affiliés).
        if self.action in ['list', 'retrieve', 'comments']:
            permission_classes = [permissions.IsAuthenticated]
        elif self.action in ['toggle_like', 'toggle_favorite', 'add_comment', 'toggle_enroll']:
            permission_classes = [permissions.IsAuthenticated]
        else:
            permission_classes = [IsTeacherOrAdmin]
        return [permission() for permission in permission_classes]

    def get_serializer_class(self):
        if self.action == 'list':
            return CourseListSerializer
        return CourseSerializer

    def get_serializer_context(self):
        context = super().get_serializer_context()
        if self.action != 'list':
            return context

        user = self.request.user
        if not user or not user.is_authenticated:
            return context

        from .models import CourseLike, CourseFavorite, Enrollment, TeacherFollow, QuizAttempt

        # Précharge les flags utilisateur en 4 requêtes au lieu de N×4
        context['liked_course_ids'] = set(
            CourseLike.objects.filter(user=user).values_list('course_id', flat=True)
        )
        context['favorited_course_ids'] = set(
            CourseFavorite.objects.filter(user=user).values_list('course_id', flat=True)
        )
        context['enrolled_course_ids'] = set(
            Enrollment.objects.filter(student=user).values_list('course_id', flat=True)
        )
        context['followed_teacher_ids'] = set(
            TeacherFollow.objects.filter(student=user).values_list('teacher_id', flat=True)
        )

        # Prérequis : requêtes groupées (évite N+1)
        list_qs = self.filter_queryset(self.get_queryset())
        prereq_pairs = list(
            list_qs.exclude(prerequisite_quiz_id=None)
            .values_list('id', 'prerequisite_quiz_id')
        )
        if prereq_pairs:
            prereq_quiz_ids = {qid for _, qid in prereq_pairs}
            passed = set(
                QuizAttempt.objects.filter(
                    student=user,
                    quiz_id__in=prereq_quiz_ids,
                    score__gte=50,
                ).values_list('quiz_id', flat=True)
            )
            context['locked_by_prereq_ids'] = {
                course_id
                for course_id, quiz_id in prereq_pairs
                if quiz_id not in passed
            }
        else:
            context['locked_by_prereq_ids'] = set()
        return context

    def get_queryset(self):
        from django.db.models import Count, Prefetch
        from lms.visibility import visible_courses_queryset
        from .models import LiveSession

        user = self.request.user
        # Portail / debug enseignant : tous ses cours (publiés ou non)
        if (
            self.request.query_params.get('scope') == 'mine'
            and user.is_authenticated
            and getattr(user, 'role', None) == 'TEACHER'
        ):
            qs = (
                Course.objects.filter(teacher=user)
                .select_related('teacher', 'promotion', 'faculty', 'prerequisite_quiz')
                .order_by('-created_at')
            )
        else:
            # Étudiants : uniquement les cours publiés de leur promotion
            qs = visible_courses_queryset(user)

        if self.action == 'list':
            # Liste légère : Subquery pour les compteurs (évite COUNT+DISTINCT)
            from django.db.models import OuterRef, Subquery, IntegerField
            from django.db.models.functions import Coalesce
            from .models import Lesson, CourseLike

            lessons_sq = (
                Lesson.objects.filter(course_id=OuterRef('pk'))
                .order_by()
                .values('course_id')
                .annotate(c=Count('*'))
                .values('c')[:1]
            )
            likes_sq = (
                CourseLike.objects.filter(course_id=OuterRef('pk'))
                .order_by()
                .values('course_id')
                .annotate(c=Count('*'))
                .values('c')[:1]
            )
            return (
                qs.select_related('teacher', 'promotion', 'faculty', 'prerequisite_quiz')
                .annotate(
                    lessons_count=Coalesce(
                        Subquery(lessons_sq, output_field=IntegerField()), 0
                    ),
                    likes_count=Coalesce(
                        Subquery(likes_sq, output_field=IntegerField()), 0
                    ),
                )
                .prefetch_related(
                    Prefetch(
                        'live_sessions',
                        queryset=LiveSession.objects.filter(is_active=True),
                    )
                )
            )

        return qs.prefetch_related(
            'lessons', 'quizzes', 'likes', 'favorited_by', 'live_sessions', 'enrollments'
        )

    def perform_create(self, serializer):
        # Les cours sont affectés uniquement par le décanat (portail web).
        from rest_framework.exceptions import PermissionDenied
        raise PermissionDenied(
            "La création de cours est réservée au décanat. "
            "Attendez l'affectation d'un cours avant de publier du contenu."
        )

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def toggle_like(self, request, pk=None):
        course = self.get_object()
        from .models import CourseLike
        like, created = CourseLike.objects.get_or_create(user=request.user, course=course)
        if not created:
            like.delete()
            return Response({'status': 'unliked'}, status=status.HTTP_200_OK)
        return Response({'status': 'liked'}, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def toggle_favorite(self, request, pk=None):
        course = self.get_object()
        from .models import CourseFavorite
        favorite, created = CourseFavorite.objects.get_or_create(user=request.user, course=course)
        if not created:
            favorite.delete()
            return Response({'status': 'unfavorited'}, status=status.HTTP_200_OK)
        return Response({'status': 'favorited'}, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def toggle_enroll(self, request, pk=None):
        course = self.get_object()
        from .models import Enrollment, Notification
        enrollment, created = Enrollment.objects.get_or_create(student=request.user, course=course)
        
        if not created:
            enrollment.delete()
            return Response({'status': 'unfollowed'}, status=status.HTTP_200_OK)
        
        # Notify Teacher
        if course.teacher_id:
            Notification.objects.create(
                user=course.teacher,
                title="Nouvel abonné !",
                message=f"{request.user.username} a commencé à suivre votre cours: {course.title}.",
                type='system'
            )
        
        return Response({'status': 'followed'}, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def update_progress(self, request, pk=None):
        course = self.get_object()
        progress = request.data.get('progress')
        if progress is None:
            return Response({'error': 'Progress value is required'}, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            progress_val = float(progress)
            if not (0 <= progress_val <= 100):
                return Response({'error': 'Progress must be between 0 and 100'}, status=status.HTTP_400_BAD_REQUEST)
        except ValueError:
            return Response({'error': 'Invalid progress value'}, status=status.HTTP_400_BAD_REQUEST)
            
        enrollment = Enrollment.objects.filter(student=request.user, course=course).first()
        if not enrollment:
            return Response({'error': 'Not enrolled in this course'}, status=status.HTTP_400_BAD_REQUEST)
            
        enrollment.progress = progress_val
        enrollment.save()
        return Response({'status': 'progress updated', 'progress': enrollment.progress}, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def add_comment(self, request, pk=None):
        course = self.get_object()
        content = request.data.get('content')
        parent_id = request.data.get('parent_id')
        if not content:
            return Response({'error': 'Content is required'}, status=status.HTTP_400_BAD_REQUEST)
        
        from .models import CourseComment, Notification
        from .serializers import CommentSerializer
        
        parent = None
        if parent_id:
            parent = get_object_or_404(CourseComment, id=parent_id, course=course)
            
        comment = CourseComment.objects.create(user=request.user, course=course, content=content, parent=parent)
        
        # Envoyer une notification à l'auteur du commentaire parent
        if parent and parent.user != request.user:
            Notification.objects.create(
                user=parent.user,
                title="Nouvelle réponse",
                message=f"{request.user.username} a répondu à votre commentaire sur {course.title}.",
                type='reply'
            )
            
        return Response(CommentSerializer(comment).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['get'], permission_classes=[permissions.IsAuthenticated])
    def comments(self, request, pk=None):
        course = self.get_object()
        from .serializers import CommentSerializer
        comments = course.comments.all()
        serializer = CommentSerializer(comments, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'], permission_classes=[IsTeacherOrAdmin])
    def start_live(self, request, pk=None):
        course = self.get_object()
        if course.teacher != request.user:
            return Response({'error': 'You are not the teacher of this course'}, status=status.HTTP_403_FORBIDDEN)
        
        # Close previous sessions
        LiveSession.objects.filter(course=course, is_active=True).update(is_active=False, ended_at=timezone.now())
        
        # Create new unique room
        room_name = f"EduRDC_{course.id}_{uuid.uuid4().hex[:8]}"
        live = LiveSession.objects.create(
            course=course,
            teacher=request.user,
            room_name=room_name
        )
        
        # Notify all enrolled students
        enrolled_students = User.objects.filter(enrollments__course=course)
        notifications = [
            Notification(
                user=student,
                title="🔴 DIRECT EN COURS",
                message=f"L'enseignant {request.user.username} a lancé un direct pour le cours: {course.title}.",
                type='system'
            ) for student in enrolled_students
        ]
        Notification.objects.bulk_create(notifications)
        
        return Response(LiveSessionSerializer(live).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[IsTeacherOrAdmin])
    def end_live(self, request, pk=None):
        course = self.get_object()
        LiveSession.objects.filter(course=course, teacher=request.user, is_active=True).update(
            is_active=False, 
            ended_at=timezone.now()
        )
        return Response({'status': 'live_ended'}, status=status.HTTP_200_OK)

class LessonViewSet(viewsets.ModelViewSet):
    queryset = Lesson.objects.all()
    serializer_class = LessonSerializer
    
    def get_permissions(self):
        if self.action in ['list', 'retrieve', 'comments']:
            permission_classes = [permissions.IsAuthenticated]
        elif self.action in ['toggle_like', 'toggle_favorite', 'add_comment']:
            permission_classes = [permissions.IsAuthenticated]
        else:
            permission_classes = [IsTeacherOrAdmin]
        return [permission() for permission in permission_classes]

    def get_queryset(self):
        from lms.visibility import visible_lessons_queryset
        return visible_lessons_queryset(self.request.user)

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        user = request.user
        
        # Logique de verrouillage (identique au serializer)
        if user.is_authenticated and user.role == 'STUDENT':
            # Si c'est la première leçon, elle est ouverte
            first_order = instance.course.lessons.values_list('order', flat=True).order_by('order').first()
            if instance.order > first_order:
                # Vérifier les quiz précédents
                previous_quizzes = instance.course.quizzes.filter(is_published=True, order__lt=instance.order)
                for quiz in previous_quizzes:
                    best_attempt = quiz.attempts.filter(student=user).order_by('-score').first()
                    if not best_attempt or best_attempt.score < 50:
                        return Response({
                            'detail': 'Cette leçon est verrouillée. Vous devez réussir le quiz précédent avec au moins 50% pour y accéder.',
                            'is_locked': True
                        }, status=status.HTTP_403_FORBIDDEN)
        
        serializer = self.get_serializer(instance)
        return Response(serializer.data)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def toggle_like(self, request, pk=None):
        lesson = self.get_object()
        from .models import LessonLike
        like, created = LessonLike.objects.get_or_create(user=request.user, lesson=lesson)
        if not created:
            like.delete()
            return Response({'status': 'unliked'}, status=status.HTTP_200_OK)
        return Response({'status': 'liked'}, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def toggle_favorite(self, request, pk=None):
        lesson = self.get_object()
        from .models import LessonFavorite
        fav, created = LessonFavorite.objects.get_or_create(user=request.user, lesson=lesson)
        if not created:
            fav.delete()
            return Response({'status': 'unfavorited'}, status=status.HTTP_200_OK)
        return Response({'status': 'favorited'}, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def add_comment(self, request, pk=None):
        lesson = self.get_object()
        content = request.data.get('content')
        parent_id = request.data.get('parent_id')
        if not content:
            return Response({'error': 'Content is required'}, status=status.HTTP_400_BAD_REQUEST)
        
        from .models import LessonComment, Notification
        from .serializers import LessonCommentSerializer
        
        parent = None
        if parent_id:
            parent = get_object_or_404(LessonComment, id=parent_id, lesson=lesson)

        comment = LessonComment.objects.create(user=request.user, lesson=lesson, content=content, parent=parent)

        # Envoyer une notification à l'auteur du commentaire parent
        if parent and parent.user != request.user:
            Notification.objects.create(
                user=parent.user,
                title="Nouvelle réponse",
                message=f"{request.user.username} a répondu à votre commentaire sur la leçon {lesson.title}.",
                type='reply'
            )

        return Response(LessonCommentSerializer(comment).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['get'], permission_classes=[permissions.AllowAny])
    def comments(self, request, pk=None):
        lesson = self.get_object()
        from .serializers import LessonCommentSerializer
        comments = lesson.comments.all()
        serializer = LessonCommentSerializer(comments, many=True)
        return Response(serializer.data)

class NotificationViewSet(viewsets.ReadOnlyModelViewSet):
    """API sans authentification pour récupérer toutes les notifications globales."""
    queryset = Notification.objects.filter(user=None).order_by('-created_at')
    serializer_class = NotificationSerializer
    permission_classes = [permissions.AllowAny]

class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        return Response(
            {
                'detail': (
                    "L'inscription libre est désactivée. Votre compte est créé par le "
                    "décanat de votre faculté. Connectez-vous avec votre matricule."
                )
            },
            status=status.HTTP_403_FORBIDDEN,
        )

class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        qs = User.objects.filter(is_active=True)
        # Recherche chat : uniquement enseignants et étudiants
        search = self.request.query_params.get('search', '').strip()
        roles = self.request.query_params.get('roles', '').strip()
        chat_only = self.request.query_params.get('chat', '').lower() in ('1', 'true', 'yes')

        if chat_only or roles or search:
            allowed = ['TEACHER', 'STUDENT']
            if roles:
                allowed = [r.strip().upper() for r in roles.split(',') if r.strip()]
                allowed = [r for r in allowed if r in ('TEACHER', 'STUDENT')]
                if not allowed:
                    allowed = ['TEACHER', 'STUDENT']
            qs = qs.filter(role__in=allowed).exclude(id=self.request.user.id)
            if search:
                from django.db.models import Q
                qs = qs.filter(
                    Q(username__icontains=search)
                    | Q(email__icontains=search)
                    | Q(first_name__icontains=search)
                    | Q(last_name__icontains=search)
                )
            return qs.order_by('username')[:40]

        # Liste générale : admin uniquement (éviter d'exposer tous les comptes)
        if self.request.user.is_superuser or getattr(self.request.user, 'role', None) == 'SUPER_ADMIN':
            return qs.order_by('-date_joined')
        return User.objects.filter(id=self.request.user.id)

    @action(detail=False, methods=['get'], permission_classes=[permissions.IsAuthenticated])
    def me(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)

    @action(detail=False, methods=['post'], url_path='complete-profile')
    def complete_profile(self, request):
        """Première connexion étudiant : ajout de l'adresse Gmail."""
        user = request.user
        if user.role != 'STUDENT':
            return Response({'detail': 'Réservé aux étudiants.'}, status=status.HTTP_403_FORBIDDEN)

        email = (request.data.get('email') or '').strip().lower()
        if not email or '@' not in email:
            return Response({'detail': 'Adresse e-mail invalide.'}, status=status.HTTP_400_BAD_REQUEST)
        if not email.endswith('@gmail.com'):
            return Response(
                {'detail': 'Veuillez utiliser une adresse Gmail (@gmail.com).'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if User.objects.filter(email__iexact=email).exclude(pk=user.pk).exists():
            return Response({'detail': 'Cette adresse Gmail est déjà utilisée.'}, status=status.HTTP_400_BAD_REQUEST)

        user.email = email
        user.profile_completed = True
        user.save(update_fields=['email', 'profile_completed'])
        return Response(UserSerializer(user).data)

    @action(detail=False, methods=['post'], url_path='change-password')
    def change_password(self, request):
        """Changement de mot de passe (étudiant / utilisateur connecté)."""
        from django.conf import settings

        user = request.user
        old_password = request.data.get('old_password') or ''
        new_password = request.data.get('new_password') or ''
        min_len = getattr(settings, 'STUDENT_PASSWORD_MIN_LENGTH', 6)

        if not old_password or not new_password:
            return Response(
                {'detail': 'Ancien et nouveau mot de passe requis.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if len(new_password) < min_len:
            return Response(
                {'detail': f'Le nouveau mot de passe doit contenir au moins {min_len} caractères.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if old_password == new_password:
            return Response(
                {'detail': 'Le nouveau mot de passe doit être différent de l\'ancien.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not user.check_password(old_password):
            return Response(
                {'detail': 'Mot de passe actuel incorrect.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user.set_password(new_password)
        user.save(update_fields=['password'])
        return Response({'detail': 'Mot de passe mis à jour avec succès.'})

    @action(detail=False, methods=['get'], permission_classes=[permissions.IsAuthenticated])
    def student_stats(self, request):
        from django.db.models import Avg
        user = request.user
        
        # Enrolled courses stats
        enrollments = Enrollment.objects.filter(student=user)
        total_courses_enrolled = enrollments.count()
        completed_courses_count = enrollments.filter(progress__gte=100.0).count()
        in_progress_courses_count = enrollments.filter(progress__gt=0.0, progress__lt=100.0).count()
        
        avg_progress = enrollments.aggregate(avg=Avg('progress'))['avg'] or 0.0
        
        # Quiz attempts stats
        quiz_attempts = QuizAttempt.objects.filter(student=user)
        total_quizzes_attempted = quiz_attempts.count()
        avg_quiz_score = quiz_attempts.aggregate(avg=Avg('score'))['avg'] or 0.0
        
        # Quiz attempts details
        attempts_details = []
        for attempt in quiz_attempts.select_related('quiz', 'quiz__course').order_by('-completed_at'):
            attempts_details.append({
                'id': attempt.id,
                'quiz_id': attempt.quiz.id if attempt.quiz else None,
                'quiz_title': attempt.quiz.title if attempt.quiz else "Quiz supprimé",
                'course_title': attempt.quiz.course.title if attempt.quiz and attempt.quiz.course else "Cours supprimé",
                'score': float(attempt.score),
                'completed_at': attempt.completed_at.isoformat() if attempt.completed_at else None,
            })
            
        # Recent activities (can combine enrollments and quiz attempts)
        activities = []
        for enroll in enrollments.select_related('course').order_by('-enrolled_at')[:5]:
            if enroll.course:
                activities.append({
                    'type': 'enrollment',
                    'description': f"Inscription au cours : {enroll.course.title}",
                    'timestamp': enroll.enrolled_at.isoformat(),
                })
        for attempt in quiz_attempts.select_related('quiz').order_by('-completed_at')[:5]:
            if attempt.completed_at and attempt.quiz:
                activities.append({
                    'type': 'quiz',
                    'description': f"Tentative au quiz '{attempt.quiz.title}' avec un score de {attempt.score}%",
                    'timestamp': attempt.completed_at.isoformat(),
                })
        
        # Sort activities by timestamp desc
        activities.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
        activities = activities[:5]
        
        return Response({
            'total_courses_enrolled': total_courses_enrolled,
            'completed_courses_count': completed_courses_count,
            'in_progress_courses_count': in_progress_courses_count,
            'average_course_progress': float(avg_progress),
            'total_quizzes_attempted': total_quizzes_attempted,
            'average_quiz_score': float(avg_quiz_score),
            'quiz_attempts': attempts_details,
            'recent_activities': activities,
        })

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def toggle_follow(self, request, pk=None):
        teacher = self.get_object()
        if teacher.role != 'TEACHER':
            return Response({'error': 'You can only follow teachers'}, status=status.HTTP_400_BAD_REQUEST)
        
        follow, created = TeacherFollow.objects.get_or_create(student=request.user, teacher=teacher)
        if not created:
            follow.delete()
            return Response({'status': 'unfollowed'}, status=status.HTTP_200_OK)
        return Response({'status': 'followed'}, status=status.HTTP_201_CREATED)

    # --- ADMIN: Activer / Désactiver un compte ---
    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated, IsAdminUser])
    def toggle_active(self, request, pk=None):
        user = self.get_object()
        user.is_active = not user.is_active
        user.save()
        return Response({
            'status': 'activated' if user.is_active else 'deactivated',
            'is_active': user.is_active,
            'user_id': user.id,
            'username': user.username,
        })

    # --- ADMIN: Lister les enseignants ---
    @action(detail=False, methods=['get'], permission_classes=[permissions.IsAuthenticated, IsAdminUser])
    def teachers(self, request):
        teachers = User.objects.filter(role='TEACHER').order_by('-date_joined')
        serializer = AdminUserSerializer(teachers, many=True)
        return Response(serializer.data)

    # --- ADMIN: Lister les étudiants ---
    @action(detail=False, methods=['get'], permission_classes=[permissions.IsAuthenticated, IsAdminUser])
    def students(self, request):
        students = User.objects.filter(role='STUDENT').order_by('-date_joined')
        serializer = AdminUserSerializer(students, many=True)
        return Response(serializer.data)

    # --- ADMIN: Créer un compte enseignant ---
    @action(detail=False, methods=['post'], permission_classes=[permissions.IsAuthenticated, IsAdminUser])
    def create_teacher(self, request):
        serializer = CreateTeacherSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.save()
            return Response(AdminUserSerializer(user).data, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class ChatRoomViewSet(viewsets.ModelViewSet):
    serializer_class = ChatRoomSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return ChatRoom.objects.filter(participants=self.request.user).order_by('-created_at')

    @action(detail=False, methods=['post'])
    def get_or_create_direct_room(self, request):
        other_user_id = request.data.get('user_id')
        if not other_user_id:
            return Response({'error': 'user_id is required'}, status=400)
        
        other_user = get_object_or_404(User, id=other_user_id)
        if other_user.role not in ('TEACHER', 'STUDENT') or request.user.role not in ('TEACHER', 'STUDENT'):
            return Response(
                {'error': 'Le chat est réservé aux enseignants et aux étudiants.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        # Look for existing 1-to-1 room
        room = ChatRoom.objects.filter(is_group=False, participants=request.user).filter(participants=other_user).first()
        
        if not room:
            room = ChatRoom.objects.create(is_group=False)
            room.participants.add(request.user, other_user)
            
        return Response(ChatRoomSerializer(room).data)

class ChatMessageViewSet(viewsets.ModelViewSet):
    serializer_class = ChatMessageSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        room_id = self.request.query_params.get('room_id')
        if room_id:
            return ChatMessage.objects.filter(room_id=room_id, room__participants=self.request.user)
        return ChatMessage.objects.none()

    def perform_create(self, serializer):
        room = serializer.validated_data.get('room')
        if room and self.request.user in room.participants.all():
            serializer.save(sender=self.request.user)
        else:
            raise serializers.ValidationError("Vous n'êtes pas participant de ce salon.")

class QuizViewSet(viewsets.ReadOnlyModelViewSet):
    from .models import Quiz
    queryset = Quiz.objects.filter(is_published=True)
    serializer_class = QuizSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        from lms.visibility import visible_quizzes_queryset
        return visible_quizzes_queryset(self.request.user)

    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        from django.utils import timezone
        from lms.models import QuizAttempt
        quiz = self.get_object()

        # (Note: Le verrouillage is_grading_locked ne doit pas s'appliquer 
        # aux quiz d'apprentissage automatiques des étudiants)

        # --- GARDE : supprimée pour permettre des tentatives illimitées ---
        # existing = QuizAttempt.objects.filter(quiz=quiz, student=student).first()
        # if existing: ...

        answers = request.data.get('answers', [])
        total_questions = quiz.questions.count()
        total_points = sum(q.points for q in quiz.questions.all())
        earned_points = 0
        correct_count = 0
        
        for q in quiz.questions.all():
            student_answer = next((a for a in answers if a.get('question_id') == q.id), None)
            if student_answer:
                choice_id = student_answer.get('choice_id')
                if q.choices.filter(id=choice_id, is_correct=True).exists():
                    earned_points += q.points
                    correct_count += 1
                    
        score_percentage = round((earned_points / total_points * 100), 2) if total_points > 0 else 0.0
        
        QuizAttempt.objects.create(
            quiz=quiz,
            student=request.user,
            score=score_percentage,
            completed_at=timezone.now()
        )
        
        return Response({
            'score': float(score_percentage),
            'correct_count': correct_count,
            'total_questions': total_questions,
            'earned_points': earned_points,
            'total_points': total_points
        })
def quiz_share_view(request, id_code):
    quiz = get_object_or_404(Quiz, id_code=id_code, is_published=True)
    return render(request, 'lms/quiz_share.html', {'quiz': quiz})

class ExternalResourceViewSet(viewsets.ReadOnlyModelViewSet):
    """Ressources externes désactivées côté portail étudiant."""
    queryset = ExternalResource.objects.none()
    serializer_class = ExternalResourceSerializer
    permission_classes = [permissions.AllowAny]


class AssignmentViewSet(viewsets.ModelViewSet):
    """Gestion des TPs : création par enseignant, soumission et correction."""
    serializer_class = AssignmentSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        course_id = self.request.query_params.get('course_id')
        qs = Assignment.objects.select_related('course', 'teacher')
        if course_id:
            qs = qs.filter(course_id=course_id)
        if user.role == 'TEACHER':
            return qs.filter(teacher=user)
        elif user.role == 'STUDENT':
            # L'étudiant voit les TPs des cours auxquels il est inscrit
            enrolled_course_ids = Enrollment.objects.filter(student=user).values_list('course_id', flat=True)
            return qs.filter(course_id__in=enrolled_course_ids)
        return qs

    def perform_create(self, serializer):
        assignment = serializer.save(teacher=self.request.user)
        # Envoyer une notification Firestore à tous les étudiants inscrits au cours
        try:
            from .firebase_admin_config import send_firebase_notification
            from .models import Enrollment
            enrollments = Enrollment.objects.filter(course=assignment.course).select_related('student')
            for enroll in enrollments:
                send_firebase_notification(
                    user=enroll.student,
                    title=f"Nouveau TP : {assignment.title}",
                    message=f"Un nouveau TP a été publié dans le cours {assignment.course.title}.",
                    notif_type="TP_NEW"
                )
        except Exception as e:
            pass

    @action(detail=True, methods=['post'], url_path='submit')
    def submit(self, request, pk=None):
        """Soumission d'un fichier TP par l'étudiant."""
        assignment = self.get_object()
        if request.user.role != 'STUDENT':
            return Response({'error': 'Seuls les étudiants peuvent soumettre un TP.'}, status=status.HTTP_403_FORBIDDEN)

        existing = AssignmentSubmission.objects.filter(assignment=assignment, student=request.user).first()
        if existing and existing.is_graded:
            return Response({'error': 'Ce TP a déjà été corrigé. Vous ne pouvez plus le modifier.'}, status=status.HTTP_400_BAD_REQUEST)

        file = request.FILES.get('file')
        if not file:
            return Response({'error': 'Aucun fichier fourni.'}, status=status.HTTP_400_BAD_REQUEST)

        if existing:
            existing.file = file
            existing.submitted_at = timezone.now()
            existing.save()
            sub = existing
        else:
            sub = AssignmentSubmission.objects.create(
                assignment=assignment,
                student=request.user,
                file=file
            )

        serializer = AssignmentSubmissionSerializer(sub, context={'request': request})
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], url_path='grade/(?P<submission_id>[0-9]+)')
    def grade(self, request, pk=None, submission_id=None):
        """Correction et attribution de note par l'enseignant."""
        assignment = self.get_object()
        if request.user.role not in ['TEACHER', 'MANAGER', 'SUPER_ADMIN']:
            return Response({'error': 'Permission refusée.'}, status=status.HTTP_403_FORBIDDEN)

        sub = get_object_or_404(AssignmentSubmission, id=submission_id, assignment=assignment)
        grade_val = request.data.get('grade')
        comment = request.data.get('grade_comment', '')

        if grade_val is None:
            return Response({'error': 'La note est requise.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            grade_decimal = float(grade_val)
            if not (0 <= grade_decimal <= 20):
                raise ValueError()
        except (ValueError, TypeError):
            return Response({'error': 'La note doit être un nombre entre 0 et 20.'}, status=status.HTTP_400_BAD_REQUEST)

        from django.utils import timezone as tz
        sub.grade = grade_decimal
        sub.grade_comment = comment
        sub.graded_at = tz.now()
        sub.is_graded = True
        sub.save()

        # Envoyer une notification Firestore à l'étudiant
        try:
            from .firebase_admin_config import send_firebase_notification
            send_firebase_notification(
                user=sub.student,
                title=f"TP Corrigé : {assignment.title}",
                message=f"Votre TP a été corrigé avec une note de {grade_decimal}/20.",
                notif_type="TP_GRADED"
            )
        except Exception as e:
            pass  # Ne pas bloquer la sauvegarde en cas de souci Firebase

        serializer = AssignmentSubmissionSerializer(sub, context={'request': request})
        return Response(serializer.data)


    @action(detail=False, methods=['get'], url_path='my-submissions')
    def my_submissions(self, request):
        """Liste de toutes les soumissions de l'étudiant connecté."""
        if request.user.role != 'STUDENT':
            return Response([], status=status.HTTP_200_OK)
        subs = AssignmentSubmission.objects.filter(student=request.user).select_related('assignment', 'assignment__course')
        serializer = AssignmentSubmissionSerializer(subs, many=True, context={'request': request})
        return Response(serializer.data)
