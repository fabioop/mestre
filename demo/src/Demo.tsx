import {
  AppWindow,
  ArrowRightCircle,
  Bluetooth,
  BookMarked,
  BookOpen,
  Calculator,
  Clipboard,
  Coffee,
  Compass,
  CircleX,
  EyeOff,
  File as FileIcon,
  FileCode,
  Folder,
  Globe,
  Lock,
  Mail,
  Monitor,
  Moon,
  Music,
  Palette,
  Power,
  ScrollText,
  Smile,
  Square,
  StickyNote,
  Terminal,
  Trash2,
  Volume2,
  Wand2,
  Wifi,
  Workflow,
  type LucideIcon,
} from "lucide-react";
import { useEffect, useState, type ReactNode } from "react";
import {
  AbsoluteFill,
  cancelRender,
  continueRender,
  delayRender,
  interpolate,
  Sequence,
  staticFile,
  useCurrentFrame,
} from "remotion";
import { AppIconMark, Mark, Panel, type PanelState, type Row } from "./Panel";
import { DISPLAY, MONO, themes, type PanelStyle } from "./style";

// MARK: Sample data. Everything on screen is made up for this film.

const appIcon = (Icon: LucideIcon, from: string, to: string) => (
  <div style={{ width: 28, height: 28, borderRadius: 7, background: `linear-gradient(160deg, ${from}, ${to})`, color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.3)" }}>
    <Icon size={17} strokeWidth={2} />
  </div>
);
const safariIcon = appIcon(Compass, "#3fb6f5", "#1668dc");
const notesIcon = appIcon(StickyNote, "#ffd84d", "#f5b800");
const mailIcon = appIcon(Mail, "#5ac8fa", "#1a7cf0");
const musicIcon = appIcon(Music, "#ff6b81", "#f0243f");
const terminalIcon = appIcon(Terminal, "#4a4a4f", "#1b1b1f");
const chromeIcon = appIcon(Globe, "#6bcf7f", "#2e9e50");
const emojiIcon = (emoji: string) => <div style={{ fontSize: 22, lineHeight: "28px", textAlign: "center" }}>{emoji}</div>;
const swatch = (color: string) => <div style={{ width: 28, height: 28, borderRadius: 7, background: color, boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.2)" }} />;

const webRow = (query: string): Row => ({ id: "web", title: `Search the web for “${query}”`, kind: "Web", symbol: Globe });

type Step = PanelState & {
  /** Frame in the scene this step starts on. Its query types itself from there. */
  at: number;
  /** Rows before the query is fully typed; defaults to the web search fallback. */
  partial?: Row[];
};

export type Feature = { title: string; blurb: string; hint?: string; duration: number; steps: Step[] };

export const features: Feature[] = [
  {
    title: "Open and switch apps",
    blurb: "Three letters is plenty. A dot marks what's running.",
    duration: 96,
    steps: [
      {
        at: 4,
        query: "saf",
        context: undefined,
        openLabel: "Switch",
        hasActions: true,
        partial: [
          { id: "safari", title: "Safari", subtitle: "/Applications", kind: "App", icon: safariIcon, running: true },
          { id: "screens", title: "Screenshot", subtitle: "/System/Applications/Utilities", kind: "App", symbol: Monitor },
        ],
        rows: [
          { id: "safari", title: "Safari", subtitle: "/Applications", kind: "App", icon: safariIcon, running: true },
          webRow("saf"),
        ],
      },
      {
        at: 44,
        query: "saf",
        openLabel: "Switch",
        hasActions: true,
        rows: [
          { id: "safari", title: "Safari", subtitle: "/Applications", kind: "App", icon: safariIcon, running: true },
          webRow("saf"),
        ],
        actionIndex: 0,
        actions: [
          { id: "open", title: "Switch", symbol: ArrowRightCircle, keys: "↩" },
          { id: "quit", title: "Quit", symbol: CircleX, keys: "⌘Q" },
          { id: "hide", title: "Hide", symbol: EyeOff, keys: "⌘H" },
        ],
      },
    ],
  },
  {
    title: "Calculator",
    blurb: "The answer is there before you finish. Return copies it.",
    duration: 72,
    steps: [
      {
        at: 4,
        query: "2*(3+4)",
        context: "Calculator",
        openLabel: "Copy Result",
        rows: [{ id: "calc", title: "14", subtitle: "2*(3+4)", kind: "Calculator", symbol: Calculator }],
      },
      {
        at: 50,
        query: "2*(3+4)",
        context: "Calculator",
        toast: "Copied",
        openLabel: "Copy Result",
        rows: [{ id: "calc", title: "14", subtitle: "2*(3+4)", kind: "Calculator", symbol: Calculator }],
      },
    ],
  },
  {
    title: "Clipboard history",
    blurb: "Recent copies: text, files, images. Return pastes.",
    duration: 72,
    steps: [
      {
        at: 4,
        query: "clip",
        openLabel: "Open",
        rows: [{ id: "clip", title: "Clipboard History", subtitle: "Recent copies: text, files, images. Return pastes", kind: "Feature", symbol: Clipboard }],
      },
      {
        at: 26,
        query: "",
        scope: { title: "Clipboard History", symbol: Clipboard },
        context: "Clipboard History",
        openLabel: "Paste",
        hasActions: true,
        rows: [
          { id: "c1", title: "Meeting moved to 3 pm", subtitle: "2 min ago", kind: "Clipboard", symbol: Clipboard },
          { id: "c2", title: "https://example.com/launch-notes", subtitle: "9 min ago", kind: "Clipboard", symbol: Clipboard },
          { id: "c3", title: "brew install ripgrep", subtitle: "24 min ago", kind: "Clipboard", symbol: Clipboard },
          { id: "c4", title: "chart.png", subtitle: "1 h ago", kind: "Clipboard", symbol: FileIcon },
        ],
      },
    ],
  },
  {
    title: "Snippets and text expansion",
    blurb: "Paste by name, or let a short trigger expand as you type.",
    duration: 66,
    steps: [
      {
        at: 4,
        query: "sign",
        context: "Snippets",
        openLabel: "Paste",
        hasActions: true,
        rows: [
          { id: "s1", title: "Email signature", subtitle: ";sig", kind: "Snippet", symbol: ScrollText },
          { id: "s2", title: "Sign-off, friendly", subtitle: ";bye", kind: "Snippet", symbol: ScrollText },
        ],
      },
    ],
  },
  {
    title: "Emoji and symbols",
    blurb: "A colon, then a word. Return pastes it where you were.",
    duration: 66,
    steps: [
      {
        at: 4,
        query: ":fire",
        context: "Emoji & Symbols",
        openLabel: "Paste",
        hasActions: true,
        rows: [
          { id: "e1", title: "fire", subtitle: "fire, hot, lit", kind: "Emoji", icon: emojiIcon("🔥") },
          { id: "e2", title: "fire engine", subtitle: "fire, engine", kind: "Emoji", icon: emojiIcon("🚒") },
          { id: "e3", title: "firecracker", subtitle: "celebration", kind: "Emoji", icon: emojiIcon("🧨") },
        ],
      },
    ],
  },
  {
    title: "Search files",
    blurb: "Spotlight by name. ⌘Y for Quick Look, ⌘↩ to reveal.",
    duration: 72,
    steps: [
      {
        at: 4,
        query: "file report",
        context: "Search Files",
        openLabel: "Open",
        hasActions: true,
        rows: [
          { id: "f1", title: "report-q3.pdf", subtitle: "~/Documents", kind: "File", symbol: FileIcon },
          { id: "f2", title: "report-draft.md", subtitle: "~/Documents/Notes", kind: "File", symbol: FileIcon },
          { id: "f3", title: "reports/", subtitle: "~/Desktop", kind: "File", symbol: Folder },
        ],
      },
    ],
  },
  {
    title: "Browse folders",
    blurb: "Type a path and walk it, completing as you go.",
    duration: 66,
    steps: [
      {
        at: 4,
        query: "~/Doc",
        context: "Browse Folders",
        openLabel: "Open Folder",
        hasActions: true,
        rows: [
          { id: "d1", title: "Documents/", subtitle: "~", kind: "File", symbol: Folder },
          { id: "d2", title: "Docker/", subtitle: "~", kind: "File", symbol: Folder },
        ],
      },
    ],
  },
  {
    title: "Open windows",
    blurb: "Jump straight to a window by its title.",
    duration: 66,
    steps: [
      {
        at: 4,
        query: "launch",
        context: undefined,
        openLabel: "Focus Window",
        rows: [
          { id: "w1", title: "Notes: Launch plan", subtitle: "Window", kind: "Window", symbol: AppWindow },
          { id: "w2", title: "Safari: Launch notes", subtitle: "Window", kind: "Window", symbol: AppWindow },
        ],
      },
    ],
  },
  {
    title: "System commands",
    blurb: "Sleep, lock, restart, empty the trash, toggle dark mode.",
    duration: 66,
    steps: [
      {
        at: 4,
        query: "sleep",
        openLabel: "Run",
        rows: [
          { id: "sl", title: "Sleep", kind: "Command", symbol: Moon },
          { id: "lk", title: "Lock Screen", kind: "Command", symbol: Lock },
          { id: "rs", title: "Restart", kind: "Command", symbol: Power },
          { id: "tr", title: "Empty Trash", kind: "Command", symbol: Trash2 },
        ],
      },
    ],
  },
  {
    title: "System Settings panes",
    blurb: "Straight to the pane, no clicking through the sidebar.",
    duration: 66,
    steps: [
      {
        at: 4,
        query: "bluetooth",
        openLabel: "Open",
        rows: [{ id: "bt", title: "Bluetooth", subtitle: "System Settings", kind: "Settings", symbol: Bluetooth }],
      },
    ],
  },
  {
    title: "Quicklinks and web search",
    blurb: "Your own short words for the sites you search.",
    duration: 72,
    steps: [
      {
        at: 4,
        query: "gh swift",
        openLabel: "Open",
        rows: [
          { id: "q1", title: "GitHub: swift", subtitle: "github.com/search", kind: "Quicklink", symbol: Globe },
          webRow("gh swift"),
        ],
      },
    ],
  },
  {
    title: "Browser bookmarks",
    blurb: "Every saved page, one word away.",
    duration: 66,
    steps: [
      {
        at: 4,
        query: "bm swift",
        context: "Browser Bookmarks",
        openLabel: "Open",
        rows: [
          { id: "b1", title: "The Swift Programming Language", subtitle: "Safari · Reading", kind: "Bookmark", symbol: BookMarked },
          { id: "b2", title: "Swift Forums", subtitle: "Chrome · Dev", kind: "Bookmark", symbol: BookMarked },
        ],
      },
    ],
  },
  {
    title: "Dictionary",
    blurb: "The system dictionary, without opening it.",
    duration: 84,
    steps: [
      {
        at: 4,
        query: "define serendipity",
        context: "Define Word",
        openLabel: "Open in Dictionary",
        hasActions: true,
        rows: [{ id: "df", title: "serendipity, noun", subtitle: "Dictionary", kind: "Definition", symbol: BookOpen },
          { id: "df2", title: "finding something good without looking for it", kind: "Definition", symbol: BookOpen }],
      },
    ],
  },
  {
    title: "Colour conversion",
    blurb: "Paste any colour, get every notation with a swatch.",
    duration: 72,
    steps: [
      {
        at: 4,
        query: "#ff8800",
        context: "Colour Converter",
        openLabel: "Copy",
        rows: [
          { id: "k1", title: "#FF8800", subtitle: "HEX", kind: "Color", icon: swatch("#ff8800") },
          { id: "k2", title: "rgb(255, 136, 0)", subtitle: "RGB", kind: "Color", icon: swatch("#ff8800") },
          { id: "k3", title: "hsl(32, 100%, 50%)", subtitle: "HSL", kind: "Color", icon: swatch("#ff8800") },
        ],
      },
    ],
  },
  {
    title: "Keep awake",
    blurb: "Until stopped, for a while, or until a time.",
    duration: 72,
    steps: [
      {
        at: 4,
        query: "awake 45m",
        context: "Keep Awake",
        openLabel: "Start",
        chips: ["for 45 min"],
        rows: [{ id: "ka", title: "Keep awake for 45 min", kind: "Keep Awake", symbol: Coffee }],
      },
    ],
  },
  {
    title: "Kill a process",
    blurb: "Sorted by memory. Return quits, ⌘⇧K force-quits.",
    duration: 72,
    steps: [
      {
        at: 4,
        query: "kill chrome",
        context: "Kill Process",
        openLabel: "Quit",
        hasActions: true,
        rows: [
          { id: "p1", title: "Google Chrome", subtitle: "1.2 GB · PID 4312", kind: "Process", icon: chromeIcon },
          { id: "p2", title: "Google Chrome Helper", subtitle: "640 MB · PID 4388", kind: "Process", icon: chromeIcon },
          { id: "p3", title: "Google Chrome Helper (GPU)", subtitle: "310 MB · PID 4351", kind: "Process", icon: chromeIcon },
        ],
      },
    ],
  },
  {
    title: "Apple Shortcuts",
    blurb: "Everything you built in Shortcuts, searchable by name.",
    duration: 66,
    steps: [
      {
        at: 4,
        query: "resize",
        openLabel: "Run",
        hasActions: true,
        rows: [{ id: "sh", title: "Resize Photos", subtitle: "Shortcuts", kind: "Shortcut", symbol: Workflow }],
      },
    ],
  },
  {
    title: "Your own scripts",
    blurb: "Pick a keyword. Script filters feed results straight in.",
    duration: 72,
    steps: [
      {
        at: 4,
        query: "deploy staging",
        context: "Scripts",
        openLabel: "Run",
        rows: [
          { id: "sc1", title: "Deploy to staging", subtitle: "deploy.sh", kind: "Script", symbol: FileCode },
          { id: "sc2", title: "Deploy status", subtitle: "deploy.sh", kind: "Script", symbol: FileCode },
        ],
      },
    ],
  },
];

const homeState: PanelState = {
  query: "",
  openLabel: "Open",
  rows: [
    { id: "h1", title: "Calculator", subtitle: "Type 2^10, sqrt(2), 15 % 4, pi*2. Return copies", kind: "Feature", symbol: Calculator, section: "Features" },
    { id: "h2", title: "Colour Converter", subtitle: "#ff8800, rgb(), hsl() → every notation with a swatch", kind: "Feature", symbol: Palette, section: "Features" },
    { id: "h3", title: "Kill Process", subtitle: "Running processes by memory. Return quits, ⌘⇧K force-quits", kind: "Feature", symbol: CircleX, section: "Features" },
    { id: "h4", title: "Keep Awake", subtitle: "Until stopped, for a while, or until a time", kind: "Feature", symbol: Coffee, section: "Features" },
    { id: "h5", title: "Clipboard History", subtitle: "Recent copies: text, files, images. Return pastes", kind: "Feature", symbol: Clipboard, section: "Features" },
    { id: "h6", title: "Emoji & Symbols", subtitle: ":fire or emoji fire. Return pastes", kind: "Feature", symbol: Smile, section: "Features" },
  ],
};

export const themeRows: PanelState = {
  query: "s",
  openLabel: "Switch",
  hasActions: true,
  rows: [
    { id: "t1", title: "Safari", subtitle: "/Applications", kind: "App", icon: safariIcon, running: true },
    { id: "t2", title: "Sleep", kind: "Command", symbol: Moon },
    { id: "t3", title: "Sound", subtitle: "System Settings", kind: "Settings", symbol: Volume2 },
    { id: "t4", title: "Search Files", subtitle: "Spotlight search by name", kind: "Feature", symbol: FileIcon },
    { id: "t5", title: "Shortcuts", subtitle: "/System/Applications", kind: "App", symbol: Wand2 },
  ],
};

// MARK: Shared pieces

const PANEL_LEFT = 880;
const PANEL_TOP = 210;
const PANEL_SCALE = 1.3;

export const useFonts = () => {
  const [handle] = useState(() => delayRender("fonts"));
  useEffect(() => {
    const faces = [
      new FontFace("Archivo", `url(${staticFile("fonts/Archivo.ttf")})`, { weight: "100 900", stretch: "62% 125%" }),
      new FontFace("JetBrains Mono", `url(${staticFile("fonts/JetBrainsMono.ttf")})`, { weight: "100 800" }),
      new FontFace("Nunito", `url(${staticFile("fonts/Nunito.ttf")})`, { weight: "200 1000" }),
    ];
    Promise.all(faces.map((face) => face.load()))
      .then((loaded) => {
        loaded.forEach((face) => document.fonts.add(face));
        continueRender(handle);
      })
      .catch(cancelRender);
  }, [handle]);
};

const Wallpaper = ({ children }: { children?: ReactNode }) => (
  <AbsoluteFill style={{ background: "#16141c" }}>
    <AbsoluteFill
      style={{
        background:
          "radial-gradient(1100px 800px at 82% 18%, rgba(116,78,214,0.55), transparent 70%), radial-gradient(1000px 800px at 12% 92%, rgba(226,83,26,0.34), transparent 70%), radial-gradient(900px 700px at 62% 100%, rgba(40,110,190,0.28), transparent 70%)",
      }}
    />
    {children}
  </AbsoluteFill>
);

const MenuBar = () => (
  <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 36, background: "rgba(20,18,26,0.45)", backdropFilter: "blur(24px)", display: "flex", alignItems: "center", justifyContent: "flex-end", gap: 24, padding: "0 24px", color: "rgba(255,255,255,0.92)", fontFamily: '-apple-system, sans-serif', fontSize: 16, fontWeight: 500 }}>
    <Wifi size={18} />
    <Mark height={13} color="rgba(255,255,255,0.95)" />
    <span>Fri 9:41</span>
  </div>
);

export const Display = ({ children, size = 84, weight = 700, color = "#fff", style }: { children: ReactNode; size?: number; weight?: number; color?: string; style?: React.CSSProperties }) => (
  <div style={{ fontFamily: DISPLAY, fontStretch: "125%", fontWeight: weight, fontSize: size, lineHeight: 1.04, letterSpacing: -size * 0.02, color, ...style }}>{children}</div>
);

export const fadeUp = (frame: number, start = 0, length = 10) => ({
  opacity: interpolate(frame, [start, start + length], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
  transform: `translateY(${interpolate(frame, [start, start + length], [14, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })}px)`,
});

const Caption = ({ title, blurb, index, total, hint }: { title: string; blurb: string; index?: number; total?: number; hint?: string }) => {
  const frame = useCurrentFrame();
  return (
    <div style={{ position: "absolute", left: 100, top: PANEL_TOP + 6, width: 700 }}>
      {index ? (
        <div style={{ ...fadeUp(frame, 0, 6), fontFamily: MONO, fontSize: 20, letterSpacing: 1, color: "rgba(255,255,255,0.55)", marginBottom: 26 }}>
          {String(index).padStart(2, "0")} / {total}
        </div>
      ) : null}
      <Display size={60} style={fadeUp(frame, 0, 6)}>
        {title}
      </Display>
      <div style={{ ...fadeUp(frame, 3, 7), fontFamily: '-apple-system, sans-serif', fontSize: 28, lineHeight: 1.35, color: "rgba(255,255,255,0.74)", marginTop: 26 }}>{blurb}</div>
      {hint ? <div style={{ ...fadeUp(frame, 6, 7), fontFamily: MONO, fontSize: 22, color: "#e8f43c", marginTop: 26 }}>{hint}</div> : null}
    </div>
  );
};

const PanelAt = ({ left = PANEL_LEFT, top = PANEL_TOP, scale = PANEL_SCALE, children }: { left?: number; top?: number; scale?: number; children: ReactNode }) => (
  <div style={{ position: "absolute", left, top, transform: `scale(${scale})`, transformOrigin: "top left" }}>{children}</div>
);

export const KeyCap = ({ label, down, wide }: { label: string; down: boolean; wide?: boolean }) => (
  <div
    style={{
      minWidth: wide ? 260 : 96,
      height: 96,
      padding: "0 24px",
      boxSizing: "border-box",
      borderRadius: 18,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontFamily: '-apple-system, sans-serif',
      fontSize: 42,
      fontWeight: 500,
      color: down ? "#16141c" : "#fff",
      background: down ? "#e8f43c" : "rgba(255,255,255,0.1)",
      border: "1px solid rgba(255,255,255,0.22)",
      transform: down ? "translateY(4px)" : undefined,
      boxShadow: down ? "none" : "0 6px 0 rgba(0,0,0,0.35)",
    }}
  >
    {label}
  </div>
);

// MARK: Scenes

const Intro = () => {
  const frame = useCurrentFrame();
  return (
    <Wallpaper>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 40 }}>
        <div style={fadeUp(frame, 0, 12)}>
          <AppIconMark size={200} />
        </div>
        <Display size={124} style={fadeUp(frame, 8, 12)}>
          Mestre
        </Display>
        <div style={{ ...fadeUp(frame, 18, 12), fontFamily: '-apple-system, sans-serif', fontSize: 36, color: "rgba(255,255,255,0.78)" }}>A free, open-source launcher for macOS.</div>
      </AbsoluteFill>
    </Wallpaper>
  );
};

const Hotkey = () => {
  const frame = useCurrentFrame();
  const pressAt = 34;
  const shown = frame >= pressAt;
  return (
    <Wallpaper>
      <MenuBar />
      <Caption title="Press ⌥ Space." blurb="The panel is there, ready to type. Press it again and it is gone." />
      <div style={{ position: "absolute", left: 100, top: 660, display: "flex", gap: 22, ...fadeUp(frame, 6, 8) }}>
        <KeyCap label="⌥" down={frame >= pressAt - 2 && frame < pressAt + 10} />
        <KeyCap label="Space" wide down={frame >= pressAt && frame < pressAt + 10} />
      </div>
      {shown ? (
        <PanelAt>
          <Panel state={homeState} style={themes.mestre} />
        </PanelAt>
      ) : null}
    </Wallpaper>
  );
};

export const stateAt = (feature: Feature, frame: number): PanelState => {
  const step = [...feature.steps].reverse().find((candidate) => frame >= candidate.at) ?? feature.steps[0];
  const typed = Math.max(0, Math.floor((frame - step.at) / 1.6));
  const previous = feature.steps[feature.steps.indexOf(step) - 1];
  // A step that keeps the previous step's query doesn't type it again.
  const query = previous?.query === step.query ? step.query : step.query.slice(0, typed);
  if (query === step.query) return step;
  if (query === "") return { query: "", rows: [], context: step.context };
  return { ...step, query, rows: step.partial ?? [webRow(query)], chips: undefined, toast: undefined, actions: undefined, openLabel: step.partial ? step.openLabel : "Search", hasActions: step.partial ? step.hasActions : false, context: step.context };
};

const FeatureScene = ({ feature, index, total }: { feature: Feature; index: number; total: number }) => {
  const frame = useCurrentFrame();
  return (
    <Wallpaper>
      <MenuBar />
      <Caption title={feature.title} blurb={feature.blurb} index={index} total={total} />
      <PanelAt>
        <Panel state={stateAt(feature, frame)} style={themes.mestre} />
      </PanelAt>
    </Wallpaper>
  );
};

const FakeWindow = ({ rect }: { rect: { x: number; y: number; w: number; h: number } }) => (
  <div style={{ position: "absolute", left: rect.x, top: rect.y, width: rect.w, height: rect.h, background: "#f5f4ef", borderRadius: 12, boxShadow: "0 24px 60px rgba(0,0,0,0.5)", overflow: "hidden" }}>
    <div style={{ height: 40, background: "#e7e5de", display: "flex", alignItems: "center", gap: 8, padding: "0 14px" }}>
      {["#ff5f57", "#febc2e", "#28c840"].map((color) => (
        <span key={color} style={{ width: 13, height: 13, borderRadius: 7, background: color }} />
      ))}
    </div>
    <div style={{ padding: 28, display: "flex", flexDirection: "column", gap: 16 }}>
      {[0.7, 0.92, 0.84, 0.6, 0.88, 0.74].map((width, i) => (
        <div key={i} style={{ height: 14, width: `${width * 100}%`, borderRadius: 7, background: "#d3d0c7" }} />
      ))}
    </div>
  </div>
);

const windowsDuration = 186;

const WindowScene = ({ index, total }: { index: number; total: number }) => {
  const frame = useCurrentFrame();
  const top = 36;
  const width = 1920, height = 1080 - top;
  const floating = { x: 560, y: 300, w: 800, h: 560 };
  const stops: [number, { x: number; y: number; w: number; h: number }, string][] = [
    [0, floating, ""],
    [58, { x: 0, y: top, w: width / 2, h: height }, "←"],
    [100, { x: width / 2, y: top, w: width / 2, h: height }, "→"],
    [142, { x: 0, y: top, w: width, h: height }, "↩"],
  ];
  const current = [...stops].reverse().find(([at]) => frame >= at)!;
  const typed = "left half".slice(0, Math.max(0, Math.floor((frame - 4) / 1.6)));
  const showPanel = frame < 58;
  const showKeys = frame >= 58;
  return (
    <Wallpaper>
      <MenuBar />
      <FakeWindow rect={current[1]} />
      {showPanel ? (
        <>
          <Caption title="Window layouts" blurb="Halves, thirds, quarters, maximize, center. Type it, or use ⌃⌥ and an arrow from anywhere." index={index} total={total} />
          <PanelAt>
            <Panel
              style={themes.mestre}
              state={{
                query: typed,
                openLabel: "Apply",
                context: "Window Layouts",
                rows: typed === "left half" ? [{ id: "lh", title: "Window: Left Half", subtitle: "Window", kind: "Window", symbol: Square }] : typed ? [webRow(typed)] : [],
              }}
            />
          </PanelAt>
        </>
      ) : null}
      {showKeys ? (
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 80, display: "flex", justifyContent: "center", gap: 20 }}>
          <KeyCap label="⌃" down />
          <KeyCap label="⌥" down />
          <KeyCap label={current[2]} down />
        </div>
      ) : null}
    </Wallpaper>
  );
};

const themeSteps: { name: string; style: PanelStyle; note: string }[] = [
  { name: "mestre", style: themes.mestre, note: "The default: system colours over glass." },
  { name: "ulm", style: themes.ulmLight, note: "A filled field, an orange accent, a monospaced query." },
  { name: "putty", style: themes.puttyDark, note: "Soft and rounded, with a filled footer." },
  { name: "tiles", style: themes.tilesLight, note: "Bright, bold selection, made for the tile home." },
  { name: "micro", style: themes.microDark, note: "Monospaced, square corners, nothing extra." },
];
const themeStepLength = 60;

const ThemesScene = () => {
  const frame = useCurrentFrame();
  const step = themeSteps[Math.min(themeSteps.length - 1, Math.floor(frame / themeStepLength))];
  return (
    <Wallpaper>
      <MenuBar />
      <div style={{ position: "absolute", left: 100, top: PANEL_TOP + 6, width: 700 }}>
        <Display size={60}>Themes</Display>
        <div style={{ fontFamily: '-apple-system, sans-serif', fontSize: 28, lineHeight: 1.35, color: "rgba(255,255,255,0.74)", marginTop: 26 }}>{step.note}</div>
        <div style={{ fontFamily: MONO, fontSize: 26, color: "#e8f43c", marginTop: 34 }}>"theme": "{step.name}"</div>
      </div>
      <PanelAt>
        <Panel state={themeRows} style={step.style} />
      </PanelAt>
    </Wallpaper>
  );
};

const ThemeGrid = () => {
  const frame = useCurrentFrame();
  const grid: PanelStyle[] = [themes.ulmLight, themes.puttyLight, themes.tilesLight, themes.microLight, themes.ulmDark, themes.puttyDark, themes.tilesDark, themes.microDark];
  return (
    <Wallpaper>
      <div style={{ position: "absolute", left: 100, top: 70, ...fadeUp(frame, 0, 8) }}>
        <Display size={52}>Light and dark. Or write your own.</Display>
      </div>
      {grid.map((style, index) => (
        <div key={index} style={{ position: "absolute", left: 88 + (index % 4) * 442, top: 240 + Math.floor(index / 4) * 340, ...fadeUp(frame, 4 + index * 2, 8) }}>
          <div style={{ transform: "scale(0.58)", transformOrigin: "top left" }}>
            <Panel state={themeRows} style={style} />
          </div>
        </div>
      ))}
    </Wallpaper>
  );
};

export const TilesHome = ({ style }: { style: PanelStyle }) => {
  const gap = 8, column = (720 - 16 - 3 * gap) / 4, rowHeight = 156;
  const tile = (index: number): React.CSSProperties => {
    const fill = style.tiles[index % style.tiles.length];
    const dark = ["#2f6fe8", "#ff453a"].includes(fill);
    return { background: fill, color: dark || fill === "#1c1c1e" ? "#fff" : "#000", borderRadius: style.tileRadius, boxSizing: "border-box" };
  };
  const statusTile = (index: number, label: string, value: string) => (
    <div style={{ ...tile(index), flex: 1, padding: "10px 12px", display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
      <div style={{ fontSize: 12, fontWeight: 600 }}>{label}</div>
      <div style={{ fontSize: 26, fontWeight: 800 }}>{value}</div>
    </div>
  );
  const recents: [string, ReactNode][] = [["Safari", safariIcon], ["Notes", notesIcon], ["Mail", mailIcon], ["Music", musicIcon]];
  return (
    <div style={{ padding: 8, display: "flex", flexDirection: "column", gap }}>
      <div style={{ display: "flex", gap, height: rowHeight }}>
        <div style={{ ...tile(0), width: column, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <svg width={120} height={120} viewBox="-60 -60 120 120">
            {Array.from({ length: 12 }, (_, hour) => (
              <line key={hour} x1="0" y1="-52" x2="0" y2="-58" stroke="currentColor" strokeOpacity="0.55" strokeWidth="1.5" strokeLinecap="round" transform={`rotate(${hour * 30})`} />
            ))}
            <line x1="0" y1="0" x2="0" y2="-30" stroke="currentColor" strokeWidth="4" strokeLinecap="round" transform="rotate(280.5)" />
            <line x1="0" y1="0" x2="0" y2="-46" stroke="currentColor" strokeWidth="3" strokeLinecap="round" transform="rotate(246)" />
            <circle r="3" fill={style.accent} />
          </svg>
        </div>
        <div style={{ width: column, display: "flex", flexDirection: "column", gap }}>
          {statusTile(1, "Battery", "82%")}
          {statusTile(2, "Fri 9", "9:41")}
        </div>
        <div style={{ ...tile(0), flex: 1, padding: 10, display: "flex", flexDirection: "column", gap: 6 }}>
          <div style={{ fontSize: 12, fontWeight: 600, paddingLeft: 4 }}>Recent</div>
          <div style={{ display: "flex", gap: 4, flex: 1, alignItems: "center" }}>
            {recents.map(([name, icon]) => (
              <div key={name} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6, fontSize: 12, fontWeight: 500 }}>
                <div style={{ transform: "scale(1.5)", margin: 8 }}>{icon}</div>
                {name}
              </div>
            ))}
          </div>
        </div>
      </div>
      <div style={{ display: "flex", gap, height: rowHeight }}>
        <div style={{ ...tile(3), width: 2 * column + gap, padding: 14, display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12, fontWeight: 600 }}>
            <Coffee size={15} /> Keep Awake
          </div>
          <div>
            <div style={{ fontSize: 36, fontWeight: 800 }}>45 min</div>
            <div style={{ fontSize: 12, fontWeight: 500 }}>until 10:26</div>
          </div>
        </div>
        <div style={{ ...tile(4), width: column, padding: 14, display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12, fontWeight: 600 }}>
            <Clipboard size={15} /> Clipboard
          </div>
          <div>
            <div style={{ fontSize: 16, fontWeight: 800, lineHeight: 1.15 }}>Meeting moved to 3 pm</div>
            <div style={{ fontSize: 12, fontWeight: 500, marginTop: 3 }}>2 min ago</div>
          </div>
        </div>
        <div style={{ ...tile(5), width: column, padding: 14, display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
          <Calculator size={16} />
          <div style={{ fontSize: 20, fontWeight: 800 }}>Calculator</div>
        </div>
      </div>
    </div>
  );
};

const TilesScene = () => (
  <Wallpaper>
    <MenuBar />
    <Caption title="A home screen, if you want one" blurb="Clock, battery, recents and live tiles. Arrow keys, Return and ⌘K work as they do in the list." hint='"home": { "layout": "tiles" }' />
    <PanelAt top={190}>
      <Panel state={{ query: "", rows: [], openLabel: "Open", context: "Mestre" }} style={themes.tilesDark}>
        <TilesHome style={themes.tilesDark} />
      </Panel>
    </PanelAt>
  </Wallpaper>
);

const ConfigLine = ({ children }: { children: ReactNode }) => <div style={{ height: 36, whiteSpace: "pre" }}>{children}</div>;
const K = ({ children }: { children: string }) => <span style={{ color: "#9cdcfe" }}>{children}</span>;
const V = ({ children }: { children: string }) => <span style={{ color: "#e8f43c" }}>{children}</span>;

const ConfigScene = () => {
  const frame = useCurrentFrame();
  const from = "mestre", to = "ulm";
  const eraseStart = 36, typeStart = 54, saveAt = 74;
  const value =
    frame < eraseStart
      ? from
      : frame < typeStart
        ? from.slice(0, Math.max(0, from.length - Math.floor((frame - eraseStart) / 2)))
        : to.slice(0, Math.floor((frame - typeStart) / 4) + 1);
  const saved = frame >= saveAt;
  return (
    <Wallpaper>
      <MenuBar />
      <div style={{ position: "absolute", left: 100, top: 100, width: 720, ...fadeUp(frame, 0, 8) }}>
        <Display size={60}>One JSON file.</Display>
        <div style={{ fontFamily: '-apple-system, sans-serif', fontSize: 28, lineHeight: 1.35, color: "rgba(255,255,255,0.74)", marginTop: 22 }}>Every key is optional. Changes apply when you save, no restart.</div>
      </div>
      <div style={{ position: "absolute", left: 100, top: 330, width: 720, borderRadius: 14, background: "rgba(16,15,22,0.9)", border: "1px solid rgba(255,255,255,0.12)", overflow: "hidden", fontFamily: MONO, fontSize: 20, color: "#d8d6e0", ...fadeUp(frame, 4, 8) }}>
        <div style={{ height: 44, display: "flex", alignItems: "center", padding: "0 18px", gap: 10, background: "rgba(255,255,255,0.06)", fontSize: 18, color: "rgba(255,255,255,0.68)" }}>
          ~/.config/mestre/config.json
          <span style={{ flex: 1 }} />
          {saved ? <span style={{ color: "#6fd08a" }}>✓ saved</span> : null}
        </div>
        <div style={{ padding: "22px 26px" }}>
          <ConfigLine>{"{"}</ConfigLine>
          <ConfigLine>
            {"  "}<K>"hotKey"</K>: <V>"option+space"</V>,
          </ConfigLine>
          <ConfigLine>
            {"  "}<K>"hotkeys"</K>: {"{ "}<K>"cmd+shift+v"</K>: <V>"feature:clipboard"</V>{" },"}
          </ConfigLine>
          <ConfigLine>
            {"  "}<K>"aliases"</K>: {"{ "}<K>"ff"</K>: <V>"Firefox"</V>{" },"}
          </ConfigLine>
          <ConfigLine>
            {"  "}<K>"panel"</K>: {"{ "}<K>"theme"</K>: <V>{`"${value}`}</V>
            <span style={{ display: "inline-block", width: 3, height: 22, verticalAlign: -4, background: saved ? "transparent" : "#fff" }} />
            <V>"</V>{" }"}
          </ConfigLine>
          <ConfigLine>{"}"}</ConfigLine>
        </div>
      </div>
      <div style={{ position: "absolute", left: 100, top: 760, width: 720, fontFamily: '-apple-system, sans-serif', fontSize: 24, lineHeight: 1.4, color: "rgba(255,255,255,0.68)", ...fadeUp(frame, 96, 8) }}>
        Settings window included, editing the same file. Import snippets, quicklinks and hotkeys from Raycast or Alfred.
      </div>
      <PanelAt>
        <Panel state={themeRows} style={saved ? themes.ulmLight : themes.mestre} />
      </PanelAt>
    </Wallpaper>
  );
};

const stats = [
  { value: "37 ms", label: "hotkey to panel on screen" },
  { value: "0.2–0.6 ms", label: "search, per keystroke, every feature on" },
  { value: "4.9 ms", label: "ranking 1,000 apps" },
  { value: "0.0 %", label: "CPU when idle" },
];

const SpeedScene = () => {
  const frame = useCurrentFrame();
  return (
    <Wallpaper>
      <AbsoluteFill style={{ padding: "110px 100px", boxSizing: "border-box" }}>
        <Display size={84} style={fadeUp(frame, 0, 8)}>
          Blazing fast.
        </Display>
        <div style={{ ...fadeUp(frame, 4, 8), fontFamily: '-apple-system, sans-serif', fontSize: 30, color: "rgba(255,255,255,0.74)", marginTop: 20 }}>Speed is a rule here, and the tests guard it.</div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 28, marginTop: 56 }}>
          {stats.map((stat, index) => (
            <div key={stat.label} style={{ ...fadeUp(frame, 10 + index * 8, 8), background: "rgba(255,255,255,0.07)", border: "1px solid rgba(255,255,255,0.12)", borderRadius: 22, padding: "34px 40px" }}>
              <Display size={78} color="#e8f43c">
                {stat.value}
              </Display>
              <div style={{ fontFamily: '-apple-system, sans-serif', fontSize: 28, color: "rgba(255,255,255,0.8)", marginTop: 14 }}>{stat.label}</div>
            </div>
          ))}
        </div>
        <div style={{ ...fadeUp(frame, 48, 8), fontFamily: '-apple-system, sans-serif', fontSize: 20, color: "rgba(255,255,255,0.55)", marginTop: 34 }}>Measured on an Apple silicon Mac, release build, October 2026.</div>
      </AbsoluteFill>
    </Wallpaper>
  );
};

const FreeScene = () => {
  const frame = useCurrentFrame();
  const words = ["Free.", "Open source.", "Yours to change."];
  return (
    <Wallpaper>
      <AbsoluteFill style={{ padding: "0 100px", justifyContent: "center" }}>
        {words.map((word, index) => (
          <Display key={word} size={132} style={{ ...fadeUp(frame, index * 14, 8), marginBottom: 12 }}>
            {word}
          </Display>
        ))}
        <div style={{ ...fadeUp(frame, 44, 8), fontFamily: '-apple-system, sans-serif', fontSize: 34, color: "rgba(255,255,255,0.78)", marginTop: 34 }}>GPL-3.0, with the source on GitHub. Mestre updates itself.</div>
      </AbsoluteFill>
    </Wallpaper>
  );
};

const Outro = () => {
  const frame = useCurrentFrame();
  return (
    <Wallpaper>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 34 }}>
        <div style={fadeUp(frame, 0, 10)}>
          <AppIconMark size={170} />
        </div>
        <Display size={108} style={fadeUp(frame, 6, 10)}>
          Mestre
        </Display>
        <div style={{ ...fadeUp(frame, 14, 10), fontFamily: MONO, fontSize: 38, color: "#e8f43c" }}>github.com/fabioop/mestre</div>
        <div style={{ ...fadeUp(frame, 20, 10), fontFamily: '-apple-system, sans-serif', fontSize: 26, color: "rgba(255,255,255,0.72)" }}>In beta. macOS 14 or later, Apple silicon.</div>
      </AbsoluteFill>
      <div style={{ ...fadeUp(frame, 30, 10), position: "absolute", bottom: 34, left: 0, right: 0, textAlign: "center", fontFamily: '-apple-system, sans-serif', fontSize: 18, color: "rgba(255,255,255,0.45)" }}>Interface recreated for this film, with sample data.</div>
    </Wallpaper>
  );
};

// MARK: Timeline

const WINDOW_SLOT = 7; // Window layouts come after Browse folders.
const featureTotal = features.length + 1;

type Scene = { duration: number; node: ReactNode };

const scenes: Scene[] = [
  { duration: 78, node: <Intro /> },
  { duration: 96, node: <Hotkey /> },
];
features.forEach((feature, position) => {
  if (position === WINDOW_SLOT) scenes.push({ duration: windowsDuration, node: <WindowScene index={WINDOW_SLOT + 1} total={featureTotal} /> });
  const index = position + 1 + (position >= WINDOW_SLOT ? 1 : 0);
  scenes.push({ duration: feature.duration, node: <FeatureScene feature={feature} index={index} total={featureTotal} /> });
});
scenes.push(
  { duration: themeSteps.length * themeStepLength, node: <ThemesScene /> },
  { duration: 96, node: <ThemeGrid /> },
  { duration: 96, node: <TilesScene /> },
  { duration: 162, node: <ConfigScene /> },
  { duration: 144, node: <SpeedScene /> },
  { duration: 96, node: <FreeScene /> },
  { duration: 120, node: <Outro /> },
);

export const totalFrames = scenes.reduce((sum, scene) => sum + scene.duration, 0);

export const Demo = () => {
  useFonts();
  let start = 0;
  return (
    <AbsoluteFill style={{ background: "#16141c" }}>
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

