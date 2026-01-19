const express = require('express');
const cors = require('cors');
const path = require('path');
const multer = require('multer');
const fs = require('fs');
const sharp = require('sharp');
const { CognitoIdentityProviderClient, InitiateAuthCommand } = require('@aws-sdk/client-cognito-identity-provider');
require('dotenv').config();

// Configure multer for file uploads (100MB limit, will resize before upload)
const upload = multer({ 
  dest: '/tmp/meural-uploads/',
  limits: { fileSize: 100 * 1024 * 1024 } // 100MB max per file (will resize)
});

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const MEURAL_API = 'https://api.meural.com/v0';
const COGNITO_CLIENT_ID = '487bd4kvb1fnop6mbgk8gu5ibf';
const COGNITO_REGION = 'eu-west-1';

let authToken = null;
let tokenExpiry = null;

// Auth helper using AWS Cognito (Meural auth method)
async function getToken() {
  if (authToken && tokenExpiry && Date.now() < tokenExpiry) {
    return authToken;
  }
  
  const username = process.env.MEURAL_USERNAME;
  // Read password from file to handle special chars like #
  let password = process.env.MEURAL_PASSWORD;
  try {
    const pwFile = path.join(__dirname, '.meural-password');
    if (fs.existsSync(pwFile)) {
      password = fs.readFileSync(pwFile, 'utf8').trim();
    }
  } catch (e) {}
  
  if (!username || !password) {
    throw new Error('MEURAL_USERNAME and MEURAL_PASSWORD must be set in .env');
  }
  
  const client = new CognitoIdentityProviderClient({ region: COGNITO_REGION });
  
  const command = new InitiateAuthCommand({
    ClientId: COGNITO_CLIENT_ID,
    AuthFlow: 'USER_PASSWORD_AUTH',
    AuthParameters: {
      USERNAME: username,
      PASSWORD: password,
    },
  });
  
  const response = await client.send(command);
  
  if (!response.AuthenticationResult?.AccessToken) {
    throw new Error('Authentication failed: ' + JSON.stringify(response));
  }
  
  authToken = response.AuthenticationResult.AccessToken;
  tokenExpiry = Date.now() + 3600000; // 1 hour
  return authToken;
}

// Meural API proxy
async function meuralRequest(method, path, body = null) {
  const token = await getToken();
  const opts = {
    method,
    headers: {
      'Authorization': `Token ${token}`,
      'Content-Type': 'application/json'
    }
  };
  if (body) opts.body = JSON.stringify(body);
  
  const res = await fetch(`${MEURAL_API}${path}`, opts);
  return res.json();
}

// === API Routes ===

// Get user info (includes storage)
app.get('/api/user', async (req, res) => {
  try {
    const data = await meuralRequest('GET', '/user');
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get all user items (photos) with pagination
app.get('/api/items', async (req, res) => {
  try {
    const page = req.query.page || 1;
    const count = req.query.count || 100;
    const data = await meuralRequest('GET', `/user/items?page=${page}&count=${count}`);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Upload items (photos)
app.post('/api/items/upload', upload.array('photos', 50), async (req, res) => {
  try {
    const token = await getToken();
    const results = [];
    
    for (const file of req.files) {
      try {
        // Read file
        let fileBuffer = fs.readFileSync(file.path);
        
        // Resize if needed (over 20MB)
        const resizeResult = await resizeIfNeeded(fileBuffer, file.originalname);
        fileBuffer = resizeResult.buffer;
        
        // Create proper form data for upload
        const mimeType = resizeResult.resized ? 'image/jpeg' : file.mimetype;
        const blob = new Blob([fileBuffer], { type: mimeType });
        const form = new FormData();
        form.append('image', blob, file.originalname);
        
        const response = await fetch(`${MEURAL_API}/items`, {
          method: 'POST',
          headers: {
            'Authorization': `Token ${token}`,
          },
          body: form
        });
        
        const data = await response.json();
        
        results.push({ 
          filename: file.originalname, 
          success: response.ok, 
          meural_id: response.ok ? data.data?.id : null,
          data: response.ok ? data : null,
          resized: resizeResult.resized ? {
            from: `${(resizeResult.originalSize / 1024 / 1024).toFixed(1)}MB`,
            to: `${(resizeResult.newSize / 1024 / 1024).toFixed(1)}MB`,
            dimensions: resizeResult.dimensions
          } : null,
          error: response.ok ? null : data
        });
        
        // Clean up temp file
        fs.unlinkSync(file.path);
      } catch (err) {
        results.push({ 
          filename: file.originalname, 
          success: false, 
          error: err.message 
        });
        // Clean up temp file on error too
        try { fs.unlinkSync(file.path); } catch (e) {}
      }
    }
    
    res.json({ results });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete an item
app.delete('/api/items/:id', async (req, res) => {
  try {
    const data = await meuralRequest('DELETE', `/items/${req.params.id}`);
    res.json({ success: true, data });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Bulk delete items
app.post('/api/items/bulk-delete', async (req, res) => {
  try {
    const { ids } = req.body;
    const results = [];
    for (const id of ids) {
      try {
        await meuralRequest('DELETE', `/items/${id}`);
        results.push({ id, success: true });
      } catch (err) {
        results.push({ id, success: false, error: err.message });
      }
    }
    res.json({ results });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Update item metadata (name, description, etc.)
app.put('/api/items/:id', async (req, res) => {
  try {
    const data = await meuralRequest('PUT', `/items/${req.params.id}`, req.body);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get all galleries (playlists)
app.get('/api/galleries', async (req, res) => {
  try {
    const data = await meuralRequest('GET', '/user/galleries');
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get items in a gallery
app.get('/api/galleries/:id/items', async (req, res) => {
  try {
    const page = req.query.page || 1;
    const count = req.query.count || 100;
    const data = await meuralRequest('GET', `/galleries/${req.params.id}/items?page=${page}&count=${count}`);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Create a gallery
app.post('/api/galleries', async (req, res) => {
  try {
    const data = await meuralRequest('POST', '/galleries', req.body);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Update a gallery
app.put('/api/galleries/:id', async (req, res) => {
  try {
    const data = await meuralRequest('PUT', `/galleries/${req.params.id}`, req.body);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete a gallery
app.delete('/api/galleries/:id', async (req, res) => {
  try {
    const data = await meuralRequest('DELETE', `/galleries/${req.params.id}`);
    res.json({ success: true, data });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Add item to gallery
app.post('/api/galleries/:galleryId/items/:itemId', async (req, res) => {
  try {
    const data = await meuralRequest('POST', `/galleries/${req.params.galleryId}/items/${req.params.itemId}`);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Remove item from gallery
app.delete('/api/galleries/:galleryId/items/:itemId', async (req, res) => {
  try {
    const data = await meuralRequest('DELETE', `/galleries/${req.params.galleryId}/items/${req.params.itemId}`);
    res.json({ success: true, data });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get all devices (frames)
app.get('/api/devices', async (req, res) => {
  try {
    const data = await meuralRequest('GET', '/user/devices');
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Assign gallery to device
app.post('/api/devices/:deviceId/galleries/:galleryId', async (req, res) => {
  try {
    const data = await meuralRequest('POST', `/devices/${req.params.deviceId}/galleries/${req.params.galleryId}`);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get device galleries
app.get('/api/devices/:id/galleries', async (req, res) => {
  try {
    const data = await meuralRequest('GET', `/devices/${req.params.id}/galleries`);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Resize image if too large for Meural (20MB limit)
async function resizeIfNeeded(fileBuffer, filename) {
  const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20MB
  const MAX_DIMENSION = 3000; // Max pixels on long edge
  const QUALITY = 90;
  
  // If file is small enough, return as-is
  if (fileBuffer.length <= MAX_FILE_SIZE) {
    return { buffer: fileBuffer, resized: false };
  }
  
  console.log(`Resizing ${filename}: ${(fileBuffer.length / 1024 / 1024).toFixed(1)}MB exceeds 20MB limit`);
  
  try {
    // Get image metadata
    const metadata = await sharp(fileBuffer).metadata();
    
    // Calculate new dimensions (maintain aspect ratio)
    let width = metadata.width;
    let height = metadata.height;
    
    if (width > height && width > MAX_DIMENSION) {
      height = Math.round(height * (MAX_DIMENSION / width));
      width = MAX_DIMENSION;
    } else if (height > MAX_DIMENSION) {
      width = Math.round(width * (MAX_DIMENSION / height));
      height = MAX_DIMENSION;
    }
    
    // Resize and compress
    const resizedBuffer = await sharp(fileBuffer)
      .resize(width, height, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: QUALITY, mozjpeg: true })
      .toBuffer();
    
    console.log(`Resized ${filename}: ${(fileBuffer.length / 1024 / 1024).toFixed(1)}MB → ${(resizedBuffer.length / 1024 / 1024).toFixed(1)}MB (${width}x${height})`);
    
    return { 
      buffer: resizedBuffer, 
      resized: true,
      originalSize: fileBuffer.length,
      newSize: resizedBuffer.length,
      dimensions: { width, height }
    };
  } catch (err) {
    console.error(`Failed to resize ${filename}:`, err.message);
    // Return original if resize fails
    return { buffer: fileBuffer, resized: false, error: err.message };
  }
}

const PORT = process.env.PORT || 3333;
app.listen(PORT, () => {
  console.log(`Meural Manager running at http://localhost:${PORT}`);
});
