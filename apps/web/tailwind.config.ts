import type { Config } from 'tailwindcss'

export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        hypo: {
          green: '#22c55e',
          blue: '#3b82f6',
          yellow: '#eab308',
          purple: '#a855f7',
          red: '#ef4444',
          gray: '#6b7280',
        },
      },
    },
  },
  plugins: [],
} satisfies Config
