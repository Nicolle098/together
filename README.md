# Together

A cross-platform emergency communication and safety app built for crisis scenarios — works fully offline, with no internet, no cell signal, and no infrastructure required.

Built for **Hardcore Entrepreneur Hackathon 6.0** 

---

## Demo & Links

- **Demo video**: [youtu.be/YXzLZYoKN9Q](https://youtu.be/YXzLZYoKN9Q)
- **Pitch video**: [youtu.be/ei3Sa_hmpWo](https://youtu.be/ei3Sa_hmpWo)
- **APK**: [Google Drive](https://drive.google.com/file/d/11Cqxz6he8wrqUGDwmQQNAWGp1em9OJw7/view?usp=drive_link)
-**Business-plan_HE-6.0**: [Google Drive](https://docs.google.com/presentation/d/1FO4o9vUIbzRGjnq5Snft6NjMtmF7IcQ8/edit?usp=drive_link&ouid=117266893885648406598&rtpof=true&sd=true)
---

## Features

- **SOS card** — blood type, allergies, medications, readable by first responders without authentication
- **Emergency contacts** — AES-256-CBC encrypted, key stored only in device secure storage
- **Safety map** — offline-first with bundled hospital, shelter, and police station data (OpenStreetMap)
- **Community hazard pins** — user-reported, AI-validated, Firestore-synced with proximity notifications
- **AI assistant** — two-tier: Gemini 2.5 Flash (primary) → HuggingFace fine-tuned Gemma (fallback)
- **Voice call mode** — hands-free STT input, TTS output, surroundings camera mode
- **P2P mesh** — Wi-Fi Direct messaging and SOS broadcast with zero internet
- **Community feed** — live Firestore posts (jobs, courses, events, tips) with offline fallback
- **Accessibility** — AMOLED pure-black theme, high-contrast mode, large text (1.3×), voice guidance

---

## Tech Stack

### Framework & Language

- Flutter 3.x / Dart — Android & iOS

### Backend & Cloud

- Firebase Authentication — email/password + guest mode
- Firebase Firestore — named 'users' database; offline cache enabled
- Firebase Cloud Messaging — push notifications
- Firebase Core

### AI

- Google Gemini 2.5 Flash — streaming chat, image understanding, safety-guide context
- HuggingFace Inference API — fine-tuned Gemma fallback (`minico72/together-ai-gemma`)

### Offline & P2P

- `nearby_service` — Wi-Fi Direct peer-to-peer mesh, no router or internet required
- `flutter_map` + OpenStreetMap — fully offline tile cache
- `shared_preferences` + local JSON cache — settings and hazard pin persistence

### Device

- `flutter_tts` — text-to-speech throughout the app
- `speech_to_text` — voice input for assistant and emergency screen
- `camera` — surroundings mode in the voice call screen
- `flutter_secure_storage` — AES key storage
- `flutter_contacts` — read starred device contacts

### Security

- `encrypt` package — AES-256-CBC for contact data; IV randomized per field

---

## Getting Started

1. Clone the repo
2. Copy `lib/config/api_keys.example.dart` to `lib/config/api_keys.dart` and fill in your keys
3. Add your `google-services.json` (Android) 
4. Run `flutter pub get`
5. Run `flutter run`
