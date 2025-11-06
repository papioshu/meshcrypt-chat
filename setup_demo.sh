#!/bin/bash

# 🔐 Terminal Chat Demo Setup Script
# This script sets up and runs the encrypted mesh chat demo

echo "🔐 Setting up Encrypted Mesh Chat Terminal Demo..."
echo "=============================================="

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed. Please install Flutter SDK first:"
    echo "   https://flutter.dev/docs/get-started/install"
    exit 1
fi

# Check Flutter doctor
echo "🔍 Checking Flutter installation..."
flutter doctor

# Navigate to project directory
cd flutter_app

# Install dependencies
echo "📦 Installing dependencies..."
flutter pub get

# Create demo main file
echo "🎭 Setting up demo application..."
if [ -f "lib/main.dart" ]; then
    echo "📁 Backing up original main.dart to main_original.dart"
    mv lib/main.dart lib/main_original.dart
fi

cp lib/main_demo.dart lib/main.dart

echo "✅ Setup complete!"
echo ""
echo "🎯 Demo Features:"
echo "   • Terminal-style UI with blinking cursor"
echo "   • 3 demo contacts with different trust levels"
echo "   • Real-time message simulation"
echo "   • Encrypted messaging demonstration"
echo "   • Connection status indicators"
echo ""
echo "🚀 To run the demo:"
echo "   cd flutter_app"
echo "   flutter run"
echo ""
echo "📱 To build for devices:"
echo "   flutter run --release"
echo ""
echo "🔄 To restore original main.dart:"
echo "   mv lib/main_original.dart lib/main.dart"
echo ""
echo "🎉 Happy coding!"