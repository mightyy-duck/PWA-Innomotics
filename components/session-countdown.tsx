"use client";

import { Clock } from "lucide-react";
import { useEffect, useState } from "react";

const format = (ms: number) => {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const m = String(Math.floor(total / 60)).padStart(2, "0");
  const s = String(total % 60).padStart(2, "0");

  return `${m}:${s}`;
};

// expiresAt: epoch ms of the Easy Auth session cookie expiry (computed server-side).
export function SessionCountdown({ expiresAt }: { expiresAt: number }) {
  // null until mounted: avoids a server/client hydration mismatch on Date.now().
  const [left, setLeft] = useState<number | null>(null);

  useEffect(() => {
    const tick = () => {
      const remaining = expiresAt - Date.now();

      setLeft(remaining);
      // Cookie is gone: a full reload lets Easy Auth send us to the login page.
      if (remaining <= 0) window.location.reload();
    };

    tick();
    const id = setInterval(tick, 1000);

    return () => clearInterval(id);
  }, [expiresAt]);

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
