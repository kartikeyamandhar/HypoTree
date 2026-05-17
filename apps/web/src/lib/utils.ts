import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import type { TestabilityClass } from '@/types/hypothesis';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export const DEPTH_COLORS = [
  'bg-blue-500',
  'bg-emerald-500',
  'bg-amber-500',
  'bg-purple-500',
] as const;

export function depthColor(depth: number): string {
  return DEPTH_COLORS[depth % DEPTH_COLORS.length] ?? 'bg-gray-500';
}

export const TESTABILITY_COLORS: Record<TestabilityClass, { bg: string; text: string; label: string }> = {
  quantitative: { bg: 'bg-green-100', text: 'text-green-700', label: 'Quantitative' },
  qualitative: { bg: 'bg-blue-100', text: 'text-blue-700', label: 'Qualitative' },
  assumption: { bg: 'bg-yellow-100', text: 'text-yellow-700', label: 'Assumption' },
  already_answered: { bg: 'bg-purple-100', text: 'text-purple-700', label: 'Already Answered' },
};

export function testabilityColor(tc: TestabilityClass) {
  return TESTABILITY_COLORS[tc] ?? { bg: 'bg-gray-100', text: 'text-gray-700', label: tc };
}
