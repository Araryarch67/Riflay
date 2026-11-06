import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// MQTT over TLS to [host]:[tlsPort]. See `mqtt.dart`.
MqttClient secureMqttClient(String host, {required int tlsPort, required int wssPort, required String clientId}) =>
    MqttServerClient.withPort(host, clientId, tlsPort)..secure = true;
