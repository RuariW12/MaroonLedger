import { useState, useEffect, useCallback } from 'react';

const STORAGE_KEY = 'ml.theme';

// Reading the stored theme can throw outright in a private window or with site
// data blocked, so every access is guarded and falls back to the OS setting.
function storedTheme() {
  try {
    const value = localStorage.getItem(STORAGE_KEY);
    return value === 'light' || value === 'dark' ? value : null;
  } catch {
    return null;
  }
}

function systemTheme() {
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function initialTheme() {
  return storedTheme() ?? systemTheme();
}

// Stamped on <html>. The stylesheet defines dark twice -- once under
// prefers-color-scheme for viewers who never touch the toggle, and once under
// [data-theme="dark"] so an explicit choice wins in both directions.
function apply(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  document.documentElement.style.colorScheme = theme;
}

export function useTheme() {
  const [theme, setTheme] = useState(initialTheme);

  useEffect(() => {
    apply(theme);
    try {
      localStorage.setItem(STORAGE_KEY, theme);
    } catch {
      // Non-fatal: the theme still applies for this session.
    }
  }, [theme]);

  // Follow the OS only while the viewer has not expressed a preference of
  // their own -- otherwise changing the system theme would silently override
  // an explicit choice.
  useEffect(() => {
    if (storedTheme()) return;

    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = (e) => setTheme(e.matches ? 'dark' : 'light');
    media.addEventListener('change', onChange);
    return () => media.removeEventListener('change', onChange);
  }, []);

  const toggle = useCallback(() => {
    setTheme((current) => (current === 'dark' ? 'light' : 'dark'));
  }, []);

  return { theme, toggle };
}
