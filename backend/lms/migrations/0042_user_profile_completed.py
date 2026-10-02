from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('lms', '0041_grade_flow_dean_then_manager'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='profile_completed',
            field=models.BooleanField(
                default=True,
                help_text="False tant que l'étudiant n'a pas renseigné son adresse Gmail.",
            ),
        ),
    ]
