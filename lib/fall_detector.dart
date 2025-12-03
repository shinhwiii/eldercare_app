// lib/fall_detector.dart
import 'dart:async';
import 'dart:math' show sqrt;
import 'package:sensors_plus/sensors_plus.dart';

typedef FallCallback = Future<void> Function();

/// 간단하고 튜닝 쉬운 휴리스틱 기반 낙상 감지:
///  - 자유낙하 구간(g < freeFallG) ▶ 임팩트(g > impactG) ▶ 부동(immobileMs 동안 분산 매우 낮음)
class FallDetector {
  final double freeFallG;     // 무중력 임계(g)
  final int    freeFallMinMs; // 무중력 최소 지속
  final double impactG;       // 임팩트 임계(g)
  final int    immobileMs;    // 부동 지속 시간
  final int    cooldownMs;    // 재알림 쿨다운
  final FallCallback onFall;

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;

  bool _isFreeFalling = false;
  int  _freeFallStart = 0;
  int  _lastImpactAt  = 0;
  int  _lastFiredAt   = 0;

  final List<double> _recentAccelMag = [];
  final List<double> _recentGyroMag  = [];
  final List<int>    _recentTs       = [];
  final int _bufMs = 3000; // 최근 3초 버퍼

  FallDetector({
    required this.onFall,
    this.freeFallG = 0.7,     // 높을수록 민감
    this.freeFallMinMs = 150, // 낮을수록 민감
    this.impactG = 1.8,       // 낮을수록 민감
    this.immobileMs = 3000,   // 낮을수록 민감
    this.cooldownMs = 15000,
  });

  void start() {
    _accelSub = accelerometerEvents.listen((e) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final a = sqrt(e.x*e.x + e.y*e.y + e.z*e.z); // m/s^2
      final g = a / 9.80665;                        // g 단위
      _push(now, accel: g);

      if (g < freeFallG) {
        if (!_isFreeFalling) {
          _isFreeFalling = true;
          _freeFallStart = now;
        }
      } else {
        if (_isFreeFalling && (now - _freeFallStart) >= freeFallMinMs) {
          // 유효 자유낙하 끝
        }
        _isFreeFalling = false;
      }

      if (g > impactG) _lastImpactAt = now;
    });

    _gyroSub = gyroscopeEvents.listen((e) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final gm = sqrt(e.x*e.x + e.y*e.y + e.z*e.z);
      _push(now, gyro: gm);
      _checkImmobile(now);
    });
  }

  Future<void> stop() async {
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub  = null;
    _recentAccelMag.clear();
    _recentGyroMag.clear();
    _recentTs.clear();
  }

  void _push(int now, {double? accel, double? gyro}) {
    while (_recentTs.isNotEmpty && now - _recentTs.first > _bufMs) {
      _recentTs.removeAt(0);
      if (_recentAccelMag.isNotEmpty) _recentAccelMag.removeAt(0);
      if (_recentGyroMag.isNotEmpty)  _recentGyroMag.removeAt(0);
    }
    _recentTs.add(now);
    _recentAccelMag.add(accel ?? (_recentAccelMag.isNotEmpty ? _recentAccelMag.last : 0));
    _recentGyroMag.add(gyro ?? (_recentGyroMag.isNotEmpty ? _recentGyroMag.last : 0));
  }

  void _checkImmobile(int now) async {
    final from = now - immobileMs;
    final idx = <int>[];
    for (int i = 0; i < _recentTs.length; i++) {
      if (_recentTs[i] >= from) idx.add(i);
    }
    if (idx.length < 10) return;

    double vA = _variance([for (final i in idx) _recentAccelMag[i]]);
    double vG = _variance([for (final i in idx) _recentGyroMag[i]]);
    final immobile = vA < 0.02 && vG < 0.02;

    final hadFreeFall = (_freeFallStart > 0) && (now - _freeFallStart <= 4000);
    final hadImpact   = (_lastImpactAt  > 0) && (now - _lastImpactAt  <= 4000);

    if (immobile && hadFreeFall && hadImpact) {
      if (now - _lastFiredAt >= cooldownMs) {
        _lastFiredAt = now;
        _freeFallStart = 0;
        _lastImpactAt  = 0;
        await onFall(); // 👉 여기서 보호자에게 알림 전송
      }
    }
  }

  double _variance(List<double> xs) {
    if (xs.isEmpty) return 0;
    final m = xs.reduce((a,b)=>a+b)/xs.length;
    double s = 0; for (final x in xs) { final d = x - m; s += d*d; }
    return s / xs.length;
  }
}
