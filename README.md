# AWS Liveness Practice v2.0 (TrollStore/Theos)

Standalone local practice app modeled more closely after the public **AWS Amplify UI Face Liveness for Swift** flow.

## v2 changes

- Rebuilt the start screen around the public Amplify UI structure: **Liveness Check**, readiness tips, photosensitivity warning, **Start video check**.
- Fixed oval challenge instead of generic multi-step KYC movement coaching.
- Public AWS-style prompts/states such as **Move closer**, **Move face to fit in oval**, **Only one face per check**, **Hold still**, **Verifying**, and countdown-related failures.
- Added a 3-2-1 countdown and a full-screen local colored-light sequence (~2 colors/sec).
- Raises iPhone display brightness while the challenge is running, then restores it afterward, matching documented mobile SDK behavior.
- Keeps Live Camera / Photos / Files sample-video inputs.
- Triple-tap during the camera challenge to show local diagnostics.

## Important

This is a **local UX/environment simulator**. It does not call AWS Rekognition, stream a liveness session, perform AWS anti-spoofing, or return a real liveness confidence score. Sample video mode is local-only and is not connected to any verification service.

## Build on WSL Ubuntu

```bash
export THEOS=$HOME/theos
chmod +x build_tipa.sh
./build_tipa.sh
```

Output:

```text
build/AWSLivenessPractice-2.0.tipa
```

GitHub Actions also builds and uploads the TrollStore `.tipa` artifact automatically.
