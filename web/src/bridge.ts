// Thin bridge between the page and the native macOS host (WKWebView).
// Page -> native: window.webkit.messageHandlers.macdraw.postMessage(msg)
// Native -> page: callAsyncJavaScript("window.macdraw.<fn>(...)")

export type ToNative =
  | { type: "ready" }
  | { type: "dirty" }
  | { type: "scene"; json: string }
  | { type: "library"; json: string }
  | { type: "log"; message: string };

type WebkitWindow = Window & {
  webkit?: { messageHandlers?: { macdraw?: { postMessage: (m: ToNative) => void } } };
};

export const isNative = () => !!(window as WebkitWindow).webkit?.messageHandlers?.macdraw;

export function post(msg: ToNative) {
  const handler = (window as WebkitWindow).webkit?.messageHandlers?.macdraw;
  if (handler) handler.postMessage(msg);
  else if (msg.type !== "dirty") console.debug("[bridge]", msg.type);
}
