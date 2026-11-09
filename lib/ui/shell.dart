import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notifications.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'home_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  int _handledRefreshRequests = 0;
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    WidgetsBinding.instance.addObserver(this);
    Notifications.refreshRequests.addListener(_onNotificationRefresh);
    _state.addListener(_onState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // First run: import the last 3 months straight away.
      // Cold start from the notification: refresh as requested.
      if (_state.settings.lastScanMs == null) {
        _handledRefreshRequests = Notifications.refreshRequests.value;
        runRefresh(context);
      } else {
        _onNotificationRefresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Notifications.refreshRequests.removeListener(_onNotificationRefresh);
    _state.removeListener(_onState);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _state.onResume();
  }

  void _onNotificationRefresh() {
    final v = Notifications.refreshRequests.value;
    if (v == _handledRefreshRequests || !mounted) return;
    _handledRefreshRequests = v;
    setState(() => _tab = 0);
    runRefresh(context);
  }

  void _onState() {
    if (_state.pendingTxnView != null && _tab != 1 && mounted) {
      setState(() => _tab = 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: const [
        HomeScreen(),
        TransactionsScreen(),
        ReportsScreen(),
        SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transactions'),
          NavigationDestination(
              icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
