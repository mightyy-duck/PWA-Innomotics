"use client";

import { useEffect } from "react";

import { logoutThen, relogin } from "@/lib/session";

// Session expiry (Pingpong: 15 min). Server-side middleware already enforces
// it on every navigation; this makes an idle open tab log out on time too.
export function SessionGuard({ expiresAt }: { expiresAt: number }) {
  useEffect(() => {
    const expire = () => window.location.assign(logoutThen(relogin()));
    const check = () => Date.now() >= expiresAt && expire();
    const t = setTimeout(expire, Math.max(0, expiresAt - Date.now()));

    document.addEventListener("visibilitychange", check); // timers throttle in background tabs

    return () => {
      clearTimeout(t);
      document.removeEventListener("visibilitychange", check);
    };
  }, [expiresAt]);

  return null;
}
