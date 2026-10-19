// @ts-check
// Whisperwell's website, published to GitHub Pages by .github/workflows/pages.yml.
// App Store Connect links to /support and /privacy: keep those paths.
const {themes: prismThemes} = require('prism-react-renderer');

const repo = 'https://github.com/AbhijeetBabar-2025/whisperwell';

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Whisperwell',
  tagline: 'Push-to-talk dictation for macOS. Speech recognition runs on your Mac.',
  favicon: 'img/favicon.png',

  url: 'https://abhijeetbabar-2025.github.io',
  baseUrl: '/whisperwell/',
  organizationName: 'AbhijeetBabar-2025',
  projectName: 'whisperwell',
  // GitHub Pages serves support.html at /support, the address App Store Connect uses.
  trailingSlash: false,

  onBrokenLinks: 'throw',

  i18n: {defaultLocale: 'en', locales: ['en']},

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
        logo: {alt: 'Whisperwell icon', src: 'img/icon.png'},
        items: [
          {type: 'docSidebar', sidebarId: 'guide', position: 'left', label: 'Docs'},
          {to: '/support', label: 'Support', position: 'left'},
          {to: '/privacy', label: 'Privacy', position: 'left'},
          {href: repo, label: 'GitHub', position: 'right'},
        ],
      },
      footer: {
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
        copyright: `Whisperwell. Built with Docusaurus.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['bash', 'json'],
      },
    }),
};

module.exports = config;
