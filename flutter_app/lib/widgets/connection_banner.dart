import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ConnectionBanner extends StatelessWidget {
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const ConnectionBanner({
    super.key,
    required this.connected,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: connected
            ? const Color(0xFF00F5A0).withOpacity(0.08)
            : const Color(0xFFFF4E6A).withOpacity(0.08),
        border: Border(
          bottom: BorderSide(
            color: connected
                ? const Color(0xFF00F5A0).withOpacity(0.2)
                : const Color(0xFFFF4E6A).withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? const Color(0xFF00F5A0) : const Color(0xFFFF4E6A),
              boxShadow: [
                BoxShadow(
                  color: connected
                      ? const Color(0xFF00F5A0).withOpacity(0.5)
                      : const Color(0xFFFF4E6A).withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            connected ? 'Conectado · ws://localhost:8765' : 'Desconectado',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              color: connected ? const Color(0xFF00F5A0) : const Color(0xFFFF4E6A),
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: connected ? onDisconnect : onConnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xFFFF4E6A).withOpacity(0.15)
                    : const Color(0xFF00F5A0).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: connected
                      ? const Color(0xFFFF4E6A).withOpacity(0.4)
                      : const Color(0xFF00F5A0).withOpacity(0.4),
                ),
              ),
              child: Text(
                connected ? 'Desconectar' : 'Conectar',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: connected ? const Color(0xFFFF4E6A) : const Color(0xFF00F5A0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
