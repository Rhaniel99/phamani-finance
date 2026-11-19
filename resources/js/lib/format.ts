import type { KPITrend } from '@/types/phamani';

const currency = new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
});

export const formatCurrency = (
    value: number | string | null | undefined,
): string => currency.format(Number(value ?? 0));

export const formatTrend = (trend: KPITrend | null): string | undefined =>
    trend ? `${trend.value > 0 ? '+' : ''}${trend.value}%` : undefined;

/**
 * Formata uma data `YYYY-MM-DD` sem sofrer com fuso horário
 * (new Date('2026-01-01') é interpretado como UTC e pode "voltar" um dia).
 */
export function formatDate(date: string | null | undefined): string {
    if (!date) return '—';

    const [year, month, day] = date.slice(0, 10).split('-').map(Number);

    return new Date(year, month - 1, day).toLocaleDateString('pt-BR');
}

/** Data local de hoje em `YYYY-MM-DD`. */
export function today(): string {
    const now = new Date();
    const pad = (n: number) => String(n).padStart(2, '0');

    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/** "2026-12-01" → "dezembro de 2026" */
export function formatMonth(date: string | null | undefined): string {
    if (!date) return '—';

    const [year, month] = date.slice(0, 7).split('-').map(Number);

    return new Date(year, month - 1, 1).toLocaleDateString('pt-BR', {
        month: 'long',
        year: 'numeric',
    });
}
