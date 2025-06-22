import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountInfoScreen extends StatefulWidget {
  const AccountInfoScreen({super.key});

  @override
  State<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> {
  final supabase = Supabase.instance.client;
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  File? _selectedImage;

  String? name;
  String? email;
  String? uid;
  String? avatarUrl;

  @override
  void initState() {
    super.initState();
    final user = supabase.auth.currentUser;
    if (user != null) {
      name = user.userMetadata?['name'] ?? user.email?.split('@')[0];
      email = user.email;
      uid = user.id;
      _loadUserDetails();
    }
  }

  Future<void> _loadUserDetails() async {
    if (uid == null) return;

    final userData =
        await supabase.from('users').select().eq('id', uid!).maybeSingle();

    if (userData != null) {
      _phoneController.text = userData['phone'] ?? '';
      avatarUrl = userData['avatar_url'];
      setState(() {});
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85, // Optional: compress image a bit
    );

    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<String?> _uploadAvatar(File image) async {
    if (uid == null) return null;

    final ext = image.path.split('.').last; // preserve original extension
    final filePath = 'avatars/$uid.$ext';

    await supabase.storage
        .from('avatars')
        .upload(filePath, image, fileOptions: const FileOptions(upsert: true));

    final url = supabase.storage.from('avatars').getPublicUrl(filePath);
    return url;
  }

  Future<void> _saveProfile() async {
    if (_phoneController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Phone number is required")));
      return;
    }

    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      String? avatar;
      if (_selectedImage != null) {
        avatar = await _uploadAvatar(_selectedImage!);
      }

      final existing =
          await supabase.from('users').select().eq('id', uid!).maybeSingle();

      final data = {
        'id': uid,
        'name': name,
        'email': email,
        'phone': _phoneController.text,
        if (avatar != null) 'avatar_url': avatar,
      };

      if (existing == null) {
        await supabase.from('users').insert(data);
      } else {
        await supabase.from('users').update(data).eq('id', uid!);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated successfully")),
      );
      _loadUserDetails();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarImage =
        _selectedImage != null
            ? FileImage(_selectedImage!)
            : (avatarUrl != null ? NetworkImage(avatarUrl!) : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Personal info"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: avatarImage as ImageProvider?,
                  child:
                      avatarImage == null
                          ? const Icon(Icons.person, size: 40)
                          : null,
                ),
                Positioned(
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: const CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.green,
                      child: Icon(Icons.add, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "Add a profile photo so drivers can recognise you",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            /*
            const SizedBox(height: 5),
            const Text(
              "When can the driver see my photo?",
              style: TextStyle(color: Colors.green, fontSize: 13),
            ),*/
            const Divider(height: 30),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(name ?? 'Name'),
              subtitle: const Text("Full name"),
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text(email ?? 'Email'),
              subtitle: const Text("Email"),
            ),
            ListTile(
              leading: const Icon(Icons.phone),
              title: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Phone number",
                  hintText: "+233...",
                  border: InputBorder.none,
                ),
              ),
              subtitle: const Text(
                "This is the number drivers will use to contact you",
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              child:
                  _isLoading
                      ? const CircularProgressIndicator()
                      : const Text("Update Profile"),
            ),
          ],
        ),
      ),
    );
  }
}
