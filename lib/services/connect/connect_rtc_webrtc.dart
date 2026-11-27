import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../player_controller.dart';
import 'connect_rtc.dart';
import 'connect_stream.dart';

/// Backed up beyond this, [RtcLink.sendBinary] waits: audio is sent as fast as the other side takes it, no faster.
const _highWater = 1 << 20;

class _WebRtcLink implements RtcLink {
  _WebRtcLink(this._pc, this._dc) {
    _dc.onMessage = (m) => _in.add(m.isBinary ? RtcData.binary(m.binary) : RtcData.text(m.text));
    _dc.onBufferedAmountLow = (_) {
      _drain?.complete();
      _drain = null;
    };
    _dc.bufferedAmountLowThreshold = _highWater ~/ 4;
    _dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelClosed) _done();
    };
    _pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _done();
      }
    };
  }

  final RTCPeerConnection _pc;
  final RTCDataChannel _dc;
  final _in = StreamController<RtcData>.broadcast();
  final _closed = Completer<void>();
  Completer<void>? _drain;

  void _done() {
    if (_closed.isCompleted) return;
    _closed.complete();
    _drain?.complete();
    unawaited(_in.close());
  }

  @override
  Stream<RtcData> get messages => _in.stream;
  @override
  Future<void> get closed => _closed.future;
  @override
  bool get isOpen => !_closed.isCompleted && _dc.state == RTCDataChannelState.RTCDataChannelOpen;

  @override
  void sendText(String text) {
    if (isOpen) unawaited(_dc.send(RTCDataChannelMessage(text)));
  }

  @override
  Future<void> sendBinary(Uint8List bytes) async {
    while (isOpen && (_dc.bufferedAmount ?? 0) > _highWater) {
      await (_drain ??= Completer<void>()).future.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    if (isOpen) await _dc.send(RTCDataChannelMessage.fromBinary(bytes));
  }

  @override
  Future<void> close() async {
    _done();
    await _dc.close();
    await _pc.close();
  }
}

/// The real thing: one WebRTC peer connection with a single ordered data channel, using flutter_webrtc.
///
/// Signals are `{k: offer|answer, sdp}` and `{k: ice, c: {...}}`. Nothing else leaves the device: no path, no
/// account and no TURN login is ever put in a signal.
Future<RtcLink> openWebRtcLink({
  required bool offerer,
  required ConnectIceConfig ice,
  required void Function(Map<String, dynamic> signal) send,
  required Stream<Map<String, dynamic>> incoming,
  required Duration timeout,
}) async {
  final pc = await createPeerConnection({'iceServers': ice.iceServers});
  final open = Completer<RTCDataChannel>();
  void channel(RTCDataChannel dc) {
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen && !open.isCompleted) open.complete(dc);
    };
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen && !open.isCompleted) open.complete(dc);
  }

  pc.onIceCandidate = (c) {
    if (c.candidate == null) return;
    send({
      'k': 'ice',
      'c': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
    });
  };
  pc.onDataChannel = channel;

  // One at a time, in order: a candidate must not be added before the description it belongs to.
  final sub = incoming
      .asyncMap((d) async {
        switch (d['k']) {
          case 'offer' when !offerer:
            await pc.setRemoteDescription(RTCSessionDescription(d['sdp'] as String, 'offer'));
            final answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            send({'k': 'answer', 'sdp': answer.sdp});
          case 'answer' when offerer:
            await pc.setRemoteDescription(RTCSessionDescription(d['sdp'] as String, 'answer'));
          case 'ice':
            final c = d['c'];
            if (c is Map<String, dynamic> && c['candidate'] is String) {
              await pc.addCandidate(
                RTCIceCandidate(c['candidate'] as String, c['sdpMid'] as String?, c['sdpMLineIndex'] as int?),
              );
            }
        }
      })
      .listen((_) {}, onError: (_) {});

  try {
    if (offerer) {
      channel(await pc.createDataChannel('riflay', RTCDataChannelInit()..ordered = true));
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      send({'k': 'offer', 'sdp': offer.sdp});
    }
    final dc = await open.future.timeout(timeout);
    return _WebRtcLink(pc, dc);
  } catch (_) {
    await pc.close();
    rethrow;
  } finally {
    unawaited(sub.cancel());
  }
}

/// This device's hub, made on first use: flutter_webrtc underneath, the marked-as-own songs gating what is served.
ConnectRtc connectRtcOf(PlayerController p) => ConnectRtc.instance ??= ConnectRtc(
  opener: openWebRtcLink,
  ownership: ConnectOwnership.shared,
  library: () => p.library,
);
