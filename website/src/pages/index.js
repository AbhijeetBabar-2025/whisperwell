import React from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import styles from './index.module.css';

const repo = 'https://github.com/AbhijeetBabar-2025/whisperwell';

function Hero() {
  return (
    <header className={styles.hero}>
      <div className={styles.heroInner}>
        <div className={styles.heroText}>
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

function Gallery() {
  return (
    <section className={styles.gallery}>
      <figure className={styles.wide}>
        <img
          src={useBaseUrl('/img/02-meant.jpg')}
          width="1600"
          height="1000"
          loading="lazy"
          alt="Smart cleanup: spoken text full of filler words and corrections becomes a clean, punctuated sentence."
        />
        <figcaption>Filler words go, corrections stick, and punctuation is added for you.</figcaption>
      </figure>
      <div className={styles.pair}>
        <figure>
          <img
            src={useBaseUrl('/img/03-private.jpg')}
            width="1600"
            height="1000"
            loading="lazy"
            alt="Private by default: on-device speech recognition, bring your own AI, works offline, respects password fields."
          />
          <figcaption>Speech recognition runs on your Mac. Nothing goes to the developer.</figcaption>
        </figure>
        <figure>
          <img
            src={useBaseUrl('/img/04-menubar.jpg')}
            width="1600"
            height="1000"
            loading="lazy"
            alt="The Whisperwell menu bar menu, showing the speech and cleanup models are ready."
          />
          <figcaption>It lives in the menu bar and shows which models are ready.</figcaption>
        </figure>
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
        <Steps />
        <Gallery />
        <Requirements />
      </main>
    </Layout>
  );
}
