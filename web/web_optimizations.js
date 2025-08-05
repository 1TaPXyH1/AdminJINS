// Web-specific optimizations for PWA Barcode Scanner
// Performance and camera handling optimizations

(function() {
  'use strict';

  // Camera stream optimization
  window.optimizeCameraStream = function(stream) {
    const tracks = stream.getVideoTracks();
    if (tracks.length > 0) {
      const track = tracks[0];
      const capabilities = track.getCapabilities ? track.getCapabilities() : {};
      const settings = track.getSettings ? track.getSettings() : {};
      
      // Apply optimal constraints for barcode scanning
      const constraints = {
        width: { ideal: 1920, max: 2560 },
        height: { ideal: 1080, max: 1440 },
        frameRate: { ideal: 30, max: 30 },
        facingMode: { exact: 'environment' }
      };
      
      // Apply autofocus if available
      if (capabilities.focusMode) {
        constraints.focusMode = 'continuous';
      }
      
      // Apply torch/flash if available
      if (capabilities.torch) {
        window.torchAvailable = true;
      }
      
      track.applyConstraints(constraints).catch(console.error);
    }
    return stream;
  };

  // Web Vibration API wrapper
  window.vibrateFeedback = function(pattern) {
    if ('vibrate' in navigator) {
      navigator.vibrate(pattern || 50);
    }
  };

  // Fullscreen API wrapper for better scanning experience
  window.enterScanFullscreen = function(element) {
    if (element.requestFullscreen) {
      element.requestFullscreen();
    } else if (element.webkitRequestFullscreen) {
      element.webkitRequestFullscreen();
    } else if (element.msRequestFullscreen) {
      element.msRequestFullscreen();
    }
  };

  // Wake Lock API to prevent screen from sleeping during scanning
  let wakeLock = null;
  
  window.requestWakeLock = async function() {
    if ('wakeLock' in navigator) {
      try {
        wakeLock = await navigator.wakeLock.request('screen');
        console.log('Wake Lock activated');
        
        // Re-acquire wake lock if visibility changes
        document.addEventListener('visibilitychange', async () => {
          if (wakeLock !== null && document.visibilityState === 'visible') {
            wakeLock = await navigator.wakeLock.request('screen');
          }
        });
      } catch (err) {
        console.error('Wake Lock failed:', err);
      }
    }
  };
  
  window.releaseWakeLock = function() {
    if (wakeLock !== null) {
      wakeLock.release();
      wakeLock = null;
      console.log('Wake Lock released');
    }
  };

  // Optimize image processing for barcode detection
  window.preprocessImage = function(imageData) {
    const data = imageData.data;
    const width = imageData.width;
    const height = imageData.height;
    
    // Convert to grayscale for better barcode detection
    for (let i = 0; i < data.length; i += 4) {
      const gray = data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114;
      data[i] = gray;
      data[i + 1] = gray;
      data[i + 2] = gray;
    }
    
    // Increase contrast
    const factor = 1.5;
    for (let i = 0; i < data.length; i += 4) {
      data[i] = Math.min(255, (data[i] - 128) * factor + 128);
      data[i + 1] = Math.min(255, (data[i + 1] - 128) * factor + 128);
      data[i + 2] = Math.min(255, (data[i + 2] - 128) * factor + 128);
    }
    
    return imageData;
  };

  // Performance monitoring
  window.monitorScanPerformance = function() {
    if ('performance' in window && 'measure' in performance) {
      performance.mark('scan-start');
      
      return {
        end: function() {
          performance.mark('scan-end');
          performance.measure('scan-duration', 'scan-start', 'scan-end');
          const measure = performance.getEntriesByName('scan-duration')[0];
          console.log(`Scan took ${measure.duration}ms`);
          performance.clearMarks();
          performance.clearMeasures();
          return measure.duration;
        }
      };
    }
    return { end: function() { return 0; } };
  };

  // Memory management - clean up camera streams
  window.cleanupCameraStream = function(stream) {
    if (stream) {
      stream.getTracks().forEach(track => {
        track.stop();
      });
    }
  };

  // Device detection for optimal settings
  window.getDeviceProfile = function() {
    const ua = navigator.userAgent.toLowerCase();
    const isMobile = /mobile|android|iphone|ipad|ipod/.test(ua);
    const isTablet = /ipad|android(?!.*mobile)/.test(ua);
    const isIOS = /iphone|ipad|ipod/.test(ua);
    const isAndroid = /android/.test(ua);
    
    return {
      isMobile,
      isTablet,
      isIOS,
      isAndroid,
      isDesktop: !isMobile && !isTablet,
      hasTouch: 'ontouchstart' in window,
      pixelRatio: window.devicePixelRatio || 1
    };
  };

  // Network speed detection for adaptive quality
  window.getNetworkSpeed = async function() {
    if ('connection' in navigator) {
      const connection = navigator.connection;
      return {
        effectiveType: connection.effectiveType,
        downlink: connection.downlink,
        rtt: connection.rtt,
        saveData: connection.saveData
      };
    }
    return { effectiveType: '4g', downlink: 10, rtt: 50, saveData: false };
  };

  // Battery status for power management
  window.getBatteryStatus = async function() {
    if ('getBattery' in navigator) {
      try {
        const battery = await navigator.getBattery();
        return {
          level: battery.level,
          charging: battery.charging
        };
      } catch (err) {
        console.error('Battery API failed:', err);
      }
    }
    return { level: 1, charging: false };
  };

  // Optimize canvas rendering for smooth preview
  window.optimizeCanvas = function(canvas) {
    const ctx = canvas.getContext('2d', {
      alpha: false,
      desynchronized: true,
      willReadFrequently: true
    });
    
    // Enable image smoothing for better quality
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    
    return ctx;
  };

  // WebAssembly feature detection for future optimizations
  window.hasWebAssembly = function() {
    try {
      if (typeof WebAssembly === 'object' &&
          typeof WebAssembly.instantiate === 'function') {
        const module = new WebAssembly.Module(
          Uint8Array.of(0x0, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00)
        );
        if (module instanceof WebAssembly.Module) {
          return new WebAssembly.Instance(module) instanceof WebAssembly.Instance;
        }
      }
    } catch (e) {
      console.error('WebAssembly check failed:', e);
    }
    return false;
  };

  // Initialize optimizations on load
  document.addEventListener('DOMContentLoaded', function() {
    console.log('PWA Scanner Optimizations Loaded');
    console.log('Device Profile:', window.getDeviceProfile());
    console.log('WebAssembly Support:', window.hasWebAssembly());
    
    // Request wake lock when scanner is active
    if (document.querySelector('.scanner-active')) {
      window.requestWakeLock();
    }
  });

  // Clean up on unload
  window.addEventListener('beforeunload', function() {
    window.releaseWakeLock();
  });

})();
