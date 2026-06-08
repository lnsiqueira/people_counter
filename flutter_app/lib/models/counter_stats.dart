class PersonEvent {
  final int trackId;
  final String direction;
  final String label;
  final String timestamp;
  final double unix;
  final int seq;

  const PersonEvent({
    required this.trackId, required this.direction, required this.label,
    required this.timestamp, required this.unix, required this.seq,
  });

  factory PersonEvent.fromJson(Map<String, dynamic> j) => PersonEvent(
        trackId:   (j['id']  as num).toInt(),
        direction: j['direction'] as String,
        label:     j['label']     as String,
        timestamp: j['timestamp'] as String,
        unix:      (j['unix'] as num).toDouble(),
        seq:       (j['seq']  as num).toInt(),
      );

  bool get isEntry => direction == 'in';
  String get timeOnly => timestamp.length >= 19 ? timestamp.substring(11, 19) : timestamp;
  String get dateOnly {
    if (timestamp.length < 10) return '';
    final parts = timestamp.substring(0, 10).split('-');
    return '${parts[2]}/${parts[1]}';
  }
}

class CounterStats {
  final int totalUnique;   // pessoas únicas (nunca zera)
  final int totalIn;
  final int totalOut;
  final int inside;
  final int activeTracks;
  final int ghostCount;
  final bool reidActive;
  final int gallerySize;
  final double timestamp;
  final List<PersonEvent> recentEvents;
  final int logSize;

  const CounterStats({
    required this.totalUnique, required this.totalIn, required this.totalOut,
    required this.inside, required this.activeTracks, required this.ghostCount,
    required this.reidActive, required this.gallerySize,
    required this.timestamp, required this.recentEvents, required this.logSize,
  });

  factory CounterStats.fromJson(Map<String, dynamic> j) => CounterStats(
        totalUnique:  (j['total_unique']  as num? ?? 0).toInt(),
        totalIn:      (j['total_in']      as num).toInt(),
        totalOut:     (j['total_out']     as num).toInt(),
        inside:       (j['inside']        as num).toInt(),
        activeTracks: (j['active_tracks'] as num).toInt(),
        ghostCount:   (j['ghost_count']   as num? ?? 0).toInt(),
        reidActive:   j['reid_active']    as bool? ?? false,
        gallerySize:  (j['gallery_size']  as num? ?? 0).toInt(),
        timestamp:    (j['timestamp']     as num).toDouble(),
        recentEvents: (j['recent_events'] as List<dynamic>? ?? [])
            .map((e) => PersonEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        logSize: (j['log_size'] as num?)?.toInt() ?? 0,
      );

  factory CounterStats.empty() => const CounterStats(
        totalUnique: 0, totalIn: 0, totalOut: 0, inside: 0,
        activeTracks: 0, ghostCount: 0, reidActive: false, gallerySize: 0,
        timestamp: 0, recentEvents: [], logSize: 0,
      );
}
