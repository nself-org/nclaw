import type { Metadata, Viewport } from 'next';
import { NextIntlClientProvider } from 'next-intl';
import { getLocale, getMessages } from 'next-intl/server';
import { ClawWebProvider } from '@/providers/claw-web-provider';
import { QueryProvider } from '@/providers/query-provider';
import '@/styles/globals.css';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'ɳClaw',
  description: 'Your AI assistant with infinite memory',
};

export const viewport: Viewport = {
  themeColor: '#0F0F1A',
};

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const locale = await getLocale();
  const messages = await getMessages();

  return (
    <html lang={locale} className="dark">
      <body>
        <NextIntlClientProvider messages={messages}>
          <QueryProvider>
            <ClawWebProvider>{children}</ClawWebProvider>
          </QueryProvider>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
