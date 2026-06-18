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
        scaffoldBackgroundColor: const Color(0xFF0D0E12),
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

  // Contrôleur pour l'animation du bouton
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  final String _batScriptContent = r'''@echo off
title Serveur local
echo Lancement du serveur sur le port 55555...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$listener = [System.Net.Sockets.TcpListener]55555; $listener.Start(); while ($true) { $client = $listener.AcceptTcpClient(); $stream = $client.GetStream(); $reader = New-Object System.IO.StreamReader($stream); $writer = New-Object System.IO.StreamWriter($stream); $writer.AutoFlush = $true; $writer.WriteLine('Connecté au PC Windows'); while ($client.Connected) { $cmd = $reader.ReadLine(); if ($cmd -eq $null) { break }; try { $out = Invoke-Expression $cmd 2>&1 | Out-String; if ([string]::IsNullOrWhiteSpace($out)) { $out = 'Commande exécutée sans retour textuel.' }; $writer.WriteLine($out); } catch { $writer.WriteLine('Erreur: ' + $_.Exception.Message); } } $client.Close(); }"
pause''';

  @override
  void train() {}

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
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
        "text": "[${DateTime.now().toString().substring(11, 19)}] $message",
        "isError": isError
      });
    });
    // Auto-scroll vers le bas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyBatScript() {
    Clipboard.setData(ClipboardData(text: _batScriptContent));
    _addLog("Script .bat copié dans le presse-papiers.");
  }

  void _toggleConnection() async {
    if (_isConnected) {
      _disconnect();
      return;
    }

    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || port == null || port < 1 || port > 65535) {
      _addLog("Erreur : configuration IP ou port invalide", isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });
    _addLog("Tentative de connexion à $ip:$port...");

    try {
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      
      setState(() {
        _isConnected = true;
        _isLoading = false;
      });
      _addLog("Connexion établie avec succès");

      _socket!.listen(
        (List<int> data) {
          final response = utf8.decode(data).trim();
          _addLog(response);
        },
        onError: (error) {
          _addLog("Erreur réseau : $error", isError: true);
          _disconnect();
        },
        onDone: () {
          _addLog("La cible a fermé la connexion");
          _disconnect();
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isConnected = false;
      });
      _addLog("Échec de la connexion : l'hôte est introuvable ou le port est fermé ($e)", isError: true);
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
    _addLog("Déconnecté de l'appareil");
  }

  void _handleCommandExecution() {
    final input = _commandController.text.trim();
    if (input.isEmpty) return;

    _commandController.clear();

    if (_socket == null) {
      _addLog("Erreur : aucun appareil connecté", isError: true);
      return;
    }
    try {
      _socket!.write("$input\n");
      _addLog("Terminal > $input");
    } catch (e) {
      _addLog("Erreur lors de l'envoi : $e", isError: true);
    }
  }

  InputDecoration _customInputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18, color: Colors.white38),
      labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF16171F),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Console de contrôle", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w640)),
        backgroundColor: const Color(0xFF16171F),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: Colors.amberAccent),
            tooltip: "Copier le script .bat",
            onPressed: _copyBatScript,
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
                    decoration: _customInputStyle("Adresse IP cible", Icons.computer),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: _customInputStyle("Port", Icons.settings_ethernet),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Zone centrale avec le bouton de connexion animé
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
                    // Anneau de chargement ou bordure d'état
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                              strokeWidth: 4,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isConnected ? const Color(0xFF10B981) : Colors.white10,
                                  width: 2,
                                ),
                              ),
                            ),
                    ),
                    // Bouton principal interne
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: _isConnected ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isConnected ? const Color(0xFF10B981) : const Color(0xFF2563EB)).withOpacity(0.4),
                            blurRadius: 15,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          _isConnected ? Icons.power_settings_new : Icons.bolt,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isConnected ? "Statut : connecté" : "Statut : déconnecté",
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: _isConnected ? const Color(0xFF10B981) : Colors.white38,
              ),
            ),
            const SizedBox(height: 40),

            // Saisie des commandes
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    decoration: _customInputStyle("Commande à exécuter", Icons.terminal),
                    onSubmitted: (_) => _handleCommandExecution(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: _handleCommandExecution,
                  child: const Icon(Icons.send, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Séparateur de console
            Row(
              children: [
                const Text("Console de sortie", style: TextStyle(color: Colors.white54, fontSize: 12)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _showLogs = !_showLogs),
                  icon: Icon(_showLogs ? Icons.visibility_off : Icons.visibility, size: 14, color: Colors.white38),
                  label: Text(
                    _showLogs ? "Masquer" : "Afficher",
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),

            if (_showLogs)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF07080B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final logItem = logs[index];
                      final bool isError = logItem["isError"] ?? false;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          logItem["text"] ?? "",
                          style: TextStyle(
                            color: isError ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
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
