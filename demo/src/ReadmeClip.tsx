import { AbsoluteFill, Easing, interpolate, Sequence, useCurrentFrame } from "remotion";
import { Display, fadeUp, features, KeyCap, stateAt, TilesHome, useFonts } from "./Demo";
import { Panel, type PanelState } from "./Panel";
import { MONO, themes, type PanelStyle } from "./style";

// The loop at the top of the README: the hotkey, the tile home, a few quick answers, then the themes take the screen.

const WIDTH = 1280;
const HEIGHT = 720;
const NIGHT = "#16141c";
const PANEL_SCALE = 1.1;
const PANEL_LEFT = (WIDTH - 720 * PANEL_SCALE) / 2;
const PANEL_TOP = 172;
const SYSTEM_TEXT = "-apple-system, sans-serif";

const Label = ({ name, detail, ink }: { name: string; detail: string; ink: string }) => (
  <div style={{ position: "absolute", left: PANEL_LEFT, right: PANEL_LEFT, top: 66, display: "flex", alignItems: "baseline", justifyContent: "space-between" }}>
    <Display size={76} color={ink}>
      {name}
    </Display>
    <div style={{ fontFamily: MONO, fontSize: 22, fontWeight: 500, color: ink }}>{detail}</div>
  </div>
);

const PanelStage = ({ state, style }: { state: PanelState; style: PanelStyle }) => (
  <div style={{ position: "absolute", left: PANEL_LEFT, top: PANEL_TOP, transform: `scale(${PANEL_SCALE})`, transformOrigin: "top left" }}>
    <Panel state={state} style={style} />
  </div>
);

/** A row only so the footer shows what Return does; the tiles draw in its place. */
const homeState: PanelState = { query: "", openLabel: "Open", hasActions: true, rows: [{ id: "home", title: "", kind: "" }] };

const HomePanel = ({ style, selected }: { style: PanelStyle; selected?: number }) => (
  <Panel state={homeState} style={style}>
    <TilesHome style={style} selected={selected} />
  </Panel>
);

const HomeStage = ({ style, selected }: { style: PanelStyle; selected?: number }) => (
  <div style={{ position: "absolute", left: PANEL_LEFT, top: PANEL_TOP, transform: `scale(${PANEL_SCALE})`, transformOrigin: "top left" }}>
    <HomePanel style={style} selected={selected} />
  </div>
);

// MARK: Hotkey, the tile home and a few answers

const PRESS_AT = 24;
const TYPE_AT = 64;
/** Skips a feature's pause before typing, so one answer runs straight into the next. */
const BEAT_LEAD = 6;

// Apps, calculator, clipboard history, emoji, file search.
const beats = [
  { feature: features[0], length: 38 },
  { feature: features[1], length: 60 },
  { feature: features[2], length: 46 },
  { feature: features[4], length: 36 },
  { feature: features[5], length: 40 },
];
const openDuration = TYPE_AT + beats.reduce((sum, beat) => sum + beat.length, 0);

const answerAt = (frame: number): PanelState => {
  let start = TYPE_AT;
  for (const beat of beats) {
    if (frame < start + beat.length) return stateAt(beat.feature, frame - start + BEAT_LEAD);
    start += beat.length;
  }
  const last = beats[beats.length - 1];
  return stateAt(last.feature, last.length + BEAT_LEAD);
};

const Open = () => {
  const frame = useCurrentFrame();
  const shown = frame >= PRESS_AT;
  const home = frame < TYPE_AT;
  return (
    <AbsoluteFill style={{ background: NIGHT }}>
      {shown ? (
        <>
          <Label name="Mestre" detail={home ? `"home": { "layout": "tiles" }` : "free, for macOS"} ink="#fff" />
          {home ? <HomeStage style={themes.mestre} /> : <PanelStage state={answerAt(frame)} style={themes.mestre} />}
        </>
      ) : (
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
          <div style={{ display: "flex", gap: 22, ...fadeUp(frame, 0, 6) }}>
            <KeyCap label="⌥" down={frame >= PRESS_AT - 6} />
            <KeyCap label="Space" wide down={frame >= PRESS_AT - 4} />
          </div>
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
};

// MARK: Themes. The whole frame changes with each one, a diagonal wipe carrying the panel with it.

type Look = { name: string; style: PanelStyle; ground: string; ink: string; selected: number };

const looks: Look[] = [
  { name: "mestre", style: themes.mestre, ground: "#3a2a78", ink: "#fff", selected: 0 },
  { name: "ulm", style: themes.ulmLight, ground: "#e2531a", ink: "#fff", selected: 4 },
  { name: "putty", style: themes.puttyDark, ground: "#e8f43c", ink: "#1d1d1b", selected: 5 },
  { name: "micro", style: themes.microDark, ground: "#b9acf0", ink: "#1b1920", selected: 6 },
  { name: "tiles", style: themes.tilesLight, ground: "#2f6fe8", ink: "#fff", selected: 1 },
];

const LOOK_LENGTH = 50;
const WIPE_LENGTH = 12;
const WIPE_SLANT = 110;

const LookLayer = ({ look }: { look: Look }) => (
  <AbsoluteFill style={{ background: look.ground }}>
    <Label name={look.name} detail={`"panel": { "theme": "${look.name}" }`} ink={look.ink} />
    <HomeStage style={look.style} selected={look.selected} />
  </AbsoluteFill>
);

/** How the opening ends, for the first wipe to carry away. */
const OpenEnd = () => (
  <AbsoluteFill style={{ background: NIGHT }}>
    <Label name="Mestre" detail="free, for macOS" ink="#fff" />
    <PanelStage state={answerAt(openDuration)} style={themes.mestre} />
  </AbsoluteFill>
);

const Themes = () => {
  const frame = useCurrentFrame();
  const index = Math.min(looks.length - 1, Math.floor(frame / LOOK_LENGTH));
  const local = frame - index * LOOK_LENGTH;
  const edge = interpolate(local, [0, WIPE_LENGTH], [-WIPE_SLANT, WIDTH + WIPE_SLANT], {
    extrapolateRight: "clamp",
    easing: Easing.inOut(Easing.cubic),
  });
  const wiping = local < WIPE_LENGTH;
  return (
    <AbsoluteFill>
      {wiping ? index > 0 ? <LookLayer look={looks[index - 1]} /> : <OpenEnd /> : null}
      <AbsoluteFill
        style={
          wiping
            ? { clipPath: `polygon(0 0, ${edge + WIPE_SLANT}px 0, ${edge - WIPE_SLANT}px ${HEIGHT}px, 0 ${HEIGHT}px)` }
            : undefined
        }
      >
        <LookLayer look={looks[index]} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// MARK: All of them together, then back to the dark the loop starts on.

const GRID_SCALE = 0.41;
const GRID_COLUMN = 720 * GRID_SCALE + 14;
const GRID_ROW = 200;
const GRID_LEFT = (WIDTH - 4 * GRID_COLUMN + 14) / 2;
const gridDuration = 96;
const grid: PanelStyle[] = [themes.ulmLight, themes.puttyLight, themes.tilesLight, themes.microLight, themes.ulmDark, themes.puttyDark, themes.tilesDark, themes.microDark];

const Grid = () => {
  const frame = useCurrentFrame();
  const out = interpolate(frame, [gridDuration - 10, gridDuration], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ background: NIGHT }}>
      <AbsoluteFill style={{ opacity: out }}>
        <div style={{ position: "absolute", left: GRID_LEFT, top: 52, ...fadeUp(frame, 0, 6) }}>
          <Display size={52}>Light and dark. Or write your own.</Display>
        </div>
        {grid.map((style, index) => (
          <div key={index} style={{ position: "absolute", left: GRID_LEFT + (index % 4) * GRID_COLUMN, top: 136 + Math.floor(index / 4) * GRID_ROW, ...fadeUp(frame, 2 + index * 2, 6) }}>
            <div style={{ transform: `scale(${GRID_SCALE})`, transformOrigin: "top left" }}>
              <HomePanel style={style} />
            </div>
          </div>
        ))}
        <div style={{ position: "absolute", left: GRID_LEFT, top: 556, fontFamily: MONO, fontSize: 22, color: "#e8f43c", ...fadeUp(frame, 22, 6) }}>~/.config/mestre/themes/&lt;name&gt;.json</div>
        <div style={{ position: "absolute", left: GRID_LEFT, top: 602, fontFamily: SYSTEM_TEXT, fontSize: 18, color: "rgba(255,255,255,0.55)", ...fadeUp(frame, 22, 6) }}>Interface recreated with sample data.</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// MARK: Timeline

const themesDuration = looks.length * LOOK_LENGTH;

export const readmeClipFrames = openDuration + themesDuration + gridDuration;
export const README_CLIP_WIDTH = WIDTH;
export const README_CLIP_HEIGHT = HEIGHT;

export const ReadmeClip = () => {
  useFonts();
  return (
    <AbsoluteFill style={{ background: NIGHT }}>
      <Sequence durationInFrames={openDuration}>
        <Open />
      </Sequence>
      <Sequence from={openDuration} durationInFrames={themesDuration}>
        <Themes />
      </Sequence>
      <Sequence from={openDuration + themesDuration} durationInFrames={gridDuration}>
        <Grid />
      </Sequence>
    </AbsoluteFill>
  );
};
