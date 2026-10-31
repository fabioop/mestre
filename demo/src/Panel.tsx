import {
  Search,
  type LucideIcon,
} from "lucide-react";
import type { CSSProperties, ReactNode } from "react";
import { useCurrentFrame } from "remotion";
import { MARK_ASPECT, MARK_PATH } from "./mark";
import type { PanelStyle } from "./style";

export type Row = {
  id: string;
  title: string;
  subtitle?: string;
  kind: string;
  /** A symbol on a tile, like the app's SF Symbols. */
  symbol?: LucideIcon;
  /** An app's own icon, a swatch or an emoji, drawn as it is. */
  icon?: ReactNode;
  running?: boolean;
  section?: string;
};

export type Action = { id: string; title: string; symbol: LucideIcon; keys?: string };

export type PanelState = {
  query: string;
  /** The placeholder shows while there is no query. */
  placeholder?: string;
  scope?: { title: string; symbol: LucideIcon };
  chips?: string[];
  rows: Row[];
  selected?: number;
  context?: string;
  openLabel?: string;
  hasActions?: boolean;
  actions?: Action[];
  actionIndex?: number;
  toast?: string;
};

const labelCase = (text: string, style: PanelStyle) =>
  style.labelCase === "upper" ? text.toUpperCase() : style.labelCase === "lower" ? text.toLowerCase() : text;

export const Key = ({ keys, style, primary, onSelection }: { keys: string; style: PanelStyle; primary?: boolean; onSelection?: boolean }) => {
  const selectedInk = onSelection ? style.selectedKeyInk : undefined;
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        minWidth: 20,
        height: 20,
        padding: "0 6px",
        boxSizing: "border-box",
        borderRadius: 5,
        fontSize: 11,
        fontFamily: style.uiFont,
        fontWeight: 500,
        background: primary && style.primaryKey ? style.primaryKey : style.keyCap,
        color: primary && style.primaryKeyInk ? style.primaryKeyInk : selectedInk ?? style.keyCapInk,
        border: `1px solid ${primary && style.primaryKey ? "transparent" : selectedInk ?? style.keyCapEdge}`,
      }}
    >
      {keys}
    </span>
  );
};

const RowView = ({ row, selected, style }: { row: Row; selected: boolean; style: PanelStyle }) => {
  const Symbol = row.symbol;
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        height: 42,
        gap: 10,
        padding: "0 10px",
        borderRadius: style.rowRadius,
        background: selected ? style.selection : "transparent",
      }}
    >
      <div style={{ width: 28, height: 28, flexShrink: 0 }}>
        {row.icon ?? (
          <div
            style={{
              width: 28,
              height: 28,
              borderRadius: style.iconRadius,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: selected ? style.selectedIconTile : style.iconTile,
              color: selected ? style.selectedIconSymbol : style.iconSymbol,
            }}
          >
            {Symbol ? <Symbol size={15} strokeWidth={2} /> : null}
          </div>
        )}
      </div>
      <div style={{ display: "flex", alignItems: "baseline", gap: 8, minWidth: 0, flex: 1, whiteSpace: "nowrap" }}>
        <span style={{ fontSize: 14, fontWeight: 500, color: selected ? style.selectionInk : style.ink }}>{row.title}</span>
        {row.running ? <span style={{ width: 6, height: 6, borderRadius: 3, background: style.running, alignSelf: "center" }} /> : null}
        {row.subtitle ? (
          <span style={{ fontSize: 13, overflow: "hidden", textOverflow: "ellipsis", color: selected ? style.selectionSecondary : style.inkSecondary }}>{row.subtitle}</span>
        ) : null}
      </div>
      <span style={{ fontSize: 12, marginLeft: 12, flexShrink: 0, color: selected ? style.selectionSecondary : style.inkSecondary }}>{labelCase(row.kind, { ...style, labelCase: style.labelCase === "upper" ? "none" : style.labelCase })}</span>
    </div>
  );
};

export const QueryField = ({ state, style }: { state: PanelState; style: PanelStyle }) => {
  const frame = useCurrentFrame();
  const caretOn = Math.floor(frame / 15) % 2 === 0;
  const Scope = state.scope?.symbol;
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: "0 16px",
        height: style.fieldHeight,
        margin: style.field ? "8px 8px 0" : 0,
        borderRadius: style.field ? Math.max(0, style.cornerRadius - 8) : 0,
        background: style.field,
      }}
    >
      <Search size={style.queryFontSize * 0.85} color={style.fieldSecondary} strokeWidth={2.2} style={{ flexShrink: 0 }} />
      {state.scope && Scope ? (
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 5,
            height: 24,
            padding: "0 8px",
            borderRadius: style.rowRadius,
            fontSize: 13,
            fontWeight: 500,
            background: style.selection,
            color: style.selectionInk,
            flexShrink: 0,
          }}
        >
          <Scope size={12} strokeWidth={2.2} />
          {state.scope.title}
        </div>
      ) : null}
      <div style={{ fontFamily: style.queryFont, fontSize: style.queryFontSize, fontWeight: style.queryWeight, color: style.fieldInk, whiteSpace: "pre", display: "flex", alignItems: "center" }}>
        {state.query}
        <span style={{ width: 2, height: style.queryFontSize * 1.15, marginLeft: 1, background: caretOn ? style.caret : "transparent" }} />
        {state.query === "" ? (
          <span style={{ color: style.fieldSecondary, marginLeft: 1 }}>{state.placeholder ?? (state.scope ? `Search ${state.scope.title}…` : "Search apps, or pick a feature below…")}</span>
        ) : null}
      </div>
    </div>
  );
};

const Divider = ({ style }: { style: PanelStyle }) => <div style={{ height: 1, background: style.divider }} />;

const Footer = ({ state, style }: { state: PanelState; style: PanelStyle }) => {
  const selected = state.selected ?? 0;
  const row = state.rows[selected];
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 12,
        height: style.footer ? 42 : 34,
        padding: style.footer ? "0 10px 0 16px" : "0 16px",
        margin: style.footer ? "0 8px 8px" : 0,
        borderRadius: style.footer ? Math.max(0, style.cornerRadius - 8) : 0,
        background: style.footer,
        fontSize: 12,
      }}
    >
      <span style={{ fontWeight: 500, color: style.footerSecondary }}>{state.context ?? "Mestre"}</span>
      {state.toast ? (
        <>
          <span style={{ width: 1, height: 14, background: style.divider }} />
          <span style={{ fontWeight: 500, color: style.footerInk }}>
            <span style={{ color: style.running, marginRight: 6 }}>✓</span>
            {state.toast}
          </span>
        </>
      ) : null}
      <span style={{ flex: 1 }} />
      {row && state.openLabel ? (
        <span style={{ display: "flex", alignItems: "center", gap: 5, color: style.footerSecondary }}>
          {state.openLabel}
          <Key keys="↩" style={style} primary />
        </span>
      ) : null}
      {row && state.hasActions ? (
        <span style={{ display: "flex", alignItems: "center", gap: 5, color: style.footerSecondary }}>
          Actions
          <Key keys="⌘K" style={style} />
        </span>
      ) : null}
    </div>
  );
};

export const panelSurface = (style: PanelStyle): CSSProperties => ({
  background: style.panel,
  backdropFilter: style.glass ? "blur(40px) saturate(1.4)" : undefined,
  borderRadius: style.cornerRadius,
  border: style.border ? `${style.borderWidth}px solid ${style.border}` : style.glass ? "1px solid rgba(255,255,255,0.14)" : undefined,
  boxShadow: "0 30px 80px rgba(0,0,0,0.45)",
  color: style.ink,
  fontFamily: style.uiFont,
  overflow: "hidden",
  width: 720,
  boxSizing: "border-box",
});

export const Panel = ({ state, style, children }: { state: PanelState; style: PanelStyle; children?: ReactNode }) => {
  const hasRows = state.rows.length > 0 || children !== undefined;
  const selected = state.selected ?? 0;
  return (
    <div style={panelSurface(style)}>
      <QueryField state={state} style={style} />
      {state.chips?.length ? (
        <div style={{ display: "flex", gap: 6, padding: "4px 16px 6px" }}>
          {state.chips.map((chip) => (
            <span key={chip} style={{ fontSize: 12, fontWeight: 500, height: 22, lineHeight: "22px", padding: "0 8px", borderRadius: style.rowRadius, background: style.iconTile, color: style.ink }}>
              {chip}
            </span>
          ))}
        </div>
      ) : null}
      {hasRows ? (
        <>
          {style.field ? null : <Divider style={style} />}
          {children ?? (
            <div style={{ padding: 8 }}>
              {state.rows.map((row, index) => (
                <div key={row.id}>
                  {row.section && state.rows[index - 1]?.section !== row.section ? (
                    <div style={{ height: 30, boxSizing: "border-box", display: "flex", alignItems: "flex-end", padding: "0 10px 6px", fontSize: 11, fontWeight: 600, letterSpacing: 0.5, color: style.inkSecondary }}>
                      {labelCase(row.section, style)}
                    </div>
                  ) : null}
                  <RowView row={row} selected={index === selected} style={style} />
                </div>
              ))}
            </div>
          )}
          {state.actions ? (
            <>
              <Divider style={style} />
              <div style={{ padding: 8 }}>
                <div style={{ height: 30, boxSizing: "border-box", display: "flex", alignItems: "flex-end", padding: "0 10px 6px", fontSize: 11, fontWeight: 600, letterSpacing: 0.5, color: style.inkSecondary }}>
                  {labelCase("Actions", style)}
                </div>
                {state.actions.map((action, index) => {
                  const on = index === (state.actionIndex ?? 0);
                  const Symbol = action.symbol;
                  return (
                    <div key={action.title} style={{ display: "flex", alignItems: "center", gap: 10, height: 30, padding: "0 10px", fontSize: 13, borderRadius: 6, background: on ? style.selection : "transparent", color: on ? style.selectionInk : style.ink }}>
                      <Symbol size={14} color={on ? style.selectionSecondary : style.inkSecondary} />
                      {action.title}
                      <span style={{ flex: 1 }} />
                      <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 11, color: on ? style.selectionSecondary : style.inkSecondary }}>{action.id}</span>
                      {action.keys ? <Key keys={action.keys} style={style} onSelection={on} /> : null}
                    </div>
                  );
                })}
              </div>
            </>
          ) : null}
          {style.footer ? null : <Divider style={style} />}
          <Footer state={state} style={style} />
        </>
      ) : null}
      {!hasRows && style.field ? <div style={{ height: 8 }} /> : null}
    </div>
  );
};

/** The app icon: putty ground, ink M. `size` is the rounded square itself. */
export const AppIconMark = ({ size }: { size: number }) => (
  <div style={{ width: size, height: size, borderRadius: size * 0.225, background: "#dcdad2", display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.08)" }}>
    <Mark height={(size * 0.64) / MARK_ASPECT} color="#1d1d1b" />
  </div>
);

export const Mark = ({ height, color }: { height: number; color: string }) => (
  <svg width={height * MARK_ASPECT} height={height} viewBox={`0 0 ${MARK_ASPECT} 1`} style={{ display: "block" }}>
    <path d={MARK_PATH} fill={color} />
  </svg>
);
