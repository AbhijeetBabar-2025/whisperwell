import React from 'react';

/**
 * A brand mark from Simple Icons (CC0 artwork; the brands are trademarks of their owners).
 * Drawn in currentColor so a row of logos reads as one calm set in light and dark mode.
 */
export default function BrandLogo({icon, size = 28, className}) {
  return (
    <svg
      className={className}
      role="img"
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="currentColor"
      aria-label={icon.title}>
      <title>{icon.title}</title>
      <path d={icon.path} />
    </svg>
  );
}
