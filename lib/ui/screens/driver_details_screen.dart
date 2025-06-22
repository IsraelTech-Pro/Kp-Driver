import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kpdriver/ui/widgets/custom_button.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class DriverDetailsScreen extends StatefulWidget {
  const DriverDetailsScreen({super.key});

  @override
  State<DriverDetailsScreen> createState() => _DriverDetailsScreenState();
}

class _DriverDetailsScreenState extends State<DriverDetailsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController licenseNumberController = TextEditingController();
  final TextEditingController ghanaCardNumberController =
      TextEditingController();
  final TextEditingController phoneNumberController = TextEditingController();

  File? licenseImage;
  File? ghanaCardImage;
  File? faceImage;

  final SupabaseClient supabase = Supabase.instance.client;
  bool _isLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;

  final RegExp licensePattern = RegExp(r'^[A-Za-z0-9]{10,}$');
  final RegExp ghanaCardPattern = RegExp(r'^GHA-\d{10}-\d{1}$');
  final RegExp phonePattern = RegExp(r'^\+?1?\d{10,15}$');

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  Future<void> _pickImage(bool isLicense) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        if (isLicense) {
          licenseImage = File(picked.path);
        } else {
          ghanaCardImage = File(picked.path);
        }
      });
    }
  }

  Future<void> _captureFaceImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() {
        faceImage = File(picked.path);
      });
    } else {
      _showError('Face capture failed. Please try again.');
    }
  }

  Future<void> _submitDetails() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (licenseNumberController.text.trim().isEmpty ||
        ghanaCardNumberController.text.trim().isEmpty ||
        phoneNumberController.text.trim().isEmpty ||
        licenseImage == null ||
        ghanaCardImage == null ||
        faceImage == null) {
      _showError('Please fill all fields and upload all required images.');
      return;
    }

    setState(() => _isLoading = true);

    final userName =
        user.userMetadata?['full_name'] ??
        user.userMetadata?['name'] ??
        'Driver';

    final updates = {
      'license_number': licenseNumberController.text.trim(),
      'ghana_card_number': ghanaCardNumberController.text.trim(),
      'phone_number': phoneNumberController.text.trim(),
      'name': userName,
    };

    try {
      final uploads = <String, File>{
        'license.png': licenseImage!,
        'ghana_card.png': ghanaCardImage!,
        'face.png': faceImage!,
      };

      for (final entry in uploads.entries) {
        final path = 'drivers/${user.id}/${entry.key}';
        await supabase.storage
            .from('driver-uploads')
            .upload(
              path,
              entry.value,
              fileOptions: const FileOptions(upsert: true),
            );
        final url = supabase.storage.from('driver-uploads').getPublicUrl(path);

        if (entry.key == 'license.png') {
          updates['license_image_url'] = url;
        } else if (entry.key == 'ghana_card.png') {
          updates['ghana_card_image_url'] = url;
        } else if (entry.key == 'face.png') {
          updates['driver_image_url'] = url;
        }
      }

      await supabase.from('drivers').update(updates).eq('id', user.id);

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      _showError("Error submitting details: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            title: const Text(
              "Error",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(message, style: const TextStyle(fontSize: 16)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "OK",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  // Ghana Card Number Formatter (auto formats and adds hyphen)
  TextInputFormatter get ghanaCardFormatter {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      String newText = newValue.text;
      if (newText.length > 3 && newText[3] != '-') {
        newText = '${newText.substring(0, 3)}-${newText.substring(3)}';
      }
      if (newText.length > 14) {
        newText = newText.substring(0, 15); // Limit the length to 14 characters
      }
      return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    });
  }

  TextInputFormatter get licenseFormatter =>
      LengthLimitingTextInputFormatter(10);
  TextInputFormatter get phoneFormatter => LengthLimitingTextInputFormatter(15);

  bool isLicenseValid() =>
      licensePattern.hasMatch(licenseNumberController.text);
  bool isGhanaCardValid() =>
      ghanaCardPattern.hasMatch(ghanaCardNumberController.text);
  bool isPhoneValid() => phonePattern.hasMatch(phoneNumberController.text);

  Widget _buildTextInput(
    String label,
    TextEditingController controller,
    String hintText,
    bool Function() isValid,
    TextInputFormatter? formatter,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF176890),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          inputFormatters: formatter != null ? [formatter] : [],
          keyboardType:
              label.toLowerCase().contains('phone')
                  ? TextInputType.phone
                  : TextInputType.text,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD9A441), width: 2),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD9A441), width: 2),
            ),
            suffixIcon: Icon(
              isValid()
                  ? FontAwesomeIcons.checkCircle
                  : FontAwesomeIcons.timesCircle,
              color: isValid() ? Colors.green : Colors.red,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget imagePreview(File? image) {
    return image != null
        ? Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(image, height: 100),
          ),
        )
        : const SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fadeInAnimation,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
            child: Column(
              children: [
                Center(
                  child: Image.asset(
                    'lib/assets/register_img.png',
                    height: 120,
                  ),
                ),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.0),
                    border: Border.all(
                      color: const Color(0xFFD9A441),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text(
                          'Driver Details',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF176890),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildTextInput(
                        'License Number (10 Alphanumeric characters)',
                        licenseNumberController,
                        'Enter License Number...',
                        isLicenseValid,
                        licenseFormatter,
                      ),
                      CustomButton(
                        text:
                            licenseImage != null
                                ? '✅ License Image Selected'
                                : 'Upload License Image',
                        onPressed: () async {
                          await _pickImage(true);
                        },
                      ),
                      imagePreview(licenseImage),
                      const SizedBox(height: 16),
                      _buildTextInput(
                        'Phone Number (10 digits)',
                        phoneNumberController,
                        'Enter Phone Number...',
                        isPhoneValid,
                        phoneFormatter,
                      ),
                      _buildTextInput(
                        'Ghana Card Number (GHA-XXXXXXXXXX-X)',
                        ghanaCardNumberController,
                        'Enter Ghana Card Number...',
                        isGhanaCardValid,
                        ghanaCardFormatter,
                      ),
                      CustomButton(
                        text:
                            ghanaCardImage != null
                                ? '✅ Ghana Card Image Selected'
                                : 'Upload Ghana Card Image',
                        onPressed: () async {
                          await _pickImage(false);
                        },
                      ),
                      imagePreview(ghanaCardImage),
                      const SizedBox(height: 16),
                      const Text(
                        'Face Verification Photo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF176890),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CustomButton(
                        text:
                            faceImage != null
                                ? '✅ Face Image Captured'
                                : 'Capture Face Image',
                        onPressed: _captureFaceImage,
                      ),
                      imagePreview(faceImage),
                      const SizedBox(height: 25),
                      _isLoading
                          ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF176890),
                            ),
                          )
                          : CustomButton(
                            text: 'Submit Details',
                            onPressed: _submitDetails,
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
