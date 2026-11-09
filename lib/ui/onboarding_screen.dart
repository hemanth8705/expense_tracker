import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    await context.read<AppState>().completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget point(IconData i, String t, String d) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(d, style: TextStyle(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Expense\nTracker', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1)),
            const SizedBox(height: 32),
            point(Icons.sms_outlined, 'Reads bank SMS only when you refresh',
                'Only debit and credit messages are kept. OTPs, offers and personal messages are ignored.'),
            point(Icons.lock_outline, 'Stays on this phone',
                'No account, no server. Everything is stored locally on your device.'),
            point(Icons.notifications_none, 'One reminder a day',
                'A daily notification with a Refresh button. Change the time in Settings.'),
            point(Icons.history, 'Starts with the last 3 months',
                'You can import older messages later from Settings.'),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _start,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Get started', style: TextStyle(fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
