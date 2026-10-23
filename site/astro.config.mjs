import { defineConfig } from 'astro/config';

// Served from GitHub Pages as a project site; drop `base` once a custom domain is set up.
export default defineConfig({
  site: 'https://marcrdgz.github.io',
  base: '/pulse',
  trailingSlash: 'ignore',
});
