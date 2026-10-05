import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
import { defineConfig, type Plugin } from 'vitest/config';

const base = process.env.BASE_PATH ?? '/cipher-penny/';

// GitHub Pages cannot send custom headers, so the CSP ships as a <meta> tag.
// Dev mode is excluded because Vite's HMR client relies on inline scripts.
const CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self'",
  "img-src 'self' data: blob:",
  "connect-src 'self'",
  "worker-src 'self'",
  "manifest-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'none'",
].join('; ');

function cspMeta(): Plugin {
  return {
    name: 'cipher-penny:csp-meta',
    apply: 'build',
    transformIndexHtml() {
      return [
        {
          tag: 'meta',
          attrs: { 'http-equiv': 'Content-Security-Policy', content: CSP },
          injectTo: 'head-prepend',
        },
      ];
    },
  };
}

export default defineConfig({
  base,
  plugins: [
    react(),
    cspMeta(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'script',
      includeAssets: ['icon.svg'],
      manifest: {
        name: 'CipherPenny',
        short_name: 'CipherPenny',
        description: '端到端加密的个人记账应用',
        lang: 'zh-CN',
        start_url: '.',
        scope: '.',
        display: 'standalone',
        background_color: '#0f172a',
        theme_color: '#0f172a',
        icons: [
          { src: 'pwa-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'pwa-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'pwa-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // vite-plugin-pwa 2 no longer implies these for autoUpdate; without them a new
        // deploy sits in "waiting" and users keep the old version indefinitely.
        skipWaiting: true,
        clientsClaim: true,
        cleanupOutdatedCaches: true,
        // Fonts are excluded from precache: the CJK font alone is ~100 slices / 4.5 MB.
        globPatterns: ['**/*.{js,css,html,svg,png,webmanifest}'],
        runtimeCaching: [
          {
            urlPattern: ({ request }) => request.destination === 'font',
            handler: 'CacheFirst',
            options: {
              cacheName: 'fonts',
              expiration: { maxEntries: 200, maxAgeSeconds: 365 * 24 * 60 * 60 },
            },
          },
        ],
      },
    }),
  ],
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
});
