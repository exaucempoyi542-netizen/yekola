import 'package:flutter/material.dart';
import '../services/sync_service.dart';

class QuizScreen extends StatefulWidget {
  final Map<String, dynamic> quiz;

  const QuizScreen({super.key, required this.quiz});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final SyncService _syncService = SyncService();
  int _currentQuestionIndex = 0;
  final Map<int, int> _selectedChoices = {};
  bool _isSubmitting = false;

  static const Color _primary = Color(0xFF152A45);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _submitQuiz() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    List<Map<String, dynamic>> answers = [];
    _selectedChoices.forEach((questionId, choiceId) {
      answers.add({
        'question_id': questionId,
        'choice_id': choiceId,
      });
    });

    final result = await _syncService.submitQuiz(widget.quiz['id'], answers);

    if (mounted) {
      if (result != null) {
        _showResultDialog(result);
      } else {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la soumission. Vérifiez votre connexion et réessayez.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Réinitialiser les réponses et recommencer depuis le début
  void _restartQuiz() {
    setState(() {
      _currentQuestionIndex = 0;
      _selectedChoices.clear();
      _isSubmitting = false;
    });
  }

  void _showResultDialog(Map<String, dynamic> result) {
    final score = (result['score'] ?? 0.0).toDouble();
    final correct = result['correct_count'] ?? 0;
    final total = result['total_questions'] ?? 0;
    final isGood = score >= 50;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon cercle
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isGood ? Colors.green.shade50 : Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isGood ? Icons.check_circle_outline : Icons.refresh_rounded,
                size: 48,
                color: isGood ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isGood ? '🎉 Quiz réussi !' : 'Quiz échoué',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isGood ? Colors.green[700] : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$correct / $total questions correctes',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              'Score : ${score.toStringAsFixed(0)} / 100',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: isGood ? Colors.green : Colors.orange,
              ),
            ),
            if (!isGood) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Il vous faut au moins 50% pour passer au module suivant. Vous pouvez recommencer autant de fois que nécessaire.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.orange),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  if (isGood) {
                    Navigator.pop(context, true); // return to lesson player
                  } else {
                    _restartQuiz();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text(
                  isGood ? 'CONTINUER LE COURS' : 'RECOMMENCER LE QUIZ',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (!isGood) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pop(context); // exit quiz
                },
                child: Text('Quitter pour le moment', style: TextStyle(color: Colors.grey[600])),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> questions = widget.quiz['questions'] ?? [];
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.quiz['title'] ?? 'Quiz'),
          backgroundColor: _primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Ce quiz ne contient aucune question.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final currentQuestion = questions[_currentQuestionIndex];
    final List<dynamic> choices = currentQuestion['choices'] ?? [];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.quiz['title'] ?? 'Quiz', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _primary,
        // Pas de timer — l'étudiant prend tout son temps
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (_currentQuestionIndex + 1) / questions.length,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(_primary),
            minHeight: 6,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question counter
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Question ${_currentQuestionIndex + 1} / ${questions.length}',
                          style: const TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Question text
                  Text(
                    currentQuestion['text'] ?? '',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Choices
                  Expanded(
                    child: ListView.builder(
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final choice = choices[index];
                        final isSelected = _selectedChoices[currentQuestion['id']] == choice['id'];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedChoices[currentQuestion['id']] = choice['id'];
                              });
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: isSelected ? _primary.withValues(alpha: 0.08) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? _primary : Colors.grey[300]!,
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [BoxShadow(color: _primary.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2))]
                                    : [],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? _primary : Colors.grey[400]!,
                                        width: 2,
                                      ),
                                      color: isSelected ? _primary : Colors.transparent,
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      choice['text'] ?? '',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? _primary : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Navigation buttons
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -4)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentQuestionIndex > 0)
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _currentQuestionIndex--;
                      });
                    },
                    icon: const Icon(Icons.arrow_back_ios, size: 14),
                    label: const Text('Précédent'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: const BorderSide(color: _primary),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          if (_currentQuestionIndex < questions.length - 1) {
                            setState(() {
                              _currentQuestionIndex++;
                            });
                          } else {
                            _submitQuiz();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          _currentQuestionIndex < questions.length - 1 ? 'Suivant →' : 'Terminer',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
