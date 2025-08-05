import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/network_service.dart';
import '../screens/home.dart';
import '../screens/result.dart';
import 'dart:async';

class PWAOptimizedScanScreen extends StatefulWidget {
  final String selectedStore;
  const PWAOptimizedScanScreen({super.key, required this.selectedStore});

  @override
  State<PWAOptimizedScanScreen> createState() => _PWAOptimizedScanScreenState();
}

class _PWAOptimizedScanScreenState extends State<PWAOptimizedScanScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  
  // Optimized controller configuration for PWA
  late MobileScannerController controller;
  
  // State management
  bool isScanning = false;
  bool torchOn = false;
  bool _showSuccess = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool isControllerInitialized = false;
  
  // Manual input support for PWA
  final TextEditingController _manualBarcodeController = TextEditingController();
  
  // Animation controllers
  late final AnimationController _borderAnimationController;
  late final Animation<double> _borderAnimation;
  late final Animation<Color?> _scanLineColorAnimation;
  
  // Debounce timer for scan detection
  Timer? _debounceTimer;
  String? _lastScannedCode;
  DateTime? _lastScanTime;
  
  // PWA-specific optimizations
  static const _webScanAreaFactor = 0.35; // Smaller scan area for web
  static const _mobileScanAreaFactor = 0.75; // Standard for mobile
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize optimized controller for PWA
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal, // Better for PWA performance
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8, 
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.codebar,
        BarcodeFormat.itf,
      ],
      detectionTimeoutMs: kIsWeb ? 250 : 500, // Faster detection on web
      returnImage: false, // Disable image return for better performance
    );
    
    // Setup animations
    _borderAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _borderAnimation = Tween<double>(
      begin: 2,
      end: 5,
    ).animate(CurvedAnimation(
      parent: _borderAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _scanLineColorAnimation = ColorTween(
      begin: Colors.blueAccent.withOpacity(0.6),
      end: Colors.blueAccent,
    ).animate(CurvedAnimation(
      parent: _borderAnimationController,
      curve: Curves.easeInOut,
    ));
    
    // Initialize camera with permission check
    _startScanning();
  }
  
  Future<void> _checkCameraPermission() async {
    try {
      // Start the controller directly - it will handle permissions internally
      await controller.start();
      
      setState(() {
        isControllerInitialized = true;
      });
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('permission')) {
          _showPermissionDialog();
        } else {
          setState(() {
            _hasError = true;
            _errorMessage = 'Failed to start camera: ${e.toString()}';
          });
        }
      }
    }
  }
  
  void _startScanning() async {
    // This method is now merged with _checkCameraPermission
    _checkCameraPermission();
  }
  
  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Доступ до камери'),
          content: const Text(
            'Для сканування штрих-кодів потрібен доступ до камери. '
            'Будь ласка, надайте дозвіл у налаштуваннях браузера.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to home
              },
              child: const Text('Скасувати'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startScanning(); // Try again
              },
              child: const Text('Спробувати знову'),
            ),
          ],
        );
      },
    );
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Optimize camera lifecycle for PWA
    if (isControllerInitialized) {
      switch (state) {
        case AppLifecycleState.resumed:
          controller.start();
          break;
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
        case AppLifecycleState.hidden:
          controller.stop();
          break;
      }
    }
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _borderAnimationController.dispose();
    _manualBarcodeController.dispose();
    controller.dispose();
    super.dispose();
  }
  
  void toggleTorch() {
    try {
      controller.toggleTorch();
      setState(() {
        torchOn = !torchOn;
      });
    } catch (e) {
      // Torch not available on this device
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Torch not available on this device'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  Future<void> _handleBarcode(String code) async {
    // Debounce logic to prevent duplicate scans
    final now = DateTime.now();
    if (_lastScannedCode == code && 
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 500) {
      return;
    }
    
    if (isScanning) return;
    
    _lastScannedCode = code;
    _lastScanTime = now;
    
    setState(() {
      isScanning = true;
      _hasError = false;
      _showSuccess = false;
    });
    
    // Haptic feedback for web (if supported)
    if (kIsWeb) {
      _triggerWebVibration();
    }
    
    // Network check
    final networkService = NetworkService();
    final isConnected = await networkService.isConnected();
    
    if (!mounted) return;
    
    if (!isConnected) {
      setState(() {
        _errorMessage = "Помилка інтернет з'єднання";
        _hasError = true;
      });
      
      _resetScanningState();
      return;
    }
    
    // Validate barcode format
    if (!_isValidBarcode(code)) {
      setState(() {
        _errorMessage = "Невірний формат штрихкоду";
        _hasError = true;
      });
      
      _resetScanningState();
      return;
    }
    
    // Success animation
    setState(() {
      _showSuccess = true;
    });
    
    // Shorter delay for PWA
    await Future.delayed(const Duration(milliseconds: 800));
    
    if (!mounted) return;
    
    // Navigate to results
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          barcode: code,
          selectedStore: widget.selectedStore,
          errorMessage: null,
        ),
      ),
    );
  }
  
  bool _isValidBarcode(String code) {
    // Enhanced validation for common barcode formats
    if (code.isEmpty) return false;
    
    // Check if it starts with expected prefix (customize as needed)
    if (code.startsWith('210700')) return true;
    
    // Check for valid EAN-13 (13 digits)
    if (RegExp(r'^\d{13}$').hasMatch(code)) return true;
    
    // Check for valid EAN-8 (8 digits)
    if (RegExp(r'^\d{8}$').hasMatch(code)) return true;
    
    // Check for valid UPC-A (12 digits)
    if (RegExp(r'^\d{12}$').hasMatch(code)) return true;
    
    // Allow other formats for flexibility
    return code.length >= 6 && code.length <= 20;
  }
  
  void _resetScanningState() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _hasError = false;
          isScanning = false;
        });
      }
    });
  }
  
  void _triggerWebVibration() {
    // Web Vibration API (if supported)
    if (kIsWeb) {
      // This would need JavaScript interop in production
      // For now, we'll just show visual feedback
    }
  }
  
  void _showManualInputDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Введіть штрихкод'),
          content: TextField(
            controller: _manualBarcodeController,
            decoration: const InputDecoration(
              hintText: 'Введіть код вручну',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            autofocus: true,
            onSubmitted: (value) {
              Navigator.of(context).pop();
              if (value.isNotEmpty) {
                _handleBarcode(value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                _manualBarcodeController.clear();
                Navigator.of(context).pop();
              },
              child: const Text('Скасувати'),
            ),
            TextButton(
              onPressed: () {
                final code = _manualBarcodeController.text;
                _manualBarcodeController.clear();
                Navigator.of(context).pop();
                if (code.isNotEmpty) {
                  _handleBarcode(code);
                }
              },
              child: const Text('Сканувати'),
            ),
          ],
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final double scanAreaSize = kIsWeb
        ? screenSize.width * _webScanAreaFactor // Smaller scan area for web
        : screenSize.width * _mobileScanAreaFactor;
    
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Сканер штрихкодів',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          actions: [
            // Manual input button (important for PWA)
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: 'Ввести вручну',
              onPressed: _showManualInputDialog,
            ),
            // Torch toggle (if available)
            if (isControllerInitialized)
              IconButton(
                icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
                tooltip: torchOn ? 'Вимкнути ліхтарик' : 'Увімкнути ліхтарик',
                onPressed: toggleTorch,
              ),
            // Close button
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              ),
              tooltip: 'Закрити',
            ),
          ],
        ),
        body: Stack(
          children: [
            // Camera preview
            if (isControllerInitialized)
              MobileScanner(
                controller: controller,
                onDetect: (capture) async {
                  if (capture.barcodes.isNotEmpty) {
                    final barcode = capture.barcodes.first;
                    if (barcode.rawValue != null) {
                      await _handleBarcode(barcode.rawValue!);
                    }
                  }
                },
                errorBuilder: (context, error) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Camera Error',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.errorDetails?.message ?? 'Failed to start camera',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () {
                                  controller.start();
                                },
                                child: const Text('Retry'),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: _showManualInputDialog,
                                child: const Text('Manual Input'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            
            if (!isControllerInitialized && !_hasError)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.blueAccent,
                ),
              ),
            
            // Scan area overlay
            if (isControllerInitialized)
              CustomPaint(
                painter: ScanOverlayPainter(
                  scanAreaSize: scanAreaSize,
                  borderColor: _hasError ? Colors.redAccent : Colors.blueAccent,
                  borderWidth: _borderAnimation.value,
                ),
                child: Container(),
              ),
            
            // Animated scan line (PWA enhancement)
            if (isControllerInitialized && !_hasError && !_showSuccess)
              AnimatedBuilder(
                animation: _borderAnimationController,
                builder: (context, child) {
                  return Positioned(
                    top: (screenSize.height - scanAreaSize) / 2,
                    left: (screenSize.width - scanAreaSize) / 2,
                    child: Container(
                      width: scanAreaSize,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: const RadialGradient(
                          colors: [
                            Color(0x4D2196F3),
                            Color(0x002196F3),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _scanLineColorAnimation.value!.withAlpha(128),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            
            // Instructions
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  kIsWeb
                      ? 'Розмістіть штрихкод у рамці або введіть вручну'
                      : 'Наведіть камеру на штрихкод',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            
            // Success overlay
            if (_showSuccess)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _showSuccess ? 1.0 : 0.0,
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(128),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.greenAccent, width: 3),
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.greenAccent,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Успішно скановано!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            // Error message
            if (_hasError)
              Positioned(
                bottom: 100,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(230),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withAlpha(76),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // PWA-specific features hint
            if (kIsWeb && isControllerInitialized)
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, color: Colors.white70, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Підказка: Використовуйте хороше освітлення',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Custom painter for scan overlay
class ScanOverlayPainter extends CustomPainter {
  final double scanAreaSize;
  final Color borderColor;
  final double borderWidth;
  
  ScanOverlayPainter({
    required this.scanAreaSize,
    required this.borderColor,
    required this.borderWidth,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth + 2
      ..strokeCap = StrokeCap.round;
    
    // Calculate scan area position
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );
    
    // Draw overlay
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(overlayPath, paint);
    
    // Draw border
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(16)),
      borderPaint,
    );
    
    // Draw corner accents
    const cornerLength = 30.0;
    
    // Top-left corner
    canvas.drawLine(
      Offset(scanRect.left, scanRect.top + cornerLength),
      Offset(scanRect.left, scanRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanRect.left, scanRect.top),
      Offset(scanRect.left + cornerLength, scanRect.top),
      cornerPaint,
    );
    
    // Top-right corner
    canvas.drawLine(
      Offset(scanRect.right - cornerLength, scanRect.top),
      Offset(scanRect.right, scanRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanRect.right, scanRect.top),
      Offset(scanRect.right, scanRect.top + cornerLength),
      cornerPaint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      Offset(scanRect.left, scanRect.bottom - cornerLength),
      Offset(scanRect.left, scanRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanRect.left, scanRect.bottom),
      Offset(scanRect.left + cornerLength, scanRect.bottom),
      cornerPaint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      Offset(scanRect.right - cornerLength, scanRect.bottom),
      Offset(scanRect.right, scanRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanRect.right, scanRect.bottom),
      Offset(scanRect.right, scanRect.bottom - cornerLength),
      cornerPaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
