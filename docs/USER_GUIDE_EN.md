# Gap Mesh User Guide for iOS

Welcome to Gap Mesh! This guide will help you get started with the app, even if you're not familiar with technology.

---

## What is Gap Mesh?

Gap Mesh is a **messaging app that works without the internet**. It connects your phone directly to nearby phones using Bluetooth, creating a "mesh network" – like a chain of people passing messages to each other.

### Why Use Gap Mesh?

- ✅ **No internet needed** – Chat when there's no Wi-Fi or mobile data
- ✅ **No phone number required** – Stay anonymous
- ✅ **No accounts** – Just install and start chatting
- ✅ **Private & secure** – Your private messages are encrypted
- ✅ **Works anywhere** – Protests, remote areas, emergencies, or just with friends nearby
- ✅ **Universal app** – Works on iPhone, iPad, and Mac

---

## Getting Started

### Step 1: Install the App

Download Gap Mesh from the **App Store**:

- Search for "Gap Mesh" in the App Store
- Or use this link: [Gap Mesh on App Store](https://apps.apple.com/us/app/bitchat-mesh/id6748219622)

### Step 2: Grant Permissions

When you first open the app, it will ask for some permissions. Here's why each one is needed:

| Permission        | Why It's Needed                                                                                    |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| **Bluetooth**     | To discover and connect with nearby Gap Mesh users                                                 |
| **Location**      | Required by iOS for Bluetooth scanning and location-based channels (we don't track your location!) |
| **Notifications** | To alert you when you receive new messages                                                         |

> 💡 **Privacy Note**: Gap Mesh does NOT track or store your location. Location permission is only required for Bluetooth scanning and optional geohash channels.

### Step 3: Choose Your Nickname

Pick a nickname that others will see when you chat. You can change it anytime!

---

## Two Ways to Chat

Gap Mesh offers two types of chat:

### 🔵 Mesh Chat (Offline Mode)

- Works **without internet**
- Uses **Bluetooth** to connect with nearby devices
- Messages hop from phone to phone (up to 7 hops)
- Best for: Local groups, protests, emergencies, remote areas

**How to use**: Just open the app and start chatting! You'll automatically connect with anyone else running Gap Mesh within Bluetooth range.

### 🟢 Location Channels (Online Mode)

- Requires **internet connection**
- Chat with people in your **geographic area**
- Channels are based on your location (block, neighborhood, city, province, region)
- Best for: Finding people in your area, local community discussions

**How to use**: Tap the location icon to see channels near you. Only a rough location is shared – never your exact GPS coordinates.

---

## Sending Messages

### Public Messages

Just type your message and tap **Send**. Everyone in the current channel will see it.

### Private Messages

To send a private message:

1. **Long press** (or tap and hold) on someone's name in the chat
2. Tap **"Message [name]"**
3. Type your private message

Private messages are **encrypted** using the Noise Protocol – only you and the recipient can read them.

### Sending Images, Voice Notes & Files

Tap the attachment icon (📎) next to the message box to:

- 📷 **Send an image** from your photo library
- 🎤 **Record a voice message** (hold to record)
- 📎 **Send a file**

---

## Finding People

### Who's Nearby?

Tap the **People** icon to see:

- Users connected via Bluetooth (mesh)
- Users in your location channel (online)

### Connection Indicators

Look for icons next to names:

- 🔒 **Lock icon**: Encrypted connection established
- ✓ **Checkmark**: Message delivered
- ✓✓ **Double checkmark**: Message read

---

## Using Commands

Gap Mesh supports IRC-style commands. Type these in the message box:

| Command            | What It Does                       |
| ------------------ | ---------------------------------- |
| `/j #channel`      | Join or create a channel           |
| `/m @name message` | Send a private message             |
| `/w`               | List online users                  |
| `/channels`        | Show all discovered channels       |
| `/block @name`     | Block someone                      |
| `/unblock @name`   | Unblock someone                    |
| `/slap @name`      | Send a playful slap (fun feature!) |
| `/hug @name`       | Send a friendly hug                |
| `/clear`           | Clear chat messages                |

---

## Settings & Customization

Tap the **⚙️ Settings** icon (or the app name/logo) to access:

### Appearance

- **Light Mode**: White background
- **Dark Mode**: Dark background (easier on the eyes)
- **System**: Follows your iPhone's theme

### Privacy Options

- **Tor Network** (Optional): Route internet traffic through Tor for extra privacy
- **Proof of Work**: Adds spam protection to location channels

---

## Safety Features

### 🚨 Emergency Data Wipe

If you need to quickly delete all your data (messages, contacts, settings):

**Triple-tap the app title** (Gap Mesh text at the top)

This instantly erases everything. Use this in emergencies when you need to protect your privacy.

### What Data is Stored?

- Your messages (locally on your device only, in the Keychain)
- Your nickname
- Your encryption keys
- App settings

### What We Never Collect

- ❌ Your real name
- ❌ Your phone number
- ❌ Your Apple ID
- ❌ Your exact location
- ❌ Your messages on any server

---

## Troubleshooting

### "I can't see anyone nearby"

1. Make sure **Bluetooth is turned on** (Settings > Bluetooth)
2. Make sure **Location Services are enabled** (Settings > Privacy > Location Services)
3. Check that Gap Mesh has location permission: Settings > Gap Mesh > Location
4. Check that others near you also have Gap Mesh open
5. Try moving closer to others (Bluetooth range is about 10-30 meters)

### "My messages aren't sending"

1. Check if you see any connected peers (look for the people icon)
2. If using location channels, check your internet connection
3. Try force-closing and reopening the app

### "I'm not receiving notifications"

1. Go to **Settings > Notifications > Gap Mesh**
2. Make sure notifications are enabled
3. Check that "Allow Notifications" is turned on

### "I can't join a channel"

Some channels may be password-protected. Ask the channel owner for the password.

---

## iOS-Specific Tips

### Background App Refresh

For best performance, enable Background App Refresh:

1. Go to **Settings > General > Background App Refresh**
2. Make sure Gap Mesh is enabled

### Low Power Mode

When Low Power Mode is on, background activities may be limited. If you're missing messages, try turning off Low Power Mode.

### iCloud Keychain

Your encryption keys are stored securely in the iOS Keychain. They're never synced to iCloud or any server.

---

## Tips for Best Experience

1. **Keep Bluetooth on** for mesh networking
2. **Allow notifications** to know when messages arrive
3. **Stay within range** – Bluetooth works best within 30 meters
4. **More people = better network** – Each phone extends the mesh range!

---

## Privacy Summary

| Data                     | Collected?                 |
| ------------------------ | -------------------------- |
| Name/Apple ID            | ❌ No                      |
| Phone Number             | ❌ No                      |
| Exact Location           | ❌ No                      |
| Messages (on servers)    | ❌ No                      |
| Rough Location (geohash) | Only for location channels |

Gap Mesh is **open source** – anyone can verify our privacy claims.

---

## Need More Help?

- 📖 **Technical Documentation**: See our GitHub repository
- 🐛 **Report Bugs**: Create an issue on GitHub
- 💬 **Community**: Join our community discussions

---

**Gap Mesh** – _Decentralized • Private • Free_
