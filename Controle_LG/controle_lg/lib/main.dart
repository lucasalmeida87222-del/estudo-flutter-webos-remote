import 'package:flutter/material.dart';

import 'webos_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controle LG webOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const RemoteScreen(),
    );
  }
}

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  final WebOSService _webOS = WebOSService();
  final TextEditingController _ipController = TextEditingController(
    text: '192.168.2.100',
  );
  final TextEditingController _macController = TextEditingController(
    text: '78:DD:12:50:96:FA',
  );
  bool _isLoading = false;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _webOS.init();
    _webOS.onStatusUpdate = (message) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    };
    _webOS.onLogUpdate = (log) {
      if (mounted) {
        setState(() {
          _logs.add(log);
        });
      }
    };
  }

  void _handleConnect() async {
    setState(() {
      _isLoading = true;
    });
    await _webOS.connect(_ipController.text.trim());
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _webOS.disconnect();
    _ipController.dispose();
    _macController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle LG webOS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: Colors.red),
            onPressed: () => _webOS.powerOff(),
          ),
          IconButton(
            icon: const Icon(Icons.power, color: Colors.green),
            onPressed: () => _webOS.powerOn(_macController.text.trim()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(labelText: 'Endereço IP da TV'),
            ),
            TextField(
              controller: _macController,
              decoration: const InputDecoration(
                labelText: 'Endereço MAC da TV',
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleConnect,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Conectar'),
            ),
            const SizedBox(height: 15),

            // Botões do Menu/Voltar/Volume
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _webOS.pressHome(),
                  icon: const Icon(Icons.home),
                  label: const Text('Menu'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _webOS.pressBack(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Voltar'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _webOS.volumeDown(),
                  icon: const Icon(Icons.volume_down),
                  label: const Text('Vol -'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _webOS.volumeUp(),
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Vol +'),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // Bloco do D-Pad / Setas de Navegação e OK
            Column(
              children: [
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: () => _webOS.pressUp(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.keyboard_arrow_left),
                      onPressed: () => _webOS.pressLeft(),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(18),
                      ),
                      onPressed: () => _webOS.pressOk(),
                      child: const Text(
                        'OK',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.keyboard_arrow_right),
                      onPressed: () => _webOS.pressRight(),
                    ),
                  ],
                ),
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: () => _webOS.pressDown(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Terminal
            Container(
              height: 120,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _logs.join('\n'),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
