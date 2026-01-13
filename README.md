# Meural Manager 🖼️

A self-hosted web interface for managing your [Meural](https://www.netgear.com/home/digital-art-canvas/meural-canvas/) digital art frames. Finally—bulk operations, playlist management, and EXIF tracking that the official app doesn't provide.

![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Why I Built This

I have four Meural frames around my house displaying family photos. The official app is... fine for casual use, but I kept hitting walls:

- **No bulk delete.** When you're at 650/700 photos and need to make room, deleting one at a time is painful.
- **No easy playlist management.** I wanted seasonal rotations, room-specific collections, curated sets.
- **No EXIF visibility.** These are my photos—I want to know what camera, lens, and settings captured each memory.

So I built this over a weekend. It runs on a Mac mini on my local network, and now managing my Meural library takes minutes instead of hours.

## Features

### 📷 Photo Management
- Grid view of your entire library with sorting and filtering
- **Bulk select and delete** — finally
- Filter by orientation (portrait/landscape), year, camera
- Add photos directly from browser with drag & drop upload
- EXIF extraction on upload (camera, lens, GPS, settings)
- Reverse geocoding for location tagging

### 📋 Playlist Management  
- Create, edit, and delete playlists
- Add/remove photos from playlists
- View playlist contents in a clean grid

### 🖼️ Frame Control
- See all your frames and their online status
- Assign playlists to specific frames
- Quick switching between collections

### 📊 EXIF Library
- Track camera gear usage across your collection
- Filter photos by camera, lens, year, GPS, aperture range
- See which lenses you actually use
- Location data extraction and display

## Quick Start

```bash
# Clone the repo
git clone https://github.com/davemorin/meural-manager.git
cd meural-manager

# Install dependencies
npm install

# Set up your credentials
cp .env.example .env
# Edit .env with your Meural account email
# Create .meural-password with your password (handles special characters)

# Run it
npm start
```

Open `http://localhost:3333` — or access it from any device on your network.

## Configuration

Create a `.env` file:

```env
MEURAL_USERNAME=your@email.com
PORT=3333
```

And a `.meural-password` file with just your password (this handles passwords with special characters like `#`):

```
yourpassword
```

## Tech Stack

- **Backend:** Express.js wrapping the Meural REST API + AWS Cognito auth
- **Frontend:** Vanilla HTML/CSS/JS (no build step, no framework bloat)
- **Database:** SQLite for EXIF metadata storage
- **APIs:** Nominatim (OpenStreetMap) for reverse geocoding

## API Notes

This wraps Meural's private API, which uses AWS Cognito for authentication. The API isn't officially documented, but it's been stable. Key endpoints:

- `GET /user` — account info and storage limits
- `GET /user/items` — your photo library
- `GET /user/galleries` — your playlists
- `GET /user/devices` — your frames
- `POST /items` — upload photos
- `DELETE /items/:id` — delete photos

## Running as a Service (macOS)

If you want this running 24/7 on a Mac mini or similar:

```bash
# Using pm2
npm install -g pm2
pm2 start server.js --name meural-manager
pm2 save
pm2 startup
```

## Known Limitations

- Meural enforces a 700 photo limit—this tool shows you where you are, but can't bypass it
- The Meural API occasionally rate limits; bulk operations include small delays
- No official API documentation means things could break if Netgear changes their backend

## Contributing

Issues and PRs welcome. This scratches my itch, but happy to make it better for others.

## License

MIT — do whatever you want with it.

---

Built with ☕ and mild frustration at the official Meural app.
