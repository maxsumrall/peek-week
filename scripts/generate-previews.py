#!/usr/bin/env python3
from __future__ import annotations

from datetime import date, timedelta
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
DOCS.mkdir(parents=True, exist_ok=True)


def iso_week_start(day: date) -> date:
    return day - timedelta(days=day.isoweekday() - 1)


def weeks_intersecting(start: date, end_exclusive: date) -> list[date]:
    cursor = iso_week_start(start)
    weeks: list[date] = []
    seen: set[date] = set()
    while cursor < end_exclusive:
        week_end = cursor + timedelta(days=7)
        if week_end > start and cursor < end_exclusive and cursor not in seen:
            weeks.append(cursor)
            seen.add(cursor)
        cursor += timedelta(days=7)
    return weeks


def quarter_bounds(day: date) -> tuple[date, date]:
    quarter = ((day.month - 1) // 3) + 1
    start_month = (quarter - 1) * 3 + 1
    start = date(day.year, start_month, 1)
    if quarter == 4:
        end = date(day.year + 1, 1, 1)
    else:
        end = date(day.year, start_month + 3, 1)
    return start, end


def year_bounds(day: date) -> tuple[date, date]:
    return date(day.year, 1, 1), date(day.year + 1, 1, 1)


def metrics(today: date) -> dict[str, object]:
    iso_year, iso_week, _ = today.isocalendar()
    current_week_start = iso_week_start(today)

    quarter_start, quarter_end = quarter_bounds(today)
    year_start, year_end = year_bounds(today)
    quarter = ((today.month - 1) // 3) + 1

    quarter_weeks = weeks_intersecting(quarter_start, quarter_end)
    year_weeks = weeks_intersecting(year_start, year_end)

    quarter_remaining_incl = sum(1 for w in quarter_weeks if w >= current_week_start)
    year_remaining_incl = sum(1 for w in year_weeks if w >= current_week_start)
    quarter_elapsed_incl = sum(1 for w in quarter_weeks if w <= current_week_start)
    year_elapsed_incl = sum(1 for w in year_weeks if w <= current_week_start)

    return {
        "iso_week": iso_week,
        "iso_year": iso_year,
        "quarter": quarter,
        "year": today.year,
        "quarter_label": f"Q{quarter} {today.year}",
        "quarter_remaining_incl": quarter_remaining_incl,
        "quarter_remaining_excl": max(0, quarter_remaining_incl - 1),
        "year_remaining_incl": year_remaining_incl,
        "year_remaining_excl": max(0, year_remaining_incl - 1),
        "quarter_total": len(quarter_weeks),
        "quarter_elapsed": quarter_elapsed_incl,
        "year_total": len(year_weeks),
        "year_elapsed": year_elapsed_incl,
        "quarter_fraction": quarter_elapsed_incl / len(quarter_weeks),
        "year_fraction": year_elapsed_incl / len(year_weeks),
    }


def html_shell(title: str, body: str, styles: str) -> str:
    return f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>{title}</title>
  <style>{styles}</style>
</head>
<body>
{body}
</body>
</html>
"""


def app_preview_html(data: dict[str, object]) -> str:
    quarter_pct = round(float(data['quarter_fraction']) * 100, 1)
    year_pct = round(float(data['year_fraction']) * 100, 1)
    styles = """
:root {
  color-scheme: dark;
  --bg-1: #121826;
  --bg-2: #1f3b57;
  --bg-3: #2c5b74;
  --bar: rgba(18, 20, 28, 0.72);
  --surface: rgba(255,255,255,0.9);
  --surface-2: rgba(248,250,252,0.92);
  --border: rgba(15, 23, 42, 0.14);
  --text: #0f172a;
  --muted: #475569;
  --teal: #0891b2;
  --amber: #d97706;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
  background:
    radial-gradient(circle at top right, rgba(255,255,255,0.18), transparent 20%),
    radial-gradient(circle at bottom left, rgba(255,255,255,0.08), transparent 30%),
    linear-gradient(135deg, var(--bg-1), var(--bg-2) 56%, var(--bg-3));
}
.canvas {
  width: 1440px;
  height: 780px;
  position: relative;
  overflow: hidden;
}
.menu-bar {
  position: absolute;
  inset: 0 0 auto 0;
  height: 42px;
  background: var(--bar);
  backdrop-filter: blur(18px);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 16px;
  color: rgba(255,255,255,0.92);
  font-size: 15px;
}
.menu-left, .menu-right {
  display: flex;
  align-items: center;
  gap: 14px;
}
.dot {
  width: 10px;
  height: 10px;
  border-radius: 999px;
  background: rgba(255,255,255,0.8);
  display: inline-block;
}
.status-pill {
  border-radius: 999px;
  padding: 3px 10px;
  background: rgba(255,255,255,0.12);
}
.status-pill.week {
  background: rgba(255,255,255,0.18);
  font-weight: 700;
  letter-spacing: 0.03em;
}
.popover {
  position: absolute;
  top: 62px;
  right: 124px;
  width: 320px;
  border-radius: 18px;
  background: var(--surface-2);
  color: var(--text);
  border: 1px solid rgba(255,255,255,0.5);
  box-shadow: 0 24px 80px rgba(0,0,0,0.28), 0 10px 26px rgba(15, 23, 42, 0.18);
  padding: 18px;
}
.popover:before {
  content: "";
  position: absolute;
  top: -9px;
  right: 78px;
  width: 18px;
  height: 18px;
  background: var(--surface-2);
  transform: rotate(45deg);
  border-left: 1px solid rgba(255,255,255,0.55);
  border-top: 1px solid rgba(255,255,255,0.55);
}
.head {
  display: flex;
  align-items: baseline;
  gap: 12px;
  margin-bottom: 16px;
}
.week {
  font-size: 34px;
  font-weight: 800;
  letter-spacing: 0.02em;
}
.brand {
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.brand small {
  color: var(--muted);
  font-size: 12px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}
.brand span {
  color: var(--muted);
  font-size: 13px;
  font-weight: 600;
}
.section { margin-top: 14px; }
.section h3 {
  margin: 0 0 5px;
  font-size: 13px;
}
.section p {
  margin: 0 0 8px;
  font-size: 12px;
  color: var(--muted);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}
.track {
  height: 9px;
  border-radius: 999px;
  background: rgba(148, 163, 184, 0.22);
  overflow: hidden;
}
.fill {
  height: 100%;
  border-radius: 999px;
}
.fill.teal { background: linear-gradient(90deg, #0ea5e9, var(--teal)); }
.fill.amber { background: linear-gradient(90deg, #f59e0b, var(--amber)); }
.quit {
  margin-top: 18px;
  display: inline-flex;
  padding: 8px 13px;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: rgba(255,255,255,0.72);
  color: var(--text);
  font-weight: 600;
  font-size: 13px;
}
.caption {
  position: absolute;
  left: 36px;
  bottom: 36px;
  color: rgba(255,255,255,0.92);
  max-width: 460px;
}
.caption .eyebrow {
  display: inline-block;
  margin-bottom: 12px;
  padding: 5px 10px;
  border-radius: 999px;
  background: rgba(255,255,255,0.12);
  font-size: 12px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.caption h1 {
  margin: 0 0 10px;
  font-size: 42px;
  line-height: 1.02;
}
.caption p {
  margin: 0;
  font-size: 17px;
  line-height: 1.45;
  color: rgba(255,255,255,0.82);
}
"""
    body = f"""
<div class=\"canvas\">
  <div class=\"menu-bar\">
    <div class=\"menu-left\">
      <span></span>
      <span>Finder</span>
      <span>File</span>
      <span>Edit</span>
      <span>View</span>
      <span>Go</span>
      <span>Window</span>
      <span>Help</span>
    </div>
    <div class=\"menu-right\">
      <span class=\"status-pill\">⌘</span>
      <span class=\"status-pill\">􀙇</span>
      <span class=\"status-pill week\">W{data['iso_week']}</span>
      <span class=\"status-pill\">Mon 23 Mar</span>
    </div>
  </div>

  <div class=\"popover\">
    <div class=\"head\">
      <div class=\"week\">W{data['iso_week']}</div>
      <div class=\"brand\">
        <small>Peek Week</small>
        <span>{data['quarter_label']}</span>
      </div>
    </div>

    <div class=\"section\">
      <h3>Quarter</h3>
      <p>{data['quarter_remaining_incl']} incl / {data['quarter_remaining_excl']} excl remaining</p>
      <div class=\"track\"><div class=\"fill teal\" style=\"width:{quarter_pct}%\"></div></div>
    </div>

    <div class=\"section\">
      <h3>Year</h3>
      <p>{data['year_remaining_incl']} incl / {data['year_remaining_excl']} excl remaining</p>
      <div class=\"track\"><div class=\"fill amber\" style=\"width:{year_pct}%\"></div></div>
    </div>

    <button class=\"quit\">Quit</button>
  </div>

  <div class=\"caption\">
    <div class=\"eyebrow\">Menu bar utility</div>
    <h1>Week number, finally where it belongs.</h1>
    <p>A tiny native app that keeps the top bar clean: just <strong>W{data['iso_week']}</strong>, with quarter/year context one click away.</p>
  </div>
</div>
"""
    return html_shell("Peek Week app preview", body, styles)


def github_preview_html(data: dict[str, object]) -> str:
    styles = """
:root {
  --bg: #f6f8fa;
  --panel: #ffffff;
  --line: #d0d7de;
  --text: #1f2328;
  --muted: #57606a;
  --blue: #0969da;
  --green: #1a7f37;
  --shadow: 0 1px 0 rgba(31,35,40,0.04), 0 8px 24px rgba(140,149,159,0.2);
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
.page {
  width: 1440px;
  min-height: 1600px;
}
.topbar {
  height: 72px;
  background: #24292f;
  color: white;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 32px;
}
.topbar .brand {
  font-size: 20px;
  font-weight: 700;
}
.shell {
  padding: 28px 36px 48px;
}
.repo-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
}
.repo-head h1 {
  margin: 0;
  font-size: 32px;
  font-weight: 500;
}
.repo-head h1 a { color: var(--blue); text-decoration: none; }
.actions {
  display: flex;
  gap: 10px;
}
.btn {
  border: 1px solid rgba(31,35,40,0.15);
  background: #f6f8fa;
  border-radius: 6px;
  padding: 8px 14px;
  font-size: 14px;
  font-weight: 600;
}
.tabs {
  display: flex;
  gap: 24px;
  padding-bottom: 14px;
  border-bottom: 1px solid var(--line);
  margin-bottom: 24px;
  color: var(--muted);
}
.tabs .active {
  color: var(--text);
  font-weight: 700;
  border-bottom: 2px solid #fd8c73;
  padding-bottom: 12px;
  margin-bottom: -14px;
}
.grid {
  display: grid;
  grid-template-columns: 320px 1fr;
  gap: 24px;
}
.card {
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: 12px;
  box-shadow: var(--shadow);
}
.sidebar { padding: 18px; }
.sidebar h3 { margin: 0 0 14px; font-size: 16px; }
.kv { display: grid; gap: 12px; font-size: 14px; color: var(--muted); }
.kv strong { color: var(--text); display: block; margin-bottom: 4px; }
.readme {
  overflow: hidden;
}
.readme-header {
  padding: 16px 20px;
  border-bottom: 1px solid var(--line);
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 14px;
  color: var(--muted);
}
.markdown {
  padding: 32px;
  background: #fff;
}
.markdown h1, .markdown h2, .markdown h3 {
  margin-top: 0;
  margin-bottom: 16px;
}
.markdown h1 {
  font-size: 38px;
  line-height: 1.1;
}
.markdown h2 {
  font-size: 24px;
  padding-bottom: 8px;
  border-bottom: 1px solid #d8dee4;
  margin-top: 34px;
}
.markdown p, .markdown li {
  font-size: 16px;
  line-height: 1.6;
}
.markdown code {
  background: #f6f8fa;
  border: 1px solid #d8dee4;
  border-radius: 6px;
  padding: 0.12em 0.32em;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 14px;
}
.hero {
  border: 1px solid var(--line);
  border-radius: 12px;
  overflow: hidden;
  margin: 24px 0;
}
.hero img {
  display: block;
  width: 100%;
}
.badges {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  margin: 18px 0 10px;
}
.badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 10px;
  border-radius: 999px;
  background: #eef6ff;
  color: var(--blue);
  font-size: 13px;
  font-weight: 700;
}
.feature-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
  margin-top: 18px;
}
.feature {
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 16px;
  background: linear-gradient(180deg, #fff, #fbfdff);
}
.feature h3 {
  margin: 0 0 8px;
  font-size: 18px;
}
.feature p {
  margin: 0;
  color: var(--muted);
}
.install {
  margin-top: 26px;
  border: 1px solid #d8dee4;
  border-radius: 12px;
  overflow: hidden;
}
.install .head {
  background: #f6f8fa;
  padding: 12px 16px;
  font-size: 13px;
  color: var(--muted);
  border-bottom: 1px solid #d8dee4;
}
.install pre {
  margin: 0;
  padding: 18px;
  background: #0d1117;
  color: #e6edf3;
  font-size: 14px;
  line-height: 1.5;
  overflow: hidden;
}
.quote {
  margin-top: 28px;
  padding: 18px 22px;
  border-left: 4px solid #1f6feb;
  background: #f6f8fa;
  border-radius: 0 10px 10px 0;
  color: #3d444d;
}
"""
    body = f"""
<div class=\"page\">
  <div class=\"topbar\">
    <div class=\"brand\">GitHub</div>
    <div>Search or jump to…</div>
  </div>
  <div class=\"shell\">
    <div class=\"repo-head\">
      <h1><a href=\"#\">max</a> / <strong>peek-week</strong></h1>
      <div class=\"actions\">
        <button class=\"btn\">Watch</button>
        <button class=\"btn\">Fork</button>
        <button class=\"btn\">Star</button>
      </div>
    </div>

    <div class=\"tabs\">
      <div class=\"active\">Code</div>
      <div>Issues</div>
      <div>Pull requests</div>
      <div>Actions</div>
      <div>Releases</div>
    </div>

    <div class=\"grid\">
      <aside class=\"card sidebar\">
        <h3>About</h3>
        <div class=\"kv\">
          <div><strong>Tiny native macOS menu bar app</strong>Shows the current ISO week number as W{data['iso_week']}.</div>
          <div><strong>Release shape</strong>Source repo, zipped <code>.app</code>, screenshots, short install instructions.</div>
          <div><strong>Tech</strong>SwiftUI + AppKit + ServiceManagement</div>
          <div><strong>Target</strong>macOS 13+</div>
          <div><strong>License</strong>MIT</div>
        </div>
      </aside>

      <section class=\"card readme\">
        <div class=\"readme-header\">
          <div>README.md</div>
          <div>Preview</div>
        </div>
        <div class=\"markdown\">
          <h1>Peek Week</h1>
          <p>A tiny native macOS menu bar app that shows the current <strong>ISO week number</strong> as <code>W{data['iso_week']}</code>.</p>

          <div class=\"badges\">
            <span class=\"badge\">ISO 8601</span>
            <span class=\"badge\">Native menu bar app</span>
            <span class=\"badge\">No runtime deps</span>
            <span class=\"badge\">Launch at login</span>
          </div>

          <div class=\"hero\">
            <img src=\"app-running.png\" alt=\"Peek Week screenshot\" />
          </div>

          <h2>What it does</h2>
          <div class=\"feature-grid\">
            <div class=\"feature\">
              <h3>Menu bar first</h3>
              <p>Shows just the week number in the top bar — nothing more unless you click.</p>
            </div>
            <div class=\"feature\">
              <h3>Quarter + year context</h3>
              <p>Shows remaining weeks both including and excluding the current week.</p>
            </div>
            <div class=\"feature\">
              <h3>Native popover</h3>
              <p>Uses a standard transient macOS popover instead of inventing weird chrome.</p>
            </div>
            <div class=\"feature\">
              <h3>Shareable build</h3>
              <p>Build script emits both the <code>.app</code> bundle and a zipped release artifact.</p>
            </div>
          </div>

          <h2>Install</h2>
          <div class=\"install\">
            <div class=\"head\">Terminal</div>
            <pre>git clone &lt;repo-url&gt;
cd peek-week
./scripts/build-app.sh 0.1.0
open "build/Peek Week.app"</pre>
          </div>

          <div class=\"quote\">macOS shows the date in the menu bar, but not the week number. Sometimes you just want to glance up and see <strong>W{data['iso_week']}</strong>.</div>
        </div>
      </section>
    </div>
  </div>
</div>
"""
    return html_shell("Peek Week GitHub preview", body, styles)


def main() -> None:
    data = metrics(date.today())
    (DOCS / "app-shot.html").write_text(app_preview_html(data), encoding="utf-8")
    (DOCS / "github-page.html").write_text(github_preview_html(data), encoding="utf-8")
    print("Wrote:")
    print(f"- {DOCS / 'app-shot.html'}")
    print(f"- {DOCS / 'github-page.html'}")


if __name__ == "__main__":
    main()
