import React from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import {Cpu, Password, Sparkle, WifiSlash} from '@phosphor-icons/react/dist/ssr';
import {
  siClaude,
  siCursor,
  siDiscord,
  siFigma,
  siFirefoxbrowser,
  siGithub,
  siGmail,
  siGooglechrome,
  siHuggingface,
  siLinear,
  siLmstudio,
  siNotion,
  siObsidian,
  siOllama,
  siSafari,
  siTelegram,
} from 'simple-icons';
import BrandLogo from '@site/src/components/BrandLogo';
import styles from './index.module.css';

const repo = 'https://github.com/AbhijeetBabar-2025/whisperwell';

// Apps people dictate into. Whisperwell works in any app; these are examples.
const apps = [
  siGmail, siNotion, siGooglechrome, siSafari, siFirefoxbrowser, siDiscord,
  siObsidian, siLinear, siGithub, siFigma, siCursor, siTelegram,
];
const models = [siClaude, siOllama, siLmstudio, siHuggingface];

function Hero() {
  return (
    <header className={styles.hero}>
      <div className={styles.heroInner}>
        <div className={styles.heroText}>
          <img className={styles.heroIcon} src={useBaseUrl('/img/icon.png')} width="72" height="72" alt="" />
          <Heading as="h1" className={styles.heroTitle}>
            Dictation that types wherever you work.
          </Heading>
          <p className={styles.heroLead}>
            Hold one key, speak naturally, and let go. Polished text lands at your cursor, in any Mac app.
          </p>
          <div className={styles.heroActions}>
            <Link className={styles.primary} to="/docs/getting-started">
              Get started
            </Link>
            <Link className={styles.secondary} href={repo}>
              <BrandLogo icon={siGithub} size={18} />
              View on GitHub
            </Link>
          </div>
        </div>
        <img
          className={styles.heroShot}
          src={useBaseUrl('/img/01-speak.jpg')}
          width="1600"
          height="1000"
          alt="A Mail message being dictated: the Whisperwell indicator shows Listening while cleaned-up text appears at the cursor."
        />
      </div>
    </header>
  );
}

function AppStrip() {
  // The list is rendered twice so the scroll can loop seamlessly; the copy is hidden from screen readers.
  const row = (hidden) => (
    <ul className={styles.logoRow} aria-hidden={hidden || undefined}>
      {apps.map((icon) => (
        <li key={icon.slug}>
          <BrandLogo icon={icon} size={30} />
          <span>{icon.title}</span>
        </li>
      ))}
    </ul>
  );
  return (
    <section className={styles.strip} aria-labelledby="apps-title">
      <p id="apps-title" className={styles.stripTitle}>
        Types into the apps you already use, and every other one.
      </p>
      <div className={styles.marquee}>
        <div className={styles.marqueeTrack}>
          {row(false)}
          {row(true)}
        </div>
      </div>
    </section>
  );
}

function Steps() {
  return (
    <section className={styles.steps}>
      <Heading as="h2" className={styles.sectionTitle}>
        One key. No windows.
      </Heading>
      <ol className={styles.stepList}>
        <li>
          <kbd className={styles.key}>⌥ option</kbd>
          <span>Hold the key until you hear a soft tink.</span>
        </li>
        <li>
          <span className={styles.stepWord}>Speak</span>
          <span>Talk the way you normally would, ums included.</span>
        </li>
        <li>
          <span className={styles.stepWord}>Let go</span>
          <span>Clean text appears where your cursor is.</span>
        </li>
      </ol>
    </section>
  );
}

function Cleanup() {
  return (
    <section className={styles.cleanup}>
      <figure>
        <img
          src={useBaseUrl('/img/02-meant.jpg')}
          width="1600"
          height="1000"
          loading="lazy"
          alt="Smart cleanup: spoken text full of filler words and corrections becomes a clean, punctuated sentence."
        />
        <figcaption>Filler words go, corrections stick, and punctuation is added for you.</figcaption>
      </figure>
    </section>
  );
}

function Features() {
  return (
    <section className={styles.features}>
      <Heading as="h2" className={styles.sectionTitle}>
        Private by default. Yours to tune.
      </Heading>
      <div className={styles.bento}>
        <article className={`${styles.cell} ${styles.cellDevice}`}>
          <Cpu size={30} weight="duotone" />
          <h3>Speech stays on your Mac</h3>
          <p>Whisper runs on Apple silicon. In on-device mode your audio is never uploaded.</p>
        </article>

        <figure className={`${styles.cell} ${styles.cellShot}`}>
          <img
            src={useBaseUrl('/img/04-menubar.jpg')}
            width="1600"
            height="1000"
            loading="lazy"
            alt="The Whisperwell menu bar menu, showing the speech and cleanup models are ready."
          />
        </figure>

        <article className={`${styles.cell} ${styles.cellOffline}`}>
          <WifiSlash size={30} weight="duotone" />
          <h3>Works offline</h3>
          <p>After a one-time model download, dictation needs no internet connection.</p>
        </article>

        <article className={`${styles.cell} ${styles.cellModels}`}>
          <Sparkle size={30} weight="duotone" />
          <h3>Bring your own AI</h3>
          <p>Clean up text with Claude using your own key, or with a model running on your machine.</p>
          <ul className={styles.modelLogos}>
            {models.map((icon) => (
              <li key={icon.slug}>
                <BrandLogo icon={icon} size={26} />
                <span>{icon.title}</span>
              </li>
            ))}
          </ul>
        </article>

        <article className={`${styles.cell} ${styles.cellSecure}`}>
          <Password size={30} weight="duotone" />
          <h3>Skips password fields</h3>
          <p>It never types into secure fields, and your clipboard comes back after every paste.</p>
        </article>
      </div>
    </section>
  );
}

function Requirements() {
  return (
    <section className={styles.requirements}>
      <div>
        <Heading as="h2" className={styles.sectionTitle}>
          What you need
        </Heading>
        <Link className={styles.primary} to="/docs/getting-started">
          Get started
        </Link>
      </div>
      <dl className={styles.reqList}>
        <div>
          <dt>A Mac with Apple silicon</dt>
          <dd>Running macOS 13 Ventura or later.</dd>
        </div>
        <div>
          <dt>About 600 MB of space</dt>
          <dd>For the Whisper speech model, downloaded once on first launch.</dd>
        </div>
        <div>
          <dt>Three permissions</dt>
          <dd>Microphone, Input Monitoring, and Accessibility. A setup window walks you through them.</dd>
        </div>
        <div>
          <dt>A cleanup model, if you want one</dt>
          <dd>
            Claude with your own API key, or a model running locally. See <Link to="/docs/local-ai">Local AI</Link>.
          </dd>
        </div>
      </dl>
    </section>
  );
}

export default function Home() {
  return (
    <Layout
      title="Push-to-talk dictation for macOS"
      description="Hold a key, speak, and polished text appears wherever you type on your Mac. Speech recognition runs privately on your device.">
      <Hero />
      <main>
        <AppStrip />
        <Steps />
        <Cleanup />
        <Features />
        <Requirements />
      </main>
    </Layout>
  );
}
