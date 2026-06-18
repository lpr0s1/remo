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
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.blueAccent,
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
  
  // Structure de logs pour gerer la coloration differentielle
  List<Map<String, dynamic>> logs = [];

  // Script .bat universel utilisant un mini serveur TCP PowerShell natif sur le port 55555
  final String _batScriptContent = r'''@echo off
title Serveur de Controle Local
echo Lancement du serveur sur le port 55555 (Port dynamique generalement libre)...
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
    _addLog("Script .bat copie dans le presse-papiers ! Cree un fichier script.bat sur ton PC et colle ce contenu.");
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

    // Verification : Est-ce une requete HTTP directe ?
    if (input.startsWith("http://") || input.startsWith("https://")) {
      _addLog("Execution requete HTTP directe...");
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(input)).timeout(const Duration(seconds: 5));
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        
        _addLog("HTTP Code : ${response.statusCode}");
        _addLog("Reponse HTTP : ${responseBody.length > 150 ? responseBody.substring(0, 150) + '...' : responseBody}");
      } catch (e) {
        _addLog("Erreur execution HTTP : $e", isError: true);
      }
    } else {
      // Envoi standard au terminal de notre script .bat via TCP
      if (_socket == null) {
        _addLog("Erreur : Impossible d envoyer, aucun appareil connecte", isError: true);
        return;
      }
      try {
        _socket!.write(input + "\n");
        _addLog("Terminal > $input");
      } catch (e) {
        _addLog("Erreur d envoi au terminal : $e", isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Remote Control Pro"),
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.insert_drive_file, color: Colors.amberAccent),
            tooltip: "Copier le script .bat pour le PC",
            onPressed: _copyBatScript,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Saisie IP / Port
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: "Adresse IP du PC",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Port",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),

            // Gros bouton de connexion arrondi avec l'indicateur [<>] demande
            GestureDetector(
              onTap: _isLoading ? null : _toggleConnection,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green : Colors.blueAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _isConnected ? Colors.green.withOpacity(0.4) : Colors.blueAccent.withOpacity(0.4),
                      blurRadius: 18,
                      spreadRadius: 3,
                    )
                  ],
                ),
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.computer, size: 38, color: Colors.white),
                            SizedBox(height: 4),
                            Text(
                              "[<>]",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 1.2
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isConnected ? "Statut : Connecte" : "Statut : Deconnecte",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 25),

            // Invite de commande (Terminal / HTTP URL Input)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    decoration: const InputDecoration(
                      labelText: "Commande Terminal ou URL HTTP (http://...)",
                      border: OutlineInputBorder(),
                      labelStyle: TextStyle(fontSize: 13),
                    ),
                    onSubmitted: (_) => _handleCommandExecution(),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.blueAccent, size: 30),
                  onPressed: _handleCommandExecution,
                ),
              ],
            ),
            const SizedBox(height: 15),
            
            // Controle des logs
            TextButton.icon(
              onPressed: () => setState(() => _showLogs = !_showLogs),
              icon: Icon(_showLogs ? Icons.visibility_off : Icons.visibility),
              label: Text(_showLogs ? "Masquer la console" : "Afficher la console"),
            ),

            // Console d'evenements
            if (_showLogs)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final logItem = logs[index];
                      final bool isError = logItem["isError"] ?? false;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: Text(
                          logItem["text"] ?? "",
                          style: TextStyle(
                            color: isError ? Colors.redAccent : Colors.white,
                            fontFamily: "monospace",
                            fontSize: 13,
                            fontWeight: isError ? FontWeight.bold : FontWeight.normal,
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
