import { defineConfig } from 'vitepress'

// GitHub Pages serves a project site under /<repo>/. Override with DOCS_BASE=/ for a custom domain.
const base = process.env.DOCS_BASE ?? '/ScaleBar/'
const repo = 'https://github.com/javedh-dev/ScaleBar'

export default defineConfig({
  title: 'ScaleBar',
  description: 'Sharp HiDPI scaling, brightness and volume for external monitors on a Mac. Free, native, open source.',
  base,
  cleanUrls: true,
  lastUpdated: true,
  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: `${base}logo.svg` }]],
  themeConfig: {
    logo: '/logo.svg',
    nav: [
      { text: 'Install', link: '/install' },
      { text: 'FAQ', link: '/faq' },
      { text: 'Development', link: '/development' },
      { text: 'Download', link: `${repo}/releases/latest` },
    ],
    sidebar: [{ text: 'ScaleBar', items: [
      { text: 'Install', link: '/install' },
      { text: 'What works where', link: '/compatibility' },
      { text: 'FAQ', link: '/faq' },
      { text: 'Development', link: '/development' },
      { text: 'Privacy policy', link: '/privacy' },
    ] }],
    socialLinks: [{ icon: 'github', link: repo }],
    search: { provider: 'local' },
    editLink: { pattern: `${repo}/edit/main/docs/:path`, text: 'Edit this page' },
    footer: { message: `Released under the MIT License. <a href="${base}privacy">Privacy policy</a>.`, copyright: 'ScaleBar' },
  },
})
