import { NextResponse, type NextRequest } from "next/server";

import { getUser } from "@/lib/easy-auth";
import { isHttps, SESSION_COOKIE, SESSION_MINUTES, signStart } from "@/lib/session";

export const dynamic = "force-dynamic";

// Easy Auth redirects here right after the login callback (post_login_redirect_uri),
// i.e. the moment its cookie was created. We stamp that moment for the countdown.
export async function GET(req: NextRequest) {
  const user = await getUser();
  const fresh = user?.issuedAt && Math.abs(Date.now() / 1000 - user.issuedAt) < 300;

  // Not a just-completed login (stale token or direct visit): can't re-stamp, or a
  // user could extend their session by revisiting this URL. Force a real login.
  if (!user || !fresh) {
    return new NextResponse(null, { status: 307, headers: { Location: "/signout", "Cache-Control": "no-store" } });
  }

  const start = Date.now();
  const res = new NextResponse(null, { status: 307, headers: { Location: "/", "Cache-Control": "no-store" } });

  res.cookies.set(SESSION_COOKIE, signStart(start), {
    path: "/",
    httpOnly: true,
    sameSite: "lax",
    secure: isHttps(req),
    expires: new Date(start + SESSION_MINUTES * 60_000),
  });

  return res;
}
