"""Utilitaires création de comptes étudiants (décanat / import)."""
import re
import unicodedata


def normalize_name_part(value: str) -> str:
    text = (value or '').strip()
    if not text:
        return ''
    text = unicodedata.normalize('NFD', text)
    text = ''.join(c for c in text if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9]', '', text.lower())


def gmail_from_prenom_nom(prenom: str, nom: str, matricule: str = '', used: set | None = None) -> str:
    """Génère prenom+nom@gmail.com (ex. exauce + mpoyi → exaucempoyi@gmail.com)."""
    used = used or set()
    base = normalize_name_part(prenom) + normalize_name_part(nom)
    if not base:
        base = normalize_name_part(matricule) or 'etudiant'

    email = f'{base}@gmail.com'
    if email not in used:
        used.add(email)
        return email

    suffix = re.sub(r'[^a-z0-9]', '', (matricule or '').lower())[-6:] or '1'
    candidate = f'{base}{suffix}@gmail.com'
    n = 2
    while candidate in used:
        candidate = f'{base}{suffix}{n}@gmail.com'
        n += 1
    used.add(candidate)
    return candidate


def split_student_names(nom: str, postnom: str, prenom: str):
    """Retourne (first_name, last_name) pour le modèle User."""
    prenom = (prenom or '').strip()
    last = ' '.join(p for p in [(nom or '').strip(), (postnom or '').strip()] if p).strip()
    if prenom:
        return prenom[:150], last[:150]
    parts = last.split(None, 1)
    if parts:
        return parts[0][:150], (parts[1][:150] if len(parts) > 1 else '')
    return '', ''
