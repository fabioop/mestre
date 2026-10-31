# Mestre demo video

A product film made with [Remotion](https://www.remotion.dev). The panel is recreated in React from the app's real strings, sizes and theme files (`Sources/MestreCore/Resources/theme-*.json`), so it is not a screen capture and contains only sample data.

```bash
npm install
npm run studio   # preview
npm run render   # v1, the feature tour: writes out/mestre-demo.mp4
npm run render:v1.1 # v1 refined: writes out/mestre-demo-v1.1.mp4
npm run render:v2   # v2, one working day, in 3D: writes out/mestre-demo-v2.mp4
```

Fonts in `public/fonts` are under the SIL Open Font License: Archivo, JetBrains Mono, Nunito. Speed figures come from `docs/development.md`; update them there first.
