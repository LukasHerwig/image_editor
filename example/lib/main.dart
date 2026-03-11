import 'dart:io';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:z_image_editor/z_image_editor.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Z Image Editor Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _editedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAndEditImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);

      if (pickedFile != null && mounted) {
        final editedImage = await Navigator.of(context).push<File>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => ZImageEditor(
              imageFile: File(pickedFile.path),
              onSave: (File edited) {
                Navigator.of(context).pop(edited);
              },
              onCancel: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        );

        if (editedImage != null) {
          setState(() {
            _editedImage = editedImage;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Z Image Editor'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_editedImage != null)
              Container(
                width: 300,
                height: 300,
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                ),
                child: Image.file(_editedImage!, fit: BoxFit.contain),
              )
            else
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No image selected',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                log('Camera button pressed');
                _pickAndEditImage(ImageSource.camera);
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo & Edit'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _pickAndEditImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose from Gallery & Edit'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
