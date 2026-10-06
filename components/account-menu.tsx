"use client";

import { Avatar, Button } from "@heroui/react";
import { LogOut } from "lucide-react";

const initials = (name: string) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join("");

export function AccountMenu({ name, email }: { name: string; email: string }) {
  return (
    <div className="flex items-center gap-3">
      <Avatar>
        <Avatar.Fallback>{initials(name) || "?"}</Avatar.Fallback>
      </Avatar>
      <div className="flex flex-col leading-tight">
        <span className="text-sm font-medium">{name}</span>
        {email && <span className="text-xs text-muted">{email}</span>}
      </div>
      {/* Full-page navigation: /signout is a route handler, not a Next page. */}
      <Button size="sm" variant="secondary" onPress={() => window.location.assign("/signout")}>
        <LogOut size={14} />
        Log out
      </Button>
    </div>
  );
}
