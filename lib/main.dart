import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/notifications.dart';
import 'services/repository.dart';
import 'services/settings.dart';
import 'state/app_state.dart';
import 'ui/onboarding_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw something immediately. Startup work runs behind this screen, so a
  // slow or failing plugin can never leave the app blank.
  runApp(const BootApp());
}

/// Runs one startup step with a time limit and a log line.
/// Non-critical steps swallow errors so the app still opens.
Future<T?> _step<T>(String name, Future<T> Function() run,
    {Duration timeout = const Duration(seconds: 8), bool critical = false}) async {
  final sw = Stopwatch()..start();
  try {
    final v = await run().timeout(timeout);
    debugPrint('[boot] $name ok (${sw.elapsedMilliseconds} ms)');
    return v;
  } catch (e, st) {
    debugPrint('[boot] $name FAILED after ${sw.elapsedMilliseconds} ms: $e');
    if (critical) Error.throwWithStackTrace(e, st);
    return null;
  }
}

Future<AppState> _boot() async {
  final settings = (await _step('settings', Settings.load, critical: true))!;
  final repo = (await _step('database', () => Repository.open(), timeout: const Duration(seconds: 30), critical: true))!;
  final state = AppState(repo, settings);
  await _step('notifications', Notifications.init);
  await _step('state', state.init);
  return state;
}

class BootApp extends StatefulWidget {
  const BootApp({super.key});
  @override
  State<BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<BootApp> {
  late Future<AppState> _future = _boot();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) {
          return ChangeNotifierProvider.value(value: snap.data!, child: const ExpenseApp());
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: snap.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, size: 40),
                        const SizedBox(height: 12),
                        const Text('The app could not start', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('${snap.error}', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => setState(() => _future = _boot()),
                          child: const Text('Try again'),
                        ),
                      ]),
                    )
                  : Image.asset('assets/logo.png', width: 72, height: 72),
            ),
          ),
        );
      },
    );
  }
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final onboarded = context.select<AppState, bool>((s) => s.settings.onboarded);
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: onboarded ? const HomeShell() : const OnboardingScreen(),
    );
  }
}
