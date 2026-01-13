# Meural Manager

A simple web interface to manage your Meural frames — bulk delete photos, create playlists, assign playlists to frames.

## Setup

1. Copy `.env.example` to `.env` and add your Meural credentials:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your Meural account email and password (same as the app).

3. Install dependencies and start:
   ```bash
   npm install
   npm start
   ```

4. Open http://localhost:3333 in your browser.

## Features

### Photos Tab
- View all your photos in a grid
- See count vs. 700 limit (with warning colors)
- Multi-select photos (click to toggle, Select All/None buttons)
- Bulk delete selected photos
- Add selected photos to a playlist

### Playlists Tab
- View all playlists
- Create new playlists
- View items in a playlist
- Remove items from a playlist
- Delete playlists

### Frames Tab
- View all 4 frames
- See online/offline status
- Assign a playlist to each frame

## Tech

- Backend: Express.js wrapping the Meural REST API
- Frontend: Vanilla HTML/CSS/JS (no build step)
- Runs on Mac mini, accessible from any device on your network

## Notes

- The 700 photo limit is enforced by Meural, not this app
- Deleting a photo removes it from all playlists automatically
- Auth token is cached for 1 hour
