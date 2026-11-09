import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/notifications.dart';
import 'services/repository.dart';
import 'services/settings.dart';
import 'state/app_state.dart';
import 'ui/onboarding_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final repo = await Repository.open();
  final state = AppState(repo, settings);
  await Notifications.init();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const ExpenseApp()));
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
