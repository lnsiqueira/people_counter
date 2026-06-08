import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final String? subtitle;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 20, spreadRadius: 2)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text('$value',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 30, fontWeight: FontWeight.w700, color: color, height: 1)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white38, letterSpacing: 0.5)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(fontSize: 9, color: Colors.white24)),
          ],
        ],
      ),
    );
  }
}
