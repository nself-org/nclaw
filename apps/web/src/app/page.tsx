'use client'

import { useState, useEffect } from 'react'

const STORAGE_KEY = 'nclaw_server_url'

export default function HomePage() {
  const [url, setUrl] = useState('')
  const [input, setInput] = useState('')
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
    const saved =
      process.env.NEXT_PUBLIC_CLAW_URL ||
      localStorage.getItem(STORAGE_KEY) ||
      ''
    if (saved) {
      setUrl(saved)
      window.location.replace(saved)
    }
  }, [])

  function connect() {
    const trimmed = input.trim().replace(/\/$/, '')
    if (!trimmed) return
    localStorage.setItem(STORAGE_KEY, trimmed)
    window.location.replace(trimmed)
  }

  function handleKey(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Enter') connect()
  }

  if (!mounted) return null

  if (url) {
    return (
      <div className="flex h-full items-center justify-center">
        <p className="text-[#9797B8] text-sm">Redirecting…</p>
      </div>
    )
  }

  return (
    <div className="flex h-full items-center justify-center px-4">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <h1 className="text-2xl font-semibold text-white">
            Connect your ɳClaw server
          </h1>
          <p className="mt-3 text-sm text-[#9797B8] leading-relaxed">
            ɳClaw is a self-hosted AI assistant. Enter the URL of your nClaw
            server to get started.
          </p>
        </div>

        <div className="space-y-3">
          <input
            type="url"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKey}
            placeholder="https://claw.yourdomain.com"
            className="w-full rounded-lg border border-[#2A2A40] bg-[#16162A] px-4 py-3 text-sm text-white placeholder-[#4A4A6A] outline-none focus:border-[#6366F1] focus:ring-1 focus:ring-[#6366F1]"
            autoFocus
          />
          <button
            type="button"
            onClick={connect}
            className="w-full rounded-lg bg-[#6366F1] px-4 py-3 text-sm font-medium text-white hover:bg-[#5254CC] active:bg-[#4446B8] transition-colors"
          >
            Connect
          </button>
        </div>

        <p className="mt-6 text-center text-xs text-[#4A4A6A]">
          Don&apos;t have a server yet?{' '}
          <a
            href="https://docs.nself.org/claw/setup"
            target="_blank"
            rel="noopener noreferrer"
            className="text-[#6366F1] hover:underline"
          >
            Set one up in 5 minutes
          </a>
        </p>
      </div>
    </div>
  )
}
