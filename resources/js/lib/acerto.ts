import { formatDate } from '@/lib/format';
import type { AcertoGroup, AcertoItem } from '@/types/phamani';

/** "dezembro" a partir de "2026-12". */
export function acertoMonthName(month: string): string {
    const [year, m] = month.split('-').map(Number);

    return new Date(year, m - 1, 1).toLocaleDateString('pt-BR', {
        month: 'long',
    });
}

/** "Acerto de dezembro · até 07/12" */
export function acertoLabel(month: string, deadline?: string): string {
    const label = `Acerto de ${acertoMonthName(month)}`;

    return deadline
        ? `${label} · até ${formatDate(deadline).slice(0, 5)}`
        : label;
}

export const ACERTO_GROUP_LABELS: Record<AcertoGroup, string> = {
    overdue: 'Em atraso',
    current: 'Acerto da vez',
    upcoming: 'Próximos (se quiser adiantar)',
};

/** Ao abrir: marca o que está em atraso e o acerto da vez. */
export function defaultSelection(items: AcertoItem[]): string[] {
    return items.filter((i) => i.group !== 'upcoming').map((i) => i.id);
}

export function sumSelected(items: AcertoItem[], selected: string[]): number {
    return items
        .filter((i) => selected.includes(i.id))
        .reduce((sum, i) => sum + i.amount, 0);
}
