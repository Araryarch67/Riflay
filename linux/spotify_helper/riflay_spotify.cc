// Spotify sign-in for Riflay's library import (Beta) on Linux, in a WebKitGTK window.
//
// flutter_inappwebview's Linux backend needs WPE WebKit, which desktop distros
// rarely ship, so the app runs this small helper instead. It loads Spotify's
// own web player, which fetches its access token itself (the secret behind
// that request rotates, so Riflay never computes it): a script injected at
// document start keeps what the page fetches, and the helper prints it as one
// JSON line on stdout and exits 0:
//
//   {"cookies":"a=b; c=d","accessToken":"...","expiresAt":1700000000000,"clientToken":"...","appVersion":"..."}
//
// No arguments: a visible sign-in window. Closing it exits 3.
// --refresh: reads the cookie header from one stdin line and loads the player
// in a window that is never shown, to get a fresh token without asking the
// user. Exit 4 when the cookies are no longer signed in, 5 on a timeout.
// Any other non-zero exit is a failure. The WebKit profile is ephemeral:
// nothing stays on disk here, the app keeps the session itself.

#include <gtk/gtk.h>
#include <libsoup/soup.h>
#include <webkit2/webkit2.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

// Spotify's login page may refuse user agents it reads as embedded web views.
constexpr char kUserAgent[] =
    "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0";
constexpr char kStartUrl[] =
    "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F";
constexpr char kPlayerUrl[] = "https://open.spotify.com/";
constexpr char kOrigin[] = "https://open.spotify.com";

constexpr int kExitClosed = 3;
constexpr int kExitSignedOut = 4;
constexpr int kExitTimeout = 5;

constexpr gint64 kRefreshTimeoutUs = 45 * G_USEC_PER_SEC;
// How long an anonymous token is waited out in --refresh before the cookies
// count as signed out: the player may swap it for the real one a moment later.
constexpr gint64 kAnonymousGraceUs = 5 * G_USEC_PER_SEC;

// Keep this block identical to SpotifyLogin.captureJs in
// lib/services/spotify_session.dart (test/spotify_session_test.dart checks).
// It runs at document start in the top frame and records, in
// window.__riflaySpotify, what the web player fetches: the token response of
// /api/token, plus the client-token / app version headers and the bearer
// token of calls to Spotify's API hosts (a fallback for the token).
// BEGIN captureJs
constexpr char kCaptureJs[] = R"JS((() => {
  if (window.__riflaySpotifyHooked) return;
  window.__riflaySpotifyHooked = true;
  const state = (window.__riflaySpotify = {
    accessToken: '', expiresAt: 0, isAnonymous: null, clientToken: '', appVersion: '',
  });
  const urlOf = (u) => {
    try { return new URL(String(u), location.href); } catch (_) { return null; }
  };
  const isTokenUrl = (u) => !!u && u.hostname === 'open.spotify.com' && u.pathname === '/api/token';
  const isApiUrl = (u) => !!u && (u.hostname === 'api-partner.spotify.com' || u.hostname === 'spclient.wg.spotify.com' ||
    u.hostname.endsWith('.spclient.spotify.com'));
  const onToken = (text) => {
    try {
      const j = JSON.parse(text);
      if (!j || typeof j.accessToken !== 'string' || !j.accessToken) return;
      state.accessToken = j.accessToken;
      state.expiresAt = Number(j.accessTokenExpirationTimestampMs) || Date.now() + 50 * 60000;
      state.isAnonymous = j.isAnonymous === true;
    } catch (_) {}
  };
  const onHeader = (name, value) => {
    try {
      const n = String(name).toLowerCase();
      const v = String(value);
      if (n === 'client-token') state.clientToken = v;
      else if (n === 'spotify-app-version') state.appVersion = v;
      else if (n === 'authorization') {
        const m = /^Bearer\s+(.+)$/i.exec(v);
        if (m && m[1] !== state.accessToken) {
          state.accessToken = m[1];
          state.expiresAt = Date.now() + 50 * 60000;
          state.isAnonymous = null;
        }
      }
    } catch (_) {}
  };
  const onHeaders = (h) => {
    try {
      if (!h) return;
      if (typeof h.forEach === 'function' && !Array.isArray(h)) h.forEach((v, k) => onHeader(k, v));
      else if (Array.isArray(h)) h.forEach((p) => { if (p && p.length > 1) onHeader(p[0], p[1]); });
      else Object.keys(h).forEach((k) => onHeader(k, h[k]));
    } catch (_) {}
  };
  const origFetch = window.fetch;
  if (typeof origFetch === 'function') {
    window.fetch = function (input, init) {
      let url = null;
      try {
        url = urlOf(input && typeof input === 'object' && 'url' in input ? input.url : input);
        if (isApiUrl(url)) {
          if (input && typeof input === 'object' && input.headers) onHeaders(input.headers);
          if (init && init.headers) onHeaders(init.headers);
        }
      } catch (_) {}
      const result = origFetch.apply(this, arguments);
      try {
        if (isTokenUrl(url)) {
          result.then((r) => { try { r.clone().text().then(onToken, () => {}); } catch (_) {} }, () => {});
        }
      } catch (_) {}
      return result;
    };
  }
  const proto = window.XMLHttpRequest && window.XMLHttpRequest.prototype;
  if (proto) {
    const origOpen = proto.open;
    const origSet = proto.setRequestHeader;
    proto.open = function (method, url) {
      try {
        this.__riflayUrl = urlOf(url);
        if (isTokenUrl(this.__riflayUrl)) {
          this.addEventListener('load', () => {
            try { if (this.responseType === '' || this.responseType === 'text') onToken(this.responseText); } catch (_) {}
          });
        }
      } catch (_) {}
      return origOpen.apply(this, arguments);
    };
    proto.setRequestHeader = function (name, value) {
      try { if (isApiUrl(this.__riflayUrl)) onHeader(name, value); } catch (_) {}
      return origSet.apply(this, arguments);
    };
  }
})();)JS";
// END captureJs

struct State {
  WebKitWebView* view = nullptr;
  bool refresh = false;
  bool polling = false;   // a poll is in flight
  bool done = false;
  bool closed = false;
  int exit_code = 1;
  gint64 started = 0;
  gint64 anonymous_since = 0;
};

std::string JsonEscape(const std::string& in) {
  std::string out;
  for (char ch : in) {
    switch (ch) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (static_cast<unsigned char>(ch) < 0x20) {
          char buf[8];
          snprintf(buf, sizeof buf, "\\u%04x", ch);
          out += buf;
        } else {
          out += ch;
        }
    }
  }
  return out;
}

void Finish(State* state, int code) {
  if (state->done) return;
  state->done = true;
  state->exit_code = code;
  gtk_main_quit();
}

// What the injected script has recorded so far.
struct Captured {
  std::string access_token;
  std::string client_token;
  std::string app_version;
  double expires_at = 0;
  bool anonymous = false;  // isAnonymous === true
};

std::string StringProperty(JSCValue* object, const char* name) {
  std::string out;
  JSCValue* value = jsc_value_object_get_property(object, name);
  if (value != nullptr) {
    if (jsc_value_is_string(value)) {
      gchar* str = jsc_value_to_string(value);
      out = str;
      g_free(str);
    }
    g_object_unref(value);
  }
  return out;
}

struct Pending {
  State* state;
  Captured captured;
};

void OnCookies(GObject* source, GAsyncResult* result, gpointer data) {
  auto* pending = static_cast<Pending*>(data);
  State* state = pending->state;
  GError* error = nullptr;
  GList* cookies = webkit_cookie_manager_get_cookies_finish(WEBKIT_COOKIE_MANAGER(source), result, &error);
  g_clear_error(&error);
  std::string header;
  bool signed_in = false;
  for (GList* l = cookies; l != nullptr; l = l->next) {
    auto* cookie = static_cast<SoupCookie*>(l->data);
    const std::string name = soup_cookie_get_name(cookie);
    // sp_dc is Spotify's long-lived login cookie: no sp_dc, no signed-in user.
    if (name == "sp_dc") signed_in = true;
    if (!header.empty()) header += "; ";
    header += name + "=" + soup_cookie_get_value(cookie);
  }
  g_list_free_full(cookies, reinterpret_cast<GDestroyNotify>(soup_cookie_free));
  const Captured& c = pending->captured;
  if (signed_in) {
    printf("{\"cookies\":\"%s\",\"accessToken\":\"%s\",\"expiresAt\":%lld,\"clientToken\":\"%s\",\"appVersion\":\"%s\"}\n",
           JsonEscape(header).c_str(), JsonEscape(c.access_token).c_str(), static_cast<long long>(c.expires_at),
           JsonEscape(c.client_token).c_str(), JsonEscape(c.app_version).c_str());
    fflush(stdout);
    Finish(state, 0);
  } else if (state->refresh) {
    // A token without the login cookie is an anonymous session in disguise.
    Finish(state, kExitSignedOut);
  }
  state->polling = false;
  delete pending;
}

void OnCaptured(GObject* source, GAsyncResult* result, gpointer data) {
  auto* state = static_cast<State*>(data);
  GError* error = nullptr;
  JSCValue* value = webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(source), result, &error);
  g_clear_error(&error);
  Captured c;
  bool have = false;
  if (value != nullptr) {
    if (jsc_value_is_object(value)) {
      c.access_token = StringProperty(value, "accessToken");
      c.client_token = StringProperty(value, "clientToken");
      c.app_version = StringProperty(value, "appVersion");
      JSCValue* expires = jsc_value_object_get_property(value, "expiresAt");
      if (expires != nullptr) {
        if (jsc_value_is_number(expires)) c.expires_at = jsc_value_to_double(expires);
        g_object_unref(expires);
      }
      JSCValue* anonymous = jsc_value_object_get_property(value, "isAnonymous");
      if (anonymous != nullptr) {
        c.anonymous = jsc_value_is_boolean(anonymous) && jsc_value_to_boolean(anonymous);
        g_object_unref(anonymous);
      }
      have = !c.access_token.empty();
    }
    g_object_unref(value);
  }
  if (have && c.anonymous) {
    const gint64 now = g_get_monotonic_time();
    if (state->anonymous_since == 0) state->anonymous_since = now;
    if (state->refresh && now - state->anonymous_since >= kAnonymousGraceUs) Finish(state, kExitSignedOut);
    have = false;
  } else if (have) {
    state->anonymous_since = 0;
  }
  // Done needs the token AND the client token the data API asks for.
  if (!have || c.client_token.empty() || state->done) {
    state->polling = false;
    return;
  }
  auto* pending = new Pending{state, c};
  WebKitWebsiteDataManager* manager = webkit_web_view_get_website_data_manager(state->view);
  webkit_cookie_manager_get_cookies(webkit_website_data_manager_get_cookie_manager(manager), kOrigin, nullptr,
                                    OnCookies, pending);
}

gboolean Poll(gpointer data) {
  auto* state = static_cast<State*>(data);
  if (state->done) return G_SOURCE_REMOVE;
  if (state->refresh && g_get_monotonic_time() - state->started >= kRefreshTimeoutUs) {
    Finish(state, kExitTimeout);
    return G_SOURCE_REMOVE;
  }
  if (!state->polling) {
    state->polling = true;
    webkit_web_view_evaluate_javascript(state->view, "window.__riflaySpotify || null", -1, nullptr, nullptr, nullptr,
                                        OnCaptured, state);
  }
  return G_SOURCE_CONTINUE;
}

// Popups ("Continue with Google" / Apple / Facebook) need a real related view:
// the provider's page talks back to the one that opened it through
// window.opener. It shares the user script, so the capture stays on.
GtkWidget* OnCreate(WebKitWebView* view, WebKitNavigationAction*, gpointer) {
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_default_size(GTK_WINDOW(window), 480, 640);
  GtkWidget* popup = webkit_web_view_new_with_related_view(view);
  gtk_container_add(GTK_CONTAINER(window), popup);
  g_signal_connect(popup, "close", G_CALLBACK(+[](WebKitWebView*, gpointer w) {
                     gtk_widget_destroy(GTK_WIDGET(w));
                   }),
                   window);
  gtk_widget_show_all(window);
  return popup;
}

struct Seed {
  State* state;
  int remaining;
};

void OnCookieAdded(GObject* source, GAsyncResult* result, gpointer data) {
  auto* seed = static_cast<Seed*>(data);
  GError* error = nullptr;
  webkit_cookie_manager_add_cookie_finish(WEBKIT_COOKIE_MANAGER(source), result, &error);
  g_clear_error(&error);
  if (--seed->remaining > 0) return;
  // Every cookie is in the jar: only now can the page be loaded signed in.
  webkit_web_view_load_uri(seed->state->view, kPlayerUrl);
  delete seed;
}

// "a=b; c=d" -> name/value pairs.
std::vector<std::pair<std::string, std::string>> ParseCookieHeader(const std::string& header) {
  std::vector<std::pair<std::string, std::string>> out;
  size_t pos = 0;
  while (pos < header.size()) {
    size_t end = header.find(';', pos);
    if (end == std::string::npos) end = header.size();
    std::string part = header.substr(pos, end - pos);
    pos = end + 1;
    const size_t start = part.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) continue;
    part = part.substr(start);
    const size_t eq = part.find('=');
    if (eq == std::string::npos || eq == 0) continue;
    out.emplace_back(part.substr(0, eq), part.substr(eq + 1));
  }
  return out;
}

}  // namespace

int main(int argc, char** argv) {
  // WebKitGTK's DMA-BUF renderer kills the process with a Wayland "Error 71
  // (Protocol error)" on NVIDIA and some hybrid-GPU setups. The window is a
  // login form: the plain renderer is plenty, and works everywhere.
  setenv("WEBKIT_DISABLE_DMABUF_RENDERER", "1", 0);

  State state;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--refresh") == 0) state.refresh = true;
  }
  std::string cookie_header;
  if (state.refresh) {
    char line[16384];
    if (fgets(line, sizeof line, stdin) != nullptr) cookie_header = line;
  }
  const auto seeds = ParseCookieHeader(cookie_header);
  bool has_login_cookie = false;
  for (const auto& s : seeds) has_login_cookie = has_login_cookie || s.first == "sp_dc";
  if (state.refresh && !has_login_cookie) return kExitSignedOut;

  gtk_init(&argc, &argv);
  state.started = g_get_monotonic_time();

  GtkWidget* window;
  if (state.refresh) {
    // Never shown, but realized, so WebKit still runs the page and its scripts.
    window = gtk_offscreen_window_new();
  } else {
    window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), "Sign in to Spotify");
    gtk_window_set_default_size(GTK_WINDOW(window), 480, 720);
    g_signal_connect(window, "delete-event", G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer data) -> gboolean {
                       static_cast<State*>(data)->closed = true;
                       return FALSE;
                     }),
                     &state);
  }
  g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), nullptr);

  WebKitWebsiteDataManager* data = webkit_website_data_manager_new_ephemeral();
  WebKitWebContext* context = webkit_web_context_new_with_website_data_manager(data);
  state.view = WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(context));
  webkit_settings_set_user_agent(webkit_web_view_get_settings(state.view), kUserAgent);

  WebKitUserScript* script = webkit_user_script_new(kCaptureJs, WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
                                                    WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
  webkit_user_content_manager_add_script(webkit_web_view_get_user_content_manager(state.view), script);
  webkit_user_script_unref(script);
  g_signal_connect(state.view, "create", G_CALLBACK(OnCreate), nullptr);

  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(state.view));
  gtk_widget_show_all(window);

  if (state.refresh) {
    WebKitCookieManager* jar = webkit_website_data_manager_get_cookie_manager(data);
    webkit_cookie_manager_set_accept_policy(jar, WEBKIT_COOKIE_POLICY_ACCEPT_ALWAYS);
    auto* seed = new Seed{&state, static_cast<int>(seeds.size())};
    for (const auto& s : seeds) {
      SoupCookie* cookie = soup_cookie_new(s.first.c_str(), s.second.c_str(), ".spotify.com", "/", -1);
      soup_cookie_set_secure(cookie, TRUE);
      webkit_cookie_manager_add_cookie(jar, cookie, nullptr, OnCookieAdded, seed);
      soup_cookie_free(cookie);
    }
  } else {
    webkit_web_view_load_uri(state.view, kStartUrl);
  }
  g_timeout_add(500, Poll, &state);
  gtk_main();
  if (state.done) return state.exit_code;
  return state.closed ? kExitClosed : 1;
}
