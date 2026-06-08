import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/counter_stats.dart';

class WebSocketService {
  final String _url;
  WebSocketChannel? _channel;

  final _frameController      = StreamController<Uint8List>.broadcast();
  final _statsController      = StreamController<CounterStats>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _fullLogController    = StreamController<List<PersonEvent>>.broadcast();

  Stream<Uint8List>       get frameStream      => _frameController.stream;
  Stream<CounterStats>    get statsStream      => _statsController.stream;
  Stream<bool>            get connectionStream => _connectionController.stream;
  Stream<List<PersonEvent>> get fullLogStream  => _fullLogController.stream;

  bool _connected = false;
  bool get isConnected => _connected;

  WebSocketService(this._url);

  void connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url));
      _connected = true;
      _connectionController.add(true);

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;

            if (data.containsKey('error')) {
              disconnect();
              return;
            }

            // Mensagem de log completo (enviada ao conectar)
            if (data['type'] == 'full_log') {
              final events = (data['event_log'] as List<dynamic>)
                  .map((e) => PersonEvent.fromJson(e as Map<String, dynamic>))
                  .toList();
              _fullLogController.add(events);
              return;
            }

            if (data['frame'] != null) {
              final bytes = base64Decode(data['frame'] as String);
              _frameController.add(bytes);
            }

            if (data['stats'] != null) {
              final stats = CounterStats.fromJson(
                data['stats'] as Map<String, dynamic>,
              );
              _statsController.add(stats);
            }
          } catch (_) {}
        },
        onDone: () {
          _connected = false;
          _connectionController.add(false);
        },
        onError: (_) {
          _connected = false;
          _connectionController.add(false);
        },
      );
    } catch (_) {
      _connected = false;
      _connectionController.add(false);
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _connected = false;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _frameController.close();
    _statsController.close();
    _connectionController.close();
    _fullLogController.close();
  }
}
