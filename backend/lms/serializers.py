from rest_framework import serializers
from .models import Course, Lesson, User, Notification, CourseLike, CourseComment, CourseFavorite, TeacherFollow, LessonComment, LessonLike, LessonFavorite, LiveSession, ChatRoom, ChatMessage, Quiz, QuizQuestion, QuizChoice, QuizAttempt, ExternalResource, Assignment, AssignmentSubmission

class UserSerializer(serializers.ModelSerializer):
    requires_email_setup = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'role', 'matricule', 'phone', 'is_active',
            'first_name', 'last_name', 'gender', 'date_joined', 'firebase_uid',
            'profile_completed', 'requires_email_setup',
        ]

    def get_requires_email_setup(self, obj):
        return (
            obj.role == 'STUDENT'
            and not obj.profile_completed
            and not (obj.email or '').strip()
        )

class AdminUserSerializer(serializers.ModelSerializer):
    """Serializer complet pour la gestion admin des utilisateurs."""
    class Meta:
        model = User
        fields = ['id', 'username', 'email', 'first_name', 'last_name', 'role', 'matricule', 'phone', 'is_active', 'date_joined']
        read_only_fields = ['date_joined']

class LessonCommentSerializer(serializers.ModelSerializer):
    username = serializers.ReadOnlyField(source='user.username')
    replies = serializers.SerializerMethodField()

    class Meta:
        model = LessonComment
        fields = ['id', 'user', 'username', 'content', 'created_at', 'parent', 'replies']
        read_only_fields = ['user']

    def get_replies(self, obj):
        # On ne sérialise que le premier niveau de réponse pour éviter la récursion infinie ou trop profonde
        if obj.replies.exists():
            return LessonCommentSerializer(obj.replies.all(), many=True, context=self.context).data
        return []

class CommentSerializer(serializers.ModelSerializer):
    username = serializers.ReadOnlyField(source='user.username')
    replies = serializers.SerializerMethodField()

    class Meta:
        model = CourseComment
        fields = ['id', 'user', 'username', 'content', 'created_at', 'parent', 'replies']
        read_only_fields = ['user']

    def get_replies(self, obj):
        if obj.replies.exists():
            return CommentSerializer(obj.replies.all(), many=True, context=self.context).data
        return []

class LessonSerializer(serializers.ModelSerializer):
    likes_count = serializers.IntegerField(source='likes.count', read_only=True)
    comments_count = serializers.IntegerField(source='comments.count', read_only=True)
    is_liked = serializers.SerializerMethodField()
    is_favorited = serializers.SerializerMethodField()
    file_size = serializers.SerializerMethodField()
    is_locked = serializers.SerializerMethodField()

    class Meta:
        model = Lesson
        fields = ['id', 'course', 'title', 'content_type', 'content_file', 'content_text', 'order', 'likes_count', 'comments_count', 'is_liked', 'is_favorited', 'file_size', 'is_locked']

    def get_is_locked(self, obj):
        user = self.context.get('request').user
        if not user or not user.is_authenticated:
            return True
        
        if user.role in ['TEACHER', 'MANAGER', 'SUPER_ADMIN'] or user.is_superuser:
            return False

        # 1. Vérifier si le cours lui-même est verrouillé par un prérequis global
        if obj.course.prerequisite_quiz:
            prereq_quiz = obj.course.prerequisite_quiz
            best_attempt = prereq_quiz.attempts.filter(student=user).order_by('-score').first()
            if not best_attempt or best_attempt.score < 50:
                return True

        # 2. Vérifier la progression séquentielle au sein du cours
        previous_lessons = obj.course.lessons.filter(order__lt=obj.order).order_by('order')
        
        for p_lesson in previous_lessons:
            if hasattr(p_lesson, 'module_quiz') and p_lesson.module_quiz and p_lesson.module_quiz.is_published:
                quiz = p_lesson.module_quiz
                best_attempt = quiz.attempts.filter(student=user).order_by('-score').first()
                if not best_attempt or best_attempt.score < 50:
                    return True
        
        return False

    def get_is_liked(self, obj):
        user = self.context.get('request').user
        if user and user.is_authenticated:
            return obj.likes.filter(user=user).exists()
        return False

    def get_is_favorited(self, obj):
        user = self.context.get('request').user
        if user and user.is_authenticated:
            return obj.favorited_by.filter(user=user).exists()
        return False
    
    def get_file_size(self, obj):
        """Retourne la taille du fichier en MB (None si fichier absent sur le disque)."""
        if not obj.content_file:
            return None
        try:
            return round(obj.content_file.size / (1024 * 1024), 2)
        except (FileNotFoundError, OSError, ValueError):
            return None

    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Ne jamais faire planter le détail cours si le média n'est pas sur le serveur
        content_file = data.get('content_file')
        if content_file and instance.content_file:
            try:
                # Vérifie l'existence sans lever une 500 côté client
                if hasattr(instance.content_file, 'storage') and hasattr(instance.content_file, 'name'):
                    if not instance.content_file.storage.exists(instance.content_file.name):
                        data['content_file'] = None
                        data['file_missing'] = True
            except (FileNotFoundError, OSError, ValueError):
                data['content_file'] = None
                data['file_missing'] = True
        return data

class LiveSessionSerializer(serializers.ModelSerializer):
    teacher_name = serializers.ReadOnlyField(source='teacher.username')
    class Meta:
        model = LiveSession
        fields = ['id', 'course', 'teacher', 'teacher_name', 'room_name', 'is_active', 'started_at']

class QuizChoiceSerializer(serializers.ModelSerializer):
    class Meta:
        model = QuizChoice
        fields = ['id', 'text', 'is_correct']

class QuizQuestionSerializer(serializers.ModelSerializer):
    choices = QuizChoiceSerializer(many=True, read_only=True)
    class Meta:
        model = QuizQuestion
        fields = ['id', 'text', 'points', 'choices']

class QuizSerializer(serializers.ModelSerializer):
    questions = QuizQuestionSerializer(many=True, read_only=True)
    has_attempted = serializers.SerializerMethodField()
    my_score = serializers.SerializerMethodField()

    class Meta:
        model = Quiz
        fields = ['id', 'id_code', 'title', 'description', 'time_limit', 'questions', 'created_at', 'is_published', 'has_attempted', 'my_score', 'quiz_type']

    def get_has_attempted(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.attempts.filter(student=request.user).exists()
        return False

    def get_my_score(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            attempt = obj.attempts.filter(student=request.user).first()
            if attempt:
                return float(attempt.score)
        return None

class CourseListSerializer(serializers.ModelSerializer):
    """Liste catalogue légère : pas de lessons/quizzes imbriqués."""
    teacher_name = serializers.ReadOnlyField(source='teacher.username')
    lessons_count = serializers.IntegerField(read_only=True, default=0)
    likes_count = serializers.IntegerField(read_only=True, default=0)
    is_following = serializers.SerializerMethodField()
    is_enrolled = serializers.SerializerMethodField()
    is_liked = serializers.SerializerMethodField()
    is_favorited = serializers.SerializerMethodField()
    is_locked = serializers.SerializerMethodField()
    active_live = serializers.SerializerMethodField()

    class Meta:
        model = Course
        fields = [
            'id', 'title', 'description', 'teacher', 'teacher_name',
            'created_at', 'is_published', 'price', 'is_free',
            'is_following', 'is_enrolled', 'is_liked', 'is_favorited',
            'likes_count', 'lessons_count', 'active_live', 'thumbnail', 'is_locked',
        ]
        read_only_fields = ['teacher']

    def get_is_liked(self, obj):
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if not user or not user.is_authenticated:
            return False
        if 'liked_course_ids' in self.context:
            return obj.id in self.context['liked_course_ids']
        return obj.likes.filter(user=user).exists()

    def get_is_favorited(self, obj):
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if not user or not user.is_authenticated:
            return False
        if 'favorited_course_ids' in self.context:
            return obj.id in self.context['favorited_course_ids']
        return obj.favorited_by.filter(user=user).exists()

    def get_is_enrolled(self, obj):
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if not user or not user.is_authenticated:
            return False
        if 'enrolled_course_ids' in self.context:
            return obj.id in self.context['enrolled_course_ids']
        return obj.enrollments.filter(student=user).exists()

    def get_is_following(self, obj):
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if not user or not user.is_authenticated or not obj.teacher_id:
            return False
        if 'followed_teacher_ids' in self.context:
            return obj.teacher_id in self.context['followed_teacher_ids']
        from .models import TeacherFollow
        return TeacherFollow.objects.filter(student=user, teacher=obj.teacher).exists()

    def get_active_live(self, obj):
        # Prefetch live_sessions : filtre en Python
        sessions = getattr(obj, '_prefetched_objects_cache', {}).get('live_sessions')
        if sessions is not None:
            for s in sessions:
                if s.is_active:
                    return LiveSessionSerializer(s).data
            return None
        active_session = obj.live_sessions.filter(is_active=True).first()
        if active_session:
            return LiveSessionSerializer(active_session).data
        return None

    def get_is_locked(self, obj):
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if not user or not user.is_authenticated:
            return False
        if user.role in ['TEACHER', 'MANAGER', 'SUPER_ADMIN'] or user.is_superuser:
            return False
        if obj.prerequisite_quiz_id:
            locked_ids = self.context.get('locked_by_prereq_ids')
            if locked_ids is not None:
                return obj.id in locked_ids
            best_attempt = obj.prerequisite_quiz.attempts.filter(student=user).order_by('-score').first()
            if not best_attempt or best_attempt.score < 50:
                return True
        return False


class CourseSerializer(serializers.ModelSerializer):
    teacher_name = serializers.ReadOnlyField(source='teacher.username')
    lessons = LessonSerializer(many=True, read_only=True)
    quizzes = QuizSerializer(many=True, read_only=True)
    is_following = serializers.SerializerMethodField()
    is_enrolled = serializers.SerializerMethodField()
    is_liked = serializers.SerializerMethodField()
    is_favorited = serializers.SerializerMethodField()
    likes_count = serializers.IntegerField(source='likes.count', read_only=True)
    active_live = serializers.SerializerMethodField()
    is_locked = serializers.SerializerMethodField()

    class Meta:
        model = Course
        fields = [
            'id', 'title', 'description', 'teacher', 'teacher_name', 
            'created_at', 'lessons', 'quizzes', 'is_published', 'price', 'is_free',
            'is_following', 'is_enrolled', 'is_liked', 'is_favorited', 
            'likes_count', 'active_live', 'thumbnail', 'is_locked'
        ]
        read_only_fields = ['teacher']

    def get_is_liked(self, obj):
        user = self.context.get('request').user
        if user.is_authenticated:
            return obj.likes.filter(user=user).exists()
        return False

    def get_is_favorited(self, obj):
        user = self.context.get('request').user
        if user.is_authenticated:
            return obj.favorited_by.filter(user=user).exists()
        return False

    def get_active_live(self, obj):
        active_session = obj.live_sessions.filter(is_active=True).first()
        if active_session:
            return LiveSessionSerializer(active_session).data
        return None

    def get_is_enrolled(self, obj):
        user = self.context.get('request').user
        if user and user.is_authenticated:
            return obj.enrollments.filter(student=user).exists()
        return False

    def get_is_following(self, obj):
        user = self.context.get('request').user
        if user and user.is_authenticated and obj.teacher_id:
            from .models import TeacherFollow
            return TeacherFollow.objects.filter(student=user, teacher=obj.teacher).exists()
        return False

    def get_is_locked(self, obj):
        user = self.context.get('request').user
        if not user or not user.is_authenticated: return False
        if user.role in ['TEACHER', 'MANAGER', 'SUPER_ADMIN'] or user.is_superuser: return False
        
        if obj.prerequisite_quiz:
            best_attempt = obj.prerequisite_quiz.attempts.filter(student=user).order_by('-score').first()
            if not best_attempt or best_attempt.score < 50:
                return True
        return False

class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ['id', 'title', 'message', 'type', 'created_at']

class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True)
    firebase_uid = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    name = serializers.CharField(required=False, allow_blank=True, write_only=True)

    class Meta:
        model = User
        fields = ['username', 'email', 'password', 'firebase_uid', 'name']

    def validate(self, attrs):
        raise serializers.ValidationError(
            "L'inscription libre est désactivée. Votre compte est créé par le décanat "
            "de votre faculté. Connectez-vous avec votre matricule et le mot de passe par défaut."
        )

class CreateTeacherSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True)

    class Meta:
        model = User
        fields = ['username', 'email', 'password', 'first_name', 'last_name', 'phone']

    def create(self, validated_data):
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=validated_data['password'],
            first_name=validated_data.get('first_name', ''),
            last_name=validated_data.get('last_name', ''),
            phone=validated_data.get('phone', ''),
            role='TEACHER'
        )
        return user

class ChatMessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.ReadOnlyField(source='sender.username')
    class Meta:
        model = ChatMessage
        fields = ['id', 'room', 'sender', 'sender_name', 'content', 'created_at', 'is_read']
        read_only_fields = ['sender']

class ChatRoomSerializer(serializers.ModelSerializer):
    last_message = serializers.SerializerMethodField()
    participants = UserSerializer(many=True, read_only=True)
    class Meta:
        model = ChatRoom
        fields = ['id', 'name', 'course', 'participants', 'is_group', 'created_at', 'last_message']

    def get_last_message(self, obj):
        last = obj.messages.last()
        if last:
            return ChatMessageSerializer(last).data
        return None

class ExternalResourceSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExternalResource
        fields = '__all__'


class AssignmentSerializer(serializers.ModelSerializer):
    teacher_name = serializers.ReadOnlyField(source='teacher.username')
    course_title = serializers.ReadOnlyField(source='course.title')
    submissions_count = serializers.SerializerMethodField()
    my_submission = serializers.SerializerMethodField()

    class Meta:
        model = Assignment
        fields = ['id', 'course', 'course_title', 'teacher', 'teacher_name', 'title', 'description', 'due_date', 'created_at', 'submissions_count', 'my_submission']
        read_only_fields = ['teacher']

    def get_submissions_count(self, obj):
        return obj.submissions.count()

    def get_my_submission(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated and request.user.role == 'STUDENT':
            sub = obj.submissions.filter(student=request.user).first()
            if sub:
                return AssignmentSubmissionSerializer(sub, context=self.context).data
        return None


class AssignmentSubmissionSerializer(serializers.ModelSerializer):
    student_name = serializers.ReadOnlyField(source='student.username')
    assignment_title = serializers.ReadOnlyField(source='assignment.title')

    class Meta:
        model = AssignmentSubmission
        fields = ['id', 'assignment', 'assignment_title', 'student', 'student_name', 'file', 'submitted_at', 'grade', 'grade_comment', 'graded_at', 'is_graded']
        read_only_fields = ['student', 'submitted_at', 'graded_at', 'is_graded']
