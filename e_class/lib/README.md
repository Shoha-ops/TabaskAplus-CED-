# `lib` structure

## Entry point

- `main.dart` starts Firebase, builds the theme and decides whether to show auth or the main app

## Screens

- `screens/auth/` login flow and auth gate
- `screens/main/` main student dashboard with tabs
- `screens/messages/` compose message flow
- `screens/settings/` appearance and theme setup

## Shared code

- `services/` Firebase, auth and app integrations
- `models/` simple data models used by screens and services

## Rule of thumb

- if the file draws UI, keep it under `screens/`
- if the file talks to Firebase, HTTP or anything external, keep it under `services/`
- if a file gets too large, split helpers next to that feature instead of pushing more into `main_screen.dart`
