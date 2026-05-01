import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/safety_place.dart';
import '../../services/app_settings_service.dart';
import '../../services/hazard_validation_service.dart';
import '../../theme/app_theme.dart';

class _PinDuration {
  const _PinDuration(this.label, this.hours);
  final String label;
  final int hours;
}

const _durations = [
  _PinDuration('6 h', 6),
  _PinDuration('12 h', 12),
  _PinDuration('24 h', 24),
  _PinDuration('3 days', 72),
  _PinDuration('1 week', 168),
];

const _defaultDurationIndex = 2; // 24 h
class ReportHazardSheet extends StatefulWidget {
  const ReportHazardSheet({super.key, required this.location});

  final LatLng location;

  @override
  State<ReportHazardSheet> createState() => _ReportHazardSheetState();
}

class _ReportHazardSheetState extends State<ReportHazardSheet> {
  final _descriptionController = TextEditingController();
  final _validationService = const HazardValidationService();

  String _selectedType = 'General hazard';
  int _selectedDurationIndex = _defaultDurationIndex;
  bool _isValidating = false;
  String? _validationError;

  static const _hazardTypes = [
    'General hazard',
    'Flooding',
    'Fire or smoke',
    'Road damage',
    'Structural damage',
    'Gas or utility',
    'Other',
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final description = _descriptionController.text.trim();

    setState(() {
      _isValidating = true;
      _validationError = null;
    });

    final result = await _validationService.validate(description);

    if (!mounted) return;
    setState(() => _isValidating = false);

    if (!result.isValid) {
      setState(() => _validationError = result.feedback);
      return;
    }

    final duration = _durations[_selectedDurationIndex];
    final expiresAt = DateTime.now().add(Duration(hours: duration.hours));

    final place = SafetyPlace(
      id: 'user-hazard-${DateTime.now().millisecondsSinceEpoch}',
      name: _selectedType,
      category: SafetyPlaceCategory.hazard,
      latitude: widget.location.latitude,
      longitude: widget.location.longitude,
      address: 'User-reported location',
      accessibilityFeatures: const [],
      hazardTags: [_selectedType],
      lastVerified:
          'Reported ${DateTime.now().toLocal().toString().substring(0, 16)}',
      notes: description,
      isUserSubmitted: true,
      expiresAt: expiresAt,
    );

    if (mounted) Navigator.of(context).pop(place);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.instance.lowBattery;
    final bg = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final bodyColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;
    final chipBg = isDark ? TogetherTheme.amoledSurfaceElevated : Colors.white;
    final chipBorder =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFD3DCE4);
    final chipSelected =
        isDark ? TogetherTheme.amoledSurfaceElevated : TogetherTheme.mist;
    final fieldBorder =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFD3DCE4);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPadding),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ────────────────────────────────────────────────────
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? TogetherTheme.amoledBorder
                      : const Color(0xFFDCE4EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A0A00)
                        : const Color(0xFFFDE8E8),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: isDark
                        ? TogetherTheme.amoledWarning
                        : const Color(0xFFB45309),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Report a Hazard',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                          fontFamily: 'RobotoSlab',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'AI-assisted review will confirm your report',
                        style: TextStyle(fontSize: 12, color: bodyColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Coordinates ───────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? TogetherTheme.amoledSurfaceElevated
                    : const Color(0xFFF0F5F8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 16,
                    color: isDark
                        ? TogetherTheme.amoledTextSecondary
                        : TogetherTheme.deepOcean,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.location.latitude.toStringAsFixed(5)}, '
                    '${widget.location.longitude.toStringAsFixed(5)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? TogetherTheme.amoledTextSecondary
                          : TogetherTheme.deepOcean,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Hazard type ───────────────────────────────────────────────
            Text(
              'Hazard type',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: bodyColor,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _hazardTypes.map((type) {
                final isSelected = _selectedType == type;
                return FilterChip(
                  selected: isSelected,
                  showCheckmark: false,
                  label: Text(type),
                  onSelected: (_) => setState(() => _selectedType = type),
                  selectedColor: chipSelected,
                  backgroundColor: chipBg,
                  side: BorderSide(color: chipBorder),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: isSelected ? titleColor : bodyColor,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Description ───────────────────────────────────────────────
            Text(
              'Description',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: bodyColor,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              maxLength: 300,
              style: TextStyle(color: titleColor),
              decoration: InputDecoration(
                filled: true,
                fillColor:
                    isDark ? TogetherTheme.amoledSurfaceElevated : Colors.white,
                hintText:
                    'Describe the danger or unsafe condition you observed…',
                hintStyle: TextStyle(color: bodyColor.withValues(alpha: 0.6)),
                errorText: _validationError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark
                        ? TogetherTheme.amoledTextSecondary
                        : TogetherTheme.deepOcean,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (_) {
                if (_validationError != null) {
                  setState(() => _validationError = null);
                }
              },
            ),
            const SizedBox(height: 16),

            // ── Pin duration ──────────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: bodyColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'Pin stays visible for',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: bodyColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_durations.length, (i) {
                  final isSelected = _selectedDurationIndex == i;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: isSelected,
                      label: Text(_durations[i].label),
                      onSelected: (_) =>
                          setState(() => _selectedDurationIndex = i),
                      selectedColor: chipSelected,
                      backgroundColor: chipBg,
                      side: BorderSide(
                        color: isSelected
                            ? (isDark
                                ? TogetherTheme.amoledTextSecondary
                                : TogetherTheme.deepOcean)
                            : chipBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: isSelected ? titleColor : bodyColor,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Expires ${_expiryPreview()}',
              style: TextStyle(
                fontSize: 12,
                color: bodyColor.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),

            // ── Submit / cancel ───────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isValidating ? null : _submit,
                icon: _isValidating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(
                  _isValidating ? 'AI reviewing report…' : 'Submit Report',
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed:
                    _isValidating ? null : () => Navigator.of(context).pop(),
                child: Text('Cancel', style: TextStyle(color: bodyColor)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _expiryPreview() {
    final hours = _durations[_selectedDurationIndex].hours;
    final expiry = DateTime.now().add(Duration(hours: hours));
    final day = expiry.toLocal();
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${weekdays[day.weekday - 1]} ${day.day} ${months[day.month - 1]} '
        'at ${day.hour.toString().padLeft(2, '0')}:${day.minute.toString().padLeft(2, '0')}';
  }
}
