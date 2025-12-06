import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/racebox_provider.dart';
import 'services/auth_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/reset_password_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize auth service
  final authService = AuthService();
  await authService.initialize();

  runApp(MyApp(authService: authService));
}

class MyApp extends StatelessWidget {
  final AuthService authService;

  const MyApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProxyProvider<AuthService, RaceboxProvider>(
          create: (_) => RaceboxProvider(),
          update: (_, authService, raceboxProvider) {
            raceboxProvider?.setAuthService(authService);
            return raceboxProvider!;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Racebox Exporter',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/forgot-password': (context) => const ForgotPasswordScreen(),
          '/dashboard': (context) => const DashboardScreen(),
        },
        onGenerateRoute: (settings) {
          // Handle routes with parameters
          if (settings.name == '/reset-password') {
            final token = settings.arguments as String?;
            if (token != null) {
              return MaterialPageRoute(
                builder: (context) => ResetPasswordScreen(token: token),
                settings: settings,
              );
            }
          }
          return null;
        },
      ),
    );
  }
}

/// Wrapper widget that shows login or dashboard based on auth state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        // Show loading while initializing
        if (!authService.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Show login if not authenticated
        if (!authService.isAuthenticated) {
          return const LoginScreen();
        }

        // Show dashboard if authenticated
        return const DashboardScreen();
      },
    );
  }
}
