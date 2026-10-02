/// Catalogue de livres et manuels gratuits proposés aux étudiants Yekola.
/// Sources légales : domaine public, Creative Commons, OpenStax, Gutenberg, etc.
class FreeBooksCatalog {
  static const List<Map<String, dynamic>> books = [
    {
      'title': 'Introduction à la psychologie',
      'author': 'OpenStax',
      'description':
          'Manuel universitaire complet sur les bases de la psychologie : cognition, développement, personnalité et santé mentale.',
      'category': 'Livres gratuits',
      'subject': 'Sciences humaines',
      'language': 'FR / EN',
      'format': 'PDF',
      'is_free': true,
      'url': 'https://openstax.org/details/books/psychology-2e',
      'thumbnail_url':
          'https://images.openstax.org/previews/psychology-2e-book.jpg',
    },
    {
      'title': 'Biology 2e',
      'author': 'OpenStax',
      'description':
          'Biologie cellulaire, génétique, évolution et écologie — idéal pour les filières scientifiques et médicales.',
      'category': 'Livres gratuits',
      'subject': 'Sciences de la vie',
      'language': 'EN',
      'format': 'PDF / Web',
      'is_free': true,
      'url': 'https://openstax.org/details/books/biology-2e',
      'thumbnail_url':
          'https://images.openstax.org/previews/biology-2e-book.jpg',
    },
    {
      'title': 'Chemistry 2e',
      'author': 'OpenStax',
      'description':
          'Chimie générale : atomes, liaisons, thermodynamique et équilibres. Manuel clair avec exercices.',
      'category': 'Livres gratuits',
      'subject': 'Chimie',
      'language': 'EN',
      'format': 'PDF / Web',
      'is_free': true,
      'url': 'https://openstax.org/details/books/chemistry-2e',
      'thumbnail_url':
          'https://images.openstax.org/previews/chemistry-2e-book.jpg',
    },
    {
      'title': 'College Algebra',
      'author': 'OpenStax',
      'description':
          'Algèbre collégiale : fonctions, équations, polynômes et applications — base solide pour les études LMD.',
      'category': 'Livres gratuits',
      'subject': 'Mathématiques',
      'language': 'EN',
      'format': 'PDF / Web',
      'is_free': true,
      'url': 'https://openstax.org/details/books/college-algebra-2e',
      'thumbnail_url':
          'https://images.openstax.org/previews/college-algebra-2e-book.jpg',
    },
    {
      'title': 'Principles of Economics 3e',
      'author': 'OpenStax',
      'description':
          'Microéconomie et macroéconomie : marchés, croissance, inflation et politiques publiques.',
      'category': 'Livres gratuits',
      'subject': 'Économie',
      'language': 'EN',
      'format': 'PDF / Web',
      'is_free': true,
      'url': 'https://openstax.org/details/books/principles-economics-3e',
      'thumbnail_url':
          'https://images.openstax.org/previews/principles-economics-3e-book.jpg',
    },
    {
      'title': 'Introduction to Business',
      'author': 'OpenStax',
      'description':
          'Gestion, marketing, finance et entrepreneuriat — introduction pratique au monde des affaires.',
      'category': 'Livres gratuits',
      'subject': 'Gestion',
      'language': 'EN',
      'format': 'PDF / Web',
      'is_free': true,
      'url': 'https://openstax.org/details/books/introduction-business',
      'thumbnail_url':
          'https://images.openstax.org/previews/introduction-business-book.jpg',
    },
    {
      'title': 'American Government 3e',
      'author': 'OpenStax',
      'description':
          'Institutions politiques, droits civiques et participation citoyenne — utile en sciences politiques / droit comparé.',
      'category': 'Livres gratuits',
      'subject': 'Droit & Politique',
      'language': 'EN',
      'format': 'PDF / Web',
      'is_free': true,
      'url': 'https://openstax.org/details/books/american-government-3e',
      'thumbnail_url':
          'https://images.openstax.org/previews/american-government-3e-book.jpg',
    },
    {
      'title': 'University Physics Volume 1',
      'author': 'OpenStax',
      'description':
          'Mécanique, ondes et thermodynamique — physique universitaire avec démonstrations et problèmes.',
      'category': 'Livres gratuits',
      'subject': 'Physique',
      'language': 'EN',
      'format': 'PDF / Web',
      'is_free': true,
      'url': 'https://openstax.org/details/books/university-physics-volume-1',
      'thumbnail_url':
          'https://images.openstax.org/previews/university-physics-volume-1-book.jpg',
    },
    {
      'title': 'Anatomy and Physiology 2e',
      'author': 'OpenStax',
      'description':
          'Anatomie et physiologie humaine : systèmes du corps, homéostasie — pour médecine, soins et biologie.',
      'category': 'Livres gratuits',
      'subject': 'Médecine / Santé',
      'language': 'EN',
      'format': 'PDF / Web',
      'is_free': true,
      'url': 'https://openstax.org/details/books/anatomy-and-physiology-2e',
      'thumbnail_url':
          'https://images.openstax.org/previews/anatomy-and-physiology-2e-book.jpg',
    },
    {
      'title': 'Writing Guide with Handbook',
      'author': 'OpenStax',
      'description':
          'Guide de rédaction académique : structure, argumentation, citations — essentiel pour les mémoires et rapports.',
      'category': 'Livres gratuits',
      'subject': 'Méthodologie',
      'language': 'EN',
      'format': 'PDF / Web',
      'is_free': true,
      'url': 'https://openstax.org/details/books/writing-guide',
      'thumbnail_url':
          'https://images.openstax.org/previews/writing-guide-book.jpg',
    },
    {
      'title': 'Les Misérables',
      'author': 'Victor Hugo',
      'description':
          'Chef-d\'œuvre de la littérature française (domaine public). Disponible gratuitement via Project Gutenberg.',
      'category': 'Livres gratuits',
      'subject': 'Littérature',
      'language': 'FR',
      'format': 'ePub / HTML',
      'is_free': true,
      'url': 'https://www.gutenberg.org/ebooks/17489',
      'thumbnail_url':
          'https://www.gutenberg.org/cache/epub/17489/pg17489.cover.medium.jpg',
    },
    {
      'title': 'Candide',
      'author': 'Voltaire',
      'description':
          'Conte philosophique classique, domaine public — lecture accessible pour les étudiants en lettres et philosophie.',
      'category': 'Livres gratuits',
      'subject': 'Littérature',
      'language': 'FR',
      'format': 'ePub / HTML',
      'is_free': true,
      'url': 'https://www.gutenberg.org/ebooks/4650',
      'thumbnail_url':
          'https://www.gutenberg.org/cache/epub/4650/pg4650.cover.medium.jpg',
    },
    {
      'title': 'Le Comte de Monte-Cristo',
      'author': 'Alexandre Dumas',
      'description':
          'Roman d\'aventure et de justice, domaine public. Excellent pour enrichir la culture littéraire.',
      'category': 'Livres gratuits',
      'subject': 'Littérature',
      'language': 'FR',
      'format': 'ePub / HTML',
      'is_free': true,
      'url': 'https://www.gutenberg.org/ebooks/17989',
      'thumbnail_url':
          'https://www.gutenberg.org/cache/epub/17989/pg17989.cover.medium.jpg',
    },
    {
      'title': 'Discourse on the Method',
      'author': 'René Descartes',
      'description':
          'Discours de la méthode (version anglaise domaine public) — fondements de la pensée rationnelle moderne.',
      'category': 'Livres gratuits',
      'subject': 'Philosophie',
      'language': 'EN',
      'format': 'ePub / HTML',
      'is_free': true,
      'url': 'https://www.gutenberg.org/ebooks/59',
      'thumbnail_url':
          'https://www.gutenberg.org/cache/epub/59/pg59.cover.medium.jpg',
    },
    {
      'title': 'The Art of War',
      'author': 'Sun Tzu',
      'description':
          'Traité classique de stratégie, domaine public — utile en management, leadership et sciences sociales.',
      'category': 'Livres gratuits',
      'subject': 'Stratégie',
      'language': 'EN',
      'format': 'ePub / HTML',
      'is_free': true,
      'url': 'https://www.gutenberg.org/ebooks/132',
      'thumbnail_url':
          'https://www.gutenberg.org/cache/epub/132/pg132.cover.medium.jpg',
    },
    {
      'title': 'Bibliothèque numérique Gallica',
      'author': 'BnF',
      'description':
          'Accès à des millions d\'ouvrages numérisés de la Bibliothèque nationale de France (gratuits).',
      'category': 'Livres gratuits',
      'subject': 'Bibliothèque',
      'language': 'FR',
      'format': 'Web',
      'is_free': true,
      'url': 'https://gallica.bnf.fr/',
      'thumbnail_url':
          'https://gallica.bnf.fr/images/static/accueil/banner_gallica.png',
    },
    {
      'title': 'Internet Archive — Open Library',
      'author': 'Internet Archive',
      'description':
          'Catalogue mondial de livres empruntables ou en domaine public : sciences, histoire, technique.',
      'category': 'Livres gratuits',
      'subject': 'Bibliothèque',
      'language': 'Multi',
      'format': 'Web / PDF',
      'is_free': true,
      'url': 'https://openlibrary.org/',
      'thumbnail_url':
          'https://archive.org/images/logo.jpg',
    },
    {
      'title': 'Directory of Open Access Books (DOAB)',
      'author': 'DOAB',
      'description':
          'Répertoire de livres académiques en libre accès (peer-reviewed) pour l\'enseignement supérieur.',
      'category': 'Livres gratuits',
      'subject': 'Recherche',
      'language': 'Multi',
      'format': 'PDF',
      'is_free': true,
      'url': 'https://www.doabooks.org/',
      'thumbnail_url':
          'https://www.doabooks.org/themes/custom/doab/logo.svg',
    },
  ];

  static List<String> get subjects {
    final set = books.map((b) => b['subject'] as String).toSet().toList()..sort();
    return ['Tous', ...set];
  }
}
