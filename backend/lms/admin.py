from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User, Course, Lesson, Enrollment, Evaluation, Grade, ExternalResource

@admin.register(User)
class CustomUserAdmin(UserAdmin):
    list_display = ('username', 'email', 'first_name', 'last_name', 'role', 'is_staff')
    list_filter = ('role', 'is_staff', 'is_active')
    search_fields = ('username', 'email', 'first_name', 'last_name')
    fieldsets = UserAdmin.fieldsets + (
        ('Informations supplémentaires', {'fields': ('role', 'phone', 'class_group', 'assigned_university', 'assigned_faculty', 'assigned_promotion')}),
    )

@admin.register(Course)
class CourseAdmin(admin.ModelAdmin):
    list_display = ('title', 'teacher', 'is_published', 'created_at')
    list_filter = ('is_published', 'created_at')
    search_fields = ('title', 'teacher__username')
    exclude = ('price', 'is_free')

@admin.register(Lesson)
class LessonAdmin(admin.ModelAdmin):
    list_display = ('title', 'course', 'content_type', 'order')
    list_filter = ('content_type',)
    search_fields = ('title', 'course__title')

@admin.register(ExternalResource)
class ExternalResourceAdmin(admin.ModelAdmin):
    list_display = ('title', 'category', 'url', 'created_at')
    list_filter = ('category', 'created_at')
    search_fields = ('title', 'description', 'url')

admin.site.register(Enrollment)
admin.site.register(Evaluation)
admin.site.register(Grade)

