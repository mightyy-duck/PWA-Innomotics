import { NextResponse, type NextRequest } from "next/server";

import { SESSION_COOKIE } from "@/lib/session";

export const dynamic = "force-dynamic";

// Log out = drop the Easy Auth session cookie(s) and our stamp here, then start a new Easy
// Auth login straight away (prompt=login in loginParameters forces it); it lands on
// /auth/established, which stamps the new login time for the countdown.
// NOT /.auth/logout: that goes through Microsoft's logout page and its
// "Pick an account to sign out" picker.
export function GET(req: NextRequest) {
  // Relative Location: req.url carries the internal bind address behind App Service.
  const res = new NextResponse(null, {
    status: 307,
    headers: { Location: "/.auth/login/aad?post_login_redirect_uri=%2Fauth%2Festablished", "Cache-Control": "no-store" },
  });
  const secure = req.nextUrl.protocol === "https:" || req.headers.get("x-forwarded-proto") === "https";

  for (const { name } of req.cookies.getAll()) {
    if (name.startsWith("AppServiceAuthSession") || name === SESSION_COOKIE) {
      res.cookies.set(name, "", { path: "/", expires: new Date(0), httpOnly: true, secure });
    }
  }

  return res;
}
