import 'package:flutter/material.dart';
import '../../model/document_model.dart';
import '../../theme/app_theme.dart';
import '../home_page_widgets/documnet.dart';

class MonthSection extends StatelessWidget {
  final MonthGroup group;
  final void Function(DocumentItem document)? onTapDocument;
  final void Function(DocumentItem document)? onMoreTapDocument;

  const MonthSection({
    super.key,
    required this.group,
    this.onTapDocument,
    this.onMoreTapDocument,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardColor,
          border: Border.all(color: colors.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: colors.longRectangleColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    group.month,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: colors.septemberColor,
                    ),
                  ),
                  Text(
                    '${group.fileCount} files',
                    style: TextStyle(fontSize: 12.5, color: colors.descriptionColor),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < group.documents.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: colors.borderColor),
              DocumentTile(
                document: group.documents[i],
                onTap: () => onTapDocument?.call(group.documents[i]),
                onMoreTap: () => onMoreTapDocument?.call(group.documents[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}