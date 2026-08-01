export const CONFIG = {
  // Server
  API_PORT: Number(process.env.FUMIRA_API_PORT || '3210'),
  WS_PORT: Number(process.env.FUMIRA_WS_PORT || '3210'), // same as API by default

  // K230 Receiver
  K230_PORT: Number(process.env.FUMIRA_K230_PORT || '19999'),
  K230_HOST: process.env.FUMIRA_K230_HOST || 'localhost',

  // Vite Dev Server (for display client)
  VITE_PORT: Number(process.env.FUMIRA_VITE_PORT || '5173'),

  // Paths
  ASSET_DIR: process.env.FUMIRA_ASSET_DIR || './assets',
  PUBLIC_DIR: './public',

  // URLs (derived)
  get API_URL() { return `http://localhost:${this.API_PORT}`; },
  get WS_URL() { return `ws://localhost:${this.API_PORT}/ws`; },
  get K230_URL() { return `http://${this.K230_HOST}:${this.K230_PORT}`; },
} as const;
