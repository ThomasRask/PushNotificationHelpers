# PushNotificationHelpers

A lightweight Delphi helper unit for sending push notifications via:

- **Apple Push Notification Service (APNS)** using HTTP/2 + JWT
- **Firebase Cloud Messaging (FCM)** using HTTPv1 + JWT

## 📦 Features

- Written in pure Delphi
- Uses `System.Net.HttpClient` (no 3rd party dependencies)
- JWT generation with [Grijjy JOSE](https://github.com/grijjy/DelphiJOSE-JWT)
- Supports custom payloads
- Works with sandbox and production

## 📂 Structure

- `src/APNS.Helper.pas` – Apple Push Notification Service (HTTP/2 + JWT)
- `src/FCM.Helper.pas` – Firebase Cloud Messaging (HTTPv1 + JWT)
- `examples/` – Minimal usage demos for each helper

## 🚀 Requirements

- Delphi 12.0 or later (required for native HTTP/2 support via THTTPClient)
- Grijjy JOSE library: [https://github.com/grijjy/DelphiJOSE-JWT](https://github.com/grijjy/DelphiJOSE-JWT)

## ✅ Example

See the `examples/` folder for quick usage.

## 📄 License

MIT – see LICENSE
