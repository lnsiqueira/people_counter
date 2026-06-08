import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const PeopleCounterApp());
}

class PeopleCounterApp extends StatelessWidget {
  const PeopleCounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'People Counter AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00F5A0),
          secondary: const Color(0xFF00D9F5),
          surface: const Color(0xFF111827),
        ),
        textTheme: GoogleFonts.spaceGroteskTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
