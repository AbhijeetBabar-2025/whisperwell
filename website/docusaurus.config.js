// @ts-check
// Whisperwell's website, published to GitHub Pages by .github/workflows/pages.yml.
// App Store Connect links to /support and /privacy: keep those paths.
const {themes: prismThemes} = require('prism-react-renderer');

const repo = 'https://github.com/AbhijeetBabar-2025/whisperwell';

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Whisperwell',
  tagline: 'Push-to-talk dictation for macOS. Speech recognition runs on your Mac.',
  favicon: 'img/favicon.svg',

  url: 'https://abhijeetbabar-2025.github.io',
  baseUrl: '/whisperwell/',
  organizationName: 'AbhijeetBabar-2025',
  projectName: 'whisperwell',
  // GitHub Pages serves support.html at /support, the address App Store Connect uses.
  trailingSlash: false,

  onBrokenLinks: 'throw',

  i18n: {defaultLocale: 'en', locales: ['en']},

  // Home-screen icon for iOS and a PNG favicon for browsers without SVG favicon support.
  headTags: [
    {tagName: 'link', attributes: {rel: 'apple-touch-icon', href: '/whisperwell/img/icon.png'}},
    {tagName: 'link', attributes: {rel: 'alternate icon', type: 'image/png', href: '/whisperwell/img/icon.png'}},
  ],

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: './sidebars.js',
          editUrl: `${repo}/edit/main/website/`,
        },
        blog: false,
        theme: {customCss: './src/css/custom.css'},
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/01-speak.jpg',
      colorMode: {respectPrefersColorScheme: true},
      navbar: {
        title: 'Whisperwell',
        logo: {alt: 'Whisperwell logo', src: 'img/logo.svg', srcDark: 'img/logo-dark.svg', width: 32, height: 32},
        items: [
          {type: 'docSidebar', sidebarId: 'guide', position: 'left', label: 'Docs'},
          {to: '/support', label: 'Support', position: 'left'},
          {to: '/privacy', label: 'Privacy', position: 'left'},
          {href: repo, position: 'right', className: 'header-github-link', 'aria-label': 'GitHub repository'},
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              {label: 'Getting started', to: '/docs/getting-started'},
              {label: 'Configuration', to: '/docs/configuration'},
              {label: 'Local AI', to: '/docs/local-ai'},
            ],
          },
          {
            title: 'Help',
            items: [
              {label: 'Support', to: '/support'},
              {label: 'Privacy policy', to: '/privacy'},
              {label: 'Report an issue', href: `${repo}/issues`},
            ],
          },
          {
            title: 'Source',
            items: [{label: 'GitHub', href: repo}],
          },
        ],
        logo: {alt: 'Whisperwell logo', src: 'img/logo-dark.svg', width: 44, height: 44, href: '/'},
        copyright:
          'Whisperwell: push-to-talk dictation for macOS. Brand logos are trademarks of their owners and appear only to show compatibility.',
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['bash', 'json'],
      },
    }),
};

module.exports = config;
