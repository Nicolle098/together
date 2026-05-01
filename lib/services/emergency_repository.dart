import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/emergency_contact.dart';
import '../models/medical_profile.dart';

/// Handles all persistence for the Emergency screen:
///
/// - SOS card (medical profile) — stored as plain JSON in Firestore under
///   `users/{uid}` in the named 'users' database. Not encrypted so that
///   first-responders can read it via the UI without additional auth.
///
/// - Manual contacts — stored AES-256-CBC encrypted in Firestore under
///   `users/{uid}/contacts/{id}`. The AES key lives only in
///   FlutterSecureStorage and never leaves the device.
///
/// - Phone contacts — read-only from the device's contact book. Only starred
///   (favourite) contacts are surfaced. No data is written to Firestore.
class EmergencyRepository {
  const EmergencyRepository();

  static const _databaseId = 'users';
  static const _usersCol = 'users';
  static const _contactsCol = 'contacts';
  static const _keyAlias = 'together_contacts_aes_v1';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: _databaseId,
      );

  // ── SOS card ──────────────────────────────────────────────────────────────

  /// Loads the SOS card (medical profile) from Firestore for [uid].
  /// Returns null on network failure or if no data has been saved yet.
  Future<MedicalProfile?> loadSosCard(String uid) async {
    try {
      final doc = await _db
          .collection(_usersCol)
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      final data = doc.data();
      if (data == null || !data.containsKey('sosCard')) return null;
      return _profileFromMap(data['sosCard'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('EmergencyRepository.loadSosCard: $e');
      return null;
    }
  }

  /// Saves the SOS card to Firestore. Merges into the existing user document
  /// so other fields (e.g. FCM token) are not overwritten.
  Future<void> saveSosCard(String uid, MedicalProfile profile) {
    return _db.collection(_usersCol).doc(uid).set(
      {
        'sosCard': _profileToMap(profile),
        'sosCardUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ── Manual contacts (encrypted) ───────────────────────────────────────────

  /// Loads all manually-added contacts for [uid] from Firestore and decrypts
  /// them using the device-local AES key. Returns an empty list on failure.
  Future<List<EmergencyContact>> loadManualContacts(String uid) async {
    try {
      final key = await _getOrCreateKey();
      final snapshot = await _db
          .collection(_usersCol)
          .doc(uid)
          .collection(_contactsCol)
          .orderBy('createdAt', descending: false)
          .get();

      final contacts = <EmergencyContact>[];
      for (final doc in snapshot.docs) {
        final contact = await _decryptContact(doc.id, doc.data(), key);
        if (contact != null) contacts.add(contact);
      }
      return contacts;
    } catch (e) {
      debugPrint('EmergencyRepository.loadManualContacts: $e');
      return const [];
    }
  }

  /// Encrypts [contact] and saves it to Firestore under `users/{uid}/contacts`.
  /// Returns the Firestore document ID assigned to the new contact.
  Future<String> saveContact(String uid, EmergencyContact contact) async {
    final key = await _getOrCreateKey();
    final ref = _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_contactsCol)
        .doc();

    await ref.set({
      'name_enc': await _encryptField(contact.name, key),
      'role_enc': await _encryptField(contact.role, key),
      'phoneNumber_enc': await _encryptField(contact.phoneNumber, key),
      'priorityLabel_enc': await _encryptField(contact.priorityLabel, key),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  /// Deletes a manually-added contact from Firestore.
  Future<void> deleteContact(String uid, String contactId) {
    return _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_contactsCol)
        .doc(contactId)
        .delete();
  }

  // ── Phone contacts ────────────────────────────────────────────────────────

  /// Requests READ_CONTACTS permission and returns the device's starred
  /// (favourite) contacts. Returns an empty list if permission is denied or
  /// if the device exposes no starred contacts.
  Future<List<EmergencyContact>> loadPhoneContacts() async {
    if (kIsWeb) return const [];
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) return const [];

      final all = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      final starred = all.where((c) => c.isStarred).toList();
      return starred.map(_contactFromPhone).toList();
    } catch (e) {
      debugPrint('EmergencyRepository.loadPhoneContacts: $e');
      return const [];
    }
  }

  // ── Encryption internals ──────────────────────────────────────────────────

  // Retrieves existing AES-256 key from secure storage, or generates a new one.
  Future<enc.Key> _getOrCreateKey() async {
    final existing = await _storage.read(key: _keyAlias);
    if (existing != null) {
      return enc.Key.fromBase64(existing);
    }
    final key = enc.Key.fromSecureRandom(32);
    await _storage.write(key: _keyAlias, value: key.base64);
    return key;
  }

  Future<String> _encryptField(String plaintext, enc.Key key) async {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    // Pack iv + ciphertext so both are available on decryption.
    return '${iv.base64}:${encrypted.base64}';
  }

  Future<String> _decryptField(String packed, enc.Key key) async {
    final parts = packed.split(':');
    if (parts.length != 2) return '';
    final iv = enc.IV.fromBase64(parts[0]);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt64(parts[1], iv: iv);
  }

  Future<EmergencyContact?> _decryptContact(
    String docId,
    Map<String, dynamic> data,
    enc.Key key,
  ) async {
    try {
      return EmergencyContact(
        id: docId,
        name: await _decryptField(data['name_enc'] as String, key),
        role: await _decryptField(data['role_enc'] as String, key),
        phoneNumber:
            await _decryptField(data['phoneNumber_enc'] as String, key),
        priorityLabel:
            await _decryptField(data['priorityLabel_enc'] as String, key),
      );
    } catch (e) {
      debugPrint('EmergencyRepository._decryptContact: failed for $docId — $e');
      return null;
    }
  }

  // ── Model mapping ─────────────────────────────────────────────────────────

  Map<String, dynamic> _profileToMap(MedicalProfile p) => {
        'bloodType': p.bloodType,
        'allergies': p.allergies,
        'medications': p.medications,
        'mobilityNeeds': p.mobilityNeeds,
        'communicationNeeds': p.communicationNeeds,
        'emergencyNotes': p.emergencyNotes,
      };

  MedicalProfile _profileFromMap(Map<String, dynamic> m) => MedicalProfile(
        bloodType: (m['bloodType'] as String?) ?? '',
        allergies: _toStringList(m['allergies']),
        medications: _toStringList(m['medications']),
        mobilityNeeds: _toStringList(m['mobilityNeeds']),
        communicationNeeds: _toStringList(m['communicationNeeds']),
        emergencyNotes: (m['emergencyNotes'] as String?) ?? '',
      );

  List<String> _toStringList(dynamic value) {
    if (value is List) return value.cast<String>();
    return const [];
  }

  EmergencyContact _contactFromPhone(Contact c) {
    final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
    return EmergencyContact(
      name: c.displayName,
      role: 'Phone contact',
      phoneNumber: phone,
      priorityLabel: 'Starred',
      isFromPhone: true,
    );
  }
}
