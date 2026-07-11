import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/glass/glass_top_bar.dart';

void main() {
  testWidgets(
      'title centers on the full bar width despite asymmetric sides '
      '(owner-reported drift)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RpgTheme.themeDataDarkGray,
      home: Scaffold(
        appBar: GlassTopBar(
          leading: const Icon(Icons.arrow_back),
          title: const Text('Zosia', key: ValueKey('t')),
          trailing: const [
            Icon(Icons.more_vert),
            CircleAvatar(radius: 18, child: Text('Z')),
          ],
        ),
        body: const SizedBox(),
      ),
    ));

    final titleCenter = tester.getCenter(find.byKey(const ValueKey('t'))).dx;
    final barCenter =
        tester.getCenter(find.byType(GlassTopBar)).dx;
    expect((titleCenter - barCenter).abs(), lessThan(1.0),
        reason: 'title must center on the whole bar, not the leftover slot');
  });
}
