import { defineConfig } from 'astro/config';

// Served at https://fireplace.ignorelist.com/welcome/ (nginx alias → ~/fireplace/landing-build/)
export default defineConfig({
  base: '/welcome',
  outDir: 'dist',
  build: { assets: 'assets' },
});
