from django.contrib.auth.hashers import PBKDF2PasswordHasher


class FastPBKDF2PasswordHasher(PBKDF2PasswordHasher):
    """
    PBKDF2 avec moins d'itérations que le défaut Django 6 (1_200_000).
    Garde une sécurité correcte tout en rendant la connexion utilisable (~0,3–0,5 s).
    Les anciens hash 1_200_000 restent vérifiables ; ils sont réécrits au login réussi.
    """

    iterations = 60_000
