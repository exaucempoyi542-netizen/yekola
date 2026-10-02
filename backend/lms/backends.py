from django.contrib.auth import get_user_model
from django.contrib.auth.backends import ModelBackend

User = get_user_model()


class EmailBackend(ModelBackend):
    """Auth rapide : username indexé d'abord, puis email / matricule."""

    def authenticate(self, request, username=None, password=None, **kwargs):
        if username is None:
            username = kwargs.get(User.USERNAME_FIELD)
        if not username or password is None:
            return None

        username = username.strip()
        user = self._find_user(username)
        if user is None:
            return None

        if user.check_password(password) and self.user_can_authenticate(user):
            return user
        return None

    def _find_user(self, username):
        # Chemin rapide (index unique username) — exact puis insensible à la casse
        user = User.objects.filter(username=username).first()
        if user is not None:
            return user

        user = User.objects.filter(username__iexact=username).first()
        if user is not None:
            return user

        # Matricule (contrainte unique, casse flexible)
        user = User.objects.filter(matricule__iexact=username).first()
        if user is not None:
            return user

        # Email seulement si ça ressemble à un email
        if '@' in username:
            return User.objects.filter(email__iexact=username).first()
        return None
