/// A connection to a public MQTT broker for Listen together over the internet: TLS on the broker's MQTT port
/// natively, a secure WebSocket in a browser (which can't open sockets). Both reach the same broker and topics, so
/// the web build and the apps share sessions.
library;

export 'mqtt_io.dart' if (dart.library.js_interop) 'mqtt_web.dart';
