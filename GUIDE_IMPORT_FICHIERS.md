# Guide d'Import de Fichiers - Système MayeleNet

## Vue d'ensemble

Le système **MayeleNet** permet aux enseignants d'importer facilement des fichiers pédagogiques (vidéos, PDF, PowerPoint) que les étudiants peuvent consulter directement dans l'application.

---

## 📚 Pour les Enseignants

### Accès au portail d'import

1. **Connectez-vous** au portail enseignant: `http://localhost:8000/teacher/`
2. Naviguez vers **Dashboard** → **Sélectionnez un cours**
3. Cliquez sur **Gestion du contenu** pour accéder à l'éditeur de leçons

### Créer une leçon avec fichier

#### 1️⃣ Sélectionner le format

Quatre formats sont disponibles:

| Format | Extensions | Taille max | Usage |
|--------|-----------|-----------|--------|
| **📹 Vidéo** | MP4, AVI, MOV, MKV, FLV, WMV, WebM | 500 MB | Leçons vidéo enregistrées |
| **📄 PDF** | PDF | 500 MB | Supports de cours, documents |
| **📊 PowerPoint** | PPT, PPTX, ODP | 500 MB | Présentations |
| **📝 Texte riche** | - | - | Contenu rédactionnel |

#### 2️⃣ Importer un fichier

**Option A: Glisser-déposer**
- Glissez le fichier directement dans la zone de dépôt
- Le fichier sera uploadé automatiquement

**Option B: Cliquer pour parcourir**
- Cliquez dans la zone de dépôt
- Sélectionnez le fichier depuis votre ordinateur

#### 3️⃣ Remplir les informations

| Champ | Description | Obligatoire |
|-------|-------------|------------|
| **Titre** | Nom de la leçon | ✓ |
| **Format** | Type de contenu | ✓ |
| **Fichier** | Document/vidéo | ✓ (sauf texte) |
| **Contenu** | Texte riche (pour texte) | ✓ (texte seulement) |

#### 4️⃣ Soumettre

Cliquez sur **"Publier le module"**
- Une barre de progression s'affiche
- La leçon sera disponible pour les étudiants immédiatement

### Exemple: Créer une leçon vidéo

```
Titre: "Introduction à Python"
Format: 📹 Vidéo
Fichier: introduction-python.mp4 (150 MB)

La vidéo sera disponible pour tous les étudiants inscrits
```

### Exemple: Créer un support PDF

```
Titre: "Chapitre 1 - Les bases"
Format: 📄 PDF
Fichier: chapitre1.pdf (45 MB)

Les étudiants pourront consulter le PDF directement dans l'app
```

### Exemple: Créer du contenu riche

```
Titre: "Concepts clés"
Format: 📝 Création de contenu riche
Contenu: Utilisez l'éditeur pour rédiger du texte formaté avec:
- Titres et sous-titres
- Listes à puces/numérotées
- Images
- Liens hypertexte
- Bloc de code
```

---

## 👨‍🎓 Pour les Étudiants

### Consulter une leçon

#### Via Application Mobile

1. **Ouvrez l'application** MayeleNet
2. Naviguez vers **Mes cours**
3. Sélectionnez un cours
4. Appuyez sur une leçon

#### Selon le type:

**📹 Vidéo**
- Lecteur vidéo intégré avec contrôles complets
- Lecture, pause, volume, plein écran
- Support du streaming (pas de téléchargement)

**📄 PDF**
- Visionneuse PDF intégrée
- Feuilletage page par page
- Zoom et lecture fluide

**📊 PowerPoint**
- Lecteur Office Online (Microsoft Viewer)
- Navigation diaporama
- Support complet des animations

**📝 Texte riche**
- Affichage optimisé du contenu
- Mise en page professionnelle
- Support des images intégrées

### Actions possibles

Pour **toutes** les leçons:
- ❤️ **Marquer comme favori** (cœur)
- 👍 **Aimer** (pouce)
- 💬 **Commenter** et discuter
- 📊 **Progression** automatique suivi

---

## ⚙️ Configuration Serveur

### Limites de fichiers

```
Taille maximum par fichier: 500 MB
Types acceptés:
  - Vidéo: MP4, AVI, MOV, MKV, FLV, WMV, WebM
  - PDF: .pdf
  - PowerPoint: .ppt, .pptx, .odp
  - Texte: HTML riche (via éditeur)
```

### API pour développeurs

**Créer une leçon via API:**
```bash
POST /api/lessons/

Content-Type: multipart/form-data

{
  "course": 1,
  "title": "Ma leçon",
  "content_type": "VIDEO",
  "content_file": <fichier>,
  "order": 1
}
```

**Récupérer une leçon:**
```bash
GET /api/lessons/{id}/

Response:
{
  "id": 1,
  "title": "Ma leçon",
  "content_type": "VIDEO",
  "content_file": "/media/lessons/video.mp4",
  "file_size": 150.5,
  "order": 1,
  "likes_count": 5,
  "comments_count": 2
}
```

---

## 🔒 Sécurité

- ✅ Validation des types de fichiers
- ✅ Limite de taille (500 MB)
- ✅ Stockage sécurisé sur serveur
- ✅ Accès contrôlé (étudiants inscrits uniquement)
- ✅ Extension de fichier vérifiée

---

## 🆘 Dépannage

### "Fichier trop volumineux"
- Réduisez la taille du fichier (max 500 MB)
- Compressez les vidéos
- Divisez en plusieurs leçons

### "Format non accepté"
- Vérifiez l'extension du fichier
- Extensions acceptées:
  - Vidéo: .mp4, .avi, .mov, .mkv, .flv, .wmv, .webm
  - PDF: .pdf
  - PowerPoint: .ppt, .pptx, .odp

### "Erreur lors du upload"
- Vérifiez votre connexion Internet
- Réessayez l'upload
- Contactez l'administrateur si le problème persiste

### La vidéo ne joue pas
- Assurez-vous que le format est compatible (MP4 recommandé)
- Vérifiez les permissions d'accès au fichier
- Essayez un autre format vidéo

---

## 📱 Compatibilité

| Platform | Support | Types acceptés |
|----------|---------|-----------------|
| **Mobile iOS** | ✅ Complète | Vidéo, PDF, PowerPoint, Texte |
| **Mobile Android** | ✅ Complète | Vidéo, PDF, PowerPoint, Texte |
| **Web** | ✅ Complète | PDF, PowerPoint (iFrame) |
| **Tablette** | ✅ Complète | Tous les types |

---

## 📊 Statistiques

Depuis le tableau de bord enseignant, suivez:
- 👥 Nombre d'étudiants inscrits
- 📊 Nombre de leçons créées
- ❤️ Nombre de likes reçus
- 💬 Nombre de commentaires

---

## ✨ Bonnes pratiques

### Pour les enseignants

1. **Titres clairs**: Utilisez des titres descriptifs
   - ❌ "Leçon 1"
   - ✅ "Introduction à la programmation orientée objet"

2. **Ordre logique**: Organisez les leçons de manière progressive
   - Théorie avant pratique
   - Concepts simples avant complexes

3. **Formats mixtes**: Combinez différents formats
   ```
   Leçon 1: Texte (introduction)
   Leçon 2: Vidéo (démonstration)
   Leçon 3: PDF (ressources supplémentaires)
   Leçon 4: PowerPoint (résumé)
   ```

4. **Fichiers optimisés**:
   - Compressez les vidéos (H.264, 1920x1080)
   - Réduisez la résolution PDF si possible
   - Limitez le nombre d'animations PowerPoint

### Pour les étudiants

1. **Téléchargez la version mobile**
2. **Consultez régulièrement les leçons**
3. **Participez avec des commentaires**
4. **Marquez les leçons importantes comme favoris**

---

## 📞 Support

Pour toute question ou problème:
- Contactez votre administrateur système
- Vérifiez la documentation officielle
- Consultez le forum d'aide

---

**Version:** 1.0  
**Dernière mise à jour:** Mai 2026  
**Système:** MayeleNet Learning Platform
