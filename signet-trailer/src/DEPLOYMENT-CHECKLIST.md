# Signet Deployment Checklist

## Before First Deployment

### ✅ Social Media Assets (CRITICAL for nice link previews)

Social platforms like Slack, iMessage, Twitter, Facebook, and LinkedIn **require PNG images** - they don't render SVG files in link previews.

**STATUS: ⚠️ REQUIRED**

#### Option 1: Use Browser-Based Generators (Easiest)

1. **OG Image (1200×630):**
   - [ ] Open `create-og-image.html` in your browser
   - [ ] Click "Generate OG Image"
   - [ ] Right-click canvas → "Save Image As..." → `og-image.png`
   - [ ] Move `og-image.png` to `/public` folder

2. **Icons (32×32, 180×180, 152×152):**
   - [ ] Open `create-icons.html` in your browser
   - [ ] Right-click each canvas and save:
     - `favicon.png` (32×32)
     - `apple-touch-icon.png` (180×180)
     - `apple-touch-icon-152x152.png` (152×152)
   - [ ] Move all PNG files to `/public` folder

3. **Optional - Favicon ICO (for legacy browser support):**
   - [ ] Use online converter: https://convertio.co/png-ico/
   - [ ] Upload `favicon.png`
   - [ ] Download as `favicon.ico`
   - [ ] Move to `/public` folder

#### Option 2: Use ImageMagick (If Installed)

```bash
cd public

# OG Image
convert -density 300 og-image.svg -resize 1200x630 og-image.png

# Favicons
convert -density 300 favicon.svg -resize 32x32 favicon.png
convert -density 300 favicon.svg -resize 180x180 apple-touch-icon.png
convert -density 300 favicon.svg -resize 152x152 apple-touch-icon-152x152.png

# ICO (optional)
convert favicon.svg -define icon:auto-resize=16,32,48 favicon.ico
```

#### Verify Files Created:
```bash
ls -lh public/*.png public/*.ico
```

You should see:
- `og-image.png` (1200×630 - around 50-200KB)
- `favicon.png` (32×32 - around 2-5KB)
- `apple-touch-icon.png` (180×180 - around 5-10KB)
- `apple-touch-icon-152x152.png` (152×152 - around 5-10KB)
- `favicon.ico` (multi-size - around 5-15KB) - optional

---

## Build & Deploy

### 1. Install Dependencies (First time only)
```bash
npm install
```

### 2. Build for Production
```bash
npm run build
```

This creates the `dist/` folder with all static files ready for deployment.

### 3. Verify Build Output
```bash
ls -lh dist/
```

Should contain:
- `index.html`
- `assets/` folder with JS and CSS
- `og-image.png` ⚠️ CHECK THIS
- `favicon.png`, `favicon.svg`, `favicon.ico` ⚠️ CHECK THIS
- `apple-touch-icon*.png` ⚠️ CHECK THIS
- `manifest.json`
- `robots.txt`
- `sitemap.xml`
- `404.html`

### 4. Deploy to OpenShift/Nginx
```bash
# Copy to your nginx web root
cp -r dist/* /path/to/nginx/webroot/signet/

# Or use rsync for updates
rsync -av --delete dist/ /path/to/nginx/webroot/signet/
```

### 5. Nginx Configuration
Make sure your nginx config has:
```nginx
server {
    listen 80;
    server_name signet.ing;
    root /path/to/nginx/webroot/signet;
    index index.html;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### 6. Reload Nginx
```bash
nginx -t          # Test config
nginx -s reload   # Reload if OK
```

---

## Post-Deployment Testing

### Test Website Loads
- [ ] Visit https://signet.ing
- [ ] Check animations play correctly
- [ ] Test mobile responsive design
- [ ] Test all navigation links

### Test Social Media Previews (IMPORTANT!)

#### Slack
- [ ] Paste `https://signet.ing` in a Slack channel
- [ ] Verify image shows (should be the OG image with "UNBREAK THE INTERNET")
- [ ] Verify title: "Signet - See What Matters and Why"
- [ ] Verify description appears

#### iMessage
- [ ] Send `https://signet.ing` in iMessage
- [ ] Verify rich preview shows with image

#### Twitter Card Validator
- [ ] Go to: https://cards-dev.twitter.com/validator
- [ ] Enter `https://signet.ing`
- [ ] Verify card preview looks correct

#### Facebook Sharing Debugger
- [ ] Go to: https://developers.facebook.com/tools/debug/
- [ ] Enter `https://signet.ing`
- [ ] Click "Scrape Again"
- [ ] Verify preview looks correct

#### LinkedIn Post Inspector
- [ ] Go to: https://www.linkedin.com/post-inspector/
- [ ] Enter `https://signet.ing`
- [ ] Verify preview looks correct

### Browser Tab Icon (Favicon)
- [ ] Check browser tab shows the "S" icon
- [ ] Test in: Chrome, Firefox, Safari, Edge

### Mobile Home Screen (iOS)
- [ ] Open site on iPhone
- [ ] Tap Share → Add to Home Screen
- [ ] Verify icon looks good on home screen

---

## Troubleshooting

### OG Image Not Showing in Social Previews
1. Check file exists: `ls dist/og-image.png`
2. Check file is PNG (not SVG)
3. Clear cache in social platform debugger
4. Facebook: Use "Scrape Again" button
5. Wait 5-10 minutes for caches to clear

### Favicon Not Showing
1. Hard refresh browser (Ctrl+Shift+F5 or Cmd+Shift+R)
2. Clear browser cache
3. Check file exists: `ls dist/favicon.png`
4. Check multiple formats are present (PNG, SVG, ICO)

### Link Preview Shows Wrong Info
1. Clear social media cache (use debugger tools above)
2. Check meta tags in `dist/index.html`
3. Verify OG image URL is absolute: `https://signet.ing/og-image.png`

---

## Quick Commands Reference

```bash
# Development
npm run dev              # Start dev server

# Production Build
npm run build            # Build for production

# Check build output
ls -lh dist/            # List build files
du -sh dist/            # Check total size

# Deploy
rsync -av --delete dist/ /nginx/webroot/signet/  # Sync to server
nginx -t && nginx -s reload                       # Test & reload nginx
```

---

## Contact

Issues with deployment? Check:
1. Browser console (F12) for JavaScript errors
2. Nginx error logs: `tail -f /var/log/nginx/error.log`
3. Browser network tab (F12 → Network) for failed requests

All metadata is already configured in `index.html` ✅
All you need to do is create the PNG assets! 🎨
