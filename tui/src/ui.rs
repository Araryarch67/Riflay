//! Drawing. Called only when something changed (an event, a key, the clock while playing).

use ratatui::Frame;
use ratatui::buffer::Buffer;
use ratatui::layout::{Alignment, Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{
    Block, BorderType, Borders, Clear, List, ListItem, ListState, Paragraph, Widget, Wrap,
};

use crate::app::{App, COVER, SOURCES, Tab, Track};

const DIM: Color = Color::Rgb(120, 120, 128);
const TEXT: Color = Color::Rgb(230, 230, 235);

fn time(ms: u64) -> String {
    let s = ms / 1000;
    if s >= 3600 {
        format!("{}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60)
    } else {
        format!("{}:{:02}", s / 60, s % 60)
    }
}

pub fn draw(f: &mut Frame, app: &App) {
    let area = f.area();
    let viz = if app.show_visualizer && area.height >= 20 {
        5
    } else {
        0
    };
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1),
            Constraint::Min(5),
            Constraint::Length(viz),
            Constraint::Length(2),
            Constraint::Length(1),
        ])
        .split(area);
    header(f, app, rows[0]);
    // The cover and the song beside the lists where there is room; on a narrow terminal the lists alone.
    let side = app.show_cover && area.width >= 78 && rows[1].height >= 12;
    let body = Layout::default()
        .direction(Direction::Horizontal)
        .constraints(if side {
            vec![Constraint::Length(COVER as u16 + 4), Constraint::Min(30)]
        } else {
            vec![Constraint::Min(30)]
        })
        .split(rows[1]);
    if side {
        now_playing(f, app, body[0]);
    }
    let main = body[body.len() - 1];
    match app.tab {
        Tab::Queue => queue(f, app, main, !side),
        Tab::Lyrics => lyrics(f, app, main),
        Tab::Search => search(f, app, main),
        Tab::Library => tracks(
            f,
            app,
            main,
            " Library ",
            &app.library,
            app.library_cursor.at,
            None,
        ),
        Tab::Playlists => playlists(f, app, main),
    }
    if viz > 0 {
        visualizer(f.buffer_mut(), app, rows[2]);
    }
    progress(f, app, rows[3]);
    footer(f, app, rows[4]);
    if app.help {
        help(f, app, area);
    }
}

fn header(f: &mut Frame, app: &App, area: Rect) {
    let mut spans = vec![
        Span::styled(
            " ♪ Riflay ",
            Style::default()
                .fg(Color::Black)
                .bg(app.accent)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(" "),
    ];
    for (i, tab) in Tab::ALL.iter().enumerate() {
        let on = *tab == app.tab;
        let style = if on {
            Style::default()
                .fg(app.accent)
                .add_modifier(Modifier::BOLD | Modifier::UNDERLINED)
        } else {
            Style::default().fg(DIM)
        };
        spans.push(Span::styled(format!(" {} {} ", i + 1, tab.title()), style));
    }
    spans.push(Span::styled(
        if app.standalone {
            "  standalone"
        } else {
            "  app"
        },
        Style::default().fg(DIM),
    ));
    f.render_widget(Paragraph::new(Line::from(spans)), area);
}

/// The cover in half blocks (two pixels a cell, top and bottom), then the song.
struct Cover<'a>(&'a [u8], usize);

impl Widget for Cover<'_> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let (rgb, size) = (self.0, self.1);
        let px = |x: usize, y: usize| {
            let i = (y * size + x) * 3;
            Color::Rgb(rgb[i], rgb[i + 1], rgb[i + 2])
        };
        for row in 0..(size / 2).min(area.height as usize) {
            for col in 0..size.min(area.width as usize) {
                if let Some(cell) = buf.cell_mut((area.x + col as u16, area.y + row as u16)) {
                    cell.set_char('▀')
                        .set_fg(px(col, row * 2))
                        .set_bg(px(col, row * 2 + 1));
                }
            }
        }
    }
}

fn now_playing(f: &mut Frame, app: &App, area: Rect) {
    let inner = Rect {
        x: area.x + 2,
        y: area.y + 1,
        width: area.width.saturating_sub(3),
        height: area.height.saturating_sub(1),
    };
    let cover_rows = (COVER / 2) as u16;
    let art = Rect {
        height: cover_rows.min(inner.height),
        ..inner
    };
    match &app.cover {
        Some((_, size, rgb)) => f.render_widget(Cover(rgb, *size), art),
        None => f.render_widget(
            Paragraph::new(
                vec![Line::raw(""); (cover_rows / 2) as usize]
                    .into_iter()
                    .chain([Line::styled("♪", Style::default().fg(DIM))])
                    .collect::<Vec<_>>(),
            )
            .alignment(Alignment::Center)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_type(BorderType::Rounded)
                    .border_style(Style::default().fg(Color::Rgb(50, 50, 56))),
            ),
            art,
        ),
    }
    let text = Rect {
        y: inner.y + cover_rows + 1,
        height: inner.height.saturating_sub(cover_rows + 1),
        ..inner
    };
    let mut lines = vec![];
    match &app.track {
        Some(t) => {
            lines.push(Line::styled(
                t.title.clone(),
                Style::default().fg(TEXT).add_modifier(Modifier::BOLD),
            ));
            lines.push(Line::styled(
                t.artist.clone(),
                Style::default().fg(app.accent),
            ));
            if !t.album.is_empty() {
                lines.push(Line::styled(t.album.clone(), Style::default().fg(DIM)));
            }
        }
        None => lines.push(Line::styled("Nothing playing", Style::default().fg(DIM))),
    }
    f.render_widget(Paragraph::new(lines).wrap(Wrap { trim: true }), text);
}

fn panel(title: &str, app: &App) -> Block<'static> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(Color::Rgb(60, 60, 68)))
        .title(Span::styled(
            title.to_string(),
            Style::default().fg(app.accent).add_modifier(Modifier::BOLD),
        ))
}

fn row(t: &Track, width: u16, mark: &str, on: bool, accent: Color) -> ListItem<'static> {
    let dur = t.duration_ms.map(time).unwrap_or_default();
    let room = (width as usize).saturating_sub(dur.len() + 6);
    let title_room = room * 3 / 5;
    let fit = |s: &str, n: usize| fit(s, n);
    let title_style = if on {
        Style::default().fg(accent).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(TEXT)
    };
    ListItem::new(Line::from(vec![
        Span::styled(format!("{mark} "), Style::default().fg(accent)),
        Span::styled(fit(&t.title, title_room), title_style),
        Span::raw(" "),
        Span::styled(fit(&t.artist, room - title_room), Style::default().fg(DIM)),
        Span::styled(format!(" {dur}"), Style::default().fg(DIM)),
    ]))
}

fn list(
    f: &mut Frame,
    app: &App,
    area: Rect,
    title: &str,
    items: Vec<ListItem<'static>>,
    at: usize,
    empty: &str,
) {
    let block = panel(title, app);
    if items.is_empty() {
        f.render_widget(
            Paragraph::new(Line::styled(empty.to_string(), Style::default().fg(DIM))).block(block),
            area,
        );
        return;
    }
    let mut state = ListState::default().with_selected(Some(at));
    let widget = List::new(items)
        .block(block)
        .highlight_style(Style::default().bg(Color::Rgb(44, 44, 52)));
    f.render_stateful_widget(widget, area, &mut state);
}

fn queue(f: &mut Frame, app: &App, area: Rect, with_song: bool) {
    let mut area = area;
    if with_song {
        // No room for the cover column: the song on a line above the queue.
        if let Some(t) = &app.track {
            let line = Line::from(vec![
                Span::styled(
                    format!(" {} ", t.title),
                    Style::default().fg(TEXT).add_modifier(Modifier::BOLD),
                ),
                Span::styled(t.artist.clone(), Style::default().fg(app.accent)),
            ]);
            f.render_widget(Paragraph::new(line), Rect { height: 1, ..area });
            area = Rect {
                y: area.y + 1,
                height: area.height.saturating_sub(1),
                ..area
            };
        }
    }
    let width = area.width.saturating_sub(4);
    let items = app
        .queue
        .iter()
        .map(|(_, current, t)| {
            row(
                t,
                width,
                if *current { "▶" } else { " " },
                *current,
                app.accent,
            )
        })
        .collect();
    list(
        f,
        app,
        area,
        " Queue ",
        items,
        app.queue_cursor.at,
        "The queue is empty. Search (/) and press Enter to play.",
    );
}

fn lyrics(f: &mut Frame, app: &App, area: Rect) {
    let block = panel(" Lyrics ", app);
    let inner_h = area.height.saturating_sub(2) as usize;
    let Some(l) = app
        .lyrics
        .as_ref()
        .filter(|l| app.track.as_ref().map(|t| &t.id) == Some(&l.track_id))
    else {
        let text = if app.track.is_some() {
            "Looking for lyrics…"
        } else {
            "Nothing playing"
        };
        f.render_widget(
            Paragraph::new(Line::styled(text, Style::default().fg(DIM)))
                .alignment(Alignment::Center)
                .block(block),
            area,
        );
        return;
    };
    if l.lines.is_empty() {
        let lines: Vec<Line> = if l.plain.is_empty() {
            vec![Line::styled(
                "No lyrics for this song",
                Style::default().fg(DIM),
            )]
        } else {
            l.plain
                .iter()
                .map(|s| Line::styled(s.clone(), Style::default().fg(TEXT)))
                .collect()
        };
        f.render_widget(
            Paragraph::new(lines)
                .alignment(Alignment::Center)
                .wrap(Wrap { trim: true })
                .block(block),
            area,
        );
        return;
    }
    // The line sung now in the middle, the ones around it fading.
    let now = app.position();
    let current = l.lines.iter().rposition(|(ms, _)| *ms <= now).unwrap_or(0);
    let top = current.saturating_sub(inner_h / 2);
    let lines: Vec<Line> = l.lines[top..l.lines.len().min(top + inner_h)]
        .iter()
        .enumerate()
        .map(|(i, (_, text))| {
            let index = top + i;
            let style = if index == current {
                Style::default().fg(app.accent).add_modifier(Modifier::BOLD)
            } else if index.abs_diff(current) <= 2 {
                Style::default().fg(TEXT)
            } else {
                Style::default().fg(DIM)
            };
            Line::styled(
                if text.is_empty() {
                    "♪".to_string()
                } else {
                    text.clone()
                },
                style,
            )
        })
        .collect();
    let title = if l.source.is_empty() {
        " Lyrics ".to_string()
    } else {
        format!(" Lyrics · {} ", l.source)
    };
    f.render_widget(
        Paragraph::new(lines)
            .alignment(Alignment::Center)
            .block(panel(&title, app)),
        area,
    );
}

fn search(f: &mut Frame, app: &App, area: Rect) {
    let parts = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(3)])
        .split(area);
    let cursor = if app.search_editing { "▏" } else { "" };
    let source = SOURCES[app.search_source];
    let input = Line::from(vec![
        Span::styled(
            format!(" {source} "),
            Style::default().fg(Color::Black).bg(app.accent),
        ),
        Span::raw("  "),
        if app.search_query.is_empty() && !app.search_editing {
            Span::styled(
                "Press / to search, Tab while typing to change the source",
                Style::default().fg(DIM),
            )
        } else {
            Span::styled(
                format!("{}{cursor}", app.search_query),
                Style::default().fg(TEXT),
            )
        },
    ]);
    let border = if app.search_editing {
        app.accent
    } else {
        Color::Rgb(60, 60, 68)
    };
    f.render_widget(
        Paragraph::new(input).block(
            Block::default()
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(Style::default().fg(border)),
        ),
        parts[0],
    );
    let width = parts[1].width.saturating_sub(4);
    let items = app
        .search_results
        .iter()
        .map(|t| row(t, width, " ", false, app.accent))
        .collect();
    let empty = if app.search_busy {
        "Searching…"
    } else {
        "Enter plays · a adds to the queue · i plays next"
    };
    list(
        f,
        app,
        parts[1],
        " Results ",
        items,
        app.search_cursor.at,
        empty,
    );
}

fn tracks(
    f: &mut Frame,
    app: &App,
    area: Rect,
    title: &str,
    tracks: &[Track],
    at: usize,
    empty: Option<&str>,
) {
    let width = area.width.saturating_sub(4);
    let playing = app.track.as_ref().map(|t| t.id.as_str());
    let items = tracks
        .iter()
        .map(|t| {
            let on = Some(t.id.as_str()) == playing;
            row(t, width, if on { "♪" } else { " " }, on, app.accent)
        })
        .collect();
    list(
        f,
        app,
        area,
        title,
        items,
        at,
        empty.unwrap_or("Nothing here yet"),
    );
}

fn playlists(f: &mut Frame, app: &App, area: Rect) {
    if let Some((_, name, t)) = &app.playlist_open {
        tracks(
            f,
            app,
            area,
            &format!(" {name} · Enter plays it · Esc back "),
            t,
            app.playlist_cursor.at,
            Some("This playlist is empty"),
        );
        return;
    }
    let items = app
        .playlists
        .iter()
        .map(|(_, name, count)| {
            ListItem::new(Line::from(vec![
                Span::styled(format!("  {name}"), Style::default().fg(TEXT)),
                Span::styled(format!("  {count} songs"), Style::default().fg(DIM)),
            ]))
        })
        .collect();
    list(
        f,
        app,
        area,
        " Playlists ",
        items,
        app.playlists_cursor.at,
        "No playlists yet",
    );
}

/// Bars, bass to treble, eighth blocks for the tops.
fn visualizer(buf: &mut Buffer, app: &App, area: Rect) {
    const STEPS: [char; 8] = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
    if app.levels.is_empty() || area.width < 4 {
        return;
    }
    let width = area.width.saturating_sub(4) as usize;
    let height = area.height as usize * 8;
    for col in 0..width {
        let band = col * app.levels.len() / width;
        let level = app.levels[band] as usize * height / 100;
        for r in 0..area.height as usize {
            let from_bottom = (area.height as usize - 1 - r) * 8;
            let fill = level.saturating_sub(from_bottom).min(8);
            if fill == 0 {
                continue;
            }
            if let Some(cell) = buf.cell_mut((area.x + 2 + col as u16, area.y + r as u16)) {
                cell.set_char(STEPS[fill - 1]).set_fg(app.accent);
            }
        }
    }
}

fn progress(f: &mut Frame, app: &App, area: Rect) {
    let now = app.position();
    let total = app.duration_ms.unwrap_or(0);
    let width = area.width.saturating_sub(4) as usize;
    let done = if total > 0 {
        (now as f64 / total as f64 * width as f64) as usize
    } else {
        0
    }
    .min(width);
    let bar = Line::from(vec![
        Span::raw("  "),
        Span::styled("━".repeat(done), Style::default().fg(app.accent)),
        Span::styled(
            if width > done { "●" } else { "" },
            Style::default().fg(TEXT),
        ),
        Span::styled(
            "─".repeat(width.saturating_sub(done + 1)),
            Style::default().fg(Color::Rgb(70, 70, 78)),
        ),
    ]);
    let state = if app.buffering {
        "◌"
    } else if app.playing {
        "▶"
    } else {
        "⏸"
    };
    let repeat = match app.repeat.as_str() {
        "all" => "↻ all",
        "one" => "↻ one",
        _ => "↻ off",
    };
    let on = |b: bool| {
        if b {
            Style::default().fg(app.accent)
        } else {
            Style::default().fg(DIM)
        }
    };
    let left = format!(
        "  {state}  {} / {}",
        time(now),
        if total > 0 {
            time(total)
        } else {
            "--:--".into()
        }
    );
    let info = Line::from(vec![
        Span::styled(left, Style::default().fg(TEXT)),
        Span::raw("    "),
        Span::styled("⇄ shuffle", on(app.shuffle)),
        Span::raw("   "),
        Span::styled(repeat, on(app.repeat != "off")),
        Span::raw("   "),
        Span::styled(
            if app.can_set_volume {
                format!("vol {}%", app.volume)
            } else {
                "vol fixed".into()
            },
            Style::default().fg(DIM),
        ),
    ]);
    f.render_widget(Paragraph::new(vec![bar, info]), area);
}

fn footer(f: &mut Frame, app: &App, area: Rect) {
    let line = if let Some(why) = &app.disconnected {
        Line::styled(
            format!(" {why}"),
            Style::default().fg(Color::Rgb(255, 170, 90)),
        )
    } else if let Some((text, _)) = &app.toast {
        Line::styled(format!(" {text}"), Style::default().fg(app.accent))
    } else if let Some(error) = &app.last_error {
        Line::styled(
            format!(" {error}"),
            Style::default().fg(Color::Rgb(255, 120, 120)),
        )
    } else {
        Line::styled(
            " space play/pause · n/p next/prev · ←/→ seek · +/- volume · / search · v visualizer · ? help · q quit",
            Style::default().fg(DIM),
        )
    };
    f.render_widget(Paragraph::new(line), area);
}

fn help(f: &mut Frame, app: &App, area: Rect) {
    let keys = [
        ("space", "play / pause"),
        ("n  p", "next / previous"),
        ("←  →", "seek 5 s   ([ ] 30 s)"),
        ("+  -", "volume"),
        ("s  r", "shuffle / repeat"),
        ("1-5  Tab", "queue, lyrics, search, library, playlists"),
        ("↑ ↓  j k", "move   (PgUp PgDn, g G)"),
        ("Enter", "play the selected song or playlist"),
        ("a  i", "add to the queue / play next"),
        ("d", "remove from the queue"),
        ("/", "search (Tab: library, YouTube, SoundCloud)"),
        ("v  c", "visualizer / cover"),
        ("q", "quit (Riflay keeps playing)"),
    ];
    let lines: Vec<Line> = keys
        .iter()
        .map(|(k, what)| {
            Line::from(vec![
                Span::styled(
                    format!(" {k:<10}"),
                    Style::default().fg(app.accent).add_modifier(Modifier::BOLD),
                ),
                Span::styled(*what, Style::default().fg(TEXT)),
            ])
        })
        .collect();
    let w = 62.min(area.width);
    let h = (lines.len() as u16 + 2).min(area.height);
    let r = Rect {
        x: area.x + (area.width - w) / 2,
        y: area.y + (area.height - h) / 2,
        width: w,
        height: h,
    };
    f.render_widget(Clear, r);
    f.render_widget(
        Paragraph::new(lines).block(panel(" Keys · any key closes ", app)),
        r,
    );
}

/// [text] in exactly [width] terminal columns: padded, or cut with an ellipsis. Measured by what each character
/// takes on screen (a Japanese character or an emoji two columns), so the columns after it stay in line.
fn fit(text: &str, width: usize) -> String {
    use unicode_width::UnicodeWidthChar;
    let mut out = String::new();
    let mut used = 0;
    let total: usize = text.chars().map(|c| c.width().unwrap_or(0)).sum();
    if total <= width {
        out.push_str(text);
        used = total;
    } else {
        for c in text.chars() {
            let w = c.width().unwrap_or(0);
            if used + w + 1 > width {
                break;
            }
            out.push(c);
            used += w;
        }
        if width > 0 {
            out.push('…');
            used += 1;
        }
    }
    out.extend(std::iter::repeat_n(' ', width.saturating_sub(used)));
    out
}

#[cfg(test)]
mod tests {
    use super::fit;
    use unicode_width::UnicodeWidthStr;

    #[test]
    fn fits_wide_characters_in_their_columns() {
        assert_eq!(fit("abc", 5), "abc  ");
        assert_eq!(fit("abcdef", 4), "abc…");
        // Japanese takes two columns a character: never more than the room, padded to it.
        for (text, width) in [
            ("あなたは マリン", 7),
            ("魅惑を隠す箱", 6),
            ("KING", 10),
            ("I'm 🏴‍☠️ here", 5),
        ] {
            assert_eq!(fit(text, width).width(), width, "{text}");
        }
    }
}
