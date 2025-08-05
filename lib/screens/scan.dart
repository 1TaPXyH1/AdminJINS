import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/network_service.dart';
import '../screens/home.dart';
import '../screens/result.dart';

class ScanScreen extends StatefulWidget {
  final String selectedStore;
  const ScanScreen({super.key, required this.selectedStore});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: [BarcodeFormat.ean13, BarcodeFormat.upcA, BarcodeFormat.code128],
  );
  bool isScanning = false;
  bool torchOn = false;

  bool _showSuccess = false;
  bool _hasError = false;
  String _errorMessage = '';

  late final AnimationController _borderAnimationController;
  late final Animation<double> _borderAnimation;

  @override
  void initState() {
    super.initState();

    _borderAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _borderAnimation = Tween<double>(begin: 2, end: 5).animate(
      CurvedAnimation(
        parent: _borderAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _borderAnimationController.dispose();
    controller.dispose();
    super.dispose();
  }

  void toggleTorch() {
    controller.toggleTorch();
    setState(() {
      torchOn = !torchOn;
    });
  }

  Future<void> _handleBarcode(String code) async {
    if (isScanning) return;

    setState(() {
      isScanning = true;
      _hasError = false;
      _showSuccess = false;
    });

    
    final networkService = NetworkService();
    final isConnected = await networkService.isConnected();

    if (!mounted) return;

    if (!isConnected) {
      setState(() {
        _errorMessage = "Помилка інтернет з'єднання";
        _hasError = true;
      });
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _hasError = false;
        isScanning = false;
      });
      return;
    }

    if (!code.startsWith('210700')) {
      setState(() {
        _errorMessage = "Невірний штрихкод";
        _hasError = true;
      });
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _hasError = false;
        isScanning = false;
      });
      return;
    }

    setState(() {
      _showSuccess = true;
    });

    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

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

  @override
  Widget build(BuildContext context) {
    final double boxSize = kIsWeb
    ? MediaQuery.of(context).size.width * 0.4
    : MediaQuery.of(context).size.width * 0.8;

    return PopScope(
      canPop: false,
      child: Semantics(
        label: 'Екран сканування',
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: const Text('Сканер'),
            centerTitle: true,
            actions: [
              if (kIsWeb)
                IconButton(
                  icon: const Icon(Icons.keyboard),
                  tooltip: 'Ввести штрихкод вручну',
                  onPressed: () async {
                    final input = await showDialog<String>(
                      context: context,
                      builder: (ctx) {
                        final controller = TextEditingController();
                        return AlertDialog(
                          title: const Text('Введіть штрихкод'),
                          content: TextField(controller: controller),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
                            TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('OK')),
                          ],
                        );
                      },
                    );
                    if (input != null && input.isNotEmpty) {
                      await _handleBarcode(input);
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                ),
                tooltip: 'Закрити сканер',
              ),
            ],
          ),
          body: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(
                controller: controller,
                onDetect: (capture) async {
                  if (capture.barcodes.isEmpty) return;
                  await _handleBarcode(capture.barcodes.first.rawValue ?? '');
                },
                errorBuilder: (context, error) {
                  setState(() {
                    _hasError = true;
                    _errorMessage = 'Помилка камери: $error';
                  });
                  return const SizedBox.shrink();
                },
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: boxSize,
                        height: boxSize,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _borderAnimationController,
                builder: (context, child) {
                  return Center(
                    child: Container(
                      width: boxSize,
                      height: boxSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _hasError
                              ? Colors.redAccent
                              : Colors.blueAccent,
                          width: _borderAnimation.value,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_hasError
                                    ? Colors.redAccent
                                    : Colors.blueAccent)
                                .withAlpha(128), // ~0.5 opacity
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(204, 38, 50, 56), // blueGrey.shade900.withOpacity(0.8)
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'Наведіть камеру на штрихкод у рамці',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            blurRadius: 3,
                            color: Colors.black54,
                            offset: Offset(0, 1),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_showSuccess)
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _showSuccess ? 1.0 : 0.0,
                    child: Container(
                      color: Colors.black54,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.greenAccent,
                              size: 80,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'УСПІШНО СКАНОВАНО',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_hasError)
                Positioned(
                  bottom: 80,
                  left: 24,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(229, 255, 82, 82), // redAccent.withOpacity(0.9)
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromARGB(128, 255, 82, 82), // redAccent.withOpacity(0.5)
                          blurRadius: 12,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      _errorMessage.isEmpty
                          ? 'Помилка сканування'
                          : _errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 24,
                child: FloatingActionButton(
                  onPressed: toggleTorch,
                  tooltip:
                      torchOn ? 'Вимкнути фонарик' : 'Увімкнути фонарик',
                  backgroundColor:
                      torchOn ? Colors.blueAccent : Colors.grey,
                  child: Icon(
                    torchOn ? Icons.flash_on : Icons.flash_off,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
