import 'package:flutter/material.dart';
import '../../controller/fileType.dart';
import '../../model/document_model.dart';
import '../../theme/app_theme.dart';

class DocumentTile extends StatelessWidget {
  final DocumentItem document;
  final VoidCallback? onTap;
  final VoidCallback? onMoreTap;

  const DocumentTile({super.key, required this.document, this.onTap, this.onMoreTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final style = document.type;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, color: style.foreground, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: colors.headingTextColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    document.subtitle,
                    style: TextStyle(fontSize: 12.5, color: colors.descriptionColor),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onMoreTap,
              icon: Icon(Icons.more_vert_rounded, color: colors.descriptionColor),
              splashRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}