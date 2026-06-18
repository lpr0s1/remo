import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

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
  final TextEditingController _portController = TextEditingController(text: "8080");
  final TextEditingController _commandController = TextEditingController();

  Socket? _socket;
  bool _isLoading = false;
  bool _isConnected = false;
  bool _showLogs = true;
  List<String> logs = [];

  void _addLog(String message) {
    setState(() {
      logs.add("[${DateTime.now().toString().substring(11, 19)}] $message");
    });
  }

  void _toggleConnection() async {
    if (_isConnected) {
      _disconnect();
      return;
    }

    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || port == null) {
      _addLog("Erreur : IP ou Port invalide");
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

      // Ecoute des reponses du PC
      _socket!.listen(
        (List<int> data) {
          final response = utf8.decode(data).trim();
          _addLog("PC : $response");
        },
        onError: (error) {
          _addLog("Erreur reseau : $error");
          _disconnect();
        },
        onDone: () {
          _addLog("Le serveur PC a ferme la connexion");
          _disconnect();
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isConnected = false;
      });
      _addLog("Echec de la connexion : $e");
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
    _addLog("Deconnecte du PC");
  }

  void _sendCommand() {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty || _socket == null) return;

    try {
      _socket!.write(cmd + "\n");
      _addLog("Envoye : $cmd");
      _commandController.clear();
    } catch (e) {
      _addLog("Erreur d envoi : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Remote Control"),
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Formulaire IP et Port
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
            const SizedBox(height: 30),

            // Bouton PC de connexion bien arrondi
            GestureDetector(
              onTap: _isLoading ? null : _toggleConnection,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green : Colors.blueAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _isConnected ? Colors.green.withOpacity(0.4) : Colors.blueAccent.withOpacity(0.4),
                      blurRadius: 15,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.computer, size: 45, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isConnected ? "Statut : Connecte" : "Statut : Deconnecte",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),

            // Zone d'envoi de commande (Visible uniquement si connecte)
            if (_isConnected)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commandController,
                      decoration: const InputDecoration(
                        labelText: "Entrer une commande",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blueAccent),
                    onPressed: _sendCommand,
                  ),
                ],
              ),
            
            const SizedBox(height: 20),
            
            // Bouton pour masquer / afficher les logs
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showLogs = !_showLogs;
                });
              },
              icon: Icon(_showLogs ? Icons.expand_less : Icons.expand_more),
              label: Text(_showLogs ? "Masquer les logs" : "Afficher les logs"),
            ),

            // Fenetre de logs
            if (_showLogs)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          logs[index],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: "monospace",
                            fontSize: 13,
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
