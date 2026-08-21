export type Theme = {
  accent: string;
  accentSoft: string;
  text: string;
  textOnAccent: string;
  panel: string;
  panelBorder: string;
  fontFamily: string;
  radius: number;
};

export const defaultTheme: Theme = {
  accent: '#4f7cff',
  accentSoft: 'rgba(79, 124, 255, 0.18)',
  text: '#f4f6fb',
  textOnAccent: '#ffffff',
  panel: 'rgba(16, 20, 32, 0.82)',
  panelBorder: 'rgba(255, 255, 255, 0.14)',
  fontFamily:
    '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Arial, sans-serif',
  radius: 20,
};
