import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'dart:async'; 
import 'package:path_provider/path_provider.dart';
import 'dart:html' as html;



import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'dart:html' as html;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Compositor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: ImageCompositorScreen(),
    );
  }
}

class ImageCompositorScreen extends StatefulWidget {
  @override
  _ImageCompositorScreenState createState() => _ImageCompositorScreenState();
}

class _ImageCompositorScreenState extends State<ImageCompositorScreen> {
  final ImagePicker _picker = ImagePicker();
  
  // For mobile
  File? _foregroundImageFile;
  List<File> _backgroundImageFiles = [];
  
  // For web
  Uint8List? _foregroundImageBytes;
  List<Uint8List> _backgroundImageBytes = [];
  
  bool _isProcessing = false;
  int _generatedCount = 0;
  
  // Output resolution
  static const double OUTPUT_WIDTH = 1080.0;
  static const double OUTPUT_HEIGHT = 1080.0;

  Future<void> _selectForegroundImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          setState(() {
            _foregroundImageBytes = bytes;
            _foregroundImageFile = null;
          });
        } else {
          setState(() {
            _foregroundImageFile = File(image.path);
            _foregroundImageBytes = null;
          });
        }
      }
    } catch (e) {
      _showErrorDialog('Error selecting foreground image: $e');
    }
  }

  Future<void> _selectBackgroundImages() async {
    try {
      final List<XFile>? images = await _picker.pickMultiImage();
      if (images != null && images.isNotEmpty) {
        if (kIsWeb) {
          List<Uint8List> imageBytes = [];
          for (XFile image in images) {
            final bytes = await image.readAsBytes();
            imageBytes.add(bytes);
          }
          setState(() {
            _backgroundImageBytes = imageBytes;
            _backgroundImageFiles.clear();
          });
        } else {
          setState(() {
            _backgroundImageFiles = images.map((xFile) => File(xFile.path)).toList();
            _backgroundImageBytes.clear();
          });
        }
      }
    } catch (e) {
      _showErrorDialog('Error selecting background images: $e');
    }
  }

  Future<void> _generateCompositeImages() async {
    bool hasForeground = kIsWeb ? _foregroundImageBytes != null : _foregroundImageFile != null;
    bool hasBackgrounds = kIsWeb ? _backgroundImageBytes.isNotEmpty : _backgroundImageFiles.isNotEmpty;
    
    if (!hasForeground || !hasBackgrounds) {
      _showErrorDialog('Please select both foreground and background images');
      return;
    }

    setState(() {
      _isProcessing = true;
      _generatedCount = 0;
    });

    try {
      // Load foreground image
      Uint8List foregroundBytes;
      if (kIsWeb) {
        foregroundBytes = _foregroundImageBytes!;
      } else {
        foregroundBytes = await _foregroundImageFile!.readAsBytes();
      }
      final foregroundImage = await _loadImage(foregroundBytes);

      // Get background images
      List<Uint8List> backgroundBytesList;
      if (kIsWeb) {
        backgroundBytesList = _backgroundImageBytes;
      } else {
        backgroundBytesList = [];
        for (File file in _backgroundImageFiles) {
          backgroundBytesList.add(await file.readAsBytes());
        }
      }

      // Process each background image
      for (int i = 0; i < backgroundBytesList.length; i++) {
        final backgroundImage = await _loadImage(backgroundBytesList[i]);

        // Create composite image with upscaling
        final compositeBytes = await _createCompositeImage(
          backgroundImage,
          foregroundImage,
        );

        // Save composite image
        final fileName = 'composite_1080p_${DateTime.now().millisecondsSinceEpoch}_$i.png';
        
        if (kIsWeb) {
          _downloadImageWeb(compositeBytes, fileName);
        } else {
          await _saveImageMobile(compositeBytes, fileName);
        }

        setState(() {
          _generatedCount++;
        });
      }

      setState(() {
        _isProcessing = false;
      });

      _showSuccessDialog('Generated $_generatedCount images successfully at 1080p resolution!');
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showErrorDialog('Error generating images: $e');
    }
  }

  Future<ui.Image> _loadImage(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completer.complete(img);
    });
    return completer.future;
  }

  Future<Uint8List> _createCompositeImage(ui.Image background, ui.Image foreground) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Always output at 1080x1080 for consistency
    const double outputWidth = OUTPUT_WIDTH;
    const double outputHeight = OUTPUT_HEIGHT;
    
    // Draw background - stretch to fill entire 1080x1080 canvas
    final bgRect = Rect.fromLTWH(0, 0, outputWidth, outputHeight);
    canvas.drawImageRect(
      background,
      Rect.fromLTWH(0, 0, background.width.toDouble(), background.height.toDouble()),
      bgRect,
      Paint(),
    );
    
    // Calculate foreground size and position
    double fgWidth = foreground.width.toDouble();
    double fgHeight = foreground.height.toDouble();
    
    // Calculate scale to maintain aspect ratio while fitting within 80% of output size
    final maxFgWidth = outputWidth * 0.8;
    final maxFgHeight = outputHeight * 0.8;
    
    double scale = 1.0;
    if (fgWidth > maxFgWidth || fgHeight > maxFgHeight) {
      final scaleX = maxFgWidth / fgWidth;
      final scaleY = maxFgHeight / fgHeight;
      scale = scaleX < scaleY ? scaleX : scaleY;
    } else {
      // Upscale small images to utilize more space
      final scaleX = maxFgWidth / fgWidth;
      final scaleY = maxFgHeight / fgHeight;
      scale = scaleX < scaleY ? scaleX : scaleY;
      // Limit upscaling to avoid too much quality loss
      scale = scale > 3.0 ? 3.0 : scale;
    }
    
    fgWidth *= scale;
    fgHeight *= scale;
    
    // Center the foreground image
    final fgX = (outputWidth - fgWidth) / 2;
    final fgY = (outputHeight - fgHeight) / 2;
    
    // Draw foreground with high quality scaling
    final fgRect = Rect.fromLTWH(fgX, fgY, fgWidth, fgHeight);
    final paint = Paint()
      ..filterQuality = FilterQuality.high; // High quality scaling
      
    canvas.drawImageRect(
      foreground,
      Rect.fromLTWH(0, 0, foreground.width.toDouble(), foreground.height.toDouble()),
      fgRect,
      paint,
    );
    
    final picture = recorder.endRecording();
    final img = await picture.toImage(outputWidth.toInt(), outputHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }

  void _downloadImageWeb(Uint8List bytes, String fileName) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _saveImageMobile(Uint8List bytes, String fileName) async {
    try {
      // For Android, save to Downloads/generated_images
      final directory = Directory('/storage/emulated/0/Download/generated_images');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes);
    } catch (e) {
      // Fallback: save to app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final generatedDir = Directory('${directory.path}/generated_images');
      if (!await generatedDir.exists()) {
        await generatedDir.create(recursive: true);
      }
      
      final file = File('${generatedDir.path}/$fileName');
      await file.writeAsBytes(bytes);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Success'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 48),
            SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            SizedBox(height: 8),
            if (kIsWeb) 
              Text('Images downloaded to your browser\'s download folder at 1080x1080 resolution.', 
                   style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                   textAlign: TextAlign.center,)
            else
              Text('Images saved to Download/generated_images/ at 1080x1080 resolution.', 
                   style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                   textAlign: TextAlign.center,),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _clearSelection() {
    setState(() {
      _foregroundImageFile = null;
      _foregroundImageBytes = null;
      _backgroundImageFiles.clear();
      _backgroundImageBytes.clear();
      _generatedCount = 0;
    });
  }

  Widget _buildImageDisplay(dynamic image, {double height = 200}) {
    if (kIsWeb && image is Uint8List) {
      return Image.memory(image, fit: BoxFit.cover, height: height, width: double.infinity);
    } else if (!kIsWeb && image is File) {
      return Image.file(image, fit: BoxFit.cover, height: height, width: double.infinity);
    }
    return Container(height: height);
  }

  bool get _hasForeground => kIsWeb ? _foregroundImageBytes != null : _foregroundImageFile != null;
  bool get _hasBackgrounds => kIsWeb ? _backgroundImageBytes.isNotEmpty : _backgroundImageFiles.isNotEmpty;
  int get _backgroundCount => kIsWeb ? _backgroundImageBytes.length : _backgroundImageFiles.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Image Compositor - 1080p'),
        backgroundColor: Colors.purple[600],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.clear_all),
            onPressed: _clearSelection,
            tooltip: 'Clear All',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Platform and output info
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.purple[600], size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Platform: ${kIsWeb ? "Web" : "Mobile"}',
                        style: TextStyle(fontSize: 14, color: Colors.purple[600], fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Output: 1080x1080px with high-quality upscaling\n• One foreground + Multiple backgrounds = Multiple outputs',
                    style: TextStyle(fontSize: 12, color: Colors.purple[600]),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),

            // Foreground Image Section
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.blue[600]),
                        SizedBox(width: 8),
                        Text(
                          'Foreground Image (Fixed)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    if (_hasForeground) ...[
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue[300]!, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: _buildImageDisplay(
                            kIsWeb ? _foregroundImageBytes : _foregroundImageFile
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'This image will be applied to all background images',
                          style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: _selectForegroundImage,
                      icon: Icon(Icons.image),
                      label: Text(_hasForeground 
                          ? 'Change Foreground Image' 
                          : 'Select Foreground Image'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            // Background Images Section
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.landscape, color: Colors.green[600]),
                        SizedBox(width: 8),
                        Text(
                          'Background Images (Multiple)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    if (_hasBackgrounds) ...[
                      Container(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _backgroundCount,
                          itemBuilder: (context, index) {
                            return Container(
                              width: 100,
                              margin: EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.green[300]!, width: 2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: _buildImageDisplay(
                                  kIsWeb ? _backgroundImageBytes[index] : _backgroundImageFiles[index],
                                  height: 120,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$_backgroundCount background(s) selected → $_backgroundCount outputs will be generated',
                          style: TextStyle(fontSize: 12, color: Colors.green[600]),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: _selectBackgroundImages,
                      icon: Icon(Icons.photo_library),
                      label: Text(_hasBackgrounds 
                          ? 'Change Background Images ($_backgroundCount selected)' 
                          : 'Select Background Images'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),

            // Generate Button
            SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _generateCompositeImages,
                icon: _isProcessing 
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(Icons.auto_awesome, size: 28),
                label: Text(
                  _isProcessing 
                      ? 'Generating 1080p Images... ($_generatedCount/$_backgroundCount)' 
                      : 'Generate $_backgroundCount Images at 1080p',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            // Generated Images Info
            if (_generatedCount > 0) ...[
              SizedBox(height: 24),
              Card(
                elevation: 4,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'Generated Images',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '$_generatedCount high-quality 1080p images generated!',
                        style: TextStyle(color: Colors.green[600], fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 4),
                      Text(
                        kIsWeb 
                            ? 'Downloaded to your browser\'s download folder' 
                            : 'Saved to: Download/generated_images/',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// void main() {
//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Image Compositor',
//       theme: ThemeData(
//         primarySwatch: Colors.blue,
//         visualDensity: VisualDensity.adaptivePlatformDensity,
//       ),
//       home: ImageCompositorScreen(),
//     );
//   }
// }

// class ImageCompositorScreen extends StatefulWidget {
//   @override
//   _ImageCompositorScreenState createState() => _ImageCompositorScreenState();
// }

// class _ImageCompositorScreenState extends State<ImageCompositorScreen> {
//   final ImagePicker _picker = ImagePicker();
  
//   // For mobile
//   File? _foregroundImageFile;
//   List<File> _backgroundImageFiles = [];
  
//   // For web
//   Uint8List? _foregroundImageBytes;
//   List<Uint8List> _backgroundImageBytes = [];
  
//   bool _isProcessing = false;
//   int _generatedCount = 0;
  
//   // Output resolution
//   static const double OUTPUT_WIDTH = 1080.0;
//   static const double OUTPUT_HEIGHT = 1080.0;

//   Future<void> _selectForegroundImage() async {
//     try {
//       final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
//       if (image != null) {
//         if (kIsWeb) {
//           final bytes = await image.readAsBytes();
//           setState(() {
//             _foregroundImageBytes = bytes;
//             _foregroundImageFile = null;
//           });
//         } else {
//           setState(() {
//             _foregroundImageFile = File(image.path);
//             _foregroundImageBytes = null;
//           });
//         }
//       }
//     } catch (e) {
//       _showErrorDialog('Error selecting foreground image: $e');
//     }
//   }

//   Future<void> _selectBackgroundImages() async {
//     try {
//       final List<XFile>? images = await _picker.pickMultiImage();
//       if (images != null && images.isNotEmpty) {
//         if (kIsWeb) {
//           List<Uint8List> imageBytes = [];
//           for (XFile image in images) {
//             final bytes = await image.readAsBytes();
//             imageBytes.add(bytes);
//           }
//           setState(() {
//             _backgroundImageBytes = imageBytes;
//             _backgroundImageFiles.clear();
//           });
//         } else {
//           setState(() {
//             _backgroundImageFiles = images.map((xFile) => File(xFile.path)).toList();
//             _backgroundImageBytes.clear();
//           });
//         }
//       }
//     } catch (e) {
//       _showErrorDialog('Error selecting background images: $e');
//     }
//   }

//   Future<void> _generateCompositeImages() async {
//     bool hasForeground = kIsWeb ? _foregroundImageBytes != null : _foregroundImageFile != null;
//     bool hasBackgrounds = kIsWeb ? _backgroundImageBytes.isNotEmpty : _backgroundImageFiles.isNotEmpty;
    
//     if (!hasForeground || !hasBackgrounds) {
//       _showErrorDialog('Please select both foreground and background images');
//       return;
//     }

//     setState(() {
//       _isProcessing = true;
//       _generatedCount = 0;
//     });

//     try {
//       // Load foreground image
//       Uint8List foregroundBytes;
//       if (kIsWeb) {
//         foregroundBytes = _foregroundImageBytes!;
//       } else {
//         foregroundBytes = await _foregroundImageFile!.readAsBytes();
//       }
//       final foregroundImage = await _loadImage(foregroundBytes);

//       // Get background images
//       List<Uint8List> backgroundBytesList;
//       if (kIsWeb) {
//         backgroundBytesList = _backgroundImageBytes;
//       } else {
//         backgroundBytesList = [];
//         for (File file in _backgroundImageFiles) {
//           backgroundBytesList.add(await file.readAsBytes());
//         }
//       }

//       // Process each background image
//       for (int i = 0; i < backgroundBytesList.length; i++) {
//         final backgroundImage = await _loadImage(backgroundBytesList[i]);

//         // Create composite image with upscaling
//         final compositeBytes = await _createCompositeImage(
//           backgroundImage,
//           foregroundImage,
//         );

//         // Save composite image
//         final fileName = 'composite_1080p_${DateTime.now().millisecondsSinceEpoch}_$i.png';
        
//         if (kIsWeb) {
//           _downloadImageWeb(compositeBytes, fileName);
//         } else {
//           await _saveImageMobile(compositeBytes, fileName);
//         }

//         setState(() {
//           _generatedCount++;
//         });
//       }

//       setState(() {
//         _isProcessing = false;
//       });

//       _showSuccessDialog('Generated $_generatedCount images successfully at 1080p resolution!');
//     } catch (e) {
//       setState(() {
//         _isProcessing = false;
//       });
//       _showErrorDialog('Error generating images: $e');
//     }
//   }

//   Future<ui.Image> _loadImage(Uint8List bytes) async {
//     final Completer<ui.Image> completer = Completer();
//     ui.decodeImageFromList(bytes, (ui.Image img) {
//       return completer.complete(img);
//     });
//     return completer.future;
//   }

//   Future<Uint8List> _createCompositeImage(ui.Image background, ui.Image foreground) async {
//     final recorder = ui.PictureRecorder();
//     final canvas = Canvas(recorder);
    
//     // Always output at 1080x1080 for consistency
//     const double outputWidth = OUTPUT_WIDTH;
//     const double outputHeight = OUTPUT_HEIGHT;
    
//     // Draw background - stretch to fill entire 1080x1080 canvas
//     final bgRect = Rect.fromLTWH(0, 0, outputWidth, outputHeight);
//     canvas.drawImageRect(
//       background,
//       Rect.fromLTWH(0, 0, background.width.toDouble(), background.height.toDouble()),
//       bgRect,
//       Paint(),
//     );
    
//     // Calculate foreground size and position
//     double fgWidth = foreground.width.toDouble();
//     double fgHeight = foreground.height.toDouble();
    
//     // Calculate scale to maintain aspect ratio while fitting within 80% of output size
//     final maxFgWidth = outputWidth * 0.8;
//     final maxFgHeight = outputHeight * 0.8;
    
//     double scale = 1.0;
//     if (fgWidth > maxFgWidth || fgHeight > maxFgHeight) {
//       final scaleX = maxFgWidth / fgWidth;
//       final scaleY = maxFgHeight / fgHeight;
//       scale = scaleX < scaleY ? scaleX : scaleY;
//     } else {
//       // Upscale small images to utilize more space
//       final scaleX = maxFgWidth / fgWidth;
//       final scaleY = maxFgHeight / fgHeight;
//       scale = scaleX < scaleY ? scaleX : scaleY;
//       // Limit upscaling to avoid too much quality loss
//       scale = scale > 3.0 ? 3.0 : scale;
//     }
    
//     fgWidth *= scale;
//     fgHeight *= scale;
    
//     // Center the foreground image
//     final fgX = (outputWidth - fgWidth) / 2;
//     final fgY = (outputHeight - fgHeight) / 2;
    
//     // Draw foreground with high quality scaling
//     final fgRect = Rect.fromLTWH(fgX, fgY, fgWidth, fgHeight);
//     final paint = Paint()
//       ..filterQuality = FilterQuality.high; // High quality scaling
      
//     canvas.drawImageRect(
//       foreground,
//       Rect.fromLTWH(0, 0, foreground.width.toDouble(), foreground.height.toDouble()),
//       fgRect,
//       paint,
//     );
    
//     final picture = recorder.endRecording();
//     final img = await picture.toImage(outputWidth.toInt(), outputHeight.toInt());
//     final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
//     return byteData!.buffer.asUint8List();
//   }

//   void _downloadImageWeb(Uint8List bytes, String fileName) {
//     final blob = html.Blob([bytes]);
//     final url = html.Url.createObjectUrlFromBlob(blob);
//     final anchor = html.AnchorElement(href: url)
//       ..setAttribute('download', fileName)
//       ..click();
//     html.Url.revokeObjectUrl(url);
//   }

//   Future<void> _saveImageMobile(Uint8List bytes, String fileName) async {
//     try {
//       // For Android, save to Downloads/generated_images
//       final directory = Directory('/storage/emulated/0/Download/generated_images');
//       if (!await directory.exists()) {
//         await directory.create(recursive: true);
//       }
      
//       final file = File('${directory.path}/$fileName');
//       await file.writeAsBytes(bytes);
//     } catch (e) {
//       // Fallback: save to app documents directory
//       final directory = await getApplicationDocumentsDirectory();
//       final generatedDir = Directory('${directory.path}/generated_images');
//       if (!await generatedDir.exists()) {
//         await generatedDir.create(recursive: true);
//       }
      
//       final file = File('${generatedDir.path}/$fileName');
//       await file.writeAsBytes(bytes);
//     }
//   }

//   void _showErrorDialog(String message) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text('Error'),
//         content: Text(message),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: Text('OK'),
//           ),
//         ],
//       ),
//     );
//   }

//   void _showSuccessDialog(String message) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text('Success'),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(Icons.check_circle, color: Colors.green, size: 48),
//             SizedBox(height: 12),
//             Text(message, textAlign: TextAlign.center),
//             SizedBox(height: 8),
//             if (kIsWeb) 
//               Text('Images downloaded to your browser\'s download folder at 1080x1080 resolution.', 
//                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//                    textAlign: TextAlign.center,)
//             else
//               Text('Images saved to Download/generated_images/ at 1080x1080 resolution.', 
//                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//                    textAlign: TextAlign.center,),
//           ],
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: Text('OK'),
//           ),
//         ],
//       ),
//     );
//   }

//   void _clearSelection() {
//     setState(() {
//       _foregroundImageFile = null;
//       _foregroundImageBytes = null;
//       _backgroundImageFiles.clear();
//       _backgroundImageBytes.clear();
//       _generatedCount = 0;
//     });
//   }

//   Widget _buildImageDisplay(dynamic image, {double height = 200}) {
//     if (kIsWeb && image is Uint8List) {
//       return Image.memory(image, fit: BoxFit.cover, height: height, width: double.infinity);
//     } else if (!kIsWeb && image is File) {
//       return Image.file(image, fit: BoxFit.cover, height: height, width: double.infinity);
//     }
//     return Container(height: height);
//   }

//   bool get _hasForeground => kIsWeb ? _foregroundImageBytes != null : _foregroundImageFile != null;
//   bool get _hasBackgrounds => kIsWeb ? _backgroundImageBytes.isNotEmpty : _backgroundImageFiles.isNotEmpty;
//   int get _backgroundCount => kIsWeb ? _backgroundImageBytes.length : _backgroundImageFiles.length;

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Image Compositor - 1080p'),
//         backgroundColor: Colors.purple[600],
//         foregroundColor: Colors.white,
//         actions: [
//           IconButton(
//             icon: Icon(Icons.clear_all),
//             onPressed: _clearSelection,
//             tooltip: 'Clear All',
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // Platform and output info
//             Container(
//               padding: EdgeInsets.all(12),
//               decoration: BoxDecoration(
//                 color: Colors.purple[50],
//                 borderRadius: BorderRadius.circular(8),
//                 border: Border.all(color: Colors.purple[200]!),
//               ),
//               child: Column(
//                 children: [
//                   Row(
//                     children: [
//                       Icon(Icons.info_outline, color: Colors.purple[600], size: 20),
//                       SizedBox(width: 8),
//                       Text(
//                         'Platform: ${kIsWeb ? "Web" : "Mobile"}',
//                         style: TextStyle(fontSize: 14, color: Colors.purple[600], fontWeight: FontWeight.bold),
//                       ),
//                     ],
//                   ),
//                   SizedBox(height: 4),
//                   Text(
//                     '• Output: 1080x1080px with high-quality upscaling\n• One foreground + Multiple backgrounds = Multiple outputs',
//                     style: TextStyle(fontSize: 12, color: Colors.purple[600]),
//                   ),
//                 ],
//               ),
//             ),
//             SizedBox(height: 16),

//             // Foreground Image Section
//             Card(
//               elevation: 4,
//               child: Padding(
//                 padding: EdgeInsets.all(16.0),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(
//                       children: [
//                         Icon(Icons.person, color: Colors.blue[600]),
//                         SizedBox(width: 8),
//                         Text(
//                           'Foreground Image (Fixed)',
//                           style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                         ),
//                       ],
//                     ),
//                     SizedBox(height: 12),
//                     if (_hasForeground) ...[
//                       Container(
//                         height: 200,
//                         decoration: BoxDecoration(
//                           border: Border.all(color: Colors.blue[300]!, width: 2),
//                           borderRadius: BorderRadius.circular(8),
//                         ),
//                         child: ClipRRect(
//                           borderRadius: BorderRadius.circular(6),
//                           child: _buildImageDisplay(
//                             kIsWeb ? _foregroundImageBytes : _foregroundImageFile
//                           ),
//                         ),
//                       ),
//                       SizedBox(height: 12),
//                       Container(
//                         padding: EdgeInsets.all(8),
//                         decoration: BoxDecoration(
//                           color: Colors.blue[50],
//                           borderRadius: BorderRadius.circular(4),
//                         ),
//                         child: Text(
//                           'This image will be applied to all background images',
//                           style: TextStyle(fontSize: 12, color: Colors.blue[600]),
//                           textAlign: TextAlign.center,
//                         ),
//                       ),
//                       SizedBox(height: 12),
//                     ],
//                     ElevatedButton.icon(
//                       onPressed: _selectForegroundImage,
//                       icon: Icon(Icons.image),
//                       label: Text(_hasForeground 
//                           ? 'Change Foreground Image' 
//                           : 'Select Foreground Image'),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.blue[600],
//                         foregroundColor: Colors.white,
//                         minimumSize: Size(double.infinity, 48),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             SizedBox(height: 16),

//             // Background Images Section
//             Card(
//               elevation: 4,
//               child: Padding(
//                 padding: EdgeInsets.all(16.0),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(
//                       children: [
//                         Icon(Icons.landscape, color: Colors.green[600]),
//                         SizedBox(width: 8),
//                         Text(
//                           'Background Images (Multiple)',
//                           style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                         ),
//                       ],
//                     ),
//                     SizedBox(height: 12),
//                     if (_hasBackgrounds) ...[
//                       Container(
//                         height: 120,
//                         child: ListView.builder(
//                           scrollDirection: Axis.horizontal,
//                           itemCount: _backgroundCount,
//                           itemBuilder: (context, index) {
//                             return Container(
//                               width: 100,
//                               margin: EdgeInsets.only(right: 8),
//                               decoration: BoxDecoration(
//                                 border: Border.all(color: Colors.green[300]!, width: 2),
//                                 borderRadius: BorderRadius.circular(8),
//                               ),
//                               child: ClipRRect(
//                                 borderRadius: BorderRadius.circular(6),
//                                 child: _buildImageDisplay(
//                                   kIsWeb ? _backgroundImageBytes[index] : _backgroundImageFiles[index],
//                                   height: 120,
//                                 ),
//                               ),
//                             );
//                           },
//                         ),
//                       ),
//                       SizedBox(height: 12),
//                       Container(
//                         padding: EdgeInsets.all(8),
//                         decoration: BoxDecoration(
//                           color: Colors.green[50],
//                           borderRadius: BorderRadius.circular(4),
//                         ),
//                         child: Text(
//                           '$_backgroundCount background(s) selected → $_backgroundCount outputs will be generated',
//                           style: TextStyle(fontSize: 12, color: Colors.green[600]),
//                           textAlign: TextAlign.center,
//                         ),
//                       ),
//                       SizedBox(height: 12),
//                     ],
//                     ElevatedButton.icon(
//                       onPressed: _selectBackgroundImages,
//                       icon: Icon(Icons.photo_library),
//                       label: Text(_hasBackgrounds 
//                           ? 'Change Background Images ($_backgroundCount selected)' 
//                           : 'Select Background Images'),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.green[600],
//                         foregroundColor: Colors.white,
//                         minimumSize: Size(double.infinity, 48),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             SizedBox(height: 24),

//             // Generate Button
//             SizedBox(
//               height: 60,
//               child: ElevatedButton.icon(
//                 onPressed: _isProcessing ? null : _generateCompositeImages,
//                 icon: _isProcessing 
//                     ? SizedBox(
//                         width: 24,
//                         height: 24,
//                         child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
//                       )
//                     : Icon(Icons.auto_awesome, size: 28),
//                 label: Text(
//                   _isProcessing 
//                       ? 'Generating 1080p Images... ($_generatedCount/$_backgroundCount)' 
//                       : 'Generate $_backgroundCount Images at 1080p',
//                   style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//                 ),
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Colors.purple[600],
//                   foregroundColor: Colors.white,
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                 ),
//               ),
//             ),

//             // Generated Images Info
//             if (_generatedCount > 0) ...[
//               SizedBox(height: 24),
//               Card(
//                 elevation: 4,
//                 child: Padding(
//                   padding: EdgeInsets.all(16.0),
//                   child: Column(
//                     children: [
//                       Icon(Icons.check_circle, color: Colors.green, size: 48),
//                       SizedBox(height: 12),
//                       Text(
//                         'Generated Images',
//                         style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                       ),
//                       SizedBox(height: 8),
//                       Text(
//                         '$_generatedCount high-quality 1080p images generated!',
//                         style: TextStyle(color: Colors.green[600], fontSize: 16),
//                         textAlign: TextAlign.center,
//                       ),
//                       SizedBox(height: 4),
//                       Text(
//                         kIsWeb 
//                             ? 'Downloaded to your browser\'s download folder' 
//                             : 'Saved to: Download/generated_images/',
//                         style: TextStyle(color: Colors.grey[600], fontSize: 12),
//                         textAlign: TextAlign.center,
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }
// }
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'dart:io';
// import 'dart:typed_data';
// import 'dart:ui' as ui;
// import 'package:flutter/foundation.dart';
// import 'dart:html' as html;
// import 'package:path_provider/path_provider.dart';

// void main() {
//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Image Compositor',
//       theme: ThemeData(
//         primarySwatch: Colors.blue,
//         visualDensity: VisualDensity.adaptivePlatformDensity,
//       ),
//       home: ImageCompositorScreen(),
//     );
//   }
// }

// class ImageCompositorScreen extends StatefulWidget {
//   @override
//   _ImageCompositorScreenState createState() => _ImageCompositorScreenState();
// }

// class _ImageCompositorScreenState extends State<ImageCompositorScreen> {
//   final ImagePicker _picker = ImagePicker();
  
//   // For mobile
//   File? _backgroundImageFile;
//   List<File> _foregroundImageFiles = [];
  
//   // For web
//   Uint8List? _backgroundImageBytes;
//   List<Uint8List> _foregroundImageBytes = [];
  
//   bool _isProcessing = false;
//   int _generatedCount = 0;

//   Future<void> _selectBackgroundImage() async {
//     try {
//       final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
//       if (image != null) {
//         if (kIsWeb) {
//           final bytes = await image.readAsBytes();
//           setState(() {
//             _backgroundImageBytes = bytes;
//             _backgroundImageFile = null;
//           });
//         } else {
//           setState(() {
//             _backgroundImageFile = File(image.path);
//             _backgroundImageBytes = null;
//           });
//         }
//       }
//     } catch (e) {
//       _showErrorDialog('Error selecting background image: $e');
//     }
//   }

//   Future<void> _selectForegroundImages() async {
//     try {
//       final List<XFile>? images = await _picker.pickMultiImage();
//       if (images != null && images.isNotEmpty) {
//         if (kIsWeb) {
//           List<Uint8List> imageBytes = [];
//           for (XFile image in images) {
//             final bytes = await image.readAsBytes();
//             imageBytes.add(bytes);
//           }
//           setState(() {
//             _foregroundImageBytes = imageBytes;
//             _foregroundImageFiles.clear();
//           });
//         } else {
//           setState(() {
//             _foregroundImageFiles = images.map((xFile) => File(xFile.path)).toList();
//             _foregroundImageBytes.clear();
//           });
//         }
//       }
//     } catch (e) {
//       _showErrorDialog('Error selecting foreground images: $e');
//     }
//   }

//   Future<void> _generateCompositeImages() async {
//     bool hasBackground = kIsWeb ? _backgroundImageBytes != null : _backgroundImageFile != null;
//     bool hasForeground = kIsWeb ? _foregroundImageBytes.isNotEmpty : _foregroundImageFiles.isNotEmpty;
    
//     if (!hasBackground || !hasForeground) {
//       _showErrorDialog('Please select both background and foreground images');
//       return;
//     }

//     setState(() {
//       _isProcessing = true;
//       _generatedCount = 0;
//     });

//     try {
//       // Load background image
//       Uint8List backgroundBytes;
//       if (kIsWeb) {
//         backgroundBytes = _backgroundImageBytes!;
//       } else {
//         backgroundBytes = await _backgroundImageFile!.readAsBytes();
//       }
//       final backgroundImage = await _loadImage(backgroundBytes);

//       // Get foreground images
//       List<Uint8List> foregroundBytesList;
//       if (kIsWeb) {
//         foregroundBytesList = _foregroundImageBytes;
//       } else {
//         foregroundBytesList = [];
//         for (File file in _foregroundImageFiles) {
//           foregroundBytesList.add(await file.readAsBytes());
//         }
//       }

//       // Process each foreground image
//       for (int i = 0; i < foregroundBytesList.length; i++) {
//         final foregroundImage = await _loadImage(foregroundBytesList[i]);

//         // Create composite image
//         final compositeBytes = await _createCompositeImage(
//           backgroundImage,
//           foregroundImage,
//         );

//         // Save composite image
//         final fileName = 'composite_image_${DateTime.now().millisecondsSinceEpoch}_$i.png';
        
//         if (kIsWeb) {
//           _downloadImageWeb(compositeBytes, fileName);
//         } else {
//           await _saveImageMobile(compositeBytes, fileName);
//         }

//         setState(() {
//           _generatedCount++;
//         });
//       }

//       setState(() {
//         _isProcessing = false;
//       });

//       _showSuccessDialog('Generated $_generatedCount images successfully!');
//     } catch (e) {
//       setState(() {
//         _isProcessing = false;
//       });
//       _showErrorDialog('Error generating images: $e');
//     }
//   }

//   Future<ui.Image> _loadImage(Uint8List bytes) async {
//     final Completer<ui.Image> completer = Completer();
//     ui.decodeImageFromList(bytes, (ui.Image img) {
//       return completer.complete(img);
//     });
//     return completer.future;
//   }

//   Future<Uint8List> _createCompositeImage(ui.Image background, ui.Image foreground) async {
//     final recorder = ui.PictureRecorder();
//     final canvas = Canvas(recorder);
    
//     // Calculate dimensions to maintain aspect ratio
//     const double maxWidth = 1080.0;
//     const double maxHeight = 1080.0;
    
//     double bgWidth = background.width.toDouble();
//     double bgHeight = background.height.toDouble();
    
//     // Scale background to fit within max dimensions
//     if (bgWidth > maxWidth || bgHeight > maxHeight) {
//       final scale = (maxWidth / bgWidth).clamp(0.0, maxHeight / bgHeight);
//       bgWidth *= scale;
//       bgHeight *= scale;
//     }
    
//     // Draw background
//     final bgRect = Rect.fromLTWH(0, 0, bgWidth, bgHeight);
//     canvas.drawImageRect(
//       background,
//       Rect.fromLTWH(0, 0, background.width.toDouble(), background.height.toDouble()),
//       bgRect,
//       Paint(),
//     );
    
//     // Calculate foreground position (centered)
//     double fgWidth = foreground.width.toDouble();
//     double fgHeight = foreground.height.toDouble();
    
//     // Scale foreground to fit within 70% of background
//     final maxFgWidth = bgWidth * 0.7;
//     final maxFgHeight = bgHeight * 0.7;
    
//     if (fgWidth > maxFgWidth || fgHeight > maxFgHeight) {
//       final scale = (maxFgWidth / fgWidth).clamp(0.0, maxFgHeight / fgHeight);
//       fgWidth *= scale;
//       fgHeight *= scale;
//     }
    
//     final fgX = (bgWidth - fgWidth) / 2;
//     final fgY = (bgHeight - fgHeight) / 2;
    
//     // Draw foreground
//     final fgRect = Rect.fromLTWH(fgX, fgY, fgWidth, fgHeight);
//     canvas.drawImageRect(
//       foreground,
//       Rect.fromLTWH(0, 0, foreground.width.toDouble(), foreground.height.toDouble()),
//       fgRect,
//       Paint(),
//     );
    
//     final picture = recorder.endRecording();
//     final img = await picture.toImage(bgWidth.toInt(), bgHeight.toInt());
//     final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
//     return byteData!.buffer.asUint8List();
//   }

//   void _downloadImageWeb(Uint8List bytes, String fileName) {
//     final blob = html.Blob([bytes]);
//     final url = html.Url.createObjectUrlFromBlob(blob);
//     final anchor = html.AnchorElement(href: url)
//       ..setAttribute('download', fileName)
//       ..click();
//     html.Url.revokeObjectUrl(url);
//   }

//   Future<void> _saveImageMobile(Uint8List bytes, String fileName) async {
//     try {
//       // For Android, we'll save to the app's documents directory
//       // You can modify this to save to Downloads folder if you add proper permissions
//       final directory = Directory('/storage/emulated/0/Download/generated_images');
//       if (!await directory.exists()) {
//         await directory.create(recursive: true);
//       }
      
//       final file = File('${directory.path}/$fileName');
//       await file.writeAsBytes(bytes);
//     } catch (e) {
//       // Fallback: save to app documents directory
//       final directory = await getApplicationDocumentsDirectory();
//       final generatedDir = Directory('${directory.path}/generated_images');
//       if (!await generatedDir.exists()) {
//         await generatedDir.create(recursive: true);
//       }
      
//       final file = File('${generatedDir.path}/$fileName');
//       await file.writeAsBytes(bytes);
//     }
//   }

//   void _showErrorDialog(String message) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text('Error'),
//         content: Text(message),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: Text('OK'),
//           ),
//         ],
//       ),
//     );
//   }

//   void _showSuccessDialog(String message) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text('Success'),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Text(message),
//             if (kIsWeb) 
//               Text('\nImages downloaded to your browser\'s download folder.', 
//                    style: TextStyle(fontSize: 12, color: Colors.grey[600]))
//             else
//               Text('\nImages saved to Download/generated_images/', 
//                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
//           ],
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: Text('OK'),
//           ),
//         ],
//       ),
//     );
//   }

//   void _clearSelection() {
//     setState(() {
//       _backgroundImageFile = null;
//       _backgroundImageBytes = null;
//       _foregroundImageFiles.clear();
//       _foregroundImageBytes.clear();
//       _generatedCount = 0;
//     });
//   }

//   Widget _buildImageDisplay(dynamic image) {
//     if (kIsWeb && image is Uint8List) {
//       return Image.memory(image, fit: BoxFit.cover);
//     } else if (!kIsWeb && image is File) {
//       return Image.file(image, fit: BoxFit.cover);
//     }
//     return Container();
//   }

//   bool get _hasBackground => kIsWeb ? _backgroundImageBytes != null : _backgroundImageFile != null;
//   bool get _hasForeground => kIsWeb ? _foregroundImageBytes.isNotEmpty : _foregroundImageFiles.isNotEmpty;
//   int get _foregroundCount => kIsWeb ? _foregroundImageBytes.length : _foregroundImageFiles.length;

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Image Compositor'),
//         backgroundColor: Colors.blue[600],
//         foregroundColor: Colors.white,
//         actions: [
//           IconButton(
//             icon: Icon(Icons.clear_all),
//             onPressed: _clearSelection,
//             tooltip: 'Clear All',
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // Platform indicator
//             Container(
//               padding: EdgeInsets.all(8),
//               decoration: BoxDecoration(
//                 color: Colors.blue[50],
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: Text(
//                 'Platform: ${kIsWeb ? "Web" : "Mobile"} ${kIsWeb ? "(Downloads to browser)" : "(Saves to device)"}',
//                 style: TextStyle(fontSize: 12, color: Colors.blue[600]),
//                 textAlign: TextAlign.center,
//               ),
//             ),
//             SizedBox(height: 16),

//             // Background Image Section
//             Card(
//               elevation: 4,
//               child: Padding(
//                 padding: EdgeInsets.all(16.0),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Background Image',
//                       style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                     ),
//                     SizedBox(height: 12),
//                     if (_hasBackground) ...[
//                       Container(
//                         height: 200,
//                         decoration: BoxDecoration(
//                           border: Border.all(color: Colors.grey[300]!),
//                           borderRadius: BorderRadius.circular(8),
//                         ),
//                         child: ClipRRect(
//                           borderRadius: BorderRadius.circular(8),
//                           child: _buildImageDisplay(
//                             kIsWeb ? _backgroundImageBytes : _backgroundImageFile
//                           ),
//                         ),
//                       ),
//                       SizedBox(height: 12),
//                     ],
//                     ElevatedButton.icon(
//                       onPressed: _selectBackgroundImage,
//                       icon: Icon(Icons.image),
//                       label: Text(_hasBackground 
//                           ? 'Change Background' 
//                           : 'Select Background Image'),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.blue[600],
//                         foregroundColor: Colors.white,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             SizedBox(height: 16),

//             // Foreground Images Section
//             Card(
//               elevation: 4,
//               child: Padding(
//                 padding: EdgeInsets.all(16.0),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Foreground Images',
//                       style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                     ),
//                     SizedBox(height: 12),
//                     if (_hasForeground) ...[
//                       Container(
//                         height: 120,
//                         child: ListView.builder(
//                           scrollDirection: Axis.horizontal,
//                           itemCount: _foregroundCount,
//                           itemBuilder: (context, index) {
//                             return Container(
//                               width: 100,
//                               margin: EdgeInsets.only(right: 8),
//                               decoration: BoxDecoration(
//                                 border: Border.all(color: Colors.grey[300]!),
//                                 borderRadius: BorderRadius.circular(8),
//                               ),
//                               child: ClipRRect(
//                                 borderRadius: BorderRadius.circular(8),
//                                 child: _buildImageDisplay(
//                                   kIsWeb ? _foregroundImageBytes[index] : _foregroundImageFiles[index]
//                                 ),
//                               ),
//                             );
//                           },
//                         ),
//                       ),
//                       SizedBox(height: 12),
//                       Text(
//                         '$_foregroundCount image(s) selected',
//                         style: TextStyle(color: Colors.grey[600]),
//                       ),
//                       SizedBox(height: 12),
//                     ],
//                     ElevatedButton.icon(
//                       onPressed: _selectForegroundImages,
//                       icon: Icon(Icons.photo_library),
//                       label: Text(_hasForeground 
//                           ? 'Change Foreground Images' 
//                           : 'Select Foreground Images'),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.green[600],
//                         foregroundColor: Colors.white,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             SizedBox(height: 24),

//             // Generate Button
//             SizedBox(
//               height: 50,
//               child: ElevatedButton.icon(
//                 onPressed: _isProcessing ? null : _generateCompositeImages,
//                 icon: _isProcessing 
//                     ? SizedBox(
//                         width: 20,
//                         height: 20,
//                         child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
//                       )
//                     : Icon(Icons.auto_awesome),
//                 label: Text(_isProcessing 
//                     ? 'Generating Images... ($_generatedCount/$_foregroundCount)' 
//                     : 'Generate Composite Images'),
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Colors.purple[600],
//                   foregroundColor: Colors.white,
//                   textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//                 ),
//               ),
//             ),

//             // Generated Images Info
//             if (_generatedCount > 0) ...[
//               SizedBox(height: 24),
//               Card(
//                 elevation: 4,
//                 child: Padding(
//                   padding: EdgeInsets.all(16.0),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         'Generated Images',
//                         style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                       ),
//                       SizedBox(height: 8),
//                       Text(
//                         '$_generatedCount images generated successfully!',
//                         style: TextStyle(color: Colors.green[600]),
//                       ),
//                       Text(
//                         kIsWeb 
//                             ? 'Downloaded to your browser\'s download folder' 
//                             : 'Saved to: Download/generated_images/',
//                         style: TextStyle(color: Colors.grey[600], fontSize: 12),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }
// }