"use client";

import { Button } from "@heroui/react";

// Full-page navigation: /relogin is a route handler, not a Next page.
export function LoginButton({ href, label }: { href: string; label: string }) {
  return <Button onPress={() => window.location.assign(href)}>{label}</Button>;
}
