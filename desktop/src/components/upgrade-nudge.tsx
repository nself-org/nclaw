import React, { useRef, useState, useEffect } from 'react'
import { invoke } from '@tauri-apps/api/core'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'

interface UpgradeConfig {
  upgrade_prompt_disabled: boolean
  last_upgrade_prompt_at: string | null
}

interface UpgradeNudgeProps {
  currentTier: number // 0–4
  recommendedTier: number // next tier up
  onDismiss?: () => void
}

/**
 * UpgradeNudge — modal prompt when device handles current tier well above target.
 * Single-fire per session using useRef flag + UpgradeConfig deferral.
 *
 * Copy: "Your device handled the T<N> benchmark well above target. Want to try T<N+1>?"
 * Buttons: "Yes, upgrade", "Not now", "Don't ask again"
 *
 * T4 special case: additional opt-in confirmation (T4 is not automatic).
 */
export const UpgradeNudge: React.FC<UpgradeNudgeProps> = ({
  currentTier,
  recommendedTier,
  onDismiss,
}) => {
  const sessionShownRef = useRef(false)
  const [isVisible, setIsVisible] = useState(false)
  const [showT4Confirmation, setShowT4Confirmation] = useState(false)

  useEffect(() => {
    // Single-fire per session
    if (sessionShownRef.current) return
    sessionShownRef.current = true

    checkShouldShow()
  }, [])

  const checkShouldShow = async () => {
    try {
      const config: UpgradeConfig = await invoke('get_upgrade_config')

      if (config.upgrade_prompt_disabled) {
        return
      }

      if (config.last_upgrade_prompt_at) {
        const lastPrompt = new Date(config.last_upgrade_prompt_at)
        const now = new Date()
        const daysSince = (now.getTime() - lastPrompt.getTime()) / (1000 * 60 * 60 * 24)
        if (daysSince < 30) {
          return
        }
      }

      setIsVisible(true)
    } catch (err) {
      console.error('Failed to check upgrade config:', err)
    }
  }

  const handleUpgrade = async () => {
    if (recommendedTier === 4) {
      setShowT4Confirmation(true)
      return
    }

    await performUpgrade()
  }

  const handleConfirmT4 = async () => {
    await performUpgrade()
  }

  const performUpgrade = async () => {
    try {
      await invoke('upgrade_to_tier', { tier: recommendedTier })
      setIsVisible(false)
      setShowT4Confirmation(false)
      onDismiss?.()
    } catch (err) {
      console.error('Failed to upgrade tier:', err)
    }
  }

  const handleNotNow = async () => {
    try {
      await invoke('defer_upgrade_prompt_30_days')
      setIsVisible(false)
      onDismiss?.()
    } catch (err) {
      console.error('Failed to defer upgrade prompt:', err)
    }
  }

  const handleDontAskAgain = async () => {
    try {
      await invoke('set_upgrade_prompt_disabled', { disabled: true })
      setIsVisible(false)
      onDismiss?.()
    } catch (err) {
      console.error('Failed to disable upgrade prompt:', err)
    }
  }

  const tierLabel = (t: number) => (t >= 0 && t <= 4 ? `T${t}` : 'Unknown')

  return (
    <Dialog open={isVisible} onOpenChange={(open) => { if (!open) { setIsVisible(false); onDismiss?.(); } }}>
      <DialogContent className="max-w-md">
        {showT4Confirmation ? (
          <>
            <DialogHeader>
              <DialogTitle>Confirm T4 Upgrade</DialogTitle>
              <DialogDescription>
                T4 (Heavy) is opt-in only — it uses very large models that may significantly impact your device. Continue?
              </DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <Button variant="outline" onClick={() => setShowT4Confirmation(false)}>
                Cancel
              </Button>
              <Button onClick={handleConfirmT4}>
                Continue
              </Button>
            </DialogFooter>
          </>
        ) : (
          <>
            <DialogHeader>
              <DialogTitle>Upgrade Available</DialogTitle>
              <DialogDescription>
                Your device handled the {tierLabel(currentTier)} benchmark well above target. Want to try{' '}
                {tierLabel(recommendedTier)}? It uses more RAM and disk but produces better answers.
              </DialogDescription>
            </DialogHeader>
            <DialogFooter className="flex-col gap-2 sm:flex-col">
              <Button className="w-full" onClick={handleUpgrade}>
                Yes, upgrade
              </Button>
              <Button variant="outline" className="w-full" onClick={handleNotNow}>
                Not now
              </Button>
              <Button
                variant="ghost"
                className="w-full text-sm text-muted-foreground"
                onClick={handleDontAskAgain}
              >
                Don't ask again
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
