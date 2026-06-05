import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

enum VisionState { initial, selected, processing, result }

abstract class VisionBaseState<T extends StatefulWidget> extends State<T> {
  final ImagePicker picker = ImagePicker();
  
  File? imageFile;
  Uint8List? imageBytes;
  String resultText = "";
  VisionState visionState = VisionState.initial;

  @override
  void initState() {
    super.initState();
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          imageFile = File(pickedFile.path);
          imageBytes = bytes;
          visionState = VisionState.selected;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  Future<void> cropImage() async {
    if (imageFile == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imageFile!.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪图片',
          toolbarColor: Theme.of(context).colorScheme.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: '裁剪图片',
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );

    if (croppedFile != null) {
      final bytes = await croppedFile.readAsBytes();
      setState(() {
        imageFile = File(croppedFile.path);
        imageBytes = bytes;
      });
    }
  }

  void reset() {
    setState(() {
      imageFile = null;
      imageBytes = null;
      resultText = "";
      visionState = VisionState.initial;
    });
  }

  void showFullScreenImage() {
    if (imageFile == null) return;
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(imageFile!),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget buildRoundButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 32),
      ),
    );
  }

  Widget buildInitialView({
    required String title,
    required String description,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 80, color: colorScheme.primary),
            ),
            const SizedBox(height: 32),
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 48),
            Row(
              children: [
                Expanded(
                  child: buildActionButton(
                    icon: Icons.camera_alt_rounded,
                    label: '拍照',
                    onTap: () => pickImage(ImageSource.camera),
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: buildActionButton(
                    icon: Icons.photo_library_rounded,
                    label: '相册',
                    onTap: () => pickImage(ImageSource.gallery),
                    color: colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSelectedView({required ColorScheme colorScheme, required VoidCallback onConfirm}) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: GestureDetector(
                onTap: showFullScreenImage,
                child: Hero(
                  tag: 'selected_image',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                      ),
                      child: Image.file(imageFile!, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              buildRoundButton(
                icon: Icons.close_rounded,
                color: Colors.redAccent,
                onTap: reset,
              ),
              buildRoundButton(
                icon: Icons.crop_rounded,
                color: colorScheme.primary,
                onTap: cropImage,
              ),
              buildRoundButton(
                icon: Icons.check_rounded,
                color: Colors.greenAccent.shade700,
                onTap: onConfirm,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildProcessingView({required String message, required ColorScheme colorScheme}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
          if (resultText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                resultText,
                style: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
