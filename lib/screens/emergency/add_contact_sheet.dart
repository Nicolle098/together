import 'package:flutter/material.dart';
import '../../models/emergency_contact.dart';
import '../../services/app_settings_service.dart';
import '../../theme/app_theme.dart';

//manually adding a contact

class AddContactSheet extends StatefulWidget {
  const AddContactSheet({super.key});

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<AddContactSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();

  final _nameCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _priorityCtrl = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _phoneCtrl.dispose();
    _priorityCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final contact = EmergencyContact(
      name: _nameCtrl.text.trim(),
      role: _roleCtrl.text.trim(),
      phoneNumber: _phoneCtrl.text.trim(),
      priorityLabel: _priorityCtrl.text.trim().isEmpty
          ? 'Trusted contact'
          : _priorityCtrl.text.trim(),
    );

    Navigator.of(context).pop(contact);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.instance.lowBattery;
    final bg = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final labelColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;
    final borderColor =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFD1D5DB);

    final fieldDecoration = InputDecoration(
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
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? TogetherTheme.amoledBorder
                      : const Color(0xFFDCE4EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add trusted contact',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: titleColor,
                fontFamily: 'RobotoSlab',
              ),
            ),
            Text(
              'Stored encrypted in the cloud. Only readable on this device.',
              style: TextStyle(fontSize: 13, color: labelColor),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              autofocus: true,
              style: TextStyle(color: titleColor),
              decoration: fieldDecoration.copyWith(labelText: 'Full name *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _roleCtrl,
              style: TextStyle(color: titleColor),
              decoration: fieldDecoration.copyWith(
                labelText: 'Role',
                hintText: 'e.g. Family, Doctor, Caregiver',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              style: TextStyle(color: titleColor),
              decoration:
                  fieldDecoration.copyWith(labelText: 'Phone number *'),
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priorityCtrl,
              style: TextStyle(color: titleColor),
              decoration: fieldDecoration.copyWith(
                labelText: 'Priority label',
                hintText: 'e.g. Call first, Medical support',
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save contact'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
