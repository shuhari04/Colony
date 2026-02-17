import 'package:flutter/material.dart';

class ColonyColors {
  static const bg0 = Color(0xFF05070D);
  static const bg1 = Color(0xFF070B14);
  static const surface0 = Color(0xFF0B1220);
  static const surface1 = Color(0xFF0F172A);
  static const border0 = Color(0xFF1B2742);
  static const text0 = Color(0xFFE6EDF7);
  static const text1 = Color(0xFFA9B5CC);
  static const muted0 = Color(0xFF6B7A99);

  static const accentCyan = Color(0xFF22D3EE);
  static const success = Color(0xFFA3E635);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFFB7185);
  static const info = Color(0xFF60A5FA);
}

class ColonyRadii {
  static const r1 = 8.0;
  static const r2 = 12.0;
  static const r3 = 16.0;
}

class ColonySpacing {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
  static const s7 = 48.0;
}

class ColonyShadows {
  static List<BoxShadow> glowSmall(Color c) => [
        BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 10, spreadRadius: 0),
      ];
}

