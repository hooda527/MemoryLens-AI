import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:memorylens_ai/app_theme.dart';
import 'package:memorylens_ai/models/document_model.dart';
import 'package:memorylens_ai/services/ai_provider.dart';
import 'package:memorylens_ai/services/extraction_service.dart';
import 'package:memorylens_ai/services/reminder_service.dart';
import 'package:memorylens_ai/services/free_tier_service.dart';
import 'package:memorylens_ai/services/navigation_history_service.dart';
import 'package:memorylens_ai/widgets/desktop_title_bar.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _storage = const FlutterSecureStorage();
  File? _selectedFile;
  Uint8List? _fileBytes;
  String? _fileName;
  String? _mimeType;

  bool _isProcessing = false;
  String _processingStep = "";
  DocumentModel? _extractedDocument;
  bool _showReviewPanel = false;

  // Controllers for editing fields
  final Map<String, TextEditingController> _controllers = {};
  DateTime? _selectedReminderDate;

  @override
  void initState() {
    super.initState();
    ref.read(navigationHistoryProvider).setInitialRoute('/capture');
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    _controllers.forEach((_, c) => c.dispose());
    _controllers.clear();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'png', 'jpeg', 'pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      setState(() {
        _selectedFile = file;
        _fileBytes = bytes;
        _fileName = result.files.single.name;
        _mimeType = _getMimeType(_fileName!);
        _extractedDocument = null;
        _showReviewPanel = false;
      });
    }
  }

  Future<void> _captureImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedFile = File(pickedFile.path);
        _fileBytes = bytes;
        _fileName = pickedFile.name;
        _mimeType = _getMimeType(_fileName!);
        _extractedDocument = null;
        _showReviewPanel = false;
      });
    }
  }

  String _getMimeType(String name) {
    if (name.toLowerCase().endsWith('.pdf')) return 'application/pdf';
    if (name.toLowerCase().endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  Future<void> _analyzeDocument() async {
    if (_fileBytes == null) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("User not authenticated.", kError);
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStep = "Checking Quota Limit...";
    });

    try {
      // Quota check
      final selectedProviderStr = await _storage.read(key: 'selected_provider') ?? ProviderType.gemini.name;
      final selectedProvider = ProviderType.values.firstWhere((e) => e.name == selectedProviderStr);
      final hasKey = await _storage.read(key: '${selectedProvider.name}_api_key') != null;

      final freeTierService = ref.read(freeTierServiceProvider);
      
      if (!hasKey && selectedProvider != ProviderType.firebaseProxy) {
        final canUse = await freeTierService.canUseFreeScans(user.uid);
        if (!canUse) {
          _showSnackBar("Free usage limit reached. Configure an API key in Settings to continue.", kError);
          setState(() => _isProcessing = false);
          return;
        }
      }

      setState(() => _processingStep = "Extracting details via AI...");

      // Choose Provider
      AIProvider provider;
      if (hasKey) {
        final apiKey = await _storage.read(key: '${selectedProvider.name}_api_key');
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

      final extractionService = ExtractionService(provider);
      final result = await extractionService.extractFromBytes(_fileBytes!, _mimeType!, user.uid);

      if (result.success && result.document != null) {
        if (!hasKey && selectedProvider != ProviderType.firebaseProxy) {
          await freeTierService.incrementScanCount(user.uid);
        }
        
        setState(() {
          _extractedDocument = result.document;
          _showReviewPanel = true;
          _initControllers(result.document!);
        });
      } else {
        _showSnackBar(result.error ?? "Failed to extract structured data.", kError);
      }
    } catch (e) {
      _showSnackBar("Error: $e", kError);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _initControllers(DocumentModel doc) {
    _disposeControllers();
    if (doc.category == DocumentCategory.bill && doc.billData != null) {
      _controllers['vendor'] = TextEditingController(text: doc.billData!.vendor);
      _controllers['amount'] = TextEditingController(text: doc.billData!.amount?.toString());
      _controllers['currency'] = TextEditingController(text: doc.billData!.currency);
      _controllers['accountNumber'] = TextEditingController(text: doc.billData!.accountNumber);
      _selectedReminderDate = doc.billData!.dueDate;
    } else if (doc.category == DocumentCategory.prescription && doc.prescriptionData != null) {
      _controllers['medicineName'] = TextEditingController(text: doc.prescriptionData!.medicineName);
      _controllers['dosage'] = TextEditingController(text: doc.prescriptionData!.dosage);
      _controllers['doctorName'] = TextEditingController(text: doc.prescriptionData!.doctorName);
      _selectedReminderDate = doc.prescriptionData!.expiryDate;
    } else if (doc.category == DocumentCategory.ticket && doc.ticketData != null) {
      _controllers['eventName'] = TextEditingController(text: doc.ticketData!.eventName);
      _controllers['venue'] = TextEditingController(text: doc.ticketData!.venue);
      _controllers['seatNumber'] = TextEditingController(text: doc.ticketData!.seatNumber);
      _controllers['price'] = TextEditingController(text: doc.ticketData!.price?.toString());
      _selectedReminderDate = doc.ticketData!.eventDate;
    } else if (doc.category == DocumentCategory.receipt && doc.receiptData != null) {
      _controllers['storeName'] = TextEditingController(text: doc.receiptData!.storeName);
      _controllers['totalAmount'] = TextEditingController(text: doc.receiptData!.totalAmount?.toString());
      _controllers['currency'] = TextEditingController(text: doc.receiptData!.currency);
      _selectedReminderDate = doc.receiptData!.purchaseDate;
    }
  }

  Future<void> _setReminder() async {
    if (_selectedReminderDate == null) {
      _showSnackBar("Please specify a valid date to schedule a reminder.", Colors.orange);
      return;
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedReminderDate!.isAfter(DateTime.now()) ? _selectedReminderDate! : DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 9, minute: 0),
      );

      if (time != null) {
        final reminderTime = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
        setState(() {
          _selectedReminderDate = reminderTime;
        });

        // Trigger local notification registration
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && _extractedDocument != null) {
          final reminderService = ref.read(reminderServiceProvider);
          final id = _extractedDocument.hashCode.abs() % 100000;
          await reminderService.scheduleReminder(
            id: id,
            title: "Reminder: ${_extractedDocument!.displayTitle}",
            body: "Your ${_extractedDocument!.category.name} is scheduled for attention now.",
            scheduledDate: reminderTime,
            documentId: _extractedDocument!.id,
            userId: user.uid,
          );
          _showSnackBar("Notification reminder scheduled successfully!", Colors.green);
        }
      }
    }
  }

  Future<void> _saveDocument() async {
    if (_extractedDocument == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isProcessing = true);

    try {
      // Build updated data models from controller inputs
      DocumentModel updatedModel = _extractedDocument!;

      if (updatedModel.category == DocumentCategory.bill) {
        updatedModel = updatedModel.copyWith(
          billData: BillData(
            vendor: _controllers['vendor']?.text,
            amount: double.tryParse(_controllers['amount']?.text ?? ''),
            currency: _controllers['currency']?.text,
            dueDate: _selectedReminderDate,
            accountNumber: _controllers['accountNumber']?.text,
          ),
        );
      } else if (updatedModel.category == DocumentCategory.prescription) {
        updatedModel = updatedModel.copyWith(
          prescriptionData: PrescriptionData(
            medicineName: _controllers['medicineName']?.text,
            dosage: _controllers['dosage']?.text,
            expiryDate: _selectedReminderDate,
            doctorName: _controllers['doctorName']?.text,
          ),
        );
      } else if (updatedModel.category == DocumentCategory.ticket) {
        updatedModel = updatedModel.copyWith(
          ticketData: TicketData(
            eventName: _controllers['eventName']?.text,
            venue: _controllers['venue']?.text,
            seatNumber: _controllers['seatNumber']?.text,
            price: double.tryParse(_controllers['price']?.text ?? ''),
            eventDate: _selectedReminderDate,
          ),
        );
      } else if (updatedModel.category == DocumentCategory.receipt) {
        updatedModel = updatedModel.copyWith(
          receiptData: ReceiptData(
            storeName: _controllers['storeName']?.text,
            totalAmount: double.tryParse(_controllers['totalAmount']?.text ?? ''),
            currency: _controllers['currency']?.text,
            purchaseDate: _selectedReminderDate,
          ),
        );
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('documents')
          .doc(updatedModel.id)
          .set(updatedModel.toMap());

      _showSnackBar("Document successfully analyzed and saved.", Colors.green);
      
      // Navigate back to Dashboard
      ref.read(navigationHistoryProvider).navigateTo('/dashboard', context);
    } catch (e) {
      _showSnackBar("Failed to save: $e", kError);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Widget _buildReviewField(String key, String label) {
    final controller = _controllers[key];
    final isMissing = _extractedDocument?.unextractedFields.contains(key) ?? false;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              if (isMissing) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                  child: const Text("Not Extracted", style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            decoration: InputDecoration(
              hintText: isMissing ? "Tap to enter manually" : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navService = ref.read(navigationHistoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DesktopTitleBar(isUploadInProgress: _isProcessing),
            Expanded(
              child: _isProcessing
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: kPrimary),
                          const SizedBox(height: 16),
                          Text(_processingStep, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                "Analyze Document",
                                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Upload a receipt, invoice, prescription, or ticket, and AI will map it to structured data.",
                                style: TextStyle(color: Colors.white60),
                              ),
                              const SizedBox(height: 24),

                              if (!_showReviewPanel) ...[
                                // Desktop Drag and Drop
                                DropTarget(
                                  onDragDone: (detail) async {
                                    if (detail.files.isNotEmpty) {
                                      final path = detail.files.first.path;
                                      final bytes = await File(path).readAsBytes();
                                      setState(() {
                                        _selectedFile = File(path);
                                        _fileBytes = bytes;
                                        _fileName = detail.files.first.name;
                                        _mimeType = _getMimeType(_fileName!);
                                      });
                                    }
                                  },
                                  child: Container(
                                    height: 220,
                                    decoration: BoxDecoration(
                                      color: kSurface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: kPrimary.withOpacity(0.3), style: BorderStyle.solid, width: 2),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.cloud_upload, size: 48, color: kPrimary),
                                        const SizedBox(height: 12),
                                        const Text("Drag & drop document files here", style: TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        const Text("or click to select manually (Images/PDFs)", style: TextStyle(color: Colors.white30, fontSize: 12)),
                                        const SizedBox(height: 16),
                                        ElevatedButton(
                                          onPressed: _pickFile,
                                          style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                                          child: const Text("Select File"),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: _captureImage,
                                    icon: const Icon(Icons.camera_alt),
                                    label: const Text("Capture with Camera"),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                if (_selectedFile != null) ...[
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.insert_drive_file, color: kSecondary),
                                          const SizedBox(width: 12),
                                          Expanded(child: Text(_fileName ?? "file")),
                                          IconButton(
                                            icon: const Icon(Icons.clear, color: kError),
                                            onPressed: () => setState(() {
                                              _selectedFile = null;
                                              _fileBytes = null;
                                            }),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                    onPressed: _analyzeDocument,
                                    style: ElevatedButton.styleFrom(backgroundColor: kSecondary, foregroundColor: Colors.black),
                                    child: const Text("Analyze Document"),
                                  ),
                                ],
                              ] else ...[
                                // Review and Confirm Screen
                                Text(
                                  "Review Extracted: ${_extractedDocument?.category.name.toUpperCase()}",
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kSecondary),
                                ),
                                const SizedBox(height: 16),
                                if (_extractedDocument?.category == DocumentCategory.bill) ...[
                                  _buildReviewField('vendor', 'Vendor / Issuer'),
                                  _buildReviewField('amount', 'Due Amount'),
                                  _buildReviewField('currency', 'Currency'),
                                  _buildReviewField('accountNumber', 'Account Number'),
                                ],
                                if (_extractedDocument?.category == DocumentCategory.prescription) ...[
                                  _buildReviewField('medicineName', 'Medicine Name'),
                                  _buildReviewField('dosage', 'Dosage / Instructions'),
                                  _buildReviewField('doctorName', 'Prescribing Doctor'),
                                ],
                                if (_extractedDocument?.category == DocumentCategory.ticket) ...[
                                  _buildReviewField('eventName', 'Event Name'),
                                  _buildReviewField('venue', 'Venue Location'),
                                  _buildReviewField('seatNumber', 'Seat / Ticket Details'),
                                  _buildReviewField('price', 'Ticket Price'),
                                ],
                                if (_extractedDocument?.category == DocumentCategory.receipt) ...[
                                  _buildReviewField('storeName', 'Store Name'),
                                  _buildReviewField('totalAmount', 'Total Paid'),
                                  _buildReviewField('currency', 'Currency'),
                                ],
                                
                                // Reminder scheduler
                                Card(
                                  color: kPrimary.withOpacity(0.05),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.notifications_active, color: kPrimary),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text("Associated Date Reminder", style: TextStyle(fontWeight: FontWeight.bold)),
                                              const SizedBox(height: 4),
                                              Text(
                                                _selectedReminderDate != null
                                                    ? DateFormat.yMMMMEEEEd().add_jm().format(_selectedReminderDate!)
                                                    : "No date associated. Select a date to create a notification.",
                                                style: const TextStyle(fontSize: 12, color: Colors.white60),
                                              ),
                                            ],
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: _setReminder,
                                          style: ElevatedButton.styleFrom(backgroundColor: kPrimary, padding: const EdgeInsets.symmetric(horizontal: 12)),
                                          child: const Text("Edit / Schedule"),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => setState(() => _showReviewPanel = false),
                                        child: const Text("Rescan"),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _saveDocument,
                                        style: ElevatedButton.styleFrom(backgroundColor: kSecondary, foregroundColor: Colors.black),
                                        child: const Text("Save Document"),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
        currentIndex: 1,
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
          if (index == 2) navService.navigateTo('/search', context);
          if (index == 3) navService.navigateTo('/settings', context);
        },
      ),
    );
  }
}
