// @ts-check
import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

/**
 * A static site: every page is rendered at build time and served as files, so
 * there is no server code to run or secure. The canonical address is set so
 * absolute links, such as the social preview image, point at the real domain.
 */
export default defineConfig({
  site: 'https://typoless.app',
  output: 'static',
  trailingSlash: 'never',
  build: {
    format: 'file',
  },
  vite: {
    plugins: [tailwindcss()],
  },
});
