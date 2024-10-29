import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Next.js Self Hosted",
  description: "This is hosted on Ubuntu Linux with Caddy as a reverse proxy.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head></head>
      <body>{children}</body>
    </html>
  );
}
