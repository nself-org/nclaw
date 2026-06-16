/**
 * useDirection — React Native RTL layout hook.
 *
 * Purpose: Reads the active locale from i18n state and returns layout
 *   helpers that flip correctly for RTL locales (Arabic etc).
 *   Use for flexDirection, textAlign, and margin/padding start/end.
 *
 * Inputs:  None — reads from i18next.language internally.
 * Outputs: { isRTL, flexRow, textAlign, marginStart, marginEnd, paddingStart, paddingEnd }
 * Constraints: Must be called inside a component (React hook rules).
 *   All consumers must use the returned helpers — no hardcoded 'left'/'right'.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T-P3-E4-W2-S3-T16 (i18n / RTL ticket).
 */

import { useTranslation } from 'react-i18next';
import { isRTL as checkIsRTL } from '@nself/i18n';
import type { FlexStyle, TextStyle } from 'react-native';

export interface DirectionHelpers {
  /** True when the active locale is RTL. */
  isRTL: boolean;
  /** flexDirection: 'row' | 'row-reverse' depending on locale. */
  flexRow: FlexStyle['flexDirection'];
  /** textAlign: 'left' | 'right' depending on locale. */
  textAlign: TextStyle['textAlign'];
  /**
   * Returns a margin value for the "start" logical side.
   * i.e. marginLeft in LTR, marginRight in RTL.
   */
  marginStart: (value: number) => { marginLeft?: number; marginRight?: number };
  /**
   * Returns a margin value for the "end" logical side.
   * i.e. marginRight in LTR, marginLeft in RTL.
   */
  marginEnd: (value: number) => { marginLeft?: number; marginRight?: number };
  /**
   * Returns padding for the "start" logical side.
   */
  paddingStart: (value: number) => { paddingLeft?: number; paddingRight?: number };
  /**
   * Returns padding for the "end" logical side.
   */
  paddingEnd: (value: number) => { paddingLeft?: number; paddingRight?: number };
}

/**
 * useDirection — returns RTL-aware layout helpers for the active locale.
 *
 * @example
 * const { isRTL, flexRow, textAlign } = useDirection();
 * <View style={{ flexDirection: flexRow }}>
 *   <Text style={{ textAlign }}>Hello</Text>
 * </View>
 */
export function useDirection(): DirectionHelpers {
  const { i18n } = useTranslation();
  const rtl = checkIsRTL(i18n.language);

  return {
    isRTL: rtl,
    flexRow: rtl ? 'row-reverse' : 'row',
    textAlign: rtl ? 'right' : 'left',
    marginStart: (v) => rtl ? { marginRight: v } : { marginLeft: v },
    marginEnd: (v) => rtl ? { marginLeft: v } : { marginRight: v },
    paddingStart: (v) => rtl ? { paddingRight: v } : { paddingLeft: v },
    paddingEnd: (v) => rtl ? { paddingLeft: v } : { paddingRight: v },
  };
}
