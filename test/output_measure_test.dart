import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/output_measure.dart';

Map<String, dynamic> _node(int id, Map<String, dynamic> props, {String state = 'running', int? rate}) => {
  'id': id,
  'type': 'PipeWire:Interface:Node',
  'info': {
    'state': state,
    'props': props,
    'params': {
      if (rate != null)
        'Format': [
          {'rate': rate},
        ],
    },
  },
};

Map<String, dynamic> _client(int id, int pid) => {
  'id': id,
  'type': 'PipeWire:Interface:Client',
  'info': {
    'props': {'application.process.id': pid},
  },
};

void main() {
  final sink = _node(61, {'media.class': 'Audio/Sink'}, rate: 44100);
  Map<String, dynamic> stream(int id, int client, {String state = 'running'}) => _node(id, {
    'media.class': 'Stream/Output/Audio',
    'client.id': client,
    'object.serial': 2000 + id,
    'node.driver-id': 61,
    'node.rate': '1/48000',
  }, state: state);

  test('finds our running stream through its client, at the rate of the device driving it', () {
    final found = OutputMeasure.findStream([
      sink,
      _client(95, 42),
      _client(96, 7),
      stream(91, 96),
      stream(104, 95),
    ], 42);
    expect(found, (serial: '2104', rate: 44100));
  });

  test("another app's stream, or ours paused, is not one", () {
    expect(OutputMeasure.findStream([sink, _client(96, 7), stream(91, 96)], 42), isNull);
    expect(OutputMeasure.findStream([sink, _client(95, 42), stream(104, 95, state: 'idle')], 42), isNull);
  });

  test('two of ours (a crossfade) are told apart from one', () {
    final found = OutputMeasure.findStream([sink, _client(95, 42), stream(91, 95), stream(104, 95)], 42);
    expect(found?.serial, isEmpty);
  });
}
