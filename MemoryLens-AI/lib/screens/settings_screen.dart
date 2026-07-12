import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:memorylens_ai/app_theme.dart';
import 'package:memorylens_ai/services/ai_provider.dart';
import 'package:memorylens_ai/services/free_tier_service.dart';
import 'package:memorylens_ai/services/navigation_history_service.dart';
import 'package:memorylens_ai/widgets/desktop_title_bar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _storage = const FlutterSecureStorage();
  ProviderType _selectedProvider = ProviderType.gemini;
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  
  bool _obscureKey = true;
  bool _isTesting = false;
  bool _isSaving = false;
  Map<String, dynamic>? _quotaInfo;

  @override
  void initState() {
    super.initState();
    ref.read(navigationHistoryProvider).setInitialRoute('/settings');
    _loadSettings();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final providerStr = await _storage.read(key: 'selected_provider') ?? ProviderType.gemini.name;
    final provider = ProviderType.values.firstWhere(
      (e) => e.name == providerStr,
      orElse: () => ProviderType.gemini,
    );

    setState(() {
      _selectedProvider = provider;
    });

    await _loadProviderKeys(provider);
    await _loadQuota();
  }

  Future<void> _loadProviderKeys(ProviderType provider) async {
    final key = await _storage.read(key: '${provider.name}_api_key') ?? '';
    _keyController.text = key;

    if (provider == ProviderType.custom) {
      _baseUrlController.text = await _storage.read(key: 'custom_base_url') ?? '';
      _modelController.text = await _storage.read(key: 'custom_model') ?? '';
    } else {
      _baseUrlController.clear();
      _modelController.clear();
    }
  }

  Future<void> _loadQuota() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final quota = await ref.read(freeTierServiceProvider).getQuotaInfo(user.uid);
      setState(() {
        _quotaInfo = quota;
      });
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    try {
      final apiKey = _keyController.text.trim();
      AIProvider testProvider;
      
      switch (_selectedProvider) {
        case ProviderType.gemini:
          testProvider = GeminiProvider(apiKey);
          break;
        case ProviderType.openai:
          testProvider = OpenAIProvider(apiKey);
          break;
        case ProviderType.claude:
          testProvider = ClaudeProvider(apiKey);
          break;
        case ProviderType.groq:
          testProvider = GroqProvider(apiKey);
          break;
        case ProviderType.custom:
          testProvider = CustomProvider(
            apiKey: apiKey,
            baseUrl: _baseUrlController.text.trim(),
            model: _modelController.text.trim(),
          );
          break;
        case ProviderType.firebaseProxy:
          testProvider = FirebaseProxyProvider();
          break;
      }

      final success = await testProvider.testConnection(apiKey);
      if (success) {
        _showSnackBar("Connection test successful!", Colors.green);
      } else {
        _showSnackBar("Connection failed. Check key/endpoint values.", kError);
      }
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}", kError);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await _storage.write(key: 'selected_provider', value: _selectedProvider.name);
      await _storage.write(key: '${_selectedProvider.name}_api_key', value: _keyController.text.trim());
      
      if (_selectedProvider == ProviderType.custom) {
        await _storage.write(key: 'custom_base_url', value: _baseUrlController.text.trim());
        await _storage.write(key: 'custom_model', value: _modelController.text.trim());
      }
      _showSnackBar("Configuration saved locally.", Colors.green);
    } catch (e) {
      _showSnackBar("Failed to save: $e", kError);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _clearKey() async {
    await _storage.delete(key: '${_selectedProvider.name}_api_key');
    _keyController.clear();
    _showSnackBar("API key cleared.", Colors.orange);
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navService = ref.read(navigationHistoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const DesktopTitleBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Settings & Keys",
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Configure your AI providers, custom API credentials, or manage your quota usage.",
                          style: TextStyle(color: Colors.white60),
                        ),
                        const SizedBox(height: 24),

                        // Free Tier Badge Section
                        if (_quotaInfo != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.auto_awesome, color: kSecondary, size: 36),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Free Tier Usage",
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "${_quotaInfo!['freeScansUsed']}/${_quotaInfo!['freeScansLimit']} free scans used today.",
                                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                                        ),
                                        const SizedBox(height: 8),
                                        LinearProgressIndicator(
                                          value: (_quotaInfo!['freeScansUsed'] as int) / (_quotaInfo!['freeScansLimit'] as int),
                                          color: kSecondary,
                                          backgroundColor: Colors.white10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),

                        // Provider Selection
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Select AI Provider", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<ProviderType>(
                                  value: _selectedProvider,
                                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
                                  items: ProviderType.values.map((type) {
                                    return DropdownMenuItem(
                                      value: type,
                                      child: Text(type.name.toUpperCase()),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedProvider = val);
                                      _loadProviderKeys(val);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                if (_selectedProvider != ProviderType.firebaseProxy) ...[
                                  TextFormField(
                                    controller: _keyController,
                                    obscureText: _obscureKey,
                                    decoration: InputDecoration(
                                      labelText: "API Key",
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                                        onPressed: () => setState(() => _obscureKey = !_obscureKey),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (_selectedProvider == ProviderType.custom) ...[
                                  TextFormField(
                                    controller: _baseUrlController,
                                    decoration: const InputDecoration(
                                      labelText: "Base URL (e.g. http://localhost:8080/v1)",
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _modelController,
                                    decoration: const InputDecoration(
                                      labelText: "Model Name (e.g. llama3)",
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                Row(
                                  children: [
                                    ElevatedButton(
                                      onPressed: _isTesting ? null : _testConnection,
                                      child: _isTesting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Text("Test Connection"),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed: _isSaving ? null : _saveSettings,
                                      style: ElevatedButton.styleFrom(backgroundColor: kSecondary, foregroundColor: Colors.black),
                                      child: const Text("Save Keys"),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: _clearKey,
                                      child: const Text("Clear Key", style: TextStyle(color: kError)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Security Disclaimer Card
                        Card(
                          color: kPrimary.withOpacity(0.1),
                          child: const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Icon(Icons.security, color: kPrimary),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    "Security Alert: Your API keys are stored only on this local device using secure storage. Keys never touch our backend, databases, or analytics providers.",
                                    style: TextStyle(fontSize: 12, color: Colors.white70),
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Sign Out Section
                        Center(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: kError),
                            onPressed: () async {
                              await FirebaseAuth.instance.signOut();
                              _showSnackBar("Signed out", Colors.orange);
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text("Sign Out of Account"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 3,
        type: BottomNavigationBarType.fixed,
        backgroundColor: kSurface,
        selectedItemColor: kPrimary,
        unselectedItemColor: Colors.white60,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.add_a_photo), label: "Capture"),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "Search"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
        ],
        onTap: (index) {
          if (index == 0) navService.navigateTo('/dashboard', context);
          if (index == 1) navService.navigateTo('/capture', context);
          if (index == 2) navService.navigateTo('/search', context);
        },
      ),
    );
  }
}
