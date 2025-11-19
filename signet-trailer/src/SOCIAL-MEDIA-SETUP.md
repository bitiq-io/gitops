# Social Media Preview Setup for Signet

## Critical Issue: SVG Images Don't Work for Social Previews

Slack, iMessage, Twitter, Facebook, and LinkedIn **do not display SVG images** in link previews. You need PNG or JPG files.

## What You Need to Create

### 1. OG Image (Open Graph - for social media previews)
**File:** `/public/og-image.png`
- **Size:** 1200 × 630 pixels (exact)
- **Format:** PNG or JPG
- **Content:** Same as the current `og-image.svg` design

**How to create it:**

#### Option A: Use Figma (Recommended)
1. Open Figma
2. Create a new frame: 1200 × 630px
3. Design with black background (#000000)
4. Add "UNBREAK THE INTERNET" text (white, Inter 900)
5. Add tagline "See what matters and why. With receipts." (purple)
6. Export as PNG at 2x resolution
7. Save as `/public/og-image.png`

#### Option B: Use Online Tool
1. Go to https://www.canva.com or https://www.photopea.com
2. Create 1200 × 630px canvas
3. Recreate the design from `og-image.svg`
4. Export as PNG
5. Save as `/public/og-image.png`

#### Option C: Convert SVG to PNG via Command Line
```bash
# Install ImageMagick (if not installed)
# macOS: brew install imagemagick
# Ubuntu: sudo apt install imagemagick

# Convert
convert -density 300 -background none public/og-image.svg -resize 1200x630 public/og-image.png
```

### 2. Apple Touch Icons (for iOS home screen)
**Files needed:**
- `/public/apple-touch-icon.png` - 180 × 180 pixels
- `/public/apple-touch-icon-152x152.png` - 152 × 152 pixels

**How to create:**
1. Use the same "S" logo design from `favicon.svg`
2. Create at 180×180px with black background and purple gradient S
3. Export as PNG
4. Resize to create the 152×152 version

### 3. Favicon PNG (for older browsers)
**File:** `/public/favicon.png`
- **Size:** 32 × 32 pixels
- **Format:** PNG with transparency

**Quick creation:**
```bash
# Convert the SVG
convert -density 300 -background none public/favicon.svg -resize 32x32 public/favicon.png
```

### 4. Favicon ICO (for legacy support)
**File:** `/public/favicon.ico`
- Contains multiple sizes: 16×16, 32×32, 48×48
- Optional but recommended for maximum compatibility

**Quick creation:**
```bash
# Create multi-size ICO
convert public/favicon.svg -define icon:auto-resize=16,32,48 public/favicon.ico
```

## After Creating the PNG Files

Once you've created the PNG files, the `index.html` is already configured correctly and will automatically use them. Just make sure:

1. ✅ `/public/og-image.png` exists (1200×630)
2. ✅ `/public/apple-touch-icon.png` exists (180×180)
3. ✅ `/public/favicon.png` exists (32×32)
4. ✅ `/public/favicon.ico` exists (multi-size)

## Testing Your Social Previews

### Slack
1. Paste `https://signet.ing` in a channel
2. Should show the OG image with title and description

### iMessage
1. Send `https://signet.ing` in a message
2. Should show rich preview with image

### Twitter
1. Use Twitter Card Validator: https://cards-dev.twitter.com/validator
2. Enter your URL to preview

### Facebook
1. Use Facebook Sharing Debugger: https://developers.facebook.com/tools/debug/
2. Enter your URL and click "Scrape Again"

### LinkedIn
1. Use LinkedIn Post Inspector: https://www.linkedin.com/post-inspector/
2. Enter your URL to preview

## Current Status

✅ All meta tags properly configured in `index.html`
✅ Proper OG tags (Open Graph)
✅ Twitter Card tags
✅ Structured data (JSON-LD)
✅ Theme colors
✅ Manifest file

❌ Need to create PNG version of OG image
❌ Need to create Apple touch icons
❌ Need to create favicon.png and favicon.ico

## Quick Checklist

- [ ] Create `/public/og-image.png` (1200×630)
- [ ] Create `/public/apple-touch-icon.png` (180×180)
- [ ] Create `/public/favicon.png` (32×32)
- [ ] Create `/public/favicon.ico` (16,32,48 sizes)
- [ ] Delete `/public/favicon.svg.tsx` (replaced by `favicon.svg`)
- [ ] Test in Slack
- [ ] Test in iMessage
- [ ] Test with Facebook Sharing Debugger
- [ ] Test with Twitter Card Validator
