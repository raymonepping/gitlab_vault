export default {
  content: ["./index.html", "./src/**/*.{vue,ts}"],
  theme: {
    extend: {
      colors: {
        bg: {
          primary: "#0B0B0C",
          secondary: "#121214",
          tertiary: "#1A1A1D",
        },
        border: "#2A2A2E",
        text: {
          primary: "#F5F5F7",
          secondary: "#A1A1AA",
          muted: "#71717A",
        },
        accent: {
          gold: "#F5B841",
          orange: "#F97316",
          yellow: "#FACC15",
        }
      }
    }
  },
  plugins: []
}