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
        scaffoldBackgroundColor: const Color(0xFF0A0A0E),
        primaryColor: const Color(0xFF3B82F6),
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

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.X");
  final TextEditingController _portController = TextEditingController(text: "55555");
  final TextEditingController _commandController = TextEditingController();

  Socket? _socket;
  bool _isLoading = false;
  bool _isConnected = false;
  bool _showLogs = true;
  List<Map<String, dynamic>> logs = [];

  final String _batScriptContent = r'''@echo off
title Serveur de Controle Local
echo Lancement du serveur sur le port 55555...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$listener = [System.Net.Sockets.TcpListener]55555; $listener.Start(); while ($true) { $client = $listener.AcceptTcpClient(); $stream = $client.GetStream(); $reader = New-Object System.IO.StreamReader($stream); $writer = New-Object System.IO.StreamWriter($stream); $writer.AutoFlush = $true; $writer.WriteLine('Connecte au PC Windows'); while ($client.Connected) { $cmd = $reader.ReadLine(); if ($cmd -eq $null) { break }; try { $out = Invoke-Expression $cmd 2>&1 | Out-String; if ([string]::IsNullOrWhiteSpace($out)) { $out = 'Commande executee sans retour textuel.' }; $writer.WriteLine($out); } catch { $writer.WriteLine('Erreur: ' + $_.Exception.Message); } } $client.Close(); }"
pause''';

  void _addLog(String message, {bool isError = false}) {
    setState(() {
      logs.add({
        "text": "[${DateTime.now().toString().substring(11, 19)}] $message",
        "isError": isError
      });
    });
  }

  void _copyBatScript() {
    Clipboard.setData(ClipboardData(text: _batScriptContent));
    _addLog("Script .bat copie ! Cree un fichier script.bat sur ton PC et colle le contenu.");
  }

  void _toggleConnection() async {
    if (_isConnected) {
      _disconnect();
      return;
    }

    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || port == null) {
      _addLog("Erreur : Configuration IP ou Port invalide", isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });
    _addLog("Tentative de connexion a $ip:$port ...");

    try {
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      
      setState(() {
        _isConnected = true;
        _isLoading = false;
      });
      _addLog("Connexion etablie avec succes");

      _socket!.listen(
        (List<int> data) {
          final response = utf8.decode(data).trim();
          _addLog("PC : $response");
        },
        onError: (error) {
          _addLog("Erreur reseau : $error", isError: true);
          _disconnect();
        },
        onDone: () {
          _addLog("Le PC a ferme la connexion");
          _disconnect();
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isConnected = false;
      });
      _addLog("Echec de la connexion : $e", isError: true);
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
    _addLog("Deconnecte de l appareil");
  }

  void _handleCommandExecution() async {
    final input = _commandController.text.trim();
    if (input.isEmpty) return;

    _commandController.clear();

    if (input.startsWith("http://") || input.startsWith("https://")) {
      _addLog("Execution requete HTTP directe...");
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(input)).timeout(const Duration(seconds: 5));
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        
        _addLog("HTTP Status : ${response.statusCode}");
        _addLog("Reponse HTTP : ${responseBody.length > 150 ? responseBody.substring(0, 150) + '...' : responseBody}");
      } catch (e) {
        _addLog("Erreur execution HTTP : $e", isError: true);
      }
    } else {
      if (_socket == null) {
        _addLog("Erreur : Aucun appareil connecte via TCP", isError: true);
        return;
      }
      try {
        _socket!.write(input + "\n");
        _addLog("Terminal > $input");
      } catch (e) {
        _addLog("Erreur d envoi : $e", isError: true);
      }
    }
  }

  InputDecoration _customInputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF14141B),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("TERMINAL INTERFACE", style: TextStyle(letterSpacing: 1.5, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF14141B),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _copyBatScript,
            child: const Text(
              "[ GET .BAT ]",
              style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ipController,
                    decoration: _customInputStyle("ADRESSE IP TARGET"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: _customInputStyle("PORT"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 35),

            // Gros bouton de connexion ultra-style sans icone avec halo
            GestureDetector(
              onTap: _isLoading ? null : _toggleConnection,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 125,
                height: 125,
                decoration: BoxDecoration(
                  color: _isConnected ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _isConnected ? const Color(0xFF10B981).withOpacity(0.35) : const Color(0xFF2563EB).withOpacity(0.35),
                      blurRadius: 25,
                      spreadRadius: 6,
                    )
                  ],
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                      : const Text(
                          "[ < > ]",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              _isConnected ? "STATUS : CONNECTE" : "STATUS : DISCONNECTED",
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 12, 
                letterSpacing: 1.2,
                color: _isConnected ? const Color(0xFF10B981) : Colors.white38,
              ),
            ),
            const SizedBox(height: 35),

            // Ligne de commande executee via bouton texte [ EXE ]
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    decoration: _customInputStyle("COMMAND TERMINAL OR HTTP URL"),
                    onSubmitted: (_) => _handleCommandExecution(),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _handleCommandExecution,
                  child: const Text(
                    "[ EXE ]",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Toggle de la console
            TextButton(
              onPressed: () => setState(() => _showLogs = !_showLogs),
              child: Text(
                _showLogs ? "[ MASQUER CONSOLE ]" : "[ AFFICHER CONSOLE ]",
                style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2),
              ),
            ),

            // Console d'evenements
            if (_showLogs)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF050507),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10, width: 1),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final logItem = logs[index];
                      final bool isError = logItem["isError"] ?? false;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                        child: Text(
                          logItem["text"] ?? "",
                          style: TextStyle(
                            color: isError ? const Color(0xFFEF4444) : Colors.white,
                            fontFamily: "monospace",
                            fontSize: 12,
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
