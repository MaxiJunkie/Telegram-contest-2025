# Telegram iOS Contest 2025 — Submission

This repository is based on the official `Telegram-iOS` project and contains my contest implementation.

## Task 1 — The tab bar

**Requirement**  
Omit background blur behind the bar itself, while preserving the glass lenses’ ability to blur the bar’s own content.

**Solution**  
Implemented a Metal-based glass renderer that:
- does **not** blur content *behind* the tab bar,
- keeps the glass lenses physically consistent by blurring **only the tab bar’s own content**,
- preserves smooth animations and a stable, clean “liquid glass” look.

A short demo video is included below.

---

## Task 2 — Buttons

**Requirement**  
This includes attach menu icon, voice and video message recording buttons, etc.

**Solution**  
Implemented the same Metal glass pipeline for interactive buttons:
- the glass effect is applied **only within the moving/active glass element**, avoiding unwanted blur around it,
- visuals remain consistent across different button states and sizes,
- tuned for smoothness and performance.

A short demo video is included below.

---

## Demo

- Task 1: <https://github.com/user-attachments/assets/e9c95aad-4974-47a8-a14d-d91de70728f1>
---

## Build notes

The app is buildable from a clean clone on a fresh macOS installation with Xcode and iOS Platform Support installed, following the standard upstream build flow.
