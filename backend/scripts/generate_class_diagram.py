"""Génère le diagramme de classes UML (Mermaid) en français à partir des modèles Django."""
from __future__ import annotations

import os
import sys

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "core.settings")
BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_ROOT)

import django

django.setup()

from django.apps import apps
from django.db import models as dj_models

SKIP_APPS = {
    "contenttypes",
    "auth",
    "admin",
    "sessions",
    "messages",
    "staticfiles",
    "token_blacklist",
    "authtoken",
}

# Noms de classes en français (mémoire)
CLASS_FR = {
    "User": "Utilisateur",
    "NationalFaculty": "FaculteNationale",
    "NationalCourse": "CoursNational",
    "AuditLog": "JournalAudit",
    "Province": "Province",
    "University": "Universite",
    "Faculty": "Faculte",
    "Promotion": "Promotion",
    "ClassGroup": "GroupeClasse",
    "Course": "Cours",
    "Lesson": "Lecon",
    "Enrollment": "Inscription",
    "Evaluation": "Evaluation",
    "Grade": "NoteEvaluation",
    "Notification": "Notification",
    "CourseLike": "LikeCours",
    "CourseComment": "CommentaireCours",
    "CourseFavorite": "FavoriCours",
    "TeacherFollow": "SuiviEnseignant",
    "LessonLike": "LikeLecon",
    "LessonComment": "CommentaireLecon",
    "LessonFavorite": "FavoriLecon",
    "LiveSession": "SessionLive",
    "ChatRoom": "SalonDiscussion",
    "ChatMessage": "MessageChat",
    "Quiz": "Quiz",
    "QuizQuestion": "QuestionQuiz",
    "QuizChoice": "ChoixQuiz",
    "QuizAttempt": "TentativeQuiz",
    "ExternalResource": "RessourceExterne",
    "CourseGrade": "NoteCours",
    "StudentAudit": "CotationEtudiant",
    "Assignment": "TravailPratique",
    "AssignmentSubmission": "SoumissionTP",
    "FacultyReport": "RapportFaculte",
    "SemesterResultReport": "RapportResultatsSemestre",
    "SemesterResultLine": "LigneResultatSemestre",
    "UniversityReport": "RapportUniversite",
    "ProvincialReport": "RapportProvincial",
    "TerritorialAlert": "AlerteTerritoriale",
}

# Attributs en français (principaux)
ATTR_FR = {
    "id": "id",
    "password": "mot_de_passe",
    "last_login": "derniere_connexion",
    "is_superuser": "est_superutilisateur",
    "username": "identifiant",
    "first_name": "prenom",
    "last_name": "nom",
    "email": "email",
    "is_staff": "est_personnel",
    "is_active": "est_actif",
    "date_joined": "date_inscription",
    "role": "role",
    "phone": "telephone",
    "matricule": "matricule",
    "assigned_semester": "semestre_assigne",
    "firebase_uid": "firebase_uid",
    "profile_completed": "profil_complete",
    "gender": "sexe",
    "class_group": "groupe_classe",
    "assigned_province": "province_assignee",
    "assigned_university": "universite_assignee",
    "assigned_faculty": "faculte_assignee",
    "assigned_promotion": "promotion_assignee",
    "assigned_promotions": "promotions_assignees",
    "national_faculty": "faculte_nationale",
    "national_course": "cours_national",
    "province": "province",
    "university": "universite",
    "faculty": "faculte",
    "promotion": "promotion",
    "teacher": "enseignant",
    "student": "etudiant",
    "course": "cours",
    "lesson": "lecon",
    "quiz": "quiz",
    "question": "question",
    "room": "salon",
    "sender": "expediteur",
    "user": "utilisateur",
    "report": "rapport",
    "submitted_by": "soumis_par",
    "followed": "suivi",
    "follower": "abonné",
    "author": "auteur",
    "evaluation": "evaluation",
    "assignment": "travail",
    "session": "session",
    "code": "code",
    "name": "nom",
    "created_at": "cree_le",
    "updated_at": "modifie_le",
    "title": "titre",
    "description": "description",
    "credits": "credits",
    "semester": "semestre",
    "institution_type": "type_etablissement",
    "address": "adresse",
    "capacity": "capacite",
    "is_grading_locked": "saisie_notes_verrouillee",
    "s1_closed": "semestre1_cloture",
    "s2_closed": "semestre2_cloture",
    "action": "action",
    "details": "details",
    "ip_address": "adresse_ip",
    "timestamp": "horodatage",
    "content": "contenu",
    "file": "fichier",
    "video_url": "url_video",
    "order": "ordre",
    "status": "statut",
    "score": "score",
    "final_score": "note_finale",
    "quiz_average": "moyenne_quiz",
    "interrogation_score": "note_interrogation",
    "exam_score": "note_examen",
    "tp": "note_tp",
    "interro": "note_interro",
    "examen": "note_examen",
    "full_name": "nom_complet",
    "message": "message",
    "is_read": "est_lu",
    "academic_year": "annee_academique",
    "total_students": "total_etudiants",
    "passed_students": "etudiants_reussis",
    "failed_students": "etudiants_echecs",
    "submitted_at": "soumis_le",
    "is_validated": "est_valide",
    "validated_at": "valide_le",
    "total_universities": "total_universites",
    "universities_reported": "universites_ayant_rapporte",
    "universities_pending": "universites_en_attente",
    "credits_reference": "credits_reference",
    "semester_credits_reference": "credits_semestre_reference",
    "promotion_label": "libelle_promotion",
    "faculty_label": "libelle_faculte",
    "s1_credits_earned": "credits_s1_obtenus",
    "s1_credits_total": "credits_s1_total",
    "s2_credits_earned": "credits_s2_obtenus",
    "s2_credits_total": "credits_s2_total",
    "credits_earned": "credits_obtenus",
    "credits_total": "credits_total",
    "result": "resultat",
    "alert_type": "type_alerte",
    "severity": "gravite",
    "is_resolved": "est_resolue",
    "resolved_at": "resolue_le",
    "start_time": "heure_debut",
    "end_time": "heure_fin",
    "meeting_link": "lien_reunion",
    "question_text": "texte_question",
    "choice_text": "texte_choix",
    "is_correct": "est_correct",
    "started_at": "commence_le",
    "completed_at": "termine_le",
    "url": "url",
    "category": "categorie",
    "due_date": "date_limite",
    "submitted_file": "fichier_soumis",
    "feedback": "commentaire",
    "text": "texte",
    "body": "corps",
    "link": "lien",
    "max_score": "note_max",
    "duration_minutes": "duree_minutes",
    "year_label": "libelle_annee",
    "level": "niveau",
}

TYPE_FR = {
    "AutoField": "Entier",
    "BigAutoField": "Entier",
    "IntegerField": "Entier",
    "PositiveIntegerField": "Entier+",
    "PositiveSmallIntegerField": "Entier+",
    "SmallIntegerField": "Entier",
    "BigIntegerField": "Entier",
    "CharField": "Texte",
    "TextField": "TexteLong",
    "EmailField": "Email",
    "URLField": "URL",
    "BooleanField": "Booleen",
    "DateTimeField": "DateHeure",
    "DateField": "Date",
    "TimeField": "Heure",
    "DecimalField": "Decimal",
    "FloatField": "Reel",
    "FileField": "Fichier",
    "ImageField": "Image",
    "JSONField": "JSON",
    "ForeignKey": "FK",
    "OneToOneField": "1:1",
    "ManyToManyField": "N:N",
}

SKIP_ATTRS = {
    "groups",
    "user_permissions",
    "password",
    "last_login",
    "is_superuser",
    "is_staff",
    "date_joined",
}


def fr_class(name: str) -> str:
    return CLASS_FR.get(name, name)


def fr_attr(name: str) -> str:
    return ATTR_FR.get(name, name)


def fr_type(internal: str) -> str:
    return TYPE_FR.get(internal, internal)


def main():
    lines = [
        "---",
        "title: Diagramme de classes — Yekola / Yekola (toutes les tables métier)",
        "---",
        "classDiagram",
        "    direction TB",
        "",
        "    %% ========== PACKAGES ==========",
        '    namespace "Referentiel national & territorial" {',
    ]

    package_map = {
        "Referentiel": [
            "Province",
            "NationalFaculty",
            "NationalCourse",
            "University",
            "Faculty",
            "Promotion",
            "ClassGroup",
        ],
        "Acteurs": ["User", "AuditLog", "Notification"],
        "Pedagogie": [
            "Course",
            "Lesson",
            "Enrollment",
            "Evaluation",
            "Grade",
            "Assignment",
            "AssignmentSubmission",
            "ExternalResource",
            "LiveSession",
        ],
        "Cotation": ["StudentAudit", "CourseGrade"],
        "Quiz": ["Quiz", "QuizQuestion", "QuizChoice", "QuizAttempt"],
        "Social": [
            "CourseLike",
            "CourseComment",
            "CourseFavorite",
            "TeacherFollow",
            "LessonLike",
            "LessonComment",
            "LessonFavorite",
            "ChatRoom",
            "ChatMessage",
        ],
        "Rapports": [
            "FacultyReport",
            "SemesterResultReport",
            "SemesterResultLine",
            "UniversityReport",
            "ProvincialReport",
            "TerritorialAlert",
        ],
    }

    # Collect models
    models_by_name = {}
    for m in apps.get_models():
        if m._meta.app_label in SKIP_APPS:
            continue
        models_by_name[m.__name__] = m

    # Emit classes grouped
    emitted = set()
    ns_titles = {
        "Referentiel": "Referentiel national et territorial",
        "Acteurs": "Acteurs et journalisation",
        "Pedagogie": "Pedagogie et enseignement",
        "Cotation": "Cotation LMD",
        "Quiz": "Evaluations quiz",
        "Social": "Interactions sociales et chat",
        "Rapports": "Remontee provinciale et nationale",
    }

    class_blocks = []
    relations = []

    for pkg, names in package_map.items():
        class_blocks.append(f'    namespace "{ns_titles[pkg]}" {{')
        for name in names:
            m = models_by_name.get(name)
            if not m:
                continue
            emitted.add(name)
            cname = fr_class(name)
            class_blocks.append(f"        class {cname} {{")
            class_blocks.append(f"            <<table {m._meta.db_table}>>")
            for f in m._meta.get_fields():
                if not getattr(f, "concrete", False):
                    continue
                if f.name in SKIP_ATTRS:
                    continue
                if getattr(f, "is_relation", False) and not getattr(f, "many_to_many", False):
                    # FK shown as attribute + relation edge
                    if getattr(f, "many_to_one", False) or getattr(f, "one_to_one", False):
                        rel_model = f.related_model
                        if rel_model and rel_model._meta.app_label not in SKIP_APPS:
                            target = fr_class(rel_model.__name__)
                            card = "1" if getattr(f, "one_to_one", False) else "1"
                            many = "1" if getattr(f, "one_to_one", False) else "*"
                            # Utilisateur "N" -- "1" Universite : universite_assignee
                            relations.append(
                                f"    {cname} \"{many}\" --> \"{card}\" {target} : {fr_attr(f.name)}"
                            )
                            class_blocks.append(
                                f"            +{fr_attr(f.name)} : FK<{target}>"
                            )
                        continue
                if getattr(f, "many_to_many", False):
                    rel_model = f.related_model
                    if rel_model and rel_model._meta.app_label not in SKIP_APPS:
                        # Only emit from one side (alphabetical) to avoid duplicates
                        if name < rel_model.__name__ or f.name == "assigned_promotions":
                            target = fr_class(rel_model.__name__)
                            relations.append(
                                f"    {cname} \"*\" --> \"*\" {target} : {fr_attr(f.name)}"
                            )
                    continue
                itype = f.get_internal_type() if hasattr(f, "get_internal_type") else "Field"
                class_blocks.append(f"            +{fr_attr(f.name)} : {fr_type(itype)}")
            class_blocks.append("        }")
        class_blocks.append("    }")
        class_blocks.append("")

    # Any leftover models
    leftovers = [n for n in models_by_name if n not in emitted]
    if leftovers:
        class_blocks.append('    namespace "Autres" {')
        for name in leftovers:
            m = models_by_name[name]
            cname = fr_class(name)
            class_blocks.append(f"        class {cname} {{")
            class_blocks.append(f"            <<table {m._meta.db_table}>>")
            class_blocks.append("        }")
        class_blocks.append("    }")

    # Deduplicate relations
    uniq_rel = []
    seen = set()
    for r in relations:
        if r not in seen:
            seen.add(r)
            uniq_rel.append(r)

    out_lines = [
        "---",
        "title: Diagramme de classes — Yekola / Yekola",
        "---",
        "",
        "```mermaid",
        "classDiagram",
        "    direction TB",
        "",
        *class_blocks,
        "    %% ========== ASSOCIATIONS ==========",
        *uniq_rel,
        "```",
        "",
        "## Légende",
        "",
        "| Symbole | Signification |",
        "|---|---|",
        "| `FK<Classe>` | Clé étrangère vers la classe |",
        "| `*` / `1` | Cardinalité (plusieurs / un) |",
        "| `N:N` | Association plusieurs-à-plusieurs |",
        "| `<<table ...>>` | Nom physique de la table MariaDB |",
        "",
        "## Flux de remontée des résultats",
        "",
        "```mermaid",
        "flowchart LR",
        "    A[CotationEtudiant / NoteCours] --> B[RapportResultatsSemestre]",
        "    B --> C[RapportFaculte]",
        "    C --> D[RapportUniversite]",
        "    D --> E[RapportProvincial]",
        "    E --> F[Super-Admin Ministere]",
        "```",
        "",
    ]

    docs = os.path.join(BACKEND_ROOT, "..", "docs")
    os.makedirs(docs, exist_ok=True)
    path = os.path.normpath(os.path.join(docs, "diagramme_classes.md"))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out_lines))

    # Also write a pure .mmd for Mermaid Live / CLI
    mmd_path = os.path.normpath(os.path.join(docs, "diagramme_classes.mmd"))
    with open(mmd_path, "w", encoding="utf-8") as f:
        f.write("classDiagram\n    direction TB\n\n")
        f.write("\n".join(class_blocks))
        f.write("\n    %% Associations\n")
        f.write("\n".join(uniq_rel))
        f.write("\n")

    print(f"OK: {path}")
    print(f"OK: {mmd_path}")
    print(f"Classes: {len(emitted)} | Relations: {len(uniq_rel)}")


if __name__ == "__main__":
    main()
