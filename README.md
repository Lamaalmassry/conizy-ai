<p align="center">
  <img src="assets/logo.png" alt="Conizy AI Logo" width="280" />
</p>

<h1 align="center">Conizy AI</h1>

<p align="center">
  Connect Insights. Act Easy.
</p>

<p align="center">
  Flutter MVP application with onboarding, local persistence, and AI chat integration via AWS Bedrock.
</p>

## Overview

Conizy AI is a Flutter-based MVP focused on a clean user experience and practical AI assistance.  
The app includes onboarding screens, local data/storage support, and backend AI messaging through an AWS Lambda endpoint connected to Amazon Bedrock.

## Features

- Modern onboarding and branded UI flow
- Local persistence using `shared_preferences` and `sqflite`
- AI chat integration through a serverless endpoint
- Cross-platform Flutter project structure (Android, iOS, Web, Desktop)
- Infrastructure-as-code for Bedrock chat backend (`Terraform`)

## Tech Stack

- **Framework:** Flutter (Dart)
- **Local Storage:** `shared_preferences`, `sqflite`
- **Networking:** `http`
- **AI Backend:** AWS Lambda + Amazon Bedrock
- **Infrastructure:** Terraform

## Project Structure

```text
.
├── lib/                    # Main Flutter application code
├── assets/                 # App assets (logo, onboarding images)
├── infra/bedrock-chat/     # Terraform + Lambda for Bedrock chat endpoint
├── android/ ios/ web/      # Platform-specific runners
└── pubspec.yaml            # Flutter dependencies and assets
```

## Getting Started

### 1) Prerequisites

- Flutter SDK (compatible with Dart `>=3.3.0 <4.0.0`)
- A device/emulator or browser target
- (Optional for AI feature) AWS account with Bedrock access

### 2) Install Dependencies

```bash
flutter pub get
```

### 3) Run the App

```bash
flutter run
```

To run on Chrome:

```bash
flutter run -d chrome
```

## AI Backend Setup (AWS Bedrock)

Infrastructure files are under:

- `infra/bedrock-chat/`

Quick deploy:

```bash
cd infra/bedrock-chat
terraform init
terraform apply -auto-approve
```

After deployment, copy `lambda_function_url` and set it in:

- `_ConizyAiService._endpoint` inside `lib/main.dart`

## Development Notes

- Main app entry point: `lib/main.dart`
- Asset configuration is managed in `pubspec.yaml`
- Keep secrets and environment-specific values out of source control

## License

This project is currently private/proprietary unless a separate license is added.
