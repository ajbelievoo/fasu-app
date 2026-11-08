/// Host request screen â€” ported from native `HostRequestActivity.java`.
///
/// Form to apply as a host: name, bio, mobile, agency code, photo upload.
/// Submits via `/hostRequest/createRequest` multipart endpoint.
library host_request;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/json_annotation_helper.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import 'package:belive/widgets/preloader.dart';

class HostRequestScreen extends StatefulWidget {
  const HostRequestScreen({super.key});

  @override
  State<HostRequestScreen> createState() => _HostRequestScreenState();
}

class _HostRequestScreenState extends State<HostRequestScreen> {
  static const String _tag = 'HostRequest';

  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _agencyCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _photoPath;
  bool _submitting = false;
  bool _isRedirecting = false;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionManager>();
    final user = session.getUser();
    _nameCtrl.text = user?.username ?? '';
    _bioCtrl.text = user?.bio ?? '';
    // Prefill the agency code for users who already joined an agency.
    _agencyCtrl.text = user?.agencyCode ?? '';
    // Rebuild when the agency field changes so the Join button hides/shows.
    _agencyCtrl.addListener(() => setState(() {}));
    if (session.userId.isNotEmpty && session.hostRequestSubmitted) {
      _isRedirecting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.goNamed(AppRoutes.hostRequestStatus);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _mobileCtrl.dispose();
    _agencyCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  /// Push the agency list (returnTo mode). When the user joins an agency it
  /// pops back true; we then prefill the agency code from the session user.
  Future<void> _openJoinAgency() async {
    final joined = await context.pushNamed<bool>(
      AppRoutes.agencyList,
      extra: AppRoutes.hostRequest,
    );
    if (joined == true && mounted) {
      final user = context.read<SessionManager>().getUser();
      final code = user?.agencyCode ?? '';
      if (code.isNotEmpty) {
        setState(() => _agencyCtrl.text = code);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(source: ImageSource.gallery);
      if (xFile != null) {
        setState(() => _photoPath = xFile.path);
      }
    } catch (e, s) {
      Log.e(_tag, 'pickImage failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to pick image');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    final mobile = _mobileCtrl.text.trim();
    final agency = _agencyCtrl.text.trim();
    final bank = _bankCtrl.text.trim();

    if (name.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter Name');
      return;
    }
    if (mobile.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter Mobile Number');
      return;
    }
    if (bio.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter Bio');
      return;
    }
    if (bank.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter Bank Details');
      return;
    }
    if (_photoPath == null || _photoPath!.isEmpty) {
      Fluttertoast.showToast(msg: 'Select Personal Photo');
      return;
    }

    setState(() => _submitting = true);

    try {
      final session = context.read<SessionManager>();
      final res = await ApiService.createHostRequest(
        userId: session.userId,
        agencyCode: agency.isNotEmpty ? agency : null,
        bio: bio,
        name: name,
        mobileNumber: mobile,
        bankDetails: bank,
        photoFile: File(_photoPath!),
      );

      if (res.status) {
        Fluttertoast.showToast(msg: 'Host Request Sent');
        session.hostRequestSubmitted = true;
        if (mounted) context.pushNamed(AppRoutes.hostRequestStatus);
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Failed to submit');
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? parseString(data['message']) : null;
      final isServerError = e.response?.statusCode == 500;
      Log.e(_tag, 'DioException ${e.response?.statusCode}', e);
      Fluttertoast.showToast(
        msg: msg ?? (isServerError ? 'Server error, please try again later' : e.message ?? 'Try Again Later'),
      );
    } catch (e, s) {
      Log.e(_tag, 'submit failed', e, s);
      Fluttertoast.showToast(msg: 'Try Again Later');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRedirecting) {
      return const Scaffold(
        body: Center(child: Preloader(color: Colors.white)),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Request'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPhotoPicker(),
              const SizedBox(height: 8),
              // Face match warning — tells user this photo will be compared
              // with their KYC selfie to prevent fraud.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.face_retouching_natural, color: AppTheme.primary, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This photo will be matched with your KYC selfie. '
                        'Use a clear, well-lit photo of your face.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildField(_nameCtrl, 'Name', Icons.person),
              const SizedBox(height: 12),
              _buildField(_mobileCtrl, 'Mobile Number', Icons.phone,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _buildField(_bioCtrl, 'Bio', Icons.description, maxLines: 3),
              const SizedBox(height: 12),
              _buildField(_agencyCtrl, 'Agency Code (optional)', Icons.business),
              // Join-agency shortcut — shown when the user hasn't joined an
              // agency yet. Takes them to the agency list; after joining it
              // pops back here and the code prefills automatically.
              if (_agencyCtrl.text.trim().isEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openJoinAgency,
                  icon: const Icon(Icons.group_add, size: 20),
                  label: const Text('Join Agency'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.5)),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildField(_bankCtrl, 'Bank Details', Icons.account_balance,
                  maxLines: 2),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: Preloader(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit Request', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: _photoPath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(File(_photoPath!), fit: BoxFit.cover),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 48, color: AppTheme.primary),
                  SizedBox(height: 8),
                  Text('Upload Personal Photo',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }
}

