import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PWA-Innomotics",
  description: "Innomotics PWA",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-background text-foreground">{children}</body>
    </html>
  );
}
