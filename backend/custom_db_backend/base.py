"""
Backend MySQL personnalisé qui bypasse la vérification de version MariaDB.
Cela permet d'utiliser MariaDB 10.4 avec Django 4.2+.
"""
from django.db.backends.mysql.base import DatabaseWrapper as MySQLDatabaseWrapper
from django.db.backends.mysql.features import DatabaseFeatures as MySQLDatabaseFeatures

class DatabaseFeatures(MySQLDatabaseFeatures):
    can_return_columns_from_insert = False
    can_return_rows_from_bulk_insert = False

class DatabaseWrapper(MySQLDatabaseWrapper):
    """Wrapper qui désactive la vérification de version MariaDB."""
    features_class = DatabaseFeatures

    def check_database_version_supported(self):
        """On bypasse le check de version pour permettre MariaDB 10.4."""
        pass
