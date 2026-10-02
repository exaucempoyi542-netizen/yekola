from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('lms', '0042_user_profile_completed'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='gender',
            field=models.CharField(
                blank=True,
                choices=[('M', 'Masculin'), ('F', 'Féminin')],
                default='',
                help_text="Sexe de l'étudiant (renseigné par le décanat).",
                max_length=1,
            ),
        ),
    ]
