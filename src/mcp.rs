// WorkDesk для Claude Code: `WorkDesk --mcp` — MCP-сервер (JSON-RPC по stdio).
// Это еще один «интерфейс» сеанса рядом с Flutter и Sciter: подключение идет по обычному протоколу,
// удаленная сторона видит обычное входящее подключение и может его разорвать.
use crate::{
    client::QualityStatus,
    input::{
        MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL, MOUSE_TYPE_DOWN, MOUSE_TYPE_MOVE,
        MOUSE_TYPE_UP, MOUSE_TYPE_WHEEL,
    },
    ui_session_interface::{io_loop, InvokeUiSession, Session},
};
use base::message_proto::*;
use hbb_common::{
    config::PeerConfig,
    rendezvous_proto::ConnType,
};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    io::{BufRead, Write},
    sync::{atomic::AtomicUsize, Arc, Mutex, RwLock},
    time::{Duration, Instant},
};

const PROTOCOL_VERSION: &str = "2025-06-18";
const MAX_IMAGE_SIDE: u32 = 1568;
const TERMINAL_ID: i32 = 1;

#[derive(Default)]
struct State {
    connected: bool,
    closed: bool,
    waiting_accept: bool,
    last_msg: Option<(String, String, String)>,
    displays: Vec<DisplayInfo>,
    current_display: i32,
    platform: String,
    hostname: String,
    username: String,
    screenshot: Option<String>,
    term_opened: Option<(bool, String)>,
    term_out: Vec<u8>,
    term_closed: bool,
}

#[derive(Clone, Default)]
pub struct McpHandler(Arc<Mutex<State>>);

impl McpHandler {
    fn st(&self) -> std::sync::MutexGuard<'_, State> {
        self.0.lock().unwrap()
    }
}

impl InvokeUiSession for McpHandler {
    fn set_cursor_data(&self, _cd: CursorData) {}
    fn set_cursor_id(&self, _id: String) {}
    fn set_cursor_position(&self, _cp: CursorPosition) {}
    fn set_display(&self, _x: i32, _y: i32, _w: i32, _h: i32, _cursor_embedded: bool, _scale: f64) {}
    fn switch_display(&self, display: &SwitchDisplay) {
        let mut st = self.st();
        st.current_display = display.display;
        if let Some(d) = st.displays.get_mut(display.display as usize) {
            d.x = display.x;
            d.y = display.y;
            d.width = display.width;
            d.height = display.height;
        }
    }
    fn set_peer_info(&self, pi: &PeerInfo) {
        let mut st = self.st();
        st.displays = pi.displays.clone();
        st.current_display = pi.current_display;
        st.platform = pi.platform.clone();
        st.hostname = pi.hostname.clone();
        st.username = pi.username.clone();
    }
    fn set_displays(&self, displays: &Vec<DisplayInfo>) {
        self.st().displays = displays.clone();
    }
    fn set_platform_additions(&self, _data: &str) {}
    fn on_connected(&self, _conn_type: ConnType) {
        let mut st = self.st();
        st.connected = true;
        st.waiting_accept = false;
    }
    fn update_privacy_mode(&self) {}
    fn set_permission(&self, _name: &str, _value: bool) {}
    fn close_success(&self) {}
    fn update_quality_status(&self, _qs: QualityStatus) {}
    fn set_connection_type(&self, _is_secured: bool, _direct: bool, _stream_type: &str) {}
    fn set_fingerprint(&self, _fingerprint: String) {}
    fn job_error(&self, _id: i32, _err: String, _file_num: i32) {}
    fn job_done(&self, _id: i32, _file_num: i32) {}
    fn clear_all_jobs(&self) {}
    fn new_message(&self, _msg: String) {}
    fn update_transfer_list(&self) {}
    fn load_last_job(&self, _cnt: i32, _job_json: &str, _auto_start: bool) {}
    fn update_folder_files(
        &self,
        _id: i32,
        _entries: &Vec<FileEntry>,
        _path: String,
        _is_local: bool,
        _only_count: bool,
    ) {
    }
    fn confirm_delete_files(&self, _id: i32, _i: i32, _name: String) {}
    fn override_file_confirm(
        &self,
        _id: i32,
        _file_num: i32,
        _to: String,
        _is_upload: bool,
        _is_identical: bool,
    ) {
    }
    fn update_block_input_state(&self, _on: bool) {}
    fn job_progress(&self, _id: i32, _file_num: i32, _speed: f64, _finished_size: f64) {}
    fn adapt_size(&self) {}
    fn on_rgba(&self, _display: usize, _rgba: &mut scrap::ImageRgb) {}
    fn msgbox(&self, msgtype: &str, title: &str, text: &str, _link: &str, _retry: bool) {
        let mut st = self.st();
        if msgtype.starts_with("wait-remote-accept") {
            st.waiting_accept = true;
        }
        if msgtype == "error" || msgtype.contains("input-password") {
            st.closed = !msgtype.contains("input-password");
        }
        st.last_msg = Some((msgtype.to_owned(), title.to_owned(), text.to_owned()));
    }
    fn cancel_msgbox(&self, _tag: &str) {}
    fn switch_back(&self, _id: &str) {}
    fn portable_service_running(&self, _running: bool) {}
    fn on_voice_call_started(&self) {}
    fn on_voice_call_closed(&self, _reason: &str) {}
    fn on_voice_call_waiting(&self) {}
    fn on_voice_call_incoming(&self) {}
    fn get_rgba(&self, _display: usize) -> *const u8 {
        std::ptr::null()
    }
    fn next_rgba(&self, _display: usize) {}
    #[cfg(all(feature = "vram", feature = "flutter"))]
    fn on_texture(&self, _display: usize, _texture: *mut std::ffi::c_void) {}
    fn set_multiple_windows_session(&self, _sessions: Vec<WindowsSession>) {}
    fn set_current_display(&self, disp_idx: i32) {
        self.st().current_display = disp_idx;
    }
    #[cfg(feature = "flutter")]
    fn is_multi_ui_session(&self) -> bool {
        false
    }
    fn update_record_status(&self, _start: bool) {}
    fn printer_request(&self, _id: i32, _path: String) {}
    fn handle_screenshot_resp(&self, _sid: String, msg: String) {
        self.st().screenshot = Some(msg);
    }
    fn handle_terminal_response(&self, response: TerminalResponse) {
        use terminal_response::Union;
        let mut st = self.st();
        match response.union {
            Some(Union::Opened(o)) => st.term_opened = Some((o.success, o.message)),
            Some(Union::Data(d)) => {
                let data = if d.compressed {
                    hbb_common::compress::decompress(&d.data)
                } else {
                    d.data.to_vec()
                };
                st.term_out.extend_from_slice(&data);
            }
            Some(Union::Closed(_)) => st.term_closed = true,
            Some(Union::Error(e)) => st.term_opened = Some((false, e.message)),
            _ => {}
        }
    }
}

struct Conn {
    id: String,
    desktop: Session<McpHandler>,
    dh: McpHandler,
    terminal: Option<(Session<McpHandler>, McpHandler)>,
    shot_size: HashMap<i32, (u32, u32)>,
    marker: u64,
}

fn start_session(id: &str, password: &str, conn_type: ConnType) -> (Session<McpHandler>, McpHandler) {
    let h = McpHandler::default();
    let session: Session<McpHandler> = Session {
        password: password.to_owned(),
        ui_handler: h.clone(),
        server_keyboard_enabled: Arc::new(RwLock::new(true)),
        server_file_transfer_enabled: Arc::new(RwLock::new(true)),
        server_clipboard_enabled: Arc::new(RwLock::new(true)),
        reconnect_count: Arc::new(AtomicUsize::new(0)),
        ..Default::default()
    };
    session
        .lc
        .write()
        .unwrap()
        .initialize(id.to_owned(), conn_type, None, false, None, None, None, "");
    let s = session.clone();
    std::thread::spawn(move || {
        let round = s.connection_round_state.lock().unwrap().new_round();
        io_loop(s, round);
    });
    (session, h)
}

fn wait_connected(h: &McpHandler, timeout: Duration) -> Result<(), String> {
    let start = Instant::now();
    loop {
        {
            let st = h.st();
            if st.connected {
                return Ok(());
            }
            if let Some((t, title, text)) = &st.last_msg {
                if st.closed || t.contains("input-password") {
                    let hint = if t.contains("input-password") {
                        " Укажите пароль (password) или попросите пользователя удаленного устройства принять подключение."
                    } else {
                        ""
                    };
                    return Err(format!("{}: {}.{}", title, text, hint));
                }
            }
        }
        if start.elapsed() > timeout {
            let waiting = h.st().waiting_accept;
            return Err(if waiting {
                "Удаленная сторона не приняла подключение за отведенное время.".to_owned()
            } else {
                "Не удалось подключиться за отведенное время.".to_owned()
            });
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

pub struct Server {
    conns: HashMap<String, Conn>,
}

fn text(s: impl Into<String>) -> Value {
    json!({ "content": [{ "type": "text", "text": s.into() }] })
}

fn err(s: impl Into<String>) -> Value {
    json!({ "content": [{ "type": "text", "text": s.into() }], "isError": true })
}

fn arg_str<'a>(a: &'a Value, k: &str) -> Option<&'a str> {
    a.get(k).and_then(|v| v.as_str())
}

fn arg_i64(a: &Value, k: &str) -> Option<i64> {
    a.get(k).and_then(|v| v.as_i64().or_else(|| v.as_f64().map(|f| f as i64)))
}

fn png_size(data: &[u8]) -> Option<(u32, u32)> {
    if data.len() < 24 || &data[1..4] != b"PNG" {
        return None;
    }
    let w = u32::from_be_bytes([data[16], data[17], data[18], data[19]]);
    let h = u32::from_be_bytes([data[20], data[21], data[22], data[23]]);
    Some((w, h))
}

fn shrink_png(data: Vec<u8>) -> (Vec<u8>, u32, u32) {
    let Some((w, h)) = png_size(&data) else {
        return (data, 0, 0);
    };
    if w.max(h) <= MAX_IMAGE_SIDE {
        return (data, w, h);
    }
    let Ok(img) = image::load_from_memory(&data) else {
        return (data, w, h);
    };
    let img = img.resize(MAX_IMAGE_SIDE, MAX_IMAGE_SIDE, image::imageops::FilterType::Triangle);
    let mut out = std::io::Cursor::new(Vec::new());
    if img.write_to(&mut out, image::ImageOutputFormat::Png).is_err() {
        return (data, w, h);
    }
    (out.into_inner(), img.width(), img.height())
}

fn strip_ansi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            match chars.peek() {
                Some('[') => {
                    chars.next();
                    while let Some(n) = chars.next() {
                        if ('@'..='~').contains(&n) {
                            break;
                        }
                    }
                }
                Some(']') => {
                    chars.next();
                    while let Some(n) = chars.next() {
                        if n == '\u{7}' {
                            break;
                        }
                        if n == '\u{1b}' {
                            chars.next();
                            break;
                        }
                    }
                }
                _ => {
                    chars.next();
                }
            }
        } else if c != '\r' {
            out.push(c);
        }
    }
    out
}

fn key_name(k: &str) -> String {
    let up = k.to_uppercase();
    let mapped = match up.as_str() {
        "ENTER" | "RETURN" => "VK_RETURN",
        "TAB" => "VK_TAB",
        "ESC" | "ESCAPE" => "VK_ESCAPE",
        "BACKSPACE" => "VK_BACK",
        "DELETE" | "DEL" => "VK_DELETE",
        "SPACE" => "VK_SPACE",
        "UP" => "VK_UP",
        "DOWN" => "VK_DOWN",
        "LEFT" => "VK_LEFT",
        "RIGHT" => "VK_RIGHT",
        "HOME" => "VK_HOME",
        "END" => "VK_END",
        "PAGEUP" => "VK_PRIOR",
        "PAGEDOWN" => "VK_NEXT",
        "INSERT" => "VK_INSERT",
        "WIN" | "META" | "SUPER" | "CMD" => "Meta",
        _ => "",
    };
    if !mapped.is_empty() {
        return mapped.to_owned();
    }
    if up.starts_with("VK_") {
        return up;
    }
    if up.len() <= 3 && up.starts_with('F') && up[1..].parse::<u8>().is_ok() {
        return format!("VK_{}", up);
    }
    if k.chars().count() == 1 {
        return k.to_lowercase();
    }
    up
}

impl Server {
    fn conn(&mut self, a: &Value) -> Result<&mut Conn, String> {
        let id = match arg_str(a, "id") {
            Some(id) => id.replace(' ', ""),
            None if self.conns.len() == 1 => self.conns.keys().next().cloned().unwrap_or_default(),
            None => return Err("Укажите id устройства.".to_owned()),
        };
        self.conns
            .get_mut(&id)
            .ok_or_else(|| format!("Нет подключения к {}. Сначала вызовите workdesk_connect.", id))
    }

    fn tools() -> Value {
        let id = json!({ "type": "string", "description": "ID устройства WorkDesk (можно не указывать, если подключение одно)" });
        json!([
            { "name": "workdesk_list_peers", "description": "Недавние устройства WorkDesk этого компьютера: ID, имя, ОС.",
              "inputSchema": { "type": "object", "properties": {} } },
            { "name": "workdesk_connect", "description": "Подключиться к устройству WorkDesk по ID. Удаленная сторона увидит обычное входящее подключение. Без пароля используется сохраненный пароль или ожидание подтверждения на удаленной стороне.",
              "inputSchema": { "type": "object", "required": ["id"], "properties": {
                  "id": { "type": "string" },
                  "password": { "type": "string", "description": "Пароль устройства (необязательно)" },
                  "timeout_sec": { "type": "integer", "default": 60 } } } },
            { "name": "workdesk_status", "description": "Состояние подключений: ОС, пользователь, мониторы.",
              "inputSchema": { "type": "object", "properties": {} } },
            { "name": "workdesk_screenshot", "description": "Снимок экрана удаленного устройства (PNG). Координаты для workdesk_mouse — в пикселях этого снимка.",
              "inputSchema": { "type": "object", "properties": { "id": id, "display": { "type": "integer", "description": "Номер монитора, по умолчанию текущий" } } } },
            { "name": "workdesk_mouse", "description": "Мышь: move, click, double_click, right_click, middle_click, scroll, drag. x, y — пиксели последнего снимка этого монитора.",
              "inputSchema": { "type": "object", "required": ["action"], "properties": { "id": id,
                  "action": { "type": "string", "enum": ["move", "click", "double_click", "right_click", "middle_click", "scroll", "drag"] },
                  "x": { "type": "integer" }, "y": { "type": "integer" },
                  "to_x": { "type": "integer", "description": "Для drag" }, "to_y": { "type": "integer" },
                  "scroll_y": { "type": "integer", "description": "Для scroll: >0 вверх, <0 вниз (щелчки колеса)" },
                  "display": { "type": "integer" } } } },
            { "name": "workdesk_type", "description": "Набрать текст на удаленном устройстве.",
              "inputSchema": { "type": "object", "required": ["text"], "properties": { "id": id, "text": { "type": "string" } } } },
            { "name": "workdesk_key", "description": "Нажать клавишу или сочетание: Enter, Tab, Esc, Backspace, Delete, стрелки, F1–F12, буква; модификаторы ctrl, alt, shift, meta.",
              "inputSchema": { "type": "object", "required": ["key"], "properties": { "id": id, "key": { "type": "string" },
                  "ctrl": { "type": "boolean" }, "alt": { "type": "boolean" }, "shift": { "type": "boolean" }, "meta": { "type": "boolean" } } } },
            { "name": "workdesk_run", "description": "Выполнить команду в терминале удаленного устройства (Windows — PowerShell, Linux/macOS — оболочка пользователя) и вернуть вывод и код выхода. Требует разрешения «Терминал» на удаленной стороне.",
              "inputSchema": { "type": "object", "required": ["command"], "properties": { "id": id, "command": { "type": "string" },
                  "timeout_sec": { "type": "integer", "default": 60 } } } },
            { "name": "workdesk_disconnect", "description": "Отключиться от устройства.",
              "inputSchema": { "type": "object", "properties": { "id": id } } }
        ])
    }

    fn call(&mut self, name: &str, a: &Value) -> Value {
        let r = match name {
            "workdesk_list_peers" => Ok(self.list_peers()),
            "workdesk_connect" => self.connect(a),
            "workdesk_status" => Ok(self.status()),
            "workdesk_screenshot" => self.screenshot(a),
            "workdesk_mouse" => self.mouse(a),
            "workdesk_type" => self.conn(a).map(|c| {
                c.desktop.input_string(arg_str(a, "text").unwrap_or(""));
                text("Текст отправлен.")
            }),
            "workdesk_key" => self.key(a),
            "workdesk_run" => self.run(a),
            "workdesk_disconnect" => self.disconnect(a),
            _ => Err(format!("Неизвестный инструмент {}", name)),
        };
        r.unwrap_or_else(err)
    }

    fn list_peers(&self) -> Value {
        let peers: Vec<Value> = PeerConfig::peers(None)
            .into_iter()
            .take(50)
            .map(|(id, _, p)| {
                json!({ "id": id, "alias": p.options.get("alias").cloned().unwrap_or_default(),
                        "hostname": p.info.hostname, "username": p.info.username, "platform": p.info.platform })
            })
            .collect();
        text(serde_json::to_string_pretty(&peers).unwrap_or_default())
    }

    fn connect(&mut self, a: &Value) -> Result<Value, String> {
        let id = arg_str(a, "id").ok_or("Укажите id устройства.")?.replace(' ', "");
        if let Some(c) = self.conns.get(&id) {
            let st = c.dh.st();
            if st.connected && !st.closed {
                return Ok(text(format!("Уже подключено к {}.", id)));
            }
        }
        if let Some(old) = self.conns.remove(&id) {
            close_conn(old);
        }
        let password = arg_str(a, "password").unwrap_or("");
        let timeout = Duration::from_secs(arg_i64(a, "timeout_sec").unwrap_or(60).clamp(5, 600) as u64);
        let (desktop, dh) = start_session(&id, password, ConnType::DEFAULT_CONN);
        if let Err(e) = wait_connected(&dh, timeout) {
            desktop.close();
            return Err(e);
        }
        let info = {
            let st = dh.st();
            format!(
                "Подключено к {}: {} ({}), пользователь {}, мониторов: {}. Удаленная сторона видит подключение и может его разорвать.",
                id, st.hostname, st.platform, st.username, st.displays.len()
            )
        };
        self.conns.insert(
            id.clone(),
            Conn { id, desktop, dh, terminal: None, shot_size: HashMap::new(), marker: 0 },
        );
        Ok(text(info))
    }

    fn status(&self) -> Value {
        let list: Vec<Value> = self
            .conns
            .values()
            .map(|c| {
                let st = c.dh.st();
                json!({ "id": c.id, "connected": st.connected && !st.closed, "hostname": st.hostname,
                        "platform": st.platform, "username": st.username, "current_display": st.current_display,
                        "displays": st.displays.iter().enumerate().map(|(i, d)| json!({
                            "display": i, "name": d.name, "width": d.width, "height": d.height })).collect::<Vec<_>>(),
                        "last_message": st.last_msg.as_ref().map(|m| format!("{}: {}", m.1, m.2)) })
            })
            .collect();
        text(serde_json::to_string_pretty(&list).unwrap_or_default())
    }

    fn screenshot(&mut self, a: &Value) -> Result<Value, String> {
        let c = self.conn(a)?;
        if !c.desktop.is_screenshot_supported() {
            return Err("Версия WorkDesk на удаленном устройстве не поддерживает снимки экрана.".to_owned());
        }
        let display = arg_i64(a, "display").map(|d| d as i32).unwrap_or_else(|| c.dh.st().current_display);
        c.dh.st().screenshot = None;
        c.desktop.take_screenshot(display, "mcp".to_owned());
        let start = Instant::now();
        let msg = loop {
            if let Some(m) = c.dh.st().screenshot.take() {
                break m;
            }
            if start.elapsed() > Duration::from_secs(30) {
                return Err("Снимок экрана не получен за 30 с.".to_owned());
            }
            std::thread::sleep(Duration::from_millis(50));
        };
        if !msg.is_empty() {
            return Err(format!("Снимок экрана: {}", msg));
        }
        let path = std::env::temp_dir().join(format!("workdesk-mcp-{}.png", std::process::id()));
        let res = crate::client::screenshot::handle_screenshot(format!("0:{}", path.display()));
        if !res.is_empty() {
            return Err(format!("Снимок экрана: {}", res));
        }
        let data = std::fs::read(&path).map_err(|e| e.to_string())?;
        std::fs::remove_file(&path).ok();
        let (png, w, h) = shrink_png(data);
        c.shot_size.insert(display, (w, h));
        Ok(json!({ "content": [
            { "type": "image", "data": crate::encode64(&png), "mimeType": "image/png" },
            { "type": "text", "text": format!("Монитор {}: снимок {}x{} пикселей.", display, w, h) }
        ] }))
    }

    fn to_remote(c: &Conn, display: i32, x: i64, y: i64) -> (i32, i32) {
        let st = c.dh.st();
        let Some(d) = st.displays.get(display as usize) else {
            return (x as i32, y as i32);
        };
        let (sw, sh) = c.shot_size.get(&display).cloned().unwrap_or((d.width as u32, d.height as u32));
        let sx = if sw > 0 { d.width as f64 / sw as f64 } else { 1.0 };
        let sy = if sh > 0 { d.height as f64 / sh as f64 } else { 1.0 };
        (d.x + (x as f64 * sx).round() as i32, d.y + (y as f64 * sy).round() as i32)
    }

    fn mouse(&mut self, a: &Value) -> Result<Value, String> {
        let c = self.conn(a)?;
        let action = arg_str(a, "action").unwrap_or("click");
        let display = arg_i64(a, "display").map(|d| d as i32).unwrap_or_else(|| c.dh.st().current_display);
        let (x, y) = match (arg_i64(a, "x"), arg_i64(a, "y")) {
            (Some(x), Some(y)) => Self::to_remote(c, display, x, y),
            _ if action == "scroll" => (0, 0),
            _ => return Err("Укажите x и y.".to_owned()),
        };
        let s = &c.desktop;
        let send = |mask: i32, x: i32, y: i32| s.send_mouse(mask, x, y, false, false, false, false);
        let pause = || std::thread::sleep(Duration::from_millis(40));
        let click = |button: i32| {
            send(MOUSE_TYPE_MOVE, x, y);
            pause();
            send(button << 3 | MOUSE_TYPE_DOWN, x, y);
            pause();
            send(button << 3 | MOUSE_TYPE_UP, x, y);
        };
        match action {
            "move" => send(MOUSE_TYPE_MOVE, x, y),
            "click" => click(MOUSE_BUTTON_LEFT),
            "double_click" => {
                click(MOUSE_BUTTON_LEFT);
                std::thread::sleep(Duration::from_millis(80));
                click(MOUSE_BUTTON_LEFT);
            }
            "right_click" => click(MOUSE_BUTTON_RIGHT),
            "middle_click" => click(MOUSE_BUTTON_WHEEL),
            "scroll" => {
                if arg_i64(a, "x").is_some() {
                    send(MOUSE_TYPE_MOVE, x, y);
                    pause();
                }
                let n = arg_i64(a, "scroll_y").unwrap_or(-3);
                for _ in 0..n.unsigned_abs().min(50) {
                    send(MOUSE_TYPE_WHEEL, 0, if n > 0 { 1 } else { -1 });
                    pause();
                }
            }
            "drag" => {
                let (tx, ty) = match (arg_i64(a, "to_x"), arg_i64(a, "to_y")) {
                    (Some(tx), Some(ty)) => Self::to_remote(c, display, tx, ty),
                    _ => return Err("Для drag укажите to_x и to_y.".to_owned()),
                };
                send(MOUSE_TYPE_MOVE, x, y);
                pause();
                send(MOUSE_BUTTON_LEFT << 3 | MOUSE_TYPE_DOWN, x, y);
                for i in 1..=10 {
                    pause();
                    send(MOUSE_TYPE_MOVE, x + (tx - x) * i / 10, y + (ty - y) * i / 10);
                }
                pause();
                send(MOUSE_BUTTON_LEFT << 3 | MOUSE_TYPE_UP, tx, ty);
            }
            other => return Err(format!("Неизвестное действие {}", other)),
        }
        Ok(text(format!("{}: выполнено.", action)))
    }

    fn key(&mut self, a: &Value) -> Result<Value, String> {
        let c = self.conn(a)?;
        let key = arg_str(a, "key").ok_or("Укажите key.")?;
        let flag = |k: &str| a.get(k).and_then(|v| v.as_bool()).unwrap_or(false);
        c.desktop.input_key(&key_name(key), true, true, flag("alt"), flag("ctrl"), flag("shift"), flag("meta"));
        Ok(text(format!("Нажато: {}", key)))
    }

    fn run(&mut self, a: &Value) -> Result<Value, String> {
        let c = self.conn(a)?;
        let command = arg_str(a, "command").ok_or("Укажите command.")?.to_owned();
        let timeout = Duration::from_secs(arg_i64(a, "timeout_sec").unwrap_or(60).clamp(1, 1800) as u64);
        let windows = c.dh.st().platform.to_lowercase().contains("windows");
        if c.terminal.as_ref().map_or(true, |(_, h)| {
            let st = h.st();
            st.closed || st.term_closed
        }) {
            if let Some((old, _)) = c.terminal.take() {
                old.close();
            }
            let password = c.desktop.password.clone();
            let (ts, th) = start_session(&c.id, &password, ConnType::TERMINAL);
            if let Err(e) = wait_connected(&th, Duration::from_secs(60)) {
                ts.close();
                return Err(format!("Терминал: {}", e));
            }
            ts.open_terminal(TERMINAL_ID, 50, 200);
            let start = Instant::now();
            loop {
                if let Some((ok, msg)) = th.st().term_opened.clone() {
                    if !ok {
                        ts.close();
                        return Err(format!("Терминал не открыт: {}", msg));
                    }
                    break;
                }
                if start.elapsed() > Duration::from_secs(30) {
                    ts.close();
                    return Err("Терминал не открылся за 30 с. Проверьте разрешение «Терминал» на удаленной стороне.".to_owned());
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            std::thread::sleep(Duration::from_millis(800));
            th.st().term_out.clear();
            c.terminal = Some((ts, th));
        }
        c.marker += 1;
        let tag = format!("{}_{}", std::process::id(), c.marker);
        // Маркер собирается из частей, чтобы эхо введенной строки не совпало с ним
        let line = if windows {
            format!("{}\r\nWrite-Output ('__WD' + '_END_{}__' + $LASTEXITCODE)\r\n", command, tag)
        } else {
            format!("{}\nprintf '%s%s\\n' '__WD' \"_END_{}__$?\"\n", command, tag)
        };
        let marker = format!("__WD_END_{}__", tag);
        let (ts, th) = c.terminal.as_ref().unwrap();
        th.st().term_out.clear();
        ts.send_terminal_input(TERMINAL_ID, line);
        let start = Instant::now();
        loop {
            let out = String::from_utf8_lossy(&th.st().term_out).to_string();
            let clean = strip_ansi(&out);
            if let Some(pos) = clean.rfind(&marker) {
                let code: String = clean[pos + marker.len()..].chars().take_while(|ch| ch.is_ascii_digit() || *ch == '-').collect();
                let body = clean[..pos].to_owned();
                let body = trim_echo(&body, &command);
                return Ok(text(format!("Код выхода: {}\n{}", if code.is_empty() { "?" } else { code.as_str() }, body)));
            }
            let gone = {
                let st = th.st();
                st.term_closed || st.closed
            };
            if gone {
                return Err(format!("Терминал закрыт удаленной стороной.\n{}", clean));
            }
            if start.elapsed() > timeout {
                return Ok(text(format!(
                    "Команда еще выполняется (прошло {} с). Вывод на сейчас:\n{}",
                    timeout.as_secs(),
                    tail(&clean, 20000)
                )));
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }

    fn disconnect(&mut self, a: &Value) -> Result<Value, String> {
        let id = self.conn(a)?.id.clone();
        if let Some(c) = self.conns.remove(&id) {
            close_conn(c);
        }
        Ok(text(format!("Отключено от {}.", id)))
    }
}

fn close_conn(c: Conn) {
    if let Some((ts, _)) = c.terminal {
        ts.close_terminal(TERMINAL_ID);
        ts.close();
    }
    c.desktop.close();
}

fn tail(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_owned();
    }
    let mut start = s.len() - max;
    while !s.is_char_boundary(start) {
        start += 1;
    }
    s[start..].to_owned()
}

fn trim_echo(body: &str, command: &str) -> String {
    let first = command.lines().next().unwrap_or("").trim();
    let lines: Vec<&str> = body
        .lines()
        .filter(|l| {
            let t = l.trim();
            !(t.contains("_END_") && (t.contains("'__WD'") || t.contains("__WD' +")))
        })
        .collect();
    let skip = lines.iter().position(|l| !first.is_empty() && l.contains(first)).map_or(0, |i| i + 1);
    let out: Vec<&str> = lines.into_iter().skip(skip).collect();
    tail(out.join("\n").trim_matches('\n'), 50000)
}

fn reply(out: &mut impl Write, id: &Value, result: Result<Value, (i64, String)>) {
    let msg = match result {
        Ok(r) => json!({ "jsonrpc": "2.0", "id": id, "result": r }),
        Err((code, m)) => json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": m } }),
    };
    let _ = writeln!(out, "{}", msg);
    let _ = out.flush();
}

pub fn run() {
    let mut server = Server { conns: HashMap::new() };
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        if line.trim().is_empty() {
            continue;
        }
        let Ok(req) = serde_json::from_str::<Value>(&line) else {
            reply(&mut stdout.lock(), &Value::Null, Err((-32700, "Parse error".to_owned())));
            continue;
        };
        let Some(id) = req.get("id").cloned() else {
            continue; // уведомление
        };
        let method = req.get("method").and_then(|m| m.as_str()).unwrap_or("");
        let params = req.get("params").cloned().unwrap_or(json!({}));
        let result = match method {
            "initialize" => Ok(json!({
                "protocolVersion": params.get("protocolVersion").and_then(|v| v.as_str()).unwrap_or(PROTOCOL_VERSION),
                "capabilities": { "tools": {} },
                "serverInfo": { "name": "workdesk", "version": crate::VERSION },
                "instructions": "WorkDesk: удаленный доступ к устройствам. Сначала workdesk_connect по ID, затем workdesk_screenshot / workdesk_mouse / workdesk_type / workdesk_key / workdesk_run. Каждое подключение видно пользователю удаленного устройства и в журнале консоли WorkDesk."
            })),
            "ping" => Ok(json!({})),
            "tools/list" => Ok(json!({ "tools": Server::tools() })),
            "tools/call" => {
                let name = params.get("name").and_then(|v| v.as_str()).unwrap_or("").to_owned();
                let args = params.get("arguments").cloned().unwrap_or(json!({}));
                Ok(server.call(&name, &args))
            }
            _ => Err((-32601, format!("Method not found: {}", method))),
        };
        reply(&mut stdout.lock(), &id, result);
    }
    for (_, c) in server.conns.drain() {
        close_conn(c);
    }
    std::thread::sleep(Duration::from_millis(300));
}
