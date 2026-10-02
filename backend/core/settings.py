"""
Django settings for core project — Yekola
"""

from pathlib import Path
import os
import mimetypes
from dotenv import load_dotenv

# Charger les variables d'environnement depuis .env
load_dotenv(Path(__file__).resolve().parent.parent / '.env')

mimetypes.add_type("application/pdf", ".pdf", True)

# Enregistrer PyMySQL comme remplacement de MySQLdb (driver pur Python)
import pymysql
pymysql.install_as_MySQLdb()

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent


# Quick-start development settings - unsuitable for production
# See https://docs.djangoproject.com/en/6.0/howto/deployment/checklist/

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = os.getenv('SECRET_KEY', 'django-insecure-02t+2ixab48xp1xc485psjhie+83j0*$)e-1=0ho5v&0et-gn*')

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = True

ALLOWED_HOSTS = ['127.0.0.1', 'localhost', '10.188.20.244', '10.196.177.244', '10.213.60.244', '*']


# Application definition 

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'corsheaders',
    'rest_framework_simplejwt',
    'lms',
    'teacher',
    'super_admin',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'core.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
                'teacher.context_processors.teacher_promotion_context',
            ],
        },
    },
]

WSGI_APPLICATION = 'core.wsgi.application'


# Database
# https://docs.djangoproject.com/en/6.0/ref/settings/#databases

DATABASES = {
    'default': {
        'ENGINE': 'custom_db_backend',  # Backend custom pour bypasser le check MariaDB 10.4
        'NAME': os.getenv('DB_NAME', 'edurdc_db'),
        'USER': os.getenv('DB_USER', 'root'),
        'PASSWORD': os.getenv('DB_PASSWORD', ''),
        'HOST': os.getenv('DB_HOST', '127.0.0.1'),
        'PORT': os.getenv('DB_PORT', '3306'),
        'CONN_MAX_AGE': 60,
        'OPTIONS': {
            'charset': 'utf8mb4',
        },
    }
}

# Django 6 utilise 1_200_000 itérations PBKDF2 (~2–3 s / login sur cette machine).
# Hasher plus léger en premier ; l'ancien reste pour vérifier les hash existants.
PASSWORD_HASHERS = [
    'lms.hashers.FastPBKDF2PasswordHasher',
    'django.contrib.auth.hashers.PBKDF2PasswordHasher',
]




# Password validation
# https://docs.djangoproject.com/en/6.0/ref/settings/#auth-password-validators

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]


# Internationalization
# https://docs.djangoproject.com/en/6.0/topics/i18n/

LANGUAGE_CODE = 'en-us'

TIME_ZONE = 'UTC'

USE_I18N = True

USE_TZ = True


# Static files (CSS, JavaScript, Images)
# https://docs.djangoproject.com/en/6.0/howto/static-files/

STATIC_URL = '/static/'
STATICFILES_DIRS = [BASE_DIR / 'static']
STATIC_ROOT = BASE_DIR / 'staticfiles'

# Media files (Uploaded by teachers)
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

# Custom User Model
AUTH_USER_MODEL = 'lms.User'

# Default primary key field type
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# CORS Configuration
CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True
CORS_EXPOSE_HEADERS = [
    'Content-Type',
    'Content-Length',
    'Content-Range',
    'Accept-Ranges',
]
CORS_ALLOW_HEADERS = [
    'accept',
    'accept-encoding',
    'authorization',
    'content-type',
    'dnt',
    'origin',
    'user-agent',
    'x-csrftoken',
    'x-requested-with',
    'range',
]

# Un seul backend : EmailBackend couvre déjà username / email / matricule.
# Évite un 2e check_password (~2–3 s) quand le mot de passe est faux.
AUTHENTICATION_BACKENDS = [
    'lms.backends.EmailBackend',
]

# Auth Configuration
LOGIN_URL = '/login/'
LOGIN_REDIRECT_URL = '/login/'

# DRF Configuration
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
        'rest_framework.authentication.SessionAuthentication',
        'rest_framework.authentication.BasicAuthentication',
    )
}

from datetime import timedelta
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(days=30),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=90),
}

# Mot de passe initial pour les comptes étudiants créés par le décanat (si non personnalisé)
STUDENT_DEFAULT_PASSWORD = 'uwb2026'
STUDENT_PASSWORD_MIN_LENGTH = 6

# Allow iframes for PDF viewing
X_FRAME_OPTIONS = 'SAMEORIGIN'

# Paramètres Jazzmin supprimés
CSRF_TRUSTED_ORIGINS = ['http://127.0.0.1:8000', 'http://localhost:8000']
CSRF_FAILURE_VIEW = 'core.csrf.csrf_failure'
# Évite les conflits de cookies si on alterne localhost / 127.0.0.1
CSRF_COOKIE_SAMESITE = 'Lax'
SESSION_COOKIE_SAMESITE = 'Lax'

# File Upload Configuration
MAX_UPLOAD_SIZE = 1024 * 1024 * 1024  # 1 GB
LESSON_FILE_UPLOAD_SIZE = 1024 * 1024 * 1024  # 1 GB
ALLOWED_VIDEO_EXTENSIONS = ['.mp4', '.avi', '.mov', '.mkv', '.flv', '.wmv', '.webm', '.m4v', '.3gp', '.mpeg', '.mpg']
ALLOWED_PDF_EXTENSIONS = ['.pdf']
ALLOWED_PPT_EXTENSIONS = ['.ppt', '.pptx', '.odp', '.ppsx', '.pps', '.potx', '.pot']
DATA_UPLOAD_MAX_MEMORY_SIZE = 1024 * 1024 * 1024  # 1 GB
FILE_UPLOAD_MAX_MEMORY_SIZE = 512 * 1024 * 1024   # 512 MB (keep memory usage reasonable)
