import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';
import 'screens/role_selection_screen.dart';
// Services
import 'services/database_factory_helper.dart';
import 'services/notification_service.dart';
// Screens
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/doctor_login_screen.dart';        
import 'screens/doctor_dashboard_screen.dart';
import 'screens/admin_login_screen.dart';          // ← NEW
import 'screens/admin_dashboard_screen.dart';      // ← NEW
// Providers
import 'providers/auth_provider.dart';
import 'providers/sync_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize database factory for all platforms
  await initializeDatabaseFactory();

  // Platform-specific initialization
  if (!kIsWeb) {
    // Mobile-specific services
    print('Running on mobile - initializing mobile services');
    await NotificationService.instance.initialize();
  } else {
    print('Running on web - web mode active');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
      ],
      child: MaterialApp(
        title: 'Health & Nutrition App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.deepPurple,
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const RoleSelectionScreen(),
          '/login': (context) => LoginScreen(),
          '/signup': (context) => SignupScreen(),
          '/home': (context) => HomeScreen(),
          '/doctor-login': (context) => DoctorLoginScreen(),
          '/doctor-dashboard': (context) => DoctorDashboardScreen(),
          '/admin-login': (context) => const AdminLoginScreen(),        // ← NEW
          '/admin-dashboard': (context) => const AdminDashboardScreen(), // ← NEW
        },
      ),
    );
  }
}