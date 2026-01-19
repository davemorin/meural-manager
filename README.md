# Meural Manager 🖼️

A self-hosted web interface for managing your [Meural](https://www.netgear.com/home/digital-art-canvas/meural-canvas/) digital art frames. Bulk operations, playlist management, and frame control that the official app doesn't provide.

## Features

### 📷 Photo Management
- Grid view of your entire library with sorting and filtering
- **Bulk select and delete** — finally
- Filter by orientation (portrait/landscape) and year
- Add photos directly from browser with drag & drop upload
- Automatic resizing for photos over 20MB

### 📋 Playlist Management  
- Create, edit, and delete playlists
- Add/remove photos from playlists
- View playlist contents in a clean grid

### 🖼️ Frame Control
- See all your frames and their online status
- Assign playlists to specific frames
- Quick switching between collections

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
# Create .meural-password with your password

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
- **Image Processing:** Sharp for automatic resizing

## API Notes

This wraps Meural's private API, which uses AWS Cognito for authentication. Key endpoints:

- `GET /user` — account info and storage limits
- `GET /user/items` — your photo library
- `GET /user/galleries` — your playlists
- `GET /user/devices` — your frames
- `POST /items` — upload photos
- `DELETE /items/:id` — delete photos

## Running as a Service (macOS)

```bash
# Using pm2
npm install -g pm2
pm2 start server.js --name meural-manager
pm2 save
pm2 startup
```

## Known Limitations

- The Meural API occasionally rate limits; bulk operations include small delays
- No official API documentation means things could break if Netgear changes their backend
- Photos over 20MB are automatically resized to fit Meural's limits

## License

MIT — do whatever you want with it.
