import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/counter_stats.dart';

class LogScreen extends StatefulWidget {
  final List<PersonEvent> events;
  const LogScreen({super.key, required this.events});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Filtros
  String _filterDirection = 'all'; // 'all' | 'in' | 'out'
  DateTimeRange? _dateRange;
  TimeOfDay? _timeFrom;
  TimeOfDay? _timeTo;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {
      _filterDirection = ['all', 'in', 'out'][_tabs.index];
    }));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<PersonEvent> get _filtered {
    return widget.events.where((e) {
      // Direção
      if (_filterDirection != 'all' && e.direction != _filterDirection) return false;

      // Período de datas
      if (_dateRange != null) {
        final dt = DateTime.tryParse(e.timestamp);
        if (dt == null) return false;
        final start = _dateRange!.start;
        final end   = _dateRange!.end.add(const Duration(days: 1));
        if (dt.isBefore(start) || dt.isAfter(end)) return false;
      }

      // Janela de horário
      if (_timeFrom != null || _timeTo != null) {
        final dt = DateTime.tryParse(e.timestamp);
        if (dt == null) return false;
        final minutes = dt.hour * 60 + dt.minute;
        if (_timeFrom != null) {
          final fromMin = _timeFrom!.hour * 60 + _timeFrom!.minute;
          if (minutes < fromMin) return false;
        }
        if (_timeTo != null) {
          final toMin = _timeTo!.hour * 60 + _timeTo!.minute;
          if (minutes > toMin) return false;
        }
      }

      return true;
    }).toList();
  }

  // Estatísticas do intervalo filtrado
  Map<String, int> get _filteredStats {
    final f = _filtered;
    final ins  = f.where((e) => e.isEntry).length;
    final outs = f.where((e) => !e.isEntry).length;
    return {'in': ins, 'out': outs, 'total': f.length};
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialDateRange: _dateRange,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF00F5A0), onPrimary: Color(0xFF0A0E1A)),
        ),
        child: child!,
      ),
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Future<void> _pickTimeFrom() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _timeFrom ?? const TimeOfDay(hour: 0, minute: 0),
      builder: (ctx, child) => _darkTimePicker(ctx, child!),
    );
    if (t != null) setState(() => _timeFrom = t);
  }

  Future<void> _pickTimeTo() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _timeTo ?? const TimeOfDay(hour: 23, minute: 59),
      builder: (ctx, child) => _darkTimePicker(ctx, child!),
    );
    if (t != null) setState(() => _timeTo = t);
  }

  Widget _darkTimePicker(BuildContext ctx, Widget child) => Theme(
    data: ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(primary: Color(0xFF00F5A0), onPrimary: Color(0xFF0A0E1A)),
    ),
    child: child,
  );

  void _clearFilters() => setState(() {
    _dateRange = null;
    _timeFrom  = null;
    _timeTo    = null;
  });

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _fmtDate(DateTime d)  => '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final stats    = _filteredStats;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Log de Pessoas',
            style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        actions: [
          if (_dateRange != null || _timeFrom != null || _timeTo != null)
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16, color: Color(0xFFFF4E6A)),
              label: Text('Limpar', style: GoogleFonts.spaceGrotesk(color: const Color(0xFFFF4E6A), fontSize: 13)),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF00F5A0),
          labelColor: const Color(0xFF00F5A0),
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'TODOS'),
            Tab(text: 'ENTRADAS'),
            Tab(text: 'SAÍDAS'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Filtros de período ──────────────────────────────────────────────
          _buildFilterRow(),

          // ── Sumário do período filtrado ─────────────────────────────────────
          _buildSummaryRow(stats),

          // ── Lista ───────────────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      // Mostrar agrupado por hora
                      final ev   = filtered[filtered.length - 1 - i]; // mais recente primeiro
                      final prev = (i < filtered.length - 1)
                          ? filtered[filtered.length - 2 - i]
                          : null;
                      final showHeader = prev == null ||
                          _hourKey(ev.timestamp) != _hourKey(prev.timestamp);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showHeader) _buildHourHeader(ev.timestamp),
                          _buildEventTile(ev),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _hourKey(String ts) => ts.length >= 13 ? ts.substring(0, 13) : ts;

  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF111827),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // Data
          _filterChip(
            icon: Icons.calendar_month_rounded,
            label: _dateRange == null
                ? 'Período'
                : '${_fmtDate(_dateRange!.start)} – ${_fmtDate(_dateRange!.end)}',
            active: _dateRange != null,
            onTap: _pickDateRange,
          ),
          // Hora de
          _filterChip(
            icon: Icons.schedule_rounded,
            label: _timeFrom == null ? 'Das...' : 'Das ${_fmtTime(_timeFrom!)}',
            active: _timeFrom != null,
            onTap: _pickTimeFrom,
          ),
          // Hora até
          _filterChip(
            icon: Icons.schedule_rounded,
            label: _timeTo == null ? 'Até...' : 'Até ${_fmtTime(_timeTo!)}',
            active: _timeTo != null,
            onTap: _pickTimeTo,
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? const Color(0xFF00F5A0) : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00F5A0).withOpacity(0.1) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? const Color(0xFF00F5A0).withOpacity(0.4) : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(Map<String, int> stats) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00F5A0).withOpacity(0.06),
            const Color(0xFF00D9F5).withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          _summaryItem('ENTRADAS', stats['in']!, const Color(0xFF00F5A0)),
          _summaryDivider(),
          _summaryItem('SAÍDAS',   stats['out']!, const Color(0xFF00D9F5)),
          _summaryDivider(),
          _summaryItem('TOTAL',    stats['total']!, const Color(0xFFFFD166)),
          if (_timeFrom != null || _timeTo != null || _dateRange != null) ...[
            _summaryDivider(),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('PERÍODO', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: Colors.white24, letterSpacing: 1)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (_dateRange != null) '${_fmtDate(_dateRange!.start)} – ${_fmtDate(_dateRange!.end)}',
                      if (_timeFrom != null || _timeTo != null)
                        '${_timeFrom != null ? _fmtTime(_timeFrom!) : '00:00'} – ${_timeTo != null ? _fmtTime(_timeTo!) : '23:59'}',
                    ].join('\n'),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int value, Color color) => Expanded(
    child: Column(
      children: [
        Text('$value', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 9, color: Colors.white38, letterSpacing: 1)),
      ],
    ),
  );

  Widget _summaryDivider() => Container(width: 1, height: 36, color: Colors.white10, margin: const EdgeInsets.symmetric(horizontal: 8));

  Widget _buildHourHeader(String ts) {
    if (ts.length < 13) return const SizedBox();
    final hour = ts.substring(11, 13);
    final date = ts.length >= 10 ? ts.substring(0, 10) : '';
    final parts = date.split('-');
    final dateLabel = parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : date;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD166).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFD166).withOpacity(0.2)),
            ),
            child: Text(
              '${hour}h00 – ${hour}h59  ·  $dateLabel',
              style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFFFFD166), fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: Colors.white10)),
        ],
      ),
    );
  }

  Widget _buildEventTile(PersonEvent e) {
    final color = e.isEntry ? const Color(0xFF00F5A0) : const Color(0xFF00D9F5);
    final icon  = e.isEntry ? Icons.login_rounded : Icons.logout_rounded;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label,
                    style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                Text('ID #${e.trackId}  ·  ${e.isEntry ? "Entrada" : "Saída"} nº ${e.seq}',
                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(e.timeOnly,
                  style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
              Text(e.dateOnly,
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white30)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search_off_rounded, size: 48, color: Colors.white24),
        const SizedBox(height: 16),
        Text('Nenhum evento encontrado',
            style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 15)),
        const SizedBox(height: 8),
        Text('Ajuste os filtros de período ou horário',
            style: GoogleFonts.spaceGrotesk(color: Colors.white24, fontSize: 12)),
      ],
    ),
  );
}
