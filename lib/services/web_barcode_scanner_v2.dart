import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/material.dart';

class WebBarcodeScannerV2 {
  static bool _libraryLoaded = false;
  static StreamController<String>? _barcodeController;
  static html.DivElement? _scannerContainer;
  static js.JsObject? _scanner;
  
  /// Ініціалізує html5-qrcode бібліотеку
  static Future<void> initializeLibrary() async {
    if (_libraryLoaded) return;
    
    // Додаємо html5-qrcode скрипт
    final script = html.ScriptElement()
      ..src = 'https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js'
      ..type = 'text/javascript';
    
    final completer = Completer<void>();
    
    script.onLoad.listen((_) {
      _libraryLoaded = true;
      completer.complete();
    });
    
    script.onError.listen((_) {
      completer.completeError('Failed to load html5-qrcode library');
    });
    
    html.document.head?.append(script);
    
    await completer.future;
  }
  
  /// Починає сканування з камери
  static Future<Stream<String>> startScanning({
    required BuildContext context,
    bool preferBackCamera = true,
  }) async {
    // Ініціалізуємо бібліотеку якщо ще не завантажена
    if (!_libraryLoaded) {
      await initializeLibrary();
    }
    
    // Створюємо новий контролер для потоку
    _barcodeController?.close();
    _barcodeController = StreamController<String>.broadcast();
    
    try {
      // Створюємо контейнер для сканера
      _scannerContainer = html.DivElement()
        ..id = 'qr-reader-${DateTime.now().millisecondsSinceEpoch}'
        ..style.position = 'fixed'
        ..style.top = '0'
        ..style.left = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.zIndex = '999999';
      
      html.document.body?.append(_scannerContainer!);
      
      // Чекаємо трохи щоб DOM оновився
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Ініціалізуємо сканер через JavaScript
      js.context.callMethod('eval', ['''
        (function() {
          const html5QrCode = new Html5Qrcode("${_scannerContainer!.id}");
          
          // Зберігаємо посилання на сканер
          window.currentScanner = html5QrCode;
          
          // Конфігурація сканера
          const config = {
            fps: 10,
            qrbox: { width: 250, height: 250 },
            aspectRatio: 1.0,
            // Підтримка різних форматів штрихкодів
            formatsToSupport: [
              Html5QrcodeSupportedFormats.QR_CODE,
              Html5QrcodeSupportedFormats.CODE_128,
              Html5QrcodeSupportedFormats.CODE_39,
              Html5QrcodeSupportedFormats.CODE_93,
              Html5QrcodeSupportedFormats.EAN_13,
              Html5QrcodeSupportedFormats.EAN_8,
              Html5QrcodeSupportedFormats.UPC_A,
              Html5QrcodeSupportedFormats.UPC_E,
              Html5QrcodeSupportedFormats.ITF,
              Html5QrcodeSupportedFormats.CODABAR,
              Html5QrcodeSupportedFormats.DATA_MATRIX,
              Html5QrcodeSupportedFormats.PDF_417
            ]
          };
          
          // Функція успішного сканування
          const onScanSuccess = (decodedText, decodedResult) => {
            console.log('Scanned barcode:', decodedText);
            window.postMessage({
              type: 'barcode_detected',
              barcode: decodedText
            }, '*');
          };
          
          // Функція помилки сканування (ігноруємо)
          const onScanFailure = (error) => {
            // Ігноруємо помилки сканування
          };
          
          // Отримуємо список камер
          Html5Qrcode.getCameras().then(devices => {
            if (devices && devices.length) {
              let cameraId = devices[0].id;
              
              // Шукаємо задню камеру якщо потрібно
              if (${preferBackCamera ? 'true' : 'false'}) {
                const backCamera = devices.find(device => 
                  device.label.toLowerCase().includes('back') ||
                  device.label.toLowerCase().includes('rear') ||
                  device.label.toLowerCase().includes('environment')
                );
                if (backCamera) {
                  cameraId = backCamera.id;
                }
              }
              
              // Запускаємо сканування
              html5QrCode.start(
                cameraId,
                config,
                onScanSuccess,
                onScanFailure
              ).catch(err => {
                console.error('Failed to start scanner:', err);
                window.postMessage({
                  type: 'scanner_error',
                  error: err.toString()
                }, '*');
              });
            } else {
              console.error('No cameras found');
              window.postMessage({
                type: 'scanner_error',
                error: 'No cameras found'
              }, '*');
            }
          }).catch(err => {
            console.error('Failed to get cameras:', err);
            window.postMessage({
              type: 'scanner_error',
              error: err.toString()
            }, '*');
          });
        })();
      ''']);
      
      // Слухаємо повідомлення від сканера
      html.window.onMessage.listen((event) {
        final data = event.data;
        if (data is Map) {
          if (data['type'] == 'barcode_detected') {
            final barcode = data['barcode'] as String;
            if (barcode.isNotEmpty) {
              _barcodeController?.add(barcode);
            }
          } else if (data['type'] == 'scanner_error') {
            _barcodeController?.addError(data['error']);
          }
        }
      });
      
    } catch (e) {
      _barcodeController?.addError('Failed to initialize scanner: $e');
    }
    
    return _barcodeController!.stream;
  }
  
  /// Зупиняє сканування та звільняє ресурси
  static void stopScanning() {
    // Зупиняємо сканер через JavaScript
    try {
      js.context.callMethod('eval', ['''
        if (window.currentScanner) {
          window.currentScanner.stop().then(() => {
            window.currentScanner.clear();
            window.currentScanner = null;
          }).catch(err => {
            console.error('Error stopping scanner:', err);
          });
        }
      ''']);
    } catch (e) {
      debugPrint('Error stopping scanner: $e');
    }
    
    // Видаляємо контейнер
    _scannerContainer?.remove();
    _scannerContainer = null;
    
    // Закриваємо контролер
    _barcodeController?.close();
    _barcodeController = null;
  }
  
  /// Перевіряє чи доступна камера
  static Future<bool> isCameraAvailable() async {
    try {
      final devices = await html.window.navigator.mediaDevices!
          .enumerateDevices();
      return devices.any((device) => device.kind == 'videoinput');
    } catch (e) {
      return false;
    }
  }
  
  /// Отримує список доступних камер
  static Future<List<html.MediaDeviceInfo>> getAvailableCameras() async {
    try {
      final devices = await html.window.navigator.mediaDevices!
          .enumerateDevices();
      return devices
          .where((device) => device.kind == 'videoinput')
          .cast<html.MediaDeviceInfo>()
          .toList();
    } catch (e) {
      return [];
    }
  }
}
