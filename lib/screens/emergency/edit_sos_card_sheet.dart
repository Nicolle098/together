import 'package:flutter/material.dart';

import '../../models/medical_profile.dart';
import '../../services/app_settings_service.dart';
import '../../theme/app_theme.dart';


class EditSosCardSheet extends StatefulWidget {
  const EditSosCardSheet({super.key, required this.profile});

  final MedicalProfile profile;

  @override
  State<EditSosCardSheet> createState() => _EditSosCardSheetState();
}

class _EditSosCardSheetState extends State<EditSosCardSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _bloodTypeCtrl;
  late final TextEditingController _allergiesCtrl;
  late final TextEditingController _medicationsCtrl;
  late final TextEditingController _mobilityCtrl;
  late final TextEditingController _communicationCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _bloodTypeCtrl = TextEditingController(text: p.bloodType);
    _allergiesCtrl = TextEditingController(text: p.allergies.join(', '));
    _medicationsCtrl = TextEditingController(text: p.medications.join(', '));
    _mobilityCtrl = TextEditingController(text: p.mobilityNeeds.join(', '));
    _communicationCtrl =
        TextEditingController(text: p.communicationNeeds.join(', '));
    _notesCtrl = TextEditingController(text: p.emergencyNotes);
  }

  @override
  void dispose() {
    _bloodTypeCtrl.dispose();
    _allergiesCtrl.dispose();
    _medicationsCtrl.dispose();
    _mobilityCtrl.dispose();
    _communicationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<String> _splitField(String raw) => raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final updated = MedicalProfile(
      bloodType: _bloodTypeCtrl.text.trim(),
      allergies: _splitField(_allergiesCtrl.text),
      medications: _splitField(_medicationsCtrl.text),
      mobilityNeeds: _splitField(_mobilityCtrl.text),
      communicationNeeds: _splitField(_communicationCtrl.text),
      emergencyNotes: _notesCtrl.text.trim(),
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.instance.lowBattery;
    final bg = isDark ? Colors.black : Colors.white;
    final surfaceColor =
        isDark ? TogetherTheme.amoledSurface : const Color(0xFFF8F5EE);
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final labelColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;
    final borderColor =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFD1D5DB);

    final fieldStyle = InputDecoration(
      filled: true,
      fillColor: isDark ? TogetherTheme.amoledSurfaceElevated : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark
              ? TogetherTheme.amoledTextSecondary
              : TogetherTheme.deepOcean,
          width: 2,
        ),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Container(
      color: bg,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              color: isDark ? TogetherTheme.amoledSurface : surfaceColor,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: labelColor),
                    tooltip: 'Cancel',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit SOS card',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                        fontFamily: 'RobotoSlab',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _save,
                    child: Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? TogetherTheme.amoledTextSecondary
                            : TogetherTheme.deepOcean,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Form ──────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HintBanner(
                        isDark: isDark,
                        text:
                            'Comma-separate multiple values for lists (e.g. Penicillin, Aspirin).',
                      ),
                      const SizedBox(height: 20),
                      _FieldLabel('Blood type', labelColor),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _bloodTypeCtrl,
                        style: TextStyle(color: titleColor),
                        decoration:
                            fieldStyle.copyWith(hintText: 'e.g. O+, AB−'),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('Allergies', labelColor),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _allergiesCtrl,
                        style: TextStyle(color: titleColor),
                        decoration: fieldStyle.copyWith(
                          hintText: 'e.g. Penicillin, Latex',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('Medications', labelColor),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _medicationsCtrl,
                        style: TextStyle(color: titleColor),
                        decoration: fieldStyle.copyWith(
                          hintText: 'e.g. Rescue inhaler, Metformin',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('Mobility needs', labelColor),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _mobilityCtrl,
                        style: TextStyle(color: titleColor),
                        decoration: fieldStyle.copyWith(
                          hintText: 'e.g. Wheelchair, Step-free entrance',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('Communication needs', labelColor),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _communicationCtrl,
                        style: TextStyle(color: titleColor),
                        decoration: fieldStyle.copyWith(
                          hintText: 'e.g. Speak clearly, Sign language',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('Emergency notes', labelColor),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _notesCtrl,
                        style: TextStyle(color: titleColor),
                        decoration: fieldStyle.copyWith(
                          hintText:
                              'Anything first responders should know immediately.',
                        ),
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _save,
                          child: const Text('Save SOS card'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      );
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.isDark, required this.text});

  final bool isDark;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? TogetherTheme.amoledSurfaceElevated
            : const Color(0xFFEAF6F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? TogetherTheme.amoledBorder
              : TogetherTheme.forest.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: isDark
                ? TogetherTheme.amoledTextSecondary
                : TogetherTheme.forest,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.forest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
