from django.test import TestCase
from django.contrib.auth import get_user_model
from lms.models import Province, University, Faculty, Promotion, ClassGroup, NationalCourse, NationalFaculty, Course, CourseGrade
import decimal

User = get_user_model()

class LMDWorkflowTestCase(TestCase):
    def setUp(self):
        # Créer Province et Université
        self.province = Province.objects.create(code='KINSHASA')
        self.university = University.objects.create(
            name="UNIKIN",
            province=self.province
        )
        self.national_faculty = NationalFaculty.objects.create(code='SCIENCES', name='Sciences')
        self.faculty = Faculty.objects.create(
            university=self.university,
            name="Sciences",
            national_faculty=self.national_faculty,
        )
        self.promotion = Promotion.objects.create(
            faculty=self.faculty,
            name="L1"
        )
        self.class_group = ClassGroup.objects.create(
            promotion=self.promotion,
            name="Groupe A"
        )
        
        # Créer un Enseignant
        self.teacher = User.objects.create_user(
            username="teacher_test",
            password="password",
            role="TEACHER",
            assigned_university=self.university,
            assigned_faculty=self.faculty,
            assigned_promotion=self.promotion
        )
        
        # Créer 2 étudiants
        self.student1 = User.objects.create_user(
            username="student1",
            password="password",
            role="STUDENT",
            class_group=self.class_group
        )
        self.student2 = User.objects.create_user(
            username="student2",
            password="password",
            role="STUDENT",
            class_group=self.class_group
        )
        
        # Créer des Cours Nationaux (un au S1, un au S2)
        # S1 (poids: 6 crédits)
        self.nc1 = NationalCourse.objects.create(
            national_faculty=self.national_faculty,
            code="INF101",
            title="Intro Info",
            credits=6,
            semester=1
        )
        # S2 (poids: 6 crédits)
        self.nc2 = NationalCourse.objects.create(
            national_faculty=self.national_faculty,
            code="INF201",
            title="POO",
            credits=6,
            semester=2
        )
        
        # Instancier les cours de l'Université
        # Cours local associé au S1 (override possible, ici 1)
        self.course_s1 = Course.objects.create(
            title="Intro Info Local",
            national_course=self.nc1,
            university=self.university,
            faculty=self.faculty,
            promotion=self.promotion,
            teacher=self.teacher,
            semester=1,
            credits=6,
            is_published=True
        )
        
        # Cours local associé au S2 (override local en 2)
        self.course_s2 = Course.objects.create(
            title="POO Local",
            national_course=self.nc2,
            university=self.university,
            faculty=self.faculty,
            promotion=self.promotion,
            teacher=self.teacher,
            semester=2,
            credits=6,
            is_published=True
        )

        # Créer les inscriptions
        from lms.models import Enrollment
        Enrollment.objects.create(student=self.student1, course=self.course_s1)
        Enrollment.objects.create(student=self.student2, course=self.course_s1)
        Enrollment.objects.create(student=self.student1, course=self.course_s2)
        Enrollment.objects.create(student=self.student2, course=self.course_s2)

        print("SETUP - USER COUNT:", User.objects.count())
        print("SETUP - COURSE COUNT:", Course.objects.count())
        print("SETUP - ENROLLMENT COUNT:", Enrollment.objects.count())
        
    def test_grading_and_credits_logic(self):
        # 1. Enregistrer des notes pour le cours du S1
        # student1 a 12/20 (doit valider les 6 crédits du cours)
        # student2 a 8/20 (ne doit pas valider les crédits)
        g1 = CourseGrade.objects.create(
            student=self.student1,
            course=self.course_s1,
            final_score=decimal.Decimal('12.00'),
            status='APPROVED'  # Directement approuvé pour simplifier le test des crédits
        )
        g2 = CourseGrade.objects.create(
            student=self.student2,
            course=self.course_s1,
            final_score=decimal.Decimal('8.00'),
            status='APPROVED'
        )
        
        # 2. Vérifier les crédits
        # Student1 doit avoir 6 crédits au S1, 0 au S2, total=6, admis=ECHOUE (car < 60)
        self.assertEqual(self.student1.s1_credits, 6)
        self.assertEqual(self.student1.s2_credits, 0)
        self.assertEqual(self.student1.total_credits, 6)
        self.assertEqual(self.student1.admission_status, "ECHOUE")
        
        # Student2 doit avoir 0 crédits
        self.assertEqual(self.student2.s1_credits, 0)
        self.assertEqual(self.student2.total_credits, 0)
        self.assertEqual(self.student2.admission_status, "ECHOUE")

    def test_semester_lock_prevents_grading(self):
        # 1. Connecter l'enseignant
        self.client.login(username="teacher_test", password="password")
        
        # Créer les grades en brouillon
        CourseGrade.objects.create(
            student=self.student1,
            course=self.course_s1,
            status='DRAFT'
        )
        
        # Clôturer le S1 au niveau de l'université
        self.university.s1_closed = True
        self.university.save()
        
        # 2. poster des notes pour un cours du S1 (devrait échouer / renvoyer une erreur)
        response = self.client.post(
            f'/teacher/courses/{self.course_s1.id}/grades/',
            {'action': 'save', f'final_{self.student1.id}': '15.00'}
        )
        
        # Le code doit renvoyer vers la saisie avec message d'erreur et ne pas modifier la note.
        self.assertEqual(response.status_code, 302) # redirection
        
        g1 = CourseGrade.objects.get(student=self.student1, course=self.course_s1)
        self.assertNotEqual(g1.final_score, decimal.Decimal('15.00')) # n'a pas été modifiée
        
        # 3. Le Semestre 2 est toujours ouvert, la saisie pour S2 devrait fonctionner
        CourseGrade.objects.create(
            student=self.student1,
            course=self.course_s2,
            status='DRAFT'
        )
        response_s2 = self.client.post(
            f'/teacher/courses/{self.course_s2.id}/grades/',
            {'action': 'save', f'final_{self.student1.id}': '18.00'},
            follow=True
        )
        
        # Afficher les messages de redirection s'il y en a
        if response_s2.context and 'messages' in response_s2.context:
            msgs = [m.message for m in response_s2.context['messages']]
            print("MESSAGES D'ERREUR DU POST S2:", msgs)
            
        g1_s2 = CourseGrade.objects.get(student=self.student1, course=self.course_s2)
        self.assertEqual(g1_s2.final_score, decimal.Decimal('18.00')) # modifiée avec succès!
