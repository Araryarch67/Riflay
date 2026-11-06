import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

/// MQTT over a secure WebSocket, `wss://[host]:[wssPort]/mqtt` (where public brokers serve it). See `mqtt.dart`.
MqttClient secureMqttClient(String host, {required int tlsPort, required int wssPort, required String clientId}) =>
    MqttBrowserClient.withPort('wss://$host/mqtt', clientId, wssPort);
