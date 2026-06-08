import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/counter_stats.dart';
import '../services/websocket_service.dart';
import '../widgets/connection_banner.dart';
import '../widgets/stat_card.dart';
import 'log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  //static const _wsUrl = 'ws://localhost:8765';
  static const _wsUrl = 'ws://localhost:8000/ws';
  //static const _wsUrl = 'wss://people-counter-api.azurewebsites.net/ws';

  late WebSocketService _ws;
  bool _connected = false;
  Uint8List? _frame;
  CounterStats _stats = CounterStats.empty();

  // Log acumulado localmente — nunca zerado
  final List<PersonEvent> _log = [];

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Badge de novos eventos
  int _newEventCount = 0;

  @override
  void initState() {
    super.initState();
    _ws = WebSocketService(_wsUrl);

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _ws.connectionStream.listen((c) => setState(() => _connected = c));
    _ws.frameStream.listen((f) => setState(() => _frame = f));

    // Ao receber stats, mergeia novos eventos no log local
    _ws.statsStream.listen((s) {
      setState(() {
        _stats = s;
        _mergeEvents(s.recentEvents);
      });
    });

    // Ao conectar, recebe log histórico completo do servidor
    _ws.fullLogStream.listen((events) {
      setState(() {
        _log.clear();
        _log.addAll(events);
      });
    });
  }

  /// Insere eventos que ainda não estão no log (evita duplicatas via unix timestamp + id)
  void _mergeEvents(List<PersonEvent> incoming) {
    final existingKeys = _log
        .map((e) => '${e.trackId}_${e.direction}_${e.unix.toStringAsFixed(0)}')
        .toSet();
    int added = 0;
    for (final ev in incoming) {
      final key = '${ev.trackId}_${ev.direction}_${ev.unix.toStringAsFixed(0)}';
      if (!existingKeys.contains(key)) {
        _log.add(ev);
        added++;
      }
    }
    if (added > 0) {
      // Ordena por unix
      _log.sort((a, b) => a.unix.compareTo(b.unix));
      _newEventCount += added;
    }
  }

  @override
  void dispose() {
    _ws.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_connected)
      _ws.disconnect();
    else
      _ws.connect();
  }

  void _openLog() {
    setState(() => _newEventCount = 0);
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => LogScreen(events: List.unmodifiable(_log))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Column(children: [
              _buildHeader(),
              ConnectionBanner(
                  connected: _connected,
                  onConnect: _toggle,
                  onDisconnect: _toggle),
            ]),
          ),
          Expanded(
            child: LayoutBuilder(builder: (ctx, constraints) {
              return constraints.maxWidth > 700
                  ? _buildWideLayout()
                  : _buildNarrowLayout();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00F5A0), Color(0xFF00D9F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.people_alt_rounded,
                color: Color(0xFF0A0E1A), size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('People Counter',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              Row(children: [
                Text('YOLOv8 + ReID',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        color: Colors.white38,
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _stats.reidActive
                        ? const Color(0xFF00F5A0).withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _stats.reidActive
                          ? const Color(0xFF00F5A0).withOpacity(0.4)
                          : Colors.white12,
                    ),
                  ),
                  child: Text(
                    _stats.reidActive ? '● ReID ON' : '○ ReID OFF',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _stats.reidActive
                          ? const Color(0xFF00F5A0)
                          : Colors.white24,
                    ),
                  ),
                ),
              ]),
            ],
          ),
          const Spacer(),
          // Botão de log com badge
          GestureDetector(
            onTap: _openLog,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.list_alt_rounded,
                          size: 16, color: Color(0xFFFFD166)),
                      const SizedBox(width: 6),
                      Text('Log  ${_log.length}',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              color: const Color(0xFFFFD166),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (_newEventCount > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF4E6A),
                        shape: BoxShape.circle,
                      ),
                      child: Text('$_newEventCount',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildVideoPanel(),
        const SizedBox(height: 16),
        _buildStatsGrid(),
        const SizedBox(height: 16),
        _buildOccupancyBar(),
        const SizedBox(height: 16),
        _buildMiniLog(),
      ]),
    );
  }

  Widget _buildWideLayout() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _buildVideoPanel()),
          const SizedBox(width: 20),
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              child: Column(children: [
                _buildStatsGrid(),
                const SizedBox(height: 16),
                _buildOccupancyBar(),
                const SizedBox(height: 16),
                _buildMiniLog(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPanel() {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _connected
                ? const Color(0xFF00F5A0).withOpacity(0.25)
                : Colors.white10,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: _frame != null
            ? Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.cover)
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Opacity(
              opacity: _pulseAnim.value,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00F5A0).withOpacity(0.08),
                ),
                child: const Icon(Icons.videocam_outlined,
                    size: 48, color: Color(0xFF00F5A0)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _connected
                ? 'Aguardando frames...'
                : 'Clique em Conectar para iniciar',
            style:
                GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Column(
      children: [
        // ── Card destaque: Total de Pessoas Únicas ───────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFFB340).withOpacity(0.15),
                const Color(0xFFFF6B00).withOpacity(0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: const Color(0xFFFFB340).withOpacity(0.35), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB340).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.people_alt_rounded,
                    color: Color(0xFFFFB340), size: 28),
              ),
              const SizedBox(width: 18),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_stats.totalUnique}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFFFB340),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PESSOAS ÚNICAS DETECTADAS',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white38,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    'nunca zera — conta cada pessoa uma vez',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10, color: Colors.white24),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Grid 2x2 com os demais indicadores ──────────────────────────────
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.15,
          children: [
            StatCard(
                label: 'ENTRADAS',
                value: _stats.totalIn,
                color: const Color(0xFF00F5A0),
                icon: Icons.login_rounded),
            StatCard(
                label: 'SAÍDAS',
                value: _stats.totalOut,
                color: const Color(0xFF00D9F5),
                icon: Icons.logout_rounded),
            StatCard(
                label: 'NO LOCAL',
                value: _stats.inside,
                color: const Color(0xFFFFD166),
                icon: Icons.people_rounded),
            StatCard(
                label: 'EM BUFFER',
                value: _stats.ghostCount,
                color: const Color(0xFFFF6B9D),
                icon: Icons.person_search_rounded,
                subtitle: 'IDs aguardando'),
          ],
        ),
      ],
    );
  }

  Widget _buildOccupancyBar() {
    const maxCapacity = 50;
    final occupancy = (_stats.inside / maxCapacity).clamp(0.0, 1.0);
    final pct = (occupancy * 100).round();
    Color barColor;
    String statusLabel;
    if (occupancy < 0.5) {
      barColor = const Color(0xFF00F5A0);
      statusLabel = 'Normal';
    } else if (occupancy < 0.8) {
      barColor = const Color(0xFFFFD166);
      statusLabel = 'Atenção';
    } else {
      barColor = const Color(0xFFFF4E6A);
      statusLabel = 'Crítico';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: barColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('OCUPAÇÃO',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: Colors.white38,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1)),
              Text('$pct%',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: barColor)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: occupancy,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: barColor)),
              const SizedBox(width: 8),
              Text(statusLabel,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      color: barColor,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${_stats.inside} / $maxCapacity',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, color: Colors.white38)),
            ],
          ),
        ],
      ),
    );
  }

  // Mini log — últimas 5 entradas
  Widget _buildMiniLog() {
    final recent = _log.reversed.take(5).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.history_rounded,
                    size: 16, color: Color(0xFFFFD166)),
                const SizedBox(width: 8),
                Text('Últimos eventos',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70)),
                const Spacer(),
                GestureDetector(
                  onTap: _openLog,
                  child: Text('Ver tudo →',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12, color: const Color(0xFF00D9F5))),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Nenhum evento ainda',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, color: Colors.white24)),
            )
          else
            ...recent.map((e) => _buildEventTile(e, compact: true)),
        ],
      ),
    );
  }

  Widget _buildEventTile(PersonEvent e, {bool compact = false}) {
    final color = e.isEntry ? const Color(0xFF00F5A0) : const Color(0xFF00D9F5);
    final icon = e.isEntry ? Icons.login_rounded : Icons.logout_rounded;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 8 : 12),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.label,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              Text('ID #${e.trackId}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, color: Colors.white38)),
            ],
          ),
          const Spacer(),
          Text(e.timeOnly,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
