def teacher_promotion_context(request):
    """Expose les promotions actives de l'enseignant à tous les templates."""
    user = getattr(request, 'user', None)
    if not user or not user.is_authenticated or getattr(user, 'role', None) != 'TEACHER':
        return {}

    try:
        from teacher.views import _get_selected_teacher_promotion
        promotions, selected = _get_selected_teacher_promotion(request, user)
    except Exception:
        return {}

    return {
        'teacher_promotions': promotions,
        'current_promotion': selected,
    }
