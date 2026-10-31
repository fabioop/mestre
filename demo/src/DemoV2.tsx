import { ThreeCanvas } from "@remotion/three";
import { Square } from "lucide-react";
import { useMemo, type CSSProperties, type ReactNode } from "react";
import { AbsoluteFill, Easing, interpolate, interpolateColors, Sequence, useCurrentFrame } from "remotion";
import * as THREE from "three";
import { Display, fadeUp, features, KeyCap, stateAt, themeRows, TilesHome, useFonts, type Feature } from "./Demo";
import { MARK_PATH } from "./mark";
import { Panel, type PanelState } from "./Panel";
import { MONO, themes, type PanelStyle } from "./style";

// The story: a thought gets lost on the way to a small task, one shortcut fixes that, and we
// follow one working day from morning to sleep. All data on screen is made up for this film.

const UI = '-apple-system, "SF Pro Text", sans-serif';
const YELLOW = "#e8f43c";

/** The glass reads badly once tilted, so v2 paints the default look. */
const mestre: PanelStyle = { ...themes.mestre, panel: "rgba(30, 29, 36, 0.94)", glass: false, border: "rgba(255,255,255,0.16)", borderWidth: 1 };

const out = Easing.bezier(0.16, 1, 0.3, 1);
const inOut = Easing.bezier(0.65, 0, 0.35, 1);
const move = (frame: number, range: [number, number], values: [number, number], easing = out) =>
  interpolate(frame, range, values, { easing, extrapolateLeft: "clamp", extrapolateRight: "clamp" });

const feature = (title: string): Feature => {
  const found = features.find((candidate) => candidate.title === title);
  if (!found) throw new Error(`No feature called ${title}`);
  return found;
};

// MARK: Stage

type Camera = { rx?: number; ry?: number; rz?: number; x?: number; y?: number; z?: number; perspective?: number };

const Stage = ({ rx = 0, ry = 0, rz = 0, x = 0, y = 0, z = 0, perspective = 1700, children }: Camera & { children: ReactNode }) => (
  <AbsoluteFill style={{ perspective, perspectiveOrigin: "50% 50%" }}>
    <AbsoluteFill style={{ transformStyle: "preserve-3d", transform: `translate3d(${x}px, ${y}px, ${z}px) rotateX(${rx}deg) rotateY(${ry}deg) rotateZ(${rz}deg)` }}>{children}</AbsoluteFill>
  </AbsoluteFill>
);

const At = ({ x = 0, y = 0, z = 0, ry = 0, rx = 0, scale = 1, opacity, children, origin = "top left" }: { x?: number; y?: number; z?: number; ry?: number; rx?: number; scale?: number; opacity?: number; origin?: string; children: ReactNode }) => (
  <div style={{ position: "absolute", left: x, top: y, transformStyle: "preserve-3d", transformOrigin: origin, opacity, transform: `translateZ(${z}px) rotateY(${ry}deg) rotateX(${rx}deg) scale(${scale})` }}>{children}</div>
);

const Glow = ({ base = "#100f15", a = "#744ed6", b = "#e2531a", strength = 0.5 }: { base?: string; a?: string; b?: string; strength?: number }) => (
  <AbsoluteFill style={{ background: base }}>
    <AbsoluteFill style={{ opacity: strength, background: `radial-gradient(1200px 900px at 80% 15%, ${a}, transparent 70%), radial-gradient(1100px 850px at 12% 95%, ${b}, transparent 70%)` }} />
  </AbsoluteFill>
);

const Line = ({ children, style }: { children: ReactNode; style?: CSSProperties }) => <div style={{ fontFamily: UI, fontSize: 30, lineHeight: 1.35, color: "rgba(255,255,255,0.78)", ...style }}>{children}</div>;

// MARK: Windows

const Win = ({ w, h, title, tint = "#f5f4ef", bar = "#e7e5de", children }: { w: number; h: number; title: string; tint?: string; bar?: string; children?: ReactNode }) => (
  <div style={{ width: w, height: h, background: tint, borderRadius: 12, overflow: "hidden", boxShadow: "0 24px 70px rgba(0,0,0,0.55)", fontFamily: UI, color: "#26252a" }}>
    <div style={{ height: 38, background: bar, display: "flex", alignItems: "center", gap: 8, padding: "0 14px", fontSize: 14, fontWeight: 600 }}>
      {["#ff5f57", "#febc2e", "#28c840"].map((color) => (
        <span key={color} style={{ width: 12, height: 12, borderRadius: 6, background: color }} />
      ))}
      <span style={{ marginLeft: 10, opacity: 0.7 }}>{title}</span>
    </div>
    {children ?? <Lines />}
  </div>
);

const Lines = () => (
  <div style={{ padding: 26, display: "flex", flexDirection: "column", gap: 15 }}>
    {[0.7, 0.92, 0.84, 0.6, 0.88, 0.74, 0.5].map((width, index) => (
      <div key={index} style={{ height: 13, width: `${width * 100}%`, borderRadius: 7, background: "rgba(0,0,0,0.14)" }} />
    ))}
  </div>
);

// MARK: Act one, the lost thought

const chaos = [
  { x: 180, y: 130, w: 760, h: 520, title: "Finder", at: 84 },
  { x: 980, y: 90, w: 760, h: 560, title: "Safari", at: 100, tint: "#eef3fb" },
  { x: 420, y: 330, w: 820, h: 560, title: "Mail", at: 118, tint: "#f3f1fa" },
  { x: 1080, y: 420, w: 680, h: 500, title: "Notes", at: 136, tint: "#fbf6df" },
  { x: 120, y: 500, w: 640, h: 460, title: "System Settings", at: 156, tint: "#ececee" },
  { x: 640, y: 170, w: 780, h: 600, title: "Safari", at: 176, tint: "#eef3fb" },
  { x: 880, y: 520, w: 700, h: 460, title: "Finder", at: 196 },
];

const cursorPath: [number, number, number][] = [
  [80, 960, 1040], [100, 300, 200], [118, 1300, 150], [136, 800, 500], [156, 1400, 560], [176, 300, 700], [196, 1000, 300], [216, 1200, 700], [240, 700, 620],
];

const steps: [number, string][] = [[88, "Find the app."], [126, "Find the window."], [164, "Find the tab."], [204, "Where was that file?"]];

const Cursor = () => (
  <svg width={38} height={52} viewBox="0 0 19 26">
    <path d="M1 1 L1 20 L6 15.6 L9.4 23.6 L12.8 22.2 L9.4 14.4 L16 14.2 Z" fill="#000" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
  </svg>
);

const LostThought = () => {
  const frame = useCurrentFrame();
  const press = 318;
  const blast = Math.max(0, frame - press);
  const rx = move(frame, [78, 300], [8, 32], inOut);
  const ry = move(frame, [78, 300], [-6, -26], inOut);
  const z = move(frame, [78, 300], [-100, -560], inOut);
  const cursorAt = cursorPath.reduce<[number, number]>(
    (position, [at, x, y], index) => {
      const previous = cursorPath[index - 1];
      if (!previous || frame < at - 12) return index === 0 ? [x, y] : position;
      const t = move(frame, [at - 12, at], [0, 1], inOut);
      return [previous[1] + (x - previous[1]) * t, previous[2] + (y - previous[2]) * t];
    },
    [cursorPath[0][1], cursorPath[0][2]],
  );
  const step = [...steps].reverse().find(([at]) => frame >= at);
  const dim = move(frame, [236, 262], [0, 0.72], inOut);
  return (
    <AbsoluteFill style={{ background: "#08080b" }}>
      {frame >= 78 ? (
        <>
          <Glow strength={0.35} />
          <Stage rx={rx} ry={ry} z={z} rz={move(frame, [78, 300], [0, -5], inOut)}>
            {chaos.map((win, index) => {
              if (frame < win.at) return null;
              const pop = move(frame, [win.at, win.at + 9], [-260, 0]);
              const direction = index % 2 === 0 ? -1 : 1;
              return (
                <At
                  key={index}
                  x={win.x + direction * blast * 90}
                  y={win.y + (index - 3) * blast * 34}
                  z={index * 60 + pop + blast * blast * 30}
                  ry={direction * blast * 7}
                  rx={blast * (index - 3) * 3}
                  opacity={move(frame, [win.at, win.at + 4], [0, 1]) * (1 - move(frame, [press + 6, press + 20], [0, 1]))}
                  origin="center"
                >
                  <Win w={win.w} h={win.h} title={win.title} tint={win.tint} />
                </At>
              );
            })}
            {frame < 236 ? (
              <At x={cursorAt[0]} y={cursorAt[1]} z={chaos.length * 60 + 60}>
                <Cursor />
              </At>
            ) : null}
          </Stage>
          <AbsoluteFill style={{ background: `rgba(6,6,9,${frame >= press ? Math.max(0, dim - blast * 0.05) : dim})` }} />
        </>
      ) : null}
      {frame < 78 ? (
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 20 }}>
          <Display size={92} style={fadeUp(frame, 4, 12)}>
            You had a good thought.
          </Display>
          <Line style={{ ...fadeUp(frame, 40, 12), fontSize: 40 }}>You just need one small thing first.</Line>
        </AbsoluteFill>
      ) : null}
      {step && frame < 236 ? (
        <div key={step[1]} style={{ position: "absolute", left: 90, bottom: 80 }}>
          <Display size={78} style={fadeUp(frame, step[0], 7)}>
            {step[1]}
          </Display>
        </div>
      ) : null}
      {frame >= 240 && frame < 290 ? (
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
          <Display size={92} style={fadeUp(frame, 240, 12)}>
            And the thought is gone.
          </Display>
        </AbsoluteFill>
      ) : null}
      {frame >= 292 ? (
        <Stage rx={move(frame, [292, 312], [40, 14])} ry={move(frame, [292, 330], [-30, -8])} z={move(frame, [292, 312], [-500, 0]) + blast * 90}>
          <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", transformStyle: "preserve-3d" }}>
            <div style={{ display: "flex", gap: 24, transform: "scale(1.9)", opacity: 1 - move(frame, [press + 4, press + 14], [0, 1]) }}>
              <KeyCap label="⌥" down={frame >= press - 2} />
              <KeyCap label="Space" wide down={frame >= press} />
            </div>
          </AbsoluteFill>
        </Stage>
      ) : null}
      {frame >= press ? <AbsoluteFill style={{ background: "#fff", opacity: 1 - move(frame, [press, press + 12], [0, 1]) }} /> : null}
    </AbsoluteFill>
  );
};
const lostThoughtLength = 340;

// MARK: The logo in real 3D

const parseMark = () => {
  const shape = new THREE.Shape();
  for (const [, op, args] of MARK_PATH.matchAll(/([MLQZ])([^MLQZ]*)/g)) {
    const n = args.trim().split(/\s+/).filter(Boolean).map(Number);
    // The path's y points down; three's points up.
    if (op === "M") shape.moveTo(n[0], 1 - n[1]);
    if (op === "L") shape.lineTo(n[0], 1 - n[1]);
    if (op === "Q") shape.quadraticCurveTo(n[0], 1 - n[1], n[2], 1 - n[3]);
    if (op === "Z") shape.closePath();
  }
  return shape;
};

const Logo3D = ({ rotationY, rotationX = 0, scale = 1 }: { rotationY: number; rotationX?: number; scale?: number }) => {
  const geometry = useMemo(() => {
    const extruded = new THREE.ExtrudeGeometry(parseMark(), { depth: 0.34, bevelEnabled: true, bevelThickness: 0.025, bevelSize: 0.018, bevelSegments: 3, curveSegments: 8 });
    extruded.center();
    return extruded;
  }, []);
  return (
    <ThreeCanvas width={1920} height={1080} camera={{ fov: 30, position: [0, 0, 5.4] }} style={{ position: "absolute", inset: 0 }}>
      <ambientLight intensity={0.55} />
      <directionalLight position={[2.5, 3, 4]} intensity={2.4} />
      <pointLight position={[-3.5, -1, 2]} intensity={16} color="#e2531a" />
      <pointLight position={[3.5, 1.5, 1]} intensity={16} color="#8f6bff" />
      <mesh geometry={geometry} rotation={[rotationX, rotationY, 0]} scale={scale}>
        <meshStandardMaterial color="#dcdad2" roughness={0.38} metalness={0.15} />
      </mesh>
    </ThreeCanvas>
  );
};

const LogoReveal = () => {
  const frame = useCurrentFrame();
  const rotationY = move(frame, [0, 46], [-Math.PI * 2.4, -0.28]) + Math.sin(frame / 34) * 0.1;
  return (
    <AbsoluteFill>
      <Glow strength={0.6} />
      <div style={{ position: "absolute", inset: 0, transform: "translateY(-120px)" }}>
        <Logo3D rotationY={rotationY} rotationX={0.1} scale={move(frame, [0, 34], [0.2, 1])} />
      </div>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "flex-end", paddingBottom: 150, gap: 22 }}>
        <Display size={116} style={fadeUp(frame, 30, 12)}>
          Mestre
        </Display>
        <Line style={{ ...fadeUp(frame, 44, 12), fontSize: 38 }}>One shortcut for all the small things.</Line>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
const logoRevealLength = 110;

// MARK: Act two, one working day

type Beat = { title?: string; say: string; duration: number; render?: (frame: number) => ReactNode };
type Chapter = {
  time: string;
  line: string;
  side: "left" | "right";
  beats: Beat[];
  light: { base: string; a: string; b: string };
  backdrop?: (beat: number, frameInBeat: number) => ReactNode;
};

const typedAt = (text: string, frame: number) => text.slice(0, Math.max(0, Math.floor((frame - 4) / 1.6)));

const SnapBeat = (frame: number) => {
  const rect = (from: [number, number, number, number], to: [number, number, number, number], at: number) => {
    const t = move(frame, [at, at + 5], [0, 1]);
    return from.map((value, index) => value + (to[index] - value) * t);
  };
  const [ax, ay, aw, ah] = rect([300, 170, 760, 560], [0, 0, 800, 900], 44);
  const [bx, by, bw, bh] = rect([860, 300, 620, 480], [800, 0, 800, 900], 84);
  const typed = typedAt("left half", frame);
  return (
    <>
      <Stage rx={move(frame, [0, 124], [24, 18], inOut)} ry={move(frame, [0, 124], [-20, 6], inOut)} rz={-3} z={-420}>
        <At x={160} y={90}>
          <div style={{ width: 1600, height: 900, background: "rgba(255,255,255,0.05)", border: "1px solid rgba(255,255,255,0.14)", borderRadius: 16, position: "relative", transformStyle: "preserve-3d" }}>
            <div style={{ position: "absolute", left: bx, top: by, transform: "translateZ(20px)" }}>
              <Win w={bw} h={bh} title="Notes" tint="#fbf6df" />
            </div>
            <div style={{ position: "absolute", left: ax, top: ay, transform: "translateZ(40px)" }}>
              <Win w={aw} h={ah} title="Safari" tint="#eef3fb" />
            </div>
          </div>
        </At>
        {frame < 44 ? (
          <At x={400} y={400} z={330} scale={1.1}>
            <Panel
              style={mestre}
              state={{ query: typed, openLabel: "Apply", context: "Window Layouts", rows: typed === "left half" ? [{ id: "lh", title: "Window: Left Half", subtitle: "Window", kind: "Window", symbol: Square }] : [] }}
            />
          </At>
        ) : null}
      </Stage>
      <div style={{ position: "absolute", left: 90, top: 70 }}>
        <Display size={60} style={fadeUp(frame, 0, 8)}>
          {frame < 44 ? "Type it." : "Or don't even open it."}
        </Display>
      </div>
      {frame >= 70 ? (
        <div style={{ position: "absolute", right: 90, bottom: 70, display: "flex", gap: 16, ...fadeUp(frame, 70, 6) }}>
          <KeyCap label="⌃" down={frame >= 80} />
          <KeyCap label="⌥" down={frame >= 80} />
          <KeyCap label="→" down={frame >= 84} />
        </div>
      ) : null}
    </>
  );
};

const mailBody = ["Meeting moved to 3 pm", "Great work on this 🔥", "Best,\nThe Launch Team"];

const MailBackdrop = (beat: number, frameInBeat: number) => {
  const lines = mailBody.filter((_, index) => index < beat || (index === beat && frameInBeat >= 40));
  return (
    <Win w={1040} h={720} title="New Message" tint="#f6f5fb">
      <div style={{ padding: "22px 30px", fontSize: 21 }}>
        <div style={{ padding: "8px 0", borderBottom: "1px solid rgba(0,0,0,0.1)", color: "rgba(0,0,0,0.55)" }}>To: team@example.com</div>
        <div style={{ padding: "8px 0", borderBottom: "1px solid rgba(0,0,0,0.1)", color: "rgba(0,0,0,0.55)", marginBottom: 20 }}>Subject: Launch</div>
        {lines.map((line) => (
          <div key={line} style={{ whiteSpace: "pre-line", marginBottom: 16, fontSize: 25 }}>
            {line}
          </div>
        ))}
      </div>
    </Win>
  );
};

const chapters: Chapter[] = [
  {
    time: "9:41",
    line: "Get to work.",
    side: "left",
    light: { base: "#1a1420", a: "#f08a3c", b: "#b0408a" },
    beats: [
      { title: "Open and switch apps", say: "Three letters. ⌘K shows what else it can do.", duration: 74 },
      { say: "", duration: 126, render: SnapBeat },
      { title: "Open windows", say: "That one tab from yesterday? Jump to its window.", duration: 46 },
    ],
  },
  {
    time: "11:05",
    line: "Answer the email.",
    side: "right",
    light: { base: "#16161f", a: "#d06a9a", b: "#3f6fe0" },
    backdrop: MailBackdrop,
    beats: [
      { title: "Clipboard history", say: "What you copied an hour ago is still there.", duration: 66 },
      { title: "Emoji and symbols", say: "A colon and a word.", duration: 50 },
      { title: "Snippets and text expansion", say: "Never type your sign-off again.", duration: 50 },
    ],
  },
  {
    time: "13:30",
    line: "Find that thing.",
    side: "left",
    light: { base: "#0f1a2c", a: "#3f8cff", b: "#25c8b5" },
    beats: [
      { title: "Search files", say: "Spotlight, by name.", duration: 52 },
      { title: "Browse folders", say: "Or just walk the path.", duration: 42 },
      { title: "Browser bookmarks", say: "Every saved page.", duration: 46 },
      { title: "Quicklinks and web search", say: "Your own short words for the sites you search.", duration: 46 },
      { title: "Dictionary", say: "What did that word mean again?", duration: 60 },
    ],
  },
  {
    time: "15:20",
    line: "Quick questions.",
    side: "right",
    light: { base: "#14191f", a: "#37b98a", b: "#d9a521" },
    beats: [
      { title: "Calculator", say: "The answer, then Return to copy it.", duration: 58 },
      { title: "Colour conversion", say: "Every notation, with a swatch.", duration: 50 },
    ],
  },
  {
    time: "16:45",
    line: "The fans kick in.",
    side: "left",
    light: { base: "#1d1712", a: "#f0a02c", b: "#e2531a" },
    beats: [
      { title: "Kill a process", say: "Sorted by memory. You know who it is.", duration: 56 },
      { title: "System Settings panes", say: "Headphones? Straight to the pane.", duration: 46 },
      { title: "Keep awake", say: "The long build won't let the Mac sleep.", duration: 52 },
    ],
  },
  {
    time: "18:10",
    line: "Hand off the boring parts.",
    side: "right",
    light: { base: "#17121f", a: "#a14fe0", b: "#e0407a" },
    beats: [
      { title: "Apple Shortcuts", say: "Everything you built in Shortcuts.", duration: 44 },
      { title: "Your own scripts", say: "Your keyword, your script.", duration: 54 },
    ],
  },
  {
    time: "19:00",
    line: "Done.",
    side: "left",
    light: { base: "#0a0c16", a: "#2c3a8c", b: "#3a2470" },
    beats: [{ title: "System commands", say: "And that's the day.", duration: 74 }],
  },
];

const dayLength = chapters.reduce((sum, chapter) => sum + chapter.beats.reduce((inner, beat) => inner + beat.duration, 0), 0);

const clockNumber = (time: string) => {
  const [hour, minute] = time.split(":").map(Number);
  return hour * 60 + minute;
};

const Day = () => {
  const frame = useCurrentFrame();
  let start = 0;
  let chapterIndex = 0;
  let beatIndex = 0;
  let chapterStart = 0;
  let beatStart = 0;
  outer: for (let c = 0; c < chapters.length; c++) {
    chapterStart = start;
    for (let b = 0; b < chapters[c].beats.length; b++) {
      chapterIndex = c;
      beatIndex = b;
      beatStart = start;
      start += chapters[c].beats[b].duration;
      if (frame < start) break outer;
    }
  }
  const chapter = chapters[chapterIndex];
  const beat = chapter.beats[beatIndex];
  const inChapter = frame - chapterStart;
  const inBeat = frame - beatStart;
  const previous = chapters[chapterIndex - 1] ?? chapter;

  const fade = move(inChapter, [0, 18], [0, 1], inOut);
  const mix = (from: string, to: string) => interpolateColors(fade, [0, 1], [from, to]);
  const light = { base: mix(previous.light.base, chapter.light.base), a: mix(previous.light.a, chapter.light.a), b: mix(previous.light.b, chapter.light.b) };

  const minutes = Math.round(interpolate(inChapter, [0, 16], [clockNumber(previous.time), clockNumber(chapter.time)], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: out }));
  const clock = `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;

  if (beat.render) {
    return (
      <AbsoluteFill>
        <Glow base={light.base} a={light.a} b={light.b} strength={0.5} />
        <div style={{ position: "absolute", right: 90, top: 60, fontFamily: MONO, fontSize: 38, color: YELLOW }}>{clock}</div>
        {beat.render(inBeat)}
      </AbsoluteFill>
    );
  }

  const left = chapter.side === "left";
  const sign = left ? 1 : -1;
  const panelX = left ? 920 : 190;
  const textX = left ? 100 : 1190;
  // A big swing when the chapter changes, a smaller one for each new task, then a slow drift.
  const swing = beatIndex === 0 || chapter.beats[beatIndex - 1].render ? { ry: 70, x: 620, z: -500, length: 18 } : { ry: 15, x: 70, z: -90, length: 9 };
  const panelRy = -sign * (9 + move(inBeat, [0, swing.length], [swing.ry, 0])) + sign * Math.sin(inChapter / 40) * 2;
  const panelShift = sign * move(inBeat, [0, swing.length], [swing.x, 0]);
  const panelZ = move(inBeat, [0, swing.length], [swing.z, 0]);
  const panelRx = 6 + Math.cos(inChapter / 46) * 1.5;
  const state = beat.title ? stateAt(feature(beat.title), inBeat) : ({ query: "", rows: [] } as PanelState);

  const isLast = chapterIndex === chapters.length - 1;
  const sleep = isLast ? move(inBeat, [44, 62], [0, 1], inOut) : 0;

  return (
    <AbsoluteFill>
      <Glow base={light.base} a={light.a} b={light.b} strength={0.55} />
      <Stage>
        {chapter.backdrop ? (
          <At x={panelX - 20} y={move(inChapter, [0, 18], [420, 150])} z={-420} ry={-sign * 15} rx={6}>
            {chapter.backdrop(beatIndex, inBeat)}
          </At>
        ) : null}
        <At x={panelX + panelShift} y={chapter.backdrop ? 470 : 280} z={panelZ} ry={panelRy} rx={panelRx} scale={1.25} origin="center top">
          <Panel state={state} style={mestre} />
        </At>
      </Stage>
      <div style={{ position: "absolute", left: textX, top: 230, width: 640 }}>
        <Display size={150} color={YELLOW} style={{ fontVariantNumeric: "tabular-nums", ...fadeUp(inChapter, 0, 10) }}>
          {clock}
        </Display>
        <Display size={56} style={{ ...fadeUp(inChapter, 4, 10), marginTop: 22 }}>
          {chapter.line}
        </Display>
        <Line style={{ ...fadeUp(inBeat, 2, 7), marginTop: 34, minHeight: 84 }}>{beat.say}</Line>
        {beat.title ? <div style={{ ...fadeUp(inBeat, 2, 7), fontFamily: MONO, fontSize: 21, color: "rgba(255,255,255,0.58)", marginTop: 18 }}>{beat.title}</div> : null}
      </div>
      {sleep > 0 ? (
        <AbsoluteFill style={{ background: `rgba(0,0,0,${sleep})` }} />
      ) : null}
    </AbsoluteFill>
  );
};

// MARK: Act three, yours

const flipThemes: { name: string; style: PanelStyle; note: string }[] = [
  { name: "ulm", style: themes.ulmLight, note: "Orange accent, monospaced query." },
  { name: "putty", style: themes.puttyDark, note: "Soft, rounded, filled footer." },
  { name: "tiles", style: themes.tilesLight, note: "Bright and bold." },
  { name: "micro", style: themes.microDark, note: "Square corners, nothing extra." },
];
const flipLength = 42;

const Flips = () => {
  const frame = useCurrentFrame();
  const index = Math.min(flipThemes.length - 1, Math.floor(frame / flipLength));
  const local = frame - index * flipLength;
  // Out to edge-on, swap the skin, in from the other edge: the mirrored back never shows.
  const leaving = index > 0 && local < 8;
  const shown = leaving ? flipThemes[index - 1] : flipThemes[index];
  const angle = index === 0 ? -10 : leaving ? move(local, [0, 8], [-10, 90], inOut) : move(local, [8, 18], [-90, -10]);
  return (
    <AbsoluteFill>
      <Glow strength={0.55} />
      <div style={{ position: "absolute", left: 100, top: 300, width: 720 }}>
        <Display size={74}>Then make it yours.</Display>
        <Line style={{ marginTop: 28, minHeight: 44 }}>{flipThemes[index].note}</Line>
        <div style={{ fontFamily: MONO, fontSize: 28, color: YELLOW, marginTop: 28 }}>"theme": "{flipThemes[index].name}"</div>
      </div>
      <Stage>
        <At x={900} y={280} ry={angle} rx={5} scale={1.25} origin="center center">
          <Panel state={themeRows} style={shown.style} />
        </At>
      </Stage>
    </AbsoluteFill>
  );
};

const Carousel = () => {
  const frame = useCurrentFrame();
  const ring: PanelStyle[] = [themes.ulmLight, themes.puttyDark, themes.tilesLight, themes.microDark, themes.ulmDark, themes.puttyLight, themes.tilesDark, themes.microLight];
  const turn = move(frame, [0, 96], [40, -170], inOut);
  return (
    <AbsoluteFill>
      <Glow strength={0.55} a="#3f6fe0" />
      <Stage perspective={2000} rx={-6} z={-860} ry={turn}>
        {ring.map((style, index) => (
          <div key={index} style={{ position: "absolute", left: 600, top: 340, backfaceVisibility: "hidden", transform: `rotateY(${index * 45}deg) translateZ(1050px)` }}>
            <Panel state={themeRows} style={style} />
          </div>
        ))}
      </Stage>
      <AbsoluteFill style={{ alignItems: "center", paddingTop: 66 }}>
        <Display size={60} style={fadeUp(frame, 0, 10)}>
          Light and dark. Or write your own.
        </Display>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const Config = () => {
  const frame = useCurrentFrame();
  const from = "mestre";
  const to = "tiles";
  const value =
    frame < 22 ? from : frame < 36 ? from.slice(0, Math.max(0, from.length - Math.floor((frame - 22) / 2))) : to.slice(0, Math.floor((frame - 36) / 2) + 1);
  const saveAt = 52;
  const saved = frame >= saveAt;
  const home = frame >= saveAt + 8;
  const skin = home ? themes.tilesDark : mestre;
  const angle = home ? move(frame, [saveAt + 8, saveAt + 18], [-90, -8]) : saved ? move(frame, [saveAt, saveAt + 8], [-8, 90], inOut) : -8;
  return (
    <AbsoluteFill>
      <Glow strength={0.55} />
      <div style={{ position: "absolute", left: 90, top: 110, width: 760 }}>
        <Display size={66} style={fadeUp(frame, 0, 8)}>
          One JSON file.
        </Display>
        <Line style={{ ...fadeUp(frame, 3, 8), marginTop: 20 }}>Every key is optional. Save, and it applies.</Line>
      </div>
      <Stage>
        <At x={90} y={340} ry={12} rx={3} origin="left center">
          <div style={{ width: 740, borderRadius: 14, background: "rgba(14,13,20,0.96)", border: "1px solid rgba(255,255,255,0.14)", overflow: "hidden", fontFamily: MONO, fontSize: 21, color: "#d8d6e0" }}>
            <div style={{ height: 44, display: "flex", alignItems: "center", padding: "0 18px", background: "rgba(255,255,255,0.06)", fontSize: 18, color: "rgba(255,255,255,0.68)" }}>
              ~/.config/mestre/config.json
              <span style={{ flex: 1 }} />
              {saved ? <span style={{ color: "#6fd08a" }}>✓ saved</span> : null}
            </div>
            <div style={{ padding: "22px 26px", lineHeight: "38px", whiteSpace: "pre" }}>
              <div>{"{"}</div>
              <div>
                {"  "}<span style={{ color: "#9cdcfe" }}>"hotKey"</span>: <span style={{ color: YELLOW }}>"option+space"</span>,
              </div>
              <div>
                {"  "}<span style={{ color: "#9cdcfe" }}>"aliases"</span>: {"{ "}<span style={{ color: "#9cdcfe" }}>"ff"</span>: <span style={{ color: YELLOW }}>"Firefox"</span>{" },"}
              </div>
              <div>
                {"  "}<span style={{ color: "#9cdcfe" }}>"home"</span>: {"{ "}<span style={{ color: "#9cdcfe" }}>"layout"</span>: <span style={{ color: YELLOW }}>"tiles"</span>{" },"}
              </div>
              <div>
                {"  "}<span style={{ color: "#9cdcfe" }}>"panel"</span>: {"{ "}<span style={{ color: "#9cdcfe" }}>"theme"</span>: <span style={{ color: YELLOW }}>"{value}"</span>{" }"}
              </div>
              <div>{"}"}</div>
            </div>
          </div>
        </At>
        <At x={920} y={170} ry={angle} rx={4} scale={1.2} origin="center center">
          {home ? (
            <Panel state={{ query: "", rows: [], openLabel: "Open", context: "Mestre" }} style={skin}>
              <TilesHome style={skin} />
            </Panel>
          ) : (
            <Panel state={themeRows} style={skin} />
          )}
        </At>
      </Stage>
      <div style={{ position: "absolute", left: 90, bottom: 70, width: 800, ...fadeUp(frame, 74, 8) }}>
        <Line style={{ fontSize: 26 }}>Coming from Raycast or Alfred? Import your snippets, quicklinks and hotkeys.</Line>
      </div>
    </AbsoluteFill>
  );
};

// MARK: Act four, why it feels this way

const stats = [
  { value: "37 ms", label: "hotkey to panel on screen" },
  { value: "0.2–0.6 ms", label: "search, per keystroke" },
  { value: "4.9 ms", label: "ranking 1,000 apps" },
  { value: "0.0 %", label: "CPU when idle" },
];
const statHold = 34;
const statGap = 1500;

const Speed = () => {
  const frame = useCurrentFrame();
  const index = Math.min(stats.length - 1, Math.floor(frame / statHold));
  const camera = index * statGap + move(frame - index * statHold, [0, 14], [-statGap, 0], inOut);
  return (
    <AbsoluteFill>
      <Glow strength={0.6} a="#744ed6" b="#2c7be0" />
      <Stage perspective={1200} z={camera}>
        {stats.map((stat, position) => {
          const distance = camera - position * statGap;
          // The figure on screen, and the last one until it has flown past the camera.
          if (position > index || position < index - 1 || distance > 900) return null;
          return (
            <AbsoluteFill key={stat.label} style={{ alignItems: "center", justifyContent: "center", transform: `translateZ(${-position * statGap}px) rotateY(${distance * 0.012}deg)` }}>
              <Display size={210} color={YELLOW}>
                {stat.value}
              </Display>
              <Line style={{ fontSize: 46, marginTop: 28 }}>{stat.label}</Line>
            </AbsoluteFill>
          );
        })}
      </Stage>
      <div style={{ position: "absolute", left: 90, top: 70 }}>
        <Display size={52}>And it never makes you wait.</Display>
      </div>
      <div style={{ position: "absolute", left: 90, bottom: 56, fontFamily: UI, fontSize: 20, color: "rgba(255,255,255,0.58)" }}>Measured on an Apple silicon Mac, release build, October 2026.</div>
    </AbsoluteFill>
  );
};
const speedLength = stats.length * statHold + 16;

// MARK: The end

const Ending = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill>
      <Glow strength={0.6} />
      <div style={{ position: "absolute", inset: 0, transform: "translate(-470px, 0)" }}>
        <Logo3D rotationY={-0.3 + Math.sin(frame / 42) * 0.32} rotationX={0.12} scale={0.82} />
      </div>
      <div style={{ position: "absolute", left: 930, top: 270, width: 900 }}>
        <Display size={104} style={fadeUp(frame, 0, 10)}>
          Keep the thought.
        </Display>
        <Line style={{ ...fadeUp(frame, 18, 10), fontSize: 38, marginTop: 34 }}>Mestre is free and open source, under GPL-3.0.</Line>
        <div style={{ ...fadeUp(frame, 34, 10), fontFamily: MONO, fontSize: 40, color: YELLOW, marginTop: 44 }}>github.com/fabioop/mestre</div>
        <Line style={{ ...fadeUp(frame, 44, 10), fontSize: 26, marginTop: 28 }}>In beta. macOS 14 or later, Apple silicon.</Line>
      </div>
      <div style={{ ...fadeUp(frame, 54, 10), position: "absolute", bottom: 34, left: 0, right: 0, textAlign: "center", fontFamily: UI, fontSize: 18, color: "rgba(255,255,255,0.45)" }}>Interface recreated for this film, with sample data.</div>
    </AbsoluteFill>
  );
};

// MARK: Timeline

const scenes: { duration: number; node: ReactNode }[] = [
  { duration: lostThoughtLength, node: <LostThought /> },
  { duration: logoRevealLength, node: <LogoReveal /> },
  { duration: dayLength, node: <Day /> },
  { duration: flipThemes.length * flipLength, node: <Flips /> },
  { duration: 96, node: <Carousel /> },
  { duration: 130, node: <Config /> },
  { duration: speedLength, node: <Speed /> },
  { duration: 170, node: <Ending /> },
];

export const totalFramesV2 = scenes.reduce((sum, scene) => sum + scene.duration, 0);

export const DemoV2 = () => {
  useFonts();
  let start = 0;
  return (
    <AbsoluteFill style={{ background: "#08080b" }}>
      {scenes.map((scene, index) => {
        const from = start;
        start += scene.duration;
        return (
          <Sequence key={index} from={from} durationInFrames={scene.duration}>
            {scene.node}
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
