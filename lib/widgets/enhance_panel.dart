import 'package:flutter/material.dart';

import '../services/enchance_service.dart';
import '../theme/app_theme.dart';

/// Collapsible enhance controls. Collapsed, it's a slim bar showing the active
/// filter name; tapping it expands a dropdown with just the two filter cards
/// (Colorful / B&W) plus Reset. Tapping a card switches the filter and the
/// preview updates instantly; Reset returns the page to the untouched original.
class EnhancePanel extends StatefulWidget {
  final EnhanceSettings settings;
  final ValueChanged<EnhanceSettings> onChanged;
  final VoidCallback onReset;
  final VoidCallback? onApplyAll;

  const EnhancePanel({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onReset,
    this.onApplyAll,
  });

  @override
  State<EnhancePanel> createState() => _EnhancePanelState();
}

class _EnhancePanelState extends State<EnhancePanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    final settings = widget.settings;
    final isColorful = settings.filter == EnhanceFilter.colorful;
    final isBlackWhite = settings.filter == EnhanceFilter.blackWhite;

    return Container(
      color: colors.searchbarColor,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Enhance',
                    style: TextStyle(
                      color: colors.headingTextColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.cardColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.borderColor),
                    ),
                    child: Text(
                      settings.filter.label,
                      style: TextStyle(
                        color: colors.buttonColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: colors.headingTextColor.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _FilterCard(
                              label: 'Colorful',
                              description: 'Bright, true colour',
                              selected: isColorful,
                              onTap: () => widget.onChanged(
                                settings.copyWith(
                                  filter: EnhanceFilter.colorful,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _FilterCard(
                              label: 'B&W',
                              description: 'Black & white',
                              selected: isBlackWhite,
                              onTap: () => widget.onChanged(
                                settings.copyWith(
                                  filter: EnhanceFilter.blackWhite,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (isColorful) ...[
                        _sliderRow(
                          colors,
                          'Saturation',
                          settings.saturation,
                          (v) => widget.onChanged(
                            settings.copyWith(saturation: v),
                          ),
                        ),
                        _sliderRow(
                          colors,
                          'Contrast',
                          settings.contrast,
                          (v) =>
                              widget.onChanged(settings.copyWith(contrast: v)),
                        ),
                      ] else
                        _sliderRow(
                          colors,
                          'Sensitivity',
                          settings.sensitivity,
                          (v) => widget.onChanged(
                            settings.copyWith(sensitivity: v),
                          ),
                        ),
                      Row(
                        children: [
                          const Spacer(),
                          TextButton.icon(
                            onPressed: widget.onReset,
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              size: 15,
                            ),
                            label: const Text('Reset'),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.headingTextColor
                                  .withValues(alpha: 0.7),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          if (widget.onApplyAll != null)
                            TextButton.icon(
                              onPressed: widget.onApplyAll,
                              icon: const Icon(
                                Icons.done_all_rounded,
                                size: 15,
                              ),
                              label: const Text('Apply All'),
                              style: TextButton.styleFrom(
                                foregroundColor: colors.buttonColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow(
    CustomAppColors colors,
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: colors.headingTextColor.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: colors.buttonColor,
              inactiveTrackColor: colors.borderColor,
              thumbColor: colors.buttonColor,
            ),
            child: Slider(
              value: value.toDouble(),
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            value == 0
                ? '0'
                : value > 0
                ? '+$value'
                : '$value',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: value == 0
                  ? colors.headingTextColor.withValues(alpha: 0.55)
                  : colors.buttonColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// A tappable filter card (Colorful / B&W). The selected card is highlighted;
/// the other stays visible so the user can switch back at any time.
class _FilterCard extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _FilterCard({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? colors.buttonColor.withValues(alpha: 0.10)
              : colors.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? colors.buttonColor : colors.borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected
                          ? colors.buttonColor
                          : colors.headingTextColor,
                    ),
                  ),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colors.headingTextColor.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: colors.buttonColor,
              ),
          ],
        ),
      ),
    );
  }
}
