import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/web_barcode_scanner_v2.dart'
    if (dart.library.html) '../services/web_barcode_scanner_v2.dart'
    if (dart.library.io) '../services/web_barcode_scanner_stub.dart';


// ===== QR Overlay Painter =====
class QrScannerOverlayPainter extends CustomPainter {
  final Color borderColor;
  final double borderRadius;
  final double borderLength;
  final double borderWidth;
  final double cutOutSize;

  QrScannerOverlayPainter({
    required this.borderColor,
    this.borderRadius = 0,
    this.borderLength = 30,
    this.borderWidth = 10,
    this.cutOutSize = 300,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;

    final double left = (size.width - cutOutSize) / 2;
    final double top = (size.height - cutOutSize) / 2;
    final double right = left + cutOutSize;
    final double bottom = top + cutOutSize;
    final r = borderRadius;
    final l = borderLength;

    // Top left
    canvas.drawLine(
      Offset(left, top + r),
      Offset(left, top + l),
      paint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left + l, top),
      paint,
    );

    // Top right
    canvas.drawLine(
      Offset(right, top + r),
      Offset(right, top + l),
      paint,
    );
    canvas.drawLine(
      Offset(right - l, top),
      Offset(right, top),
      paint,
    );

    // Bottom left
    canvas.drawLine(
      Offset(left, bottom - r),
      Offset(left, bottom - l),
      paint,
    );
    canvas.drawLine(
      Offset(left, bottom),
      Offset(left + l, bottom),
      paint,
    );

    // Bottom right
    canvas.drawLine(
      Offset(right, bottom - r),
      Offset(right, bottom - l),
      paint,
    );
    canvas.drawLine(
      Offset(right - l, bottom),
      Offset(right, bottom),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
// ===== END QR Overlay Painter =====

class PlatformBarcodeScanner extends StatefulWidget {
  final Function(String) onBarcodeDetected;
  final bool torchEnabled;
  final Function(bool)? onTorchToggle;
  
  const PlatformBarcodeScanner({
    super.key,
    required this.onBarcodeDetected,
    this.torchEnabled = false,
    this.onTorchToggle,
  });

  @override
  State<PlatformBarcodeScanner> createState() => _PlatformBarcodeScannerState();
}

class _PlatformBarcodeScannerState extends State<PlatformBarcodeScanner> {
  // Mobile scanner controller
  MobileScannerController? _mobileController;
  
  // Web scanner stream
  Stream<String>? _webScannerStream;
  
  bool _isInitialized = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;
  
  @override
  void initState() {
    super.initState();
    _initializeScanner();
  }
  
  Future<void> _initializeScanner() async {
    if (kIsWeb) {
      await _initializeWebScanner();
    } else {
      _initializeMobileScanner();
    }
  }
  
  Future<void> _initializeWebScanner() async {
    try {
      await WebBarcodeScannerV2.initializeLibrary();
      _webScannerStream = await WebBarcodeScannerV2.startScanning(
        context: context,
        preferBackCamera: true,
      );
      
      if (!mounted) return;
      
      _webScannerStream!.listen((barcode) {
        _handleBarcodeDetected(barcode);
      });
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Web scanner initialization failed: $e');
      }
    }
  }
  
  void _initializeMobileScanner() {
    _mobileController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: widget.torchEnabled,
    );
    
    setState(() {
      _isInitialized = true;
    });
  }
  
  void _handleBarcodeDetected(String barcode) {
    final now = DateTime.now();
    
    // Prevent duplicate scans within 2 seconds
    if (_lastScannedCode == barcode && 
        _lastScanTime != null && 
        now.difference(_lastScanTime!).inSeconds < 2) {
      return;
    }
    
    _lastScannedCode = barcode;
    _lastScanTime = now;
    
    widget.onBarcodeDetected(barcode);
  }
  
  Future<void> _toggleTorch() async {
    if (kIsWeb) {
      // Torch not supported in web version
      return;
    } else {
      await _mobileController?.toggleTorch();
    }
    widget.onTorchToggle?.call(!widget.torchEnabled);
  }
  
  @override
  void dispose() {
    if (kIsWeb) {
      WebBarcodeScannerV2.stopScanning();
    } else {
      _mobileController?.dispose();
    }
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Ініціалізація камери...'),
          ],
        ),
      );
    }
    
    return Stack(
      children: [
        // Scanner view
        if (kIsWeb) _buildWebScanner() else _buildMobileScanner(),
        
        // Overlay with scanning frame
        _buildScanningOverlay(),
        
        // Torch button
        Positioned(
          top: 50,
          right: 20,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Colors.black54,
            onPressed: _toggleTorch,
            child: Icon(
              widget.torchEnabled ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
          ),
        ),
        
        // Manual input button
        Positioned(
          bottom: 100,
          left: 20,
          right: 20,
          child: ElevatedButton.icon(
            onPressed: _showManualInputDialog,
            icon: const Icon(Icons.keyboard),
            label: const Text('Ввести вручну'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildWebScanner() {
    // Для веб-версії html5-qrcode створює свій власний UI
    // Тому просто показуємо чорний фон
    return SizedBox.expand(
      child: Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt, color: Colors.white70, size: 48),
              SizedBox(height: 16),
              Text(
                'Камера активна\nНаведіть на штрих-код',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildMobileScanner() {
    if (_mobileController == null) {
      return const SizedBox.expand(
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_off, color: Colors.white, size: 48),
                SizedBox(height: 16),
                Text(
                  'Контролер камери не ініціалізовано',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: MobileScanner(
        controller: _mobileController!,
        errorBuilder: (context, error) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Помилка камери:\n${error.errorDetails?.message ?? error.toString()}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Перезапуск камери
                      _mobileController?.dispose();
                      _initializeMobileScanner();
                    },
                    child: const Text('Повторити'),
                  ),
                ],
              ),
            ),
          );
        },
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            _handleBarcodeDetected(barcodes.first.rawValue!);
          }
        },
      ),
    );
  }
  
  Widget _buildScanningOverlay() {
  // Тільки рамка, без затемнення
  return IgnorePointer(
    ignoring: true,
    child: CustomPaint(
      size: Size.infinite,
      painter: QrScannerOverlayPainter(
        borderColor: Colors.blue,
        borderRadius: 10,
        borderLength: 30,
        borderWidth: 10,
        cutOutSize: 300,
      ),
    ),
  );
}



  void _showManualInputDialog() {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Введіть штрих-код'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '2107001234567',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Скасувати'),
          ),
          ElevatedButton(
            onPressed: () {
              final barcode = controller.text.trim();
              if (barcode.isNotEmpty) {
                Navigator.pop(context);
                _handleBarcodeDetected(barcode);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// Custom overlay shape for scanning frame
class QrScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QrScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 3.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path getLeftTopPath(Rect rect) {
      return Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, rect.top + borderRadius)
        ..quadraticBezierTo(rect.left, rect.top, rect.left + borderRadius, rect.top)
        ..lineTo(rect.right, rect.top);
    }

    return getLeftTopPath(rect)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final borderWidthSize = width / 2;
    final height = rect.height;
    final borderOffset = borderWidth / 2;
    final mBorderLength = borderLength > min(cutOutSize / 2, 90) ? borderWidthSize / 2 : borderLength;
    final mCutOutSize = cutOutSize < min(width, height) ? cutOutSize : min(width, height) - 20;

    final backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final boxPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.dstOut;

    final cutOutRect = Rect.fromLTWH(
      rect.left + width / 2 - mCutOutSize / 2 + borderOffset,
      rect.top + height / 2 - mCutOutSize / 2 + borderOffset,
      mCutOutSize - borderOffset * 2,
      mCutOutSize - borderOffset * 2,
    );

    canvas
      ..saveLayer(rect, backgroundPaint)
      ..drawRect(rect, backgroundPaint)
      ..drawRRect(RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)), boxPaint)
      ..restore();

    // Draw corner borders
    final path = Path()
      // Top left
      ..moveTo(cutOutRect.left - borderOffset, cutOutRect.top + mBorderLength)
      ..lineTo(cutOutRect.left - borderOffset, cutOutRect.top + borderRadius)
      ..quadraticBezierTo(cutOutRect.left - borderOffset, cutOutRect.top - borderOffset,
          cutOutRect.left + borderRadius, cutOutRect.top - borderOffset)
      ..lineTo(cutOutRect.left + mBorderLength, cutOutRect.top - borderOffset)
      // Top right
      ..moveTo(cutOutRect.right - mBorderLength, cutOutRect.top - borderOffset)
      ..lineTo(cutOutRect.right - borderRadius, cutOutRect.top - borderOffset)
      ..quadraticBezierTo(cutOutRect.right + borderOffset, cutOutRect.top - borderOffset,
          cutOutRect.right + borderOffset, cutOutRect.top + borderRadius)
      ..lineTo(cutOutRect.right + borderOffset, cutOutRect.top + mBorderLength)
      // Bottom right
      ..moveTo(cutOutRect.right + borderOffset, cutOutRect.bottom - mBorderLength)
      ..lineTo(cutOutRect.right + borderOffset, cutOutRect.bottom - borderRadius)
      ..quadraticBezierTo(cutOutRect.right + borderOffset, cutOutRect.bottom + borderOffset,
          cutOutRect.right - borderRadius, cutOutRect.bottom + borderOffset)
      ..lineTo(cutOutRect.right - mBorderLength, cutOutRect.bottom + borderOffset)
      // Bottom left
      ..moveTo(cutOutRect.left + mBorderLength, cutOutRect.bottom + borderOffset)
      ..lineTo(cutOutRect.left + borderRadius, cutOutRect.bottom + borderOffset)
      ..quadraticBezierTo(cutOutRect.left - borderOffset, cutOutRect.bottom + borderOffset,
          cutOutRect.left - borderOffset, cutOutRect.bottom - borderRadius)
      ..lineTo(cutOutRect.left - borderOffset, cutOutRect.bottom - mBorderLength);

    canvas.drawPath(path, borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth,
      overlayColor: overlayColor,
    );
  }

  double min(double a, double b) => a < b ? a : b;
}
