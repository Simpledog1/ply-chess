import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../analysis/review.dart';
import 'services.dart';
import 'theme.dart';

const accuracyNote =
    'Accuracy follows the Lichess formula: each move scores 0–100 from how much '
    'it lowered your winning chances, as estimated by Stockfish at a fixed depth. '
    'Ply reports the plain average over your moves. It is an estimate: it depends on '
    'search depth, treats every move equally (easy recaptures count as much as hard '
    'decisions), and is not comparable with other sites\' numbers. Best moves and forced '
    'moves score 100.';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Services.of(context).analysis;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final r = a.review;
        final moves = a.moveReviews;
        final theme = Theme.of(context);
        void jump(int ply) {
          a.goTo(ply);
          Navigator.pop(context);
        }

        if (r == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Game review')),
            body: const Center(child: Text('No review yet')),
          );
        }
        final w = summarize(moves, Side.white),
            b = summarize(moves, Side.black);
        final critical = criticalMoments(moves);
        final missed = missedOpportunities(moves);
        String moveName(MoveReview m) =>
            '${a.game.positionAt(m.ply).fullmoves}${m.mover == Side.white ? '.' : '…'} ${m.san}${classSymbol(m.cls)}';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Game review'),
            actions: [
              IconButton(
                tooltip: 'About accuracy',
                icon: const Icon(Icons.info_outline),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('About these numbers'),
                    content: const Text(accuracyNote),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (!r.complete)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.hourglass_bottom),
                    title: Text(
                      'Partial review: ${r.analysedCount} of ${r.positions.length} positions',
                    ),
                    subtitle: const Text(
                      'Moves next to unanalysed positions are not classified.',
                    ),
                  ),
                ),
              Text(
                '${r.engine} · depth ${r.depth} for every position',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _SummaryTable(
                white: w,
                black: b,
                whiteName: a.game.headers['White'],
                blackName: a.game.headers['Black'],
              ),
              const SizedBox(height: 16),
              Text(
                'Winning chances (White)',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 120,
                child: EvalGraph(
                  review: r,
                  moves: moves,
                  current: a.ply,
                  onTap: jump,
                ),
              ),
              const SizedBox(height: 16),
              if (critical.isNotEmpty) ...[
                Text('Critical moments', style: theme.textTheme.titleSmall),
                for (final m in critical)
                  _MomentTile(
                    m: m,
                    title: moveName(m),
                    onTap: () => jump(m.ply + 1),
                  ),
                const SizedBox(height: 12),
              ],
              if (missed.isNotEmpty) ...[
                Text('Missed opportunities', style: theme.textTheme.titleSmall),
                for (final m in missed)
                  _MomentTile(
                    m: m,
                    title: moveName(m),
                    onTap: () => jump(m.ply),
                    missed: true,
                  ),
                const SizedBox(height: 12),
              ],
              Text('Every move', style: theme.textTheme.titleSmall),
              for (final m in moves)
                if (m != null)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => jump(m.ply + 1),
                    leading: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: classColor(m.cls),
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text('${moveName(m)}  ·  ${m.cls.label}'),
                    trailing: Text(
                      '${m.before.label} → ${m.after.label}'
                      '${m.loss >= 0.5 ? '  (−${m.loss.toStringAsFixed(0)}%)' : ''}',
                    ),
                  ),
              const SizedBox(height: 12),
              Text(
                'Classifications use the drop in the mover\'s winning chances: inaccuracy ≥ '
                '${a.settings.thresholds.inaccuracy.toStringAsFixed(0)}, mistake ≥ '
                '${a.settings.thresholds.mistake.toStringAsFixed(0)}, blunder ≥ '
                '${a.settings.thresholds.blunder.toStringAsFixed(0)} percentage points (change in Settings). '
                'Explanations are assembled from Stockfish\'s lines, not written by a language model.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryTable extends StatelessWidget {
  const _SummaryTable({
    required this.white,
    required this.black,
    this.whiteName,
    this.blackName,
  });
  final SideSummary white, black;
  final String? whiteName, blackName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String name(String? n, String d) => n == null || n == '?' ? d : n;
    TableRow row(
      String label,
      String wv,
      String bv, {
      Color? color,
      bool bold = false,
    }) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(label, style: TextStyle(color: color)),
        ),
        Text(
          wv,
          textAlign: TextAlign.end,
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
        ),
        Text(
          bv,
          textAlign: TextAlign.end,
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
        ),
      ],
    );
    String acc(SideSummary s) =>
        s.accuracy == null ? '–' : '${s.accuracy!.toStringAsFixed(1)}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Table(
          columnWidths: const {0: FlexColumnWidth(1.4)},
          children: [
            TableRow(
              children: [
                const SizedBox(),
                Text(
                  name(whiteName, 'White'),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  name(blackName, 'Black'),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            row('Accuracy (estimate)', acc(white), acc(black), bold: true),
            for (final c in MoveClass.values)
              row(
                c.label,
                '${white.counts[c]}',
                '${black.counts[c]}',
                color: classColor(c),
              ),
          ],
        ),
      ),
    );
  }
}

class _MomentTile extends StatelessWidget {
  const _MomentTile({
    required this.m,
    required this.title,
    required this.onTap,
    this.missed = false,
  });
  final MoveReview m;
  final String title;
  final VoidCallback onTap;
  final bool missed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          missed ? Icons.search : Icons.warning_amber_rounded,
          color: classColor(m.cls),
        ),
        title: Text('$title  ${m.cls.label}'),
        subtitle: Text(
          [
            if (m.tags.isNotEmpty) m.tags.map((t) => t.label).join(' · '),
            m.explanation,
          ].join('\n'),
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: true,
      ),
    );
  }
}

/// White's winning chances after every ply; tap to jump to a position.
class EvalGraph extends StatelessWidget {
  const EvalGraph({
    super.key,
    required this.review,
    required this.moves,
    required this.current,
    required this.onTap,
  });
  final GameReview review;
  final List<MoveReview?> moves;
  final int current;
  final void Function(int ply) onTap;

  @override
  Widget build(BuildContext context) {
    final n = review.positions.length;
    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          onTapUp: (d) => onTap(
            ((d.localPosition.dx / c.maxWidth) * (n - 1)).round().clamp(
              0,
              n - 1,
            ),
          ),
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _GraphPainter(
              review,
              moves,
              current,
              Theme.of(context).colorScheme,
            ),
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.review, this.moves, this.current, this.scheme);
  final GameReview review;
  final List<MoveReview?> moves;
  final int current;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final n = review.positions.length;
    if (n < 2) return;
    double x(int i) => size.width * i / (n - 1);
    double y(double w) => size.height * (1 - w / 100);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = const Color(0xFF3A3A3A),
    );
    final path = Path()..moveTo(0, size.height);
    double last = 50;
    for (var i = 0; i < n; i++) {
      final p = review.positions[i];
      last = p?.eval.whiteWinPercent ?? last;
      path.lineTo(x(i), y(last));
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFFEDEDED));
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = scheme.primary.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(x(current.clamp(0, n - 1)), 0),
      Offset(x(current.clamp(0, n - 1)), size.height),
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2,
    );
    for (final m in moves) {
      if (m == null || !m.cls.isError) continue;
      final p = review.positions[m.ply + 1];
      if (p == null) continue;
      canvas.drawCircle(
        Offset(x(m.ply + 1), y(p.eval.whiteWinPercent)),
        4,
        Paint()..color = classColor(m.cls),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
