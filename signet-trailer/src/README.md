# Signet Landing Page

A cinematic landing page for Signet featuring a dramatic "UNBREAK THE INTERNET" animation with glitch effects, particle animations, and sequential messaging.

## What This Is

This is a React + TypeScript single-page application built with:
- **React** - UI framework
- **Motion** (formerly Framer Motion) - Animation library
- **Tailwind CSS** - Styling
- **Vite** - Build tool (bundler)

The app is 100% client-side with no backend dependencies, making it perfect for static hosting.

## Prerequisites

You need Node.js installed on your build machine:
- **Node.js** 18 or higher
- **npm** (comes with Node.js)

Check if you have them:
```bash
node --version
npm --version
```

If you don't have Node.js, download it from: https://nodejs.org/

## Building the App

### 1. Get the Files
Download/export all the project files from Figma Make and place them in a folder (e.g., `signet-landing`).

### 2. Install Dependencies
Open a terminal in the project folder and run:
```bash
npm install
```

This downloads all the libraries (React, Motion, Tailwind, etc.) into a `node_modules/` folder. This step only needs to be done once, or when dependencies change.

### 3. Build for Production
Run the build command:
```bash
npm run build
```

This creates a `dist/` folder containing your static files:
```
dist/
├── index.html
├── assets/
│   ├── index-[hash].js
│   ├── index-[hash].css
│   └── ...
├── favicon.svg
├── og-image.png
├── manifest.json
├── robots.txt
├── sitemap.xml
└── 404.html
```

These are the files you'll deploy to nginx.

## Deploying to Nginx on OpenShift

### 1. Copy Built Files
Copy everything from the `dist/` folder to your nginx web root:
```bash
# Example - adjust paths for your setup
cp -r dist/* /path/to/nginx/webroot/signet/
```

### 2. Configure Nginx
Since this is a single-page application (SPA), nginx needs to serve `index.html` for all routes. Add this to your nginx config:

```nginx
server {
    listen 80;
    server_name signet.ing;
    
    root /path/to/nginx/webroot/signet;
    index index.html;
    
    # Custom 404 page
    error_page 404 /404.html;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # Serve 404 page
    location = /404.html {
        internal;
    }
    
    # Optional: Cache static assets
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Optional: Cache other static files
    location ~* \.(svg|png|jpg|jpeg|gif|ico|json|txt|xml)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
```

The important part is `try_files $uri $uri/ /index.html;` - this ensures the React app loads correctly.

### 3. Reload Nginx
After updating the config:
```bash
nginx -t  # Test config
nginx -s reload  # Reload if test passes
```

### 4. Access Your Site
Navigate to your domain - you should see the Signet landing page with the full animation!

## Development Mode (Optional)

If you want to preview changes locally before building:

```bash
npm run dev
```

This starts a development server (usually at `http://localhost:5173`) with hot-reload - changes appear instantly without rebuilding.

## Project Structure

```
/
├── App.tsx                  # Main landing page component
├── index.html               # HTML entry point with SEO meta tags
├── src/
│   └── main.tsx            # React app bootstrapper
├── public/                  # Static assets (copied to dist/)
│   ├── favicon.svg         # Site icon
│   ├── og-image.png        # Social media preview image
│   ├── manifest.json       # PWA manifest
│   ├── robots.txt          # Search engine crawler instructions
│   ├── sitemap.xml         # Site structure for SEO
│   └── 404.html            # Custom error page
├── styles/globals.css       # Global styles and Tailwind config
├── components/
│   ├── figma/              # Figma-specific components
│   └── ui/                 # ShadCN UI components (unused in this project)
├── package.json            # Dependencies and scripts
└── README.md               # This file
```

## Troubleshooting

**Build fails with "command not found":**
- Make sure Node.js and npm are installed
- Try running `npm install` first

**Nginx shows blank page:**
- Check that `index.html` exists in your web root
- Verify the nginx config has `try_files $uri $uri/ /index.html;`
- Check browser console (F12) for errors

**Animations don't play:**
- Ensure all files from `dist/assets/` are copied correctly
- Check browser console for JavaScript errors

**Changes not appearing:**
- After modifying code, you must run `npm run build` again
- Clear browser cache or do a hard refresh (Ctrl+Shift+R)

## Need to Make Changes?

1. Edit the files (mainly `/App.tsx`)
2. Test in dev mode: `npm run dev`
3. Rebuild: `npm run build`
4. Copy new `dist/` files to nginx
5. Hard refresh browser to see changes

## Dependencies

All dependencies are defined in `package.json` and installed via `npm install`. Main libraries:
- `react` - UI framework
- `motion` - Animation library
- `tailwindcss` - CSS framework
- `vite` - Build tool

## License & Credits

Built with Figma Make.
