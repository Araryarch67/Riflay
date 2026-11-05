// How a link reaches Riflay outside Android's intents (see lib/services/incoming_links.dart): handed from a
// second process on computers, or read from the page's address on the web.
export 'link_relay_io.dart' if (dart.library.js_interop) 'link_relay_web.dart';
