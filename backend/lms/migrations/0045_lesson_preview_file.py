from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('lms', '0044_user_role_db_index'),
    ]

    operations = [
        migrations.AddField(
            model_name='lesson',
            name='preview_file',
            field=models.FileField(blank=True, null=True, upload_to='lessons/previews/'),
        ),
    ]
