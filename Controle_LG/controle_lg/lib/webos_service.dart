import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebOSService {
  WebSocketChannel? _commandChannel;
  WebSocketChannel? _pointerChannel;
  StreamSubscription? _subscription;
  String? _clientKey;
  int _requestId = 0;
  bool isAuthorized = false;

  Function(String message)? onStatusUpdate;
  Function(String log)? onLogUpdate;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _clientKey = prefs.getString('webos_client_key');
    _log('Chave em memória: $_clientKey');
  }

  void _log(String message) {
    print(message);
    onLogUpdate?.call(message);
  }

  Future<void> connect(String tvIp) async {
    _log('Conectando em ws://$tvIp:3000...');

    try {
      await disconnect();

      final socket = await WebSocket.connect('ws://$tvIp:3000').timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Sem resposta da TV.');
        },
      );

      _commandChannel = IOWebSocketChannel(socket);

      _subscription = _commandChannel!.stream.listen(
        (message) async {
          _log('TV: $message');
          final data = jsonDecode(message);

          if (data['type'] == 'registered') {
            final newKey = data['payload']?['client-key'];
            if (newKey != null) {
              _clientKey = newKey;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('webos_client_key', newKey);
            }

            isAuthorized = true;
            onStatusUpdate?.call('TV Conectada!');
            _log('>>> CONECTADO E AUTORIZADO <<<');

            // Aguarda 600ms para a TV estabilizar a sessão antes de solicitar o socket secundário
            Future.delayed(const Duration(milliseconds: 600), () {
              _requestPointerSocket();
            });
          } else if (data['type'] == 'response' &&
              data['id'] == 'req_pointer') {
            final socketPath = data['payload']?['socketPath'];
            if (socketPath != null && socketPath.toString().isNotEmpty) {
              await _connectPointerSocket(socketPath.toString());
            } else {
              _log('Erro: socketPath não retornado pela TV.');
            }
          }
        },
        onError: (error) {
          isAuthorized = false;
          _log('ERRO CANAL: $error');
          onStatusUpdate?.call('Erro de Conexão');
        },
        onDone: () {
          isAuthorized = false;
          _log('Conexão encerrada.');
        },
      );

      _registerDevice();
    } catch (e) {
      isAuthorized = false;
      _log('ERRO CONEXÃO: $e');
      onStatusUpdate?.call('Erro ao conectar.');
    }
  }

  void _registerDevice() {
    final handshake = {
      "type": "register",
      "id": "register_${_requestId++}",
      "payload": {
        "forcePairing": false,
        "pairingType": "PROMPT",
        if (_clientKey != null) "client-key": _clientKey,
        "manifest": {
          "manifestVersion": 1,
          "appVersion": "1.0.0",
          "signed": {
            "created": "2026-01-01",
            "appId": "com.controle.lg.final",
            "vendorId": "com.controle.lg",
            "localizedAppNames": {"": "Controle Remote LG"},
            "permissions": [
              "LAUNCH",
              "CONTROL_AUDIO",
              "CONTROL_NAVIGATE",
              "CONTROL_POWER",
              "READ_INSTALLED_APPS",
              "READ_INPUT_DEVICE_KEYS",
            ],
            "serial": "1",
          },
        },
      },
    };

    _send(handshake);
  }

  void _requestPointerSocket() {
    _log('Solicitando Pointer Socket...');
    final message = {
      "id": "req_pointer",
      "type": "request",
      "uri": "ssap://com.webos.service.networkinput/getPointerInputSocket",
    };
    _send(message);
  }

  Future<void> _connectPointerSocket(String socketUrl) async {
    try {
      _log('Conectando Pointer Socket em: $socketUrl');
      final socket = await WebSocket.connect(socketUrl)
          .timeout(const Duration(seconds: 5));
      _pointerChannel = IOWebSocketChannel(socket);
      _log('>>> POINTER SOCKET CONECTADO: SETAS E OK LIBERADOS <<<');
      onStatusUpdate?.call('Controle Completo Pronto!');
    } catch (e) {
      _log('Erro ao conectar Pointer Socket: $e');
    }
  }

  void sendCommand(String uri, [Map<String, dynamic>? payload]) {
    if (_commandChannel == null) {
      _log('Erro: Não conectado à TV.');
      return;
    }

    final message = {
      "id": "req_${_requestId++}",
      "type": "request",
      "uri": uri,
      if (payload != null) "payload": payload,
    };
    _log('ENVIANDO (SSAP): $uri');
    _send(message);
  }

  void _send(Map<String, dynamic> data) {
    if (_commandChannel != null) {
      _commandChannel!.sink.add(jsonEncode(data));
    }
  }

  void _sendButtonEvent(String buttonName) {
    if (_pointerChannel != null) {
      _log('ENVIANDO BOTÃO (Hardware): $buttonName');
      _pointerChannel!.sink.add('type:button\nname:$buttonName\n\n');
    } else {
      _log('Pointer Socket não pronto. Solicitando novo socket...');
      _requestPointerSocket();
    }
  }

  // --- BOTÕES SISTEMA (CANAL PRINCIPAL) ---
  void pressHome() =>
      sendCommand("ssap://system.launcher/open", {"id": "com.webos.app.home"});
  void pressBack() => sendCommand("ssap://system.launcher/open", {
    "id": "com.webos.app.livetv",
  });
  void volumeUp() => sendCommand("ssap://audio/volumeUp");
  void volumeDown() => sendCommand("ssap://audio/volumeDown");
  void toggleMute() => sendCommand("ssap://audio/setMute", {"mute": true});
  void powerOff() => sendCommand("ssap://system/turnOff");

  // --- SETAS E OK (POINTER SOCKET EXCLUSIVO) ---
  void pressOk() => _sendButtonEvent("ENTER");
  void pressUp() => _sendButtonEvent("UP");
  void pressDown() => _sendButtonEvent("DOWN");
  void pressLeft() => _sendButtonEvent("LEFT");
  void pressRight() => _sendButtonEvent("RIGHT");

  Future<void> powerOn(String macAddress) async {
    try {
      final cleanMac = macAddress.replaceAll(':', '').replaceAll('-', '');
      if (cleanMac.length != 12) return;

      final List<int> macBytes = [];
      for (int i = 0; i < 12; i += 2) {
        macBytes.add(int.parse(cleanMac.substring(i, i + 2), radix: 16));
      }

      final List<int> packet = List<int>.from(List.filled(6, 0xFF));
      for (int i = 0; i < 16; i++) {
        packet.addAll(macBytes);
      }

      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(packet, InternetAddress('255.255.255.255'), 9);
      socket.close();

      _log('Sinal Ligar enviado!');
      onStatusUpdate?.call('Sinal enviado!');
    } catch (e) {
      _log('ERRO WoL: $e');
    }
  }

  Future<void> disconnect() async {
    isAuthorized = false;
    await _subscription?.cancel();
    _subscription = null;
    await _commandChannel?.sink.close();
    _commandChannel = null;
    await _pointerChannel?.sink.close();
    _pointerChannel = null;
  }
}
