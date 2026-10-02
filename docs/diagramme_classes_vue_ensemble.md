---
title: Diagramme de classes — vue d'ensemble MayeleNet / MayeleNet
---

# Diagramme de classes (vue d'ensemble)

Fichier complet (40 tables) : [`diagramme_classes.md`](./diagramme_classes.md) · [`diagramme_classes.mmd`](./diagramme_classes.mmd)

```mermaid
classDiagram
    direction TB

    class Province {
        +id : Entier
        +code : Texte
        +cree_le : DateHeure
    }

    class Universite {
        +id : Entier
        +nom : Texte
        +type_etablissement : Texte
        +adresse : Texte
        +telephone : Texte
        +email : Email
        +capacite : Entier+
        +saisie_notes_verrouillee : Booleen
        +semestre1_cloture : Booleen
        +semestre2_cloture : Booleen
    }

    class Faculte {
        +id : Entier
        +nom : Texte
    }

    class Promotion {
        +id : Entier
        +nom : Texte
        +niveau : Texte
    }

    class GroupeClasse {
        +id : Entier
        +nom : Texte
    }

    class Utilisateur {
        +id : Entier
        +identifiant : Texte
        +prenom : Texte
        +nom : Texte
        +email : Email
        +role : Texte
        +matricule : Texte
        +sexe : Texte
        +telephone : Texte
    }

    class FaculteNationale {
        +id : Entier
        +code : Texte
        +nom : Texte
        +est_actif : Booleen
    }

    class CoursNational {
        +id : Entier
        +code : Texte
        +titre : Texte
        +credits : Entier+
        +semestre : Entier
    }

    class Cours {
        +id : Entier
        +titre : Texte
        +credits : Entier+
        +semestre : Entier
    }

    class Lecon {
        +id : Entier
        +titre : Texte
        +contenu : TexteLong
        +ordre : Entier
    }

    class CotationEtudiant {
        +id : Entier
        +nom_complet : Texte
        +note_tp : Decimal
        +note_interro : Decimal
        +note_examen : Decimal
        +statut : Texte
    }

    class NoteCours {
        +id : Entier
        +note_interrogation : Decimal
        +note_examen : Decimal
        +note_finale : Decimal
        +statut : Texte
    }

    class RapportFaculte {
        +id : Entier
        +titre : Texte
        +annee_academique : Texte
        +total_etudiants : Entier
        +etudiants_reussis : Entier
        +etudiants_echecs : Entier
        +est_valide : Booleen
    }

    class RapportResultatsSemestre {
        +id : Entier
        +titre : Texte
        +annee_academique : Texte
        +credits_reference : Entier+
        +total_etudiants : Entier
        +etudiants_reussis : Entier
        +etudiants_echecs : Entier
    }

    class LigneResultatSemestre {
        +id : Entier
        +nom_complet : Texte
        +credits_s1_obtenus : Entier
        +credits_s2_obtenus : Entier
        +credits_obtenus : Entier
        +resultat : Texte
    }

    class RapportUniversite {
        +id : Entier
        +titre : Texte
        +annee_academique : Texte
        +total_etudiants : Entier
        +etudiants_reussis : Entier
        +etudiants_echecs : Entier
        +est_valide : Booleen
    }

    class RapportProvincial {
        +id : Entier
        +titre : Texte
        +annee_academique : Texte
        +total_universites : Entier
        +total_etudiants : Entier
        +etudiants_reussis : Entier
        +etudiants_echecs : Entier
        +est_valide : Booleen
    }

    class AlerteTerritoriale {
        +id : Entier
        +type_alerte : Texte
        +message : Texte
        +gravite : Texte
        +est_resolue : Booleen
    }

    Province "1" <-- "*" Universite : province
    Universite "1" <-- "*" Faculte : universite
    Faculte "1" <-- "*" Promotion : faculte
    Promotion "1" <-- "*" GroupeClasse : promotion
    FaculteNationale "1" <-- "*" CoursNational : faculte_nationale
    Universite "1" <-- "*" Utilisateur : universite_assignee
    Faculte "1" <-- "*" Utilisateur : faculte_assignee
    Province "1" <-- "*" Utilisateur : province_assignee
    GroupeClasse "1" <-- "*" Utilisateur : groupe_classe
    Promotion "1" <-- "*" Cours : promotion
    Utilisateur "1" <-- "*" Cours : enseignant
    CoursNational "1" <-- "*" Cours : cours_national
    Cours "1" <-- "*" Lecon : cours
    Cours "1" <-- "*" CotationEtudiant : cours
    Utilisateur "1" <-- "*" CotationEtudiant : etudiant
    Utilisateur "1" <-- "*" CotationEtudiant : enseignant
    Cours "1" <-- "*" NoteCours : cours
    Utilisateur "1" <-- "*" NoteCours : etudiant
    Universite "1" <-- "*" RapportFaculte : universite
    Faculte "1" <-- "*" RapportFaculte : faculte
    Universite "1" <-- "*" RapportResultatsSemestre : universite
    Faculte "1" <-- "*" RapportResultatsSemestre : faculte
    Promotion "1" <-- "*" RapportResultatsSemestre : promotion
    RapportResultatsSemestre "1" <-- "*" LigneResultatSemestre : rapport
    Utilisateur "1" <-- "*" LigneResultatSemestre : etudiant
    Universite "1" <-- "*" RapportUniversite : universite
    Province "1" <-- "*" RapportProvincial : province
    Province "1" <-- "*" AlerteTerritoriale : province
    Universite "1" <-- "*" AlerteTerritoriale : universite
```

## Rôles de Utilisateur

| Valeur | Libellé |
|---|---|
| `SUPER_ADMIN` | Super Administrateur (Ministère) |
| `PROVINCIAL_ADMIN` | Administrateur Provincial |
| `MANAGER` | Gestionnaire (Université) |
| `DEAN` | Décanat (Faculté) |
| `TEACHER` | Enseignant |
| `STUDENT` | Étudiant |

## Remontée des résultats

```mermaid
flowchart LR
    CE[CotationEtudiant] --> RRS[RapportResultatsSemestre]
    RRS --> RF[RapportFaculte]
    RF --> RU[RapportUniversite]
    RU --> RP[RapportProvincial]
    RP --> MIN[Ministere / Super-Admin]
```
