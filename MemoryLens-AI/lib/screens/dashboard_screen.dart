import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:memorylens_ai/app_theme.dart';
import 'package:memorylens_ai/models/document_model.dart';
import 'package:memorylens_ai/services/navigation_history_service.dart';
import 'package:memorylens_ai/services/free_tier_service.dart';
import 'package:memorylens_ai/services/ai_provider.dart';
import 'package:memorylens_ai/widgets/desktop_title_bar.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _storage = const FlutterSecureStorage();
  Map<String, dynamic>? _quotaInfo;
  String _aiSummaryText = "Select 'Generate Summary' to synthesize analysis of your documents.";
  bool _isGeneratingSummary = false;
  List<DocumentModel> _recentDocs = [];
  bool _isLoadingRecent = true;

  @override
  void initState() {
    super.initState();
    ref.read(navigationHistoryProvider).setInitialRoute('/dashboard');
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingRecent = false;
      });
      return;
    }

    // Load Quota
    final selectedProviderStr = await _storage.read(key: 'selected_provider') ?? ProviderType.gemini.name;
    final selectedProvider = ProviderType.values.firstWhere((e) => e.name == selectedProviderStr);
    final hasKey = await _storage.read(key: '${selectedProvider.name}_api_key') != null;

    if (!hasKey && selectedProvider != ProviderType.firebaseProxy) {
      final quota = await ref.read(freeTierServiceProvider).getQuotaInfo(user.uid);
      setState(() {
        _quotaInfo = quota;
      });
    } else {
      setState(() {
        _quotaInfo = null;
      });
    }

    // Load Documents
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('documents')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      final docs = snap.docs.map((d) => DocumentModel.fromMap(d.data())).toList();
      setState(() {
        _recentDocs = docs;
        _isLoadingRecent = false;
      });
    } catch (e) {
      setState(() => _isLoadingRecent = false);
    }
  }

  Future<void> _generateAISummary(List<DocumentModel> allDocs) async {
    if (allDocs.isEmpty) {
      setState(() {
        _aiSummaryText = "You have no stored documents. Upload files to generate a summary.";
      });
      return;
    }

    setState(() => _isGeneratingSummary = true);

    try {
      final selectedProviderStr = await _storage.read(key: 'selected_provider') ?? ProviderType.gemini.name;
      final selectedProvider = ProviderType.values.firstWhere((e) => e.name == selectedProviderStr);
      final apiKey = await _storage.read(key: '${selectedProvider.name}_api_key');

      AIProvider provider;
      if (apiKey != null && apiKey.isNotEmpty) {
        switch (selectedProvider) {
          case ProviderType.gemini:
            provider = GeminiProvider(apiKey);
            break;
          case ProviderType.openai:
            provider = OpenAIProvider(apiKey);
            break;
          case ProviderType.claude:
            provider = ClaudeProvider(apiKey);
            break;
          case ProviderType.groq:
            provider = GroqProvider(apiKey);
            break;
          case ProviderType.custom:
            final baseUrl = await _storage.read(key: 'custom_base_url');
            final modelName = await _storage.read(key: 'custom_model');
            provider = CustomProvider(apiKey: apiKey, baseUrl: baseUrl, model: modelName);
            break;
          default:
            provider = FirebaseProxyProvider();
        }
      } else {
        provider = FirebaseProxyProvider();
      }

      final docDetails = allDocs.map((doc) {
        return "- Category: ${doc.category.name}, Title: ${doc.displayTitle}, Date: ${doc.primaryDate?.toIso8601String() ?? 'N/A'}, Summary: ${doc.aiSummary ?? 'N/A'}";
      }).join("\n");

      final prompt = "You are a helpful virtual assistant. Below is a list of documents in the user's secure locker. Analyze the list and write a brief summary (2-3 sentences max) highlighting what requires attention first, such as upcoming bills or expiring medicine.\n\n$docDetails";

      // Passing dummy file bytes since analyzeDocument expects it for Vision,
      // but here we are sending a pure text prompt.
      final result = await provider.analyzeDocument([], 'text/plain', prompt);
      setState(() {
        _aiSummaryText = result;
      });
    } catch (e) {
      setState(() {
        _aiSummaryText = "Could not generate summary at this time: ${e.toString()}";
      });
    } finally {
      setState(() => _isGeneratingSummary = false);
    }
  }

  void _showDetailSheet(DocumentModel doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, controller) {
            return SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _getCategoryIcon(doc.category, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          doc.displayTitle,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text("Category: ${doc.category.name.toUpperCase()}", style: const TextStyle(color: kSecondary)),
                  const SizedBox(height: 16),
                  if (doc.aiSummary != null) ...[
                    const Text("Summary", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(doc.aiSummary!, style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 20),
                  ],
                  const Text("Extracted Fields", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildFieldsView(doc),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFieldsView(DocumentModel doc) {
    final Map<String, String?> fields = {};
    if (doc.category == DocumentCategory.bill && doc.billData != null) {
      fields['Vendor'] = doc.billData!.vendor;
      fields['Amount'] = doc.billData!.amount != null ? "${doc.billData!.currency ?? ''} ${doc.billData!.amount}" : null;
      fields['Due Date'] = doc.billData!.dueDate != null ? DateFormat.yMMMd().format(doc.billData!.dueDate!) : null;
      fields['Account Number'] = doc.billData!.accountNumber;
    } else if (doc.category == DocumentCategory.prescription && doc.prescriptionData != null) {
      fields['Medicine'] = doc.prescriptionData!.medicineName;
      fields['Dosage'] = doc.prescriptionData!.dosage;
      fields['Expiry'] = doc.prescriptionData!.expiryDate != null ? DateFormat.yMMMd().format(doc.prescriptionData!.expiryDate!) : null;
      fields['Doctor'] = doc.prescriptionData!.doctorName;
    } else if (doc.category == DocumentCategory.ticket && doc.ticketData != null) {
      fields['Event Name'] = doc.ticketData!.eventName;
      fields['Event Date'] = doc.ticketData!.eventDate != null ? DateFormat.yMMMd().format(doc.ticketData!.eventDate!) : null;
      fields['Venue'] = doc.ticketData!.venue;
      fields['Seat'] = doc.ticketData!.seatNumber;
    }

    if (fields.isEmpty) return const Text("No specific fields extracted.");

    return Column(
      children: fields.entries.map((e) {
        final isUnextracted = doc.unextractedFields.contains(e.key.toLowerCase().replaceAll(' ', ''));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.key, style: const TextStyle(color: Colors.white60)),
              isUnextracted || e.value == null
                  ? const Text("Could not extract", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))
                  : Text(e.value!, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _getCategoryIcon(DocumentCategory cat, {double size = 20}) {
    switch (cat) {
      case DocumentCategory.bill:
        return Icon(Icons.receipt_long, color: Colors.redAccent, size: size);
      case DocumentCategory.prescription:
        return Icon(Icons.medication, color: Colors.greenAccent, size: size);
      case DocumentCategory.ticket:
        return Icon(Icons.confirmation_number, color: Colors.orangeAccent, size: size);
      case DocumentCategory.receipt:
        return Icon(Icons.shopping_cart, color: Colors.blueAccent, size: size);
      case DocumentCategory.exam:
        return Icon(Icons.assignment, color: Colors.purpleAccent, size: size);
      case DocumentCategory.notice:
        return Icon(Icons.campaign, color: Colors.yellowAccent, size: size);
      case DocumentCategory.other:
        return Icon(Icons.description, color: Colors.white70, size: size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final navService = ref.read(navigationHistoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DesktopTitleBar(onRefresh: _loadDashboardData),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: user == null
                    ? const Stream.empty()
                    : FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('documents')
                        .snapshots(),
                builder: (context, snapshot) {
                  List<DocumentModel> allDocs = [];
                  if (snapshot.hasData) {
                    allDocs = snapshot.data!.docs
                        .map((d) => DocumentModel.fromMap(d.data() as Map<String, dynamic>))
                        .toList();
                  }

                  // Perform aggregations
                  final totalDocuments = allDocs.length;
                  final now = DateTime.now();
                  final currentMonth = now.month;
                  
                  final billsDueThisMonth = allDocs.where((doc) {
                    if (doc.category != DocumentCategory.bill || doc.billData?.dueDate == null) return false;
                    return doc.billData!.dueDate!.month == currentMonth && doc.billData!.dueDate!.year == now.year;
                  }).length;

                  final medicinesExpiringSoon = allDocs.where((doc) {
                    if (doc.category != DocumentCategory.prescription || doc.prescriptionData?.expiryDate == null) return false;
                    final diff = doc.prescriptionData!.expiryDate!.difference(now).inDays;
                    return diff >= 0 && diff <= 30;
                  }).length;

                  final upcomingEvents = allDocs.where((doc) {
                    if (doc.category != DocumentCategory.ticket || doc.ticketData?.eventDate == null) return false;
                    final diff = doc.ticketData!.eventDate!.difference(now).inDays;
                    return diff >= 0 && diff <= 7;
                  }).length;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Welcome back, ${user?.email?.split('@')[0] ?? 'Explorer'}",
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    const Text("Here's your live AI-analyzed locker overview", style: TextStyle(color: Colors.white60)),
                                  ],
                                ),
                                if (_quotaInfo != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: kSecondary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: kSecondary.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      "${(_quotaInfo!['freeScansLimit'] as int) - (_quotaInfo!['freeScansUsed'] as int)} free scans left today",
                                      style: const TextStyle(color: kSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Statistics Cards Grid
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                _buildStatCard("Total Items", totalDocuments.toString(), Icons.folder_open, kPrimary),
                                _buildStatCard("Bills Due", billsDueThisMonth.toString(), Icons.alarm, Colors.redAccent),
                                _buildStatCard("Meds Expiring", medicinesExpiringSoon.toString(), Icons.medication, Colors.greenAccent),
                                _buildStatCard("Tickets", upcomingEvents.toString(), Icons.event, Colors.orangeAccent),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // AI summary card
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.auto_awesome, color: kSecondary),
                                            SizedBox(width: 8),
                                            Text("AI Analytics Summary", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: _isGeneratingSummary ? null : () => _generateAISummary(allDocs),
                                          icon: const Icon(Icons.refresh, size: 14),
                                          label: const Text("Generate Summary", style: TextStyle(fontSize: 11)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kPrimary,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    _isGeneratingSummary
                                        ? const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)))
                                        : Text(
                                            _aiSummaryText,
                                            style: const TextStyle(color: Colors.white70, height: 1.4),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Recent Documents
                            const Text("Recent Documents", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            _isLoadingRecent
                                ? const Center(child: CircularProgressIndicator())
                                : _recentDocs.isEmpty
                                    ? Container(
                                        height: 120,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12)),
                                        child: const Text("No recent documents. Upload your first scan!", style: TextStyle(color: Colors.white30)),
                                      )
                                    : ListView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: _recentDocs.length,
                                        itemBuilder: (context, idx) {
                                          final doc = _recentDocs[idx];
                                          return Card(
                                            margin: const EdgeInsets.only(bottom: 12),
                                            child: ListTile(
                                              leading: _getCategoryIcon(doc.category),
                                              title: Text(doc.displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                                              subtitle: Text(doc.aiSummary ?? "No summary"),
                                              trailing: const Icon(Icons.chevron_right),
                                              onTap: () => _showDetailSheet(doc),
                                            ),
                                          );
                                        },
                                      ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        onPressed: () => navService.navigateTo('/capture', context),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
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
          if (index == 1) navService.navigateTo('/capture', context);
          if (index == 2) navService.navigateTo('/search', context);
          if (index == 3) navService.navigateTo('/settings', context);
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
  }
}
