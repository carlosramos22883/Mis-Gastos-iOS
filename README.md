# Mis Gastos - iOS

Aplicación móvil nativa de iOS desarrollada en **Swift** con **SwiftUI** para controlar gastos personales.

## Características

- Registro e inicio de sesión con email/contraseña
- Inicio de sesión con Google
- Recuperación de contraseña
- Perfil de usuario
- Persistencia de sesión con Keychain
- Consumo de API REST (Laravel + Sanctum)

## Tecnologías

- **Lenguaje:** Swift 5+
- **UI Framework:** SwiftUI
- **Arquitectura:** MVVM (Model-View-ViewModel)
- **Networking:** URLSession nativo
- **Seguridad:** Keychain para tokens JWT
- **Autenticación:** Laravel Sanctum + Google Sign-In SDK
- **Gestor de dependencias:** Swift Package Manager (SPM)

## Requisitos

- Xcode 15+
- iOS 16.0+
- Cuenta de Apple Developer (para testing en dispositivo físico)
- Backend Laravel corriendo (ver [repositorio del backend](https://github.com/carlosramos22883/mis-gastos))

## Instalación

1. Clona este repositorio:
   ```bash
   git clone https://github.com/carlosramos22883/mis-gastos-ios.git
