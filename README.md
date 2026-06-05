# Iris

<table align="center">
  <tr>
    <td valign="bottom">
      <img src="assets/img/Iris_female.png" height="500">
    </td>
    <td valign="bottom">
      <img height="500" alt="irischat" src="https://github.com/user-attachments/assets/12613655-da36-4206-b3f9-322fd2ede6d1" />
    </td>
    <td valign="bottom">
      <img src="assets/img/Iris_Hi.png" height="500"" alt="Iris">
    </td>
  </tr>
</table>

<p align="center"><strong>Iris</strong></p>

# 🌟 Iris - Offline Language Learning App

A pure Flutter project for language learning powered by Large Language Models (LLM), using Google's **Gemma 4** on-device model for completely offline capabilities.

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-green.svg?style=flat)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 📌 Introduction

> ⚠️ **Network Notice for Chinese Mainland Users:**
> Due to network restrictions and unstable connections for large file downloads, the automatic network download feature has not been fully tested. 
> 
> **Currently, only local file model loading is officially supported.** Please download the required models manually using the links below.

### 🤖 Model Downloads
It is highly recommended to download **both** models. You can easily switch between them in the app (`My -> Model Configuration`) by importing them from your phone's local storage.

| Model Name | Description & Performance | Download Link |
| :--- | :--- | :--- |
| **Gemma-4-E2B** | Faster response, but some complex functions may not work perfectly. | [🔗 HuggingFace](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) |
| **Gemma-4-E4B** | Higher accuracy and better capabilities, but slightly slower. | [🔗 HuggingFace](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) |

### 📖 Dictionary Support
* The app comes integrated with the **Jmdict** Japanese dictionary (located in the `assets` directory).
* If you are building the project locally and want the latest version, you can download it from [JMdictSQLite](https://github.com/seanmcbroom/JMdictSQLite).

---

## 🚀 Usage & Installation

> [!WARNING]
> **Hardware Requirements:** > Please ensure your Android device has a functioning GPU. Low-end processors (e.g., older Snapdragon chips) may cause **Memory Overflow (OOM)**, causing the app to crash during model activation.

### 1. Direct Install (Recommended)
Download and install the latest compiled APK directly from the release page:
👉 [**Download Latest Release (ARM64-v8a)**](https://github.com/unrealcjt/Iris/releases/latest/download/app-arm64-v8a-release.apk)

### 2. Setup Guide
1. Download the preferred Gemma 4 model (`.litertlm`) to your phone's local storage.
2. Open the app, navigate to **My -> Model Configuration (我的 -> 模型配置)**, and import the downloaded model.
3. Restart the app, or tap the **Mascot** icon at the bottom of the home page to manually activate the model in Chat mode.

