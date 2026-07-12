import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:memorylens_ai/app_theme.dart';
import 'package:memorylens_ai/models/document_model.dart';
import 'package:memorylens_ai/services/navigation_history_service.dart';
import 'package:memorylens_ai/widgets/desktop_title_bar.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _searchQuery = "";
  DocumentCategory? _selectedCategory;
  List<DocumentModel> _allDocs = [];
  List<DocumentModel> _filteredDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    ref.read(navigationHistoryProvider).setInitialRoute('/search');
    _fetchDocs();
  }

  Future<void> _fetchDocs() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('documents')
          .orderBy('createdAt', descending: true)
          .get();

      final docs = snap.docs.map((d) => DocumentModel.fromMap(d.data())).toList();
      setState(() {
        _allDocs = docs;
        _isLoading = false;
        _filterDocs();
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterDocs() {
    setState(() {
      _filteredDocs = _allDocs.where((doc) {
        // Category Filter
        if (_selectedCategory != null && doc.category != _selectedCategory) {
          return false;
        }

        // Keyword Filter
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          final matchesTitle = doc.displayTitle.toLowerCase().contains(query);
          final matchesSummary = doc.aiSummary?.toLowerCase().contains(query) ?? false;
          final matchesRaw = doc.rawText?.toLowerCase().contains(query) ?? false;

          return matchesTitle || matchesSummary || matchesRaw;
        }

        return true;
      }).toList();
    });
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
        final formattedDate = doc.primaryDate != null ? DateFormat.yMMMd().format(doc.primaryDate!) : "No date";
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
                  const SizedBox(height: 24),
                  if (doc.rawText != null) ...[
                    const Text("Raw Extracted Text", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: kCardColor, borderRadius: BorderRadius.circular(8)),
                      width: double.infinity,
                      child: Text(doc.rawText!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white60)),
                    ),
                  ],
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
      fields['Price'] = doc.ticketData!.price != null ? "\$${doc.ticketData!.price}" : null;
    } else if (doc.category == DocumentCategory.receipt && doc.receiptData != null) {
      fields['Store Name'] = doc.receiptData!.storeName;
      fields['Total'] = doc.receiptData!.totalAmount != null ? "${doc.receiptData!.currency ?? ''} ${doc.receiptData!.totalAmount}" : null;
      fields['Purchase Date'] = doc.receiptData!.purchaseDate != null ? DateFormat.yMMMd().format(doc.receiptData!.purchaseDate!) : null;
    }

    if (fields.isEmpty) return const Text("No specific structured fields extracted.");

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
    final navService = ref.read(navigationHistoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const DesktopTitleBar(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Search by keyword, vendor, store or category details...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchQuery = "";
                              _filterDocs();
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _filterDocs();
                  });
                },
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text("All"),
                    selected: _selectedCategory == null,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _selectedCategory = null;
                          _filterDocs();
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ...DocumentCategory.values.map((cat) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(cat.name[0].toUpperCase() + cat.name.substring(1)),
                        selected: _selectedCategory == cat,
                        onSelected: (sel) {
                          setState(() {
                            _selectedCategory = sel ? cat : null;
                            _filterDocs();
                          });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredDocs.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.white24),
                              SizedBox(height: 12),
                              Text("No matching documents found", style: TextStyle(color: Colors.white60)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredDocs.length,
                          itemBuilder: (context, idx) {
                            final doc = _filteredDocs[idx];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: _getCategoryIcon(doc.category),
                                title: Text(doc.displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  doc.aiSummary ?? "No summary available",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showDetailSheet(doc),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
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
          if (index == 3) navService.navigateTo('/settings', context);
        },
      ),
    );
  }
}
