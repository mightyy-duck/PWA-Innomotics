"use client";

import { Clock } from "lucide-react";
import { useEffect, useState } from "react";

const format = (ms: number) => {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const m = String(Math.floor(total / 60)).padStart(2, "0");
  const s = String(total % 60).padStart(2, "0");

  return `${m}:${s}`;
};

// expiresAt: epoch ms the app-enforced session ends (login stamp + SESSION_MINUTES).
export function SessionCountdown({ expiresAt, serverNow }: { expiresAt: number; serverNow: number }) {
  // null until mounted: avoids a server/client hydration mismatch on Date.now().
  const [left, setLeft] = useState<number | null>(null);

  useEffect(() => {
    // Server clock offset, so a wrong device clock can't skew the countdown.
    const offset = serverNow - Date.now();
    const tick = () => {
      const remaining = expiresAt - (Date.now() + offset);

      setLeft(remaining);
      // The app owns the limit (middleware.ts would bounce us here anyway); /signout
      // drops the cookies and starts a fresh login whatever Easy Auth thinks.
      if (remaining <= 0) {
        clearInterval(id);
        window.location.assign("/signout");
      }
    };

    const id = setInterval(tick, 1000);

    tick();

    // Timers are throttled/frozen in background tabs; re-check when the tab returns.
    const onShow = () => document.visibilityState === "visible" && tick();

    document.addEventListener("visibilitychange", onShow);
    window.addEventListener("pageshow", onShow);

    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", onShow);
      window.removeEventListener("pageshow", onShow);
    };
  }, [expiresAt, serverNow]);

  return (
    <p className="mt-2 flex items-center gap-1.5" aria-live="off">
      <Clock size={14} />
      Session expires in{" "}
      <span className={`font-mono tabular-nums ${left !== null && left < 60_000 ? "text-danger" : ""}`}>
        {left === null ? "--:--" : format(left)}
      </span>
    </p>
  );
}
