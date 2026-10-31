import micro from "../../Sources/MestreCore/Resources/theme-micro.json";
import putty from "../../Sources/MestreCore/Resources/theme-putty.json";
import tiles from "../../Sources/MestreCore/Resources/theme-tiles.json";
import ulm from "../../Sources/MestreCore/Resources/theme-ulm.json";

export const SYSTEM = '-apple-system, "SF Pro Text", "Helvetica Neue", sans-serif';
export const MONO = '"JetBrains Mono", Menlo, monospace';
export const ROUNDED = '"Nunito", -apple-system, sans-serif';
export const DISPLAY = '"Archivo", -apple-system, sans-serif';

export type PanelStyle = {
  panel: string;
  glass: boolean;
  border?: string;
  borderWidth: number;
  ink: string;
  inkSecondary: string;
  divider: string;
  accent: string;
  running: string;
  selection: string;
  selectionInk: string;
  selectionSecondary: string;
  iconTile: string;
  iconSymbol: string;
  selectedIconTile: string;
  selectedIconSymbol: string;
  keyCap: string;
  keyCapInk: string;
  keyCapEdge: string;
  selectedKeyInk?: string;
  primaryKey?: string;
  primaryKeyInk?: string;
  field?: string;
  fieldInk: string;
  fieldSecondary: string;
  caret: string;
  footer?: string;
  footerInk: string;
  footerSecondary: string;
  tiles: string[];
  cornerRadius: number;
  rowRadius: number;
  iconRadius: number;
  tileRadius: number;
  fieldHeight: number;
  queryFontSize: number;
  labelCase: "upper" | "lower" | "none";
  uiFont: string;
  queryFont: string;
  queryWeight: number;
};

/** The default look, Config.Panel's values over glass: the theme named "mestre" has no file. */
const mestreDark: PanelStyle = {
  panel: "rgba(38, 38, 44, 0.74)",
  glass: true,
  borderWidth: 0,
  ink: "#ffffff",
  inkSecondary: "rgba(255,255,255,0.62)",
  divider: "rgba(255,255,255,0.09)",
  accent: "#a88cff",
  running: "#30d158",
  selection: "rgba(168,140,255,0.24)",
  selectionInk: "#ffffff",
  selectionSecondary: "rgba(255,255,255,0.68)",
  iconTile: "rgba(255,255,255,0.09)",
  iconSymbol: "rgba(255,255,255,0.72)",
  selectedIconTile: "rgba(168,140,255,0.22)",
  selectedIconSymbol: "#a88cff",
  keyCap: "rgba(255,255,255,0.09)",
  keyCapInk: "rgba(255,255,255,0.72)",
  keyCapEdge: "rgba(255,255,255,0.1)",
  fieldInk: "#ffffff",
  fieldSecondary: "rgba(255,255,255,0.55)",
  caret: "#ffffff",
  footerInk: "#ffffff",
  footerSecondary: "rgba(255,255,255,0.58)",
  tiles: [],
  cornerRadius: 12,
  rowRadius: 8,
  iconRadius: 7,
  tileRadius: 16,
  fieldHeight: 52,
  queryFontSize: 20,
  labelCase: "upper",
  uiFont: SYSTEM,
  queryFont: SYSTEM,
  queryWeight: 400,
};

type ThemeFile = {
  cornerRadius?: number;
  rowRadius?: number;
  iconRadius?: number;
  tileRadius?: number;
  borderWidth?: number;
  fieldHeight?: number;
  queryFontSize?: number;
  labelCase?: string;
  fonts?: { ui?: string; query?: string; queryWeight?: string };
  light?: Record<string, unknown>;
  dark?: Record<string, unknown>;
};

const faces: Record<string, string> = { system: SYSTEM, rounded: ROUNDED, monospaced: MONO };
const weights: Record<string, number> = { light: 300, regular: 400, medium: 500, semibold: 600, bold: 700, heavy: 800 };

/** PanelStyle.swift's rule: what a theme leaves out keeps the panel's own look. */
const resolve = (file: ThemeFile, mode: "light" | "dark"): PanelStyle => {
  const c = (file[mode] ?? {}) as Record<string, string & string[]>;
  const ink = c.ink;
  return {
    ...mestreDark,
    panel: c.panel,
    glass: false,
    border: c.border,
    borderWidth: file.borderWidth ?? 0,
    ink,
    inkSecondary: c.inkSecondary,
    divider: c.divider,
    accent: c.accent,
    running: c.running,
    selection: c.selection,
    selectionInk: c.selectionInk,
    selectionSecondary: c.selectionSecondary,
    iconTile: c.iconTile,
    iconSymbol: c.iconSymbol,
    selectedIconTile: c.selectedIconTile,
    selectedIconSymbol: c.selectedIconSymbol,
    keyCap: c.keyCap,
    keyCapInk: c.keyCapInk,
    keyCapEdge: c.keyCapEdge ?? "transparent",
    selectedKeyInk: c.selectedKeyInk,
    primaryKey: c.primaryKey,
    primaryKeyInk: c.primaryKeyInk,
    field: c.field,
    fieldInk: c.fieldInk ?? ink,
    fieldSecondary: c.fieldSecondary ?? c.inkSecondary,
    caret: c.caret ?? ink,
    footer: c.footer,
    footerInk: c.footerInk ?? ink,
    footerSecondary: c.footerSecondary ?? c.inkSecondary,
    tiles: c.tiles ?? [],
    cornerRadius: file.cornerRadius ?? 12,
    rowRadius: file.rowRadius ?? 8,
    iconRadius: file.iconRadius ?? 7,
    tileRadius: file.tileRadius ?? 16,
    fieldHeight: file.fieldHeight ?? 52,
    queryFontSize: file.queryFontSize ?? 20,
    labelCase: (file.labelCase ?? "upper") as PanelStyle["labelCase"],
    uiFont: faces[file.fonts?.ui ?? "system"] ?? SYSTEM,
    queryFont: faces[file.fonts?.query ?? "system"] ?? SYSTEM,
    queryWeight: weights[file.fonts?.queryWeight ?? "regular"] ?? 400,
  };
};

export const themes = {
  mestre: mestreDark,
  ulmDark: resolve(ulm, "dark"),
  ulmLight: resolve(ulm, "light"),
  puttyDark: resolve(putty, "dark"),
  puttyLight: resolve(putty, "light"),
  tilesDark: resolve(tiles, "dark"),
  tilesLight: resolve(tiles, "light"),
  microDark: resolve(micro, "dark"),
  microLight: resolve(micro, "light"),
};
