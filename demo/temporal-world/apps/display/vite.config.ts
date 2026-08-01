import { defineConfig } from 'vite';
import path from 'path';

// Read shared config at Vite eval time (runs in Node, not browser)
const API_PORT = Number(process.env.FUMIRA_API_PORT || '3210');
const VITE_PORT = Number(process.env.FUMIRA_VITE_PORT || '5173');

export default defineConfig({
  resolve: {
    alias: {
      '@fumira/contracts': path.resolve(__dirname, '../../packages/contracts/src'),
      '@fumira/clay-builders': path.resolve(__dirname, '../../packages/clay-builders/src'),
      '@fumira/scene-runtime': path.resolve(__dirname, '../../packages/scene-runtime/src'),
    },
  },
  server: {
    port: VITE_PORT,
    proxy: {
      '/api': `http://localhost:${API_PORT}`,
      '/ws': {
        target: `ws://localhost:${API_PORT}`,
        ws: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks(id) {
          // three.js core (~500KB minified)
          if (id.includes('node_modules/three/build/')) {
            return 'three-core';
          }
          // three.js addon controls
          if (id.includes('node_modules/three/examples/')) {
            return 'three-addons';
          }
          // scene-runtime + clay-builders (diorama engine)
          if (
            id.includes('packages/scene-runtime/') ||
            id.includes('packages/clay-builders/')
          ) {
            return 'diorama';
          }
        },
      },
    },
    chunkSizeWarningLimit: 300, // warn if any chunk > 300KB
  },
});
