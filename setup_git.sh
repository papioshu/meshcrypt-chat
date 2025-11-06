#!/bin/bash

# MeshCrypt Chat - Git Setup Script
echo "🚀 Setting up Git repository for MeshCrypt Chat..."

# Navigate to project directory
cd "$(dirname "$0")"

# Initialize git
echo "📦 Initializing Git repository..."
git init

# Add all files
echo "📁 Adding all files to repository..."
git add .

# Create initial commit
echo "💾 Creating initial commit..."
git commit -m "Initial commit: MeshCrypt Chat - Privacy-first encrypted mesh messaging app

Features:
- End-to-end encryption with X25519 + AES-256-GCM
- Multi-transport support (BLE, LoRa, libp2p)
- Terminal-style UI with blinking cursor
- SQLCipher encrypted local storage
- F-Droid ready for distribution
- GPL-3.0 licensed

Copyright (c) 2025 Tevin"

# Set main branch
echo "🌟 Setting main branch..."
git branch -M main

echo "✅ Git repository ready!"
echo ""
echo "Next steps:"
echo "1. Create a repository on GitHub"
echo "2. Copy the repository URL"
echo "3. Run: git remote add origin https://github.com/YOUR_USERNAME/your-repo-name.git"
echo "4. Run: git push -u origin main"
echo ""
echo "Or manually add remote and push using GitHub CLI:"
echo "gh repo create meshcrypt-chat --public --source=. --push"