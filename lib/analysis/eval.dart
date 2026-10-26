import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

/// An engine evaluation, always stored from White's point of view.
///
/// UCI engines report scores relative to the side to move; convert with
/// [Eval.fromUci] so that every stored value shares one perspective.
class Eval {
  /// Centipawn score. `null` when this is a mate score.
  final int? cp;

  /// Moves until mate (0 = the side to move is already checkmated).
  /// `null` when this is a centipawn score.
  final int? mateIn;

  /// For mate scores: true when White is the side delivering mate.
  final bool whiteMates;

  const Eval.cp(int this.cp) : mateIn = null, whiteMates = false;

  const Eval.mate(int this.mateIn, {required this.whiteMates}) : cp = null;

  /// Converts a UCI `score cp` / `score mate` value (side-to-move relative)
  /// into a White-relative [Eval].
  factory Eval.fromUci({int? cp, int? mate, required Side turn}) {
    final sign = turn == Side.white ? 1 : -1;
    if (mate != null) {
      // mate > 0: side to move mates; mate <= 0: side to move gets mated.
      final moverMates = mate > 0;
      final whiteMates = moverMates == (turn == Side.white);
      return Eval.mate(mate.abs(), whiteMates: whiteMates);
    }
    return Eval.cp(sign * (cp ?? 0));
  }

  bool get isMate => mateIn != null;

  /// Win probability for White in percent (0–100), using the logistic model
  /// published by Lichess (`50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1)`).
  double get whiteWinPercent {
    if (isMate) return whiteMates ? 100 : 0;
    final c = cp!.clamp(-1000, 1000);
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * c)) - 1);
  }

  double winPercentFor(Side side) =>
      side == Side.white ? whiteWinPercent : 100 - whiteWinPercent;

  /// Short label such as `+0.34`, `-1.20`, `#3`, `#-2`.
  String get label {
    if (isMate) {
      if (mateIn == 0) return whiteMates ? '1-0' : '0-1';
      return whiteMates ? '#$mateIn' : '#-$mateIn';
    }
    final v = cp! / 100;
    return '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}';
  }

  Map<String, dynamic> toJson() =>
      isMate ? {'mate': mateIn, 'w': whiteMates} : {'cp': cp};

  factory Eval.fromJson(Map<String, dynamic> j) => j.containsKey('mate')
      ? Eval.mate(j['mate'] as int, whiteMates: j['w'] as bool)
      : Eval.cp(j['cp'] as int);

  @override
  bool operator ==(Object other) =>
      other is Eval &&
      other.cp == cp &&
      other.mateIn == mateIn &&
      other.whiteMates == whiteMates;

  @override
  int get hashCode => Object.hash(cp, mateIn, whiteMates);

  @override
  String toString() => 'Eval($label)';
}
