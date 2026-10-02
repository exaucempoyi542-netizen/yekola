# Diagrammes UML — Chapitre 4 MayeleNet (100 % français)

## Comment générer les images

1. Ouvre **[PlantUML Online](https://www.plantuml.com/plantuml/uml)**.
2. Copie **tout le contenu** d’un fichier `.puml` (de `@startuml` à `@enduml`).
3. Colle dans l’éditeur → le diagramme s’affiche.
4. Exporte en **PNG** ou **SVG**, puis insère dans Word.

## Fichiers (libellés entièrement en français)

| Fichier | Figure | Contenu |
|---------|--------|---------|
| `01_cas_utilisation.puml` | Figure 4.1 | Cas d’utilisation UC01–UC17 |
| `02_diagramme_classes.puml` | Figure 4.2 | Classes, attributs, associations |
| `03_sequence_cotes.puml` | Figure 4.3 | Séquence cotes → Décanat |
| `04_sequence_rapport_annuel.puml` | Figure 4.4 | Séquence rapport annuel |
| `05_sequence_rapport_province.puml` | Figure 4.5 | Séquence rapport → province |
| `06_activite_cycle_cote.puml` | Figure 4.6 | Activité cycle de vie d’une cote |
| `07_architecture.puml` | Figure 4.7 | Architecture technique |

## Correspondance modèles Django (noms techniques → français)

| Nom technique (code) | Nom sur le diagramme |
|----------------------|----------------------|
| University | Universite |
| Faculty | Faculte |
| ClassGroup | GroupeClasse |
| User | Utilisateur |
| Course | Cours |
| Lesson | Lecon |
| Assignment | Devoir |
| StudentAudit | CoteEtudiant |
| CourseGrade | NoteCours |
| SemesterResultReport | RapportResultatsSemestre |
| FacultyReport | RapportFacultaire |
| UniversityReport | RapportUniversitaire |
| ProvincialReport | RapportProvincial |
| AuditLog | JournalAudit |
| DRAFT | Brouillon |
| SUBMITTED_TO_DEAN | Soumis au Décanat |
| VALIDATED_BY_DEAN | Validé par le Décanat |
