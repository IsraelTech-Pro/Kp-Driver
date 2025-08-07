import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class HelpPage extends StatefulWidget {
  final String driverId;
  const HelpPage({Key? key, required this.driverId}) : super(key: key);

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _feedbackController = TextEditingController();
  bool _sending = false;
  String? _feedbackStatus;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _sending = true; _feedbackStatus = null; });
    final supabase = Supabase.instance.client;
    try {
      await supabase.from('driver_feedback').insert({
        'driver_id': widget.driverId,
        'message': _feedbackController.text,
      });
      setState(() { _feedbackStatus = 'Thank you for your feedback!'; });
      _feedbackController.clear();
    } catch (e) {
      setState(() { _feedbackStatus = 'Failed to send feedback.'; });
    } finally {
      setState(() { _sending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F2),
      appBar: AppBar(
        title: const Text('Help & Support', style: TextStyle(color: Color(0xFFCFA72E), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFCFA72E)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Animated FAQ
            Row(
              children: [
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1 + 0.05 * _animationController.value,
                      child: child,
                    );
                  },
                  child: const Icon(Icons.help_outline, color: Color(0xFFCFA72E), size: 32),
                ),
                const SizedBox(width: 10),
                const Text('Frequently Asked Questions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 12),
            _buildFAQCard('How do I use navigation?', 'Tap the navigation icon on any ride to open your preferred maps app.'),
            _buildFAQCard('How do I contact support?', 'Use the support options below or send feedback.'),
            _buildFAQCard('How do I view my ride history?', 'Go to the Rides tab to see all your completed and uncompleted rides.'),
            const SizedBox(height: 30),

            // Feedback Form
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: 0.2 * _animationController.value,
                              child: child,
                            );
                          },
                          child: const Icon(Icons.feedback, color: Colors.blueAccent, size: 28),
                        ),
                        const SizedBox(width: 8),
                        const Text('Send Feedback', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _feedbackController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Describe your issue, suggestion, or question...',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      ),
                      validator: (val) => (val == null || val.trim().isEmpty) ? 'Feedback cannot be empty' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _sending ? null : _submitFeedback,
                          icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
                          label: const Text('Send'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFCFA72E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                        if (_feedbackStatus != null) ...[
                          const SizedBox(width: 14),
                          Text(_feedbackStatus!, style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Support Options
            Text('Contact Support', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFCFA72E))),
            const SizedBox(height: 12),
            Row(
              children: [
                _supportButton(Icons.email, 'Email', Colors.blue, () {
                  // TODO: Implement email launch
                }),
                const SizedBox(width: 16),
                _supportButton(Icons.phone, 'Call', Colors.green, () {
                  // TODO: Implement phone launch
                }),
                const SizedBox(width: 16),
                _supportButton(FontAwesomeIcons.whatsapp, 'WhatsApp', Colors.teal, () {
                  // TODO: Implement WhatsApp launch
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQCard(String question, String answer) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFCFA72E))),
          const SizedBox(height: 4),
          Text(answer, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _supportButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: onTap,
      ),
    );
  }
}
